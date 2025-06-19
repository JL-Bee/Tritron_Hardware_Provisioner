// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/provisioner_bloc.dart' as provisioner;
import 'package:collection/collection.dart';
import '../protocols/rtm_console_protocol.dart';
import '../widgets/error_notification.dart';
import '../widgets/bloc_console_widget.dart';
import '../widgets/slider_input.dart';
import '../models/serial_port_info.dart';
import '../models/mesh_device.dart';
import '../models/dali_lc.dart';
import '../models/radar_info.dart';
import '../models/fade_time.dart';
import '../services/serial_port_service.dart' as serial;
import 'action_history_screen.dart';
import 'provisioner_connection_screen.dart';
import 'dart:async';


enum CommandStatus { idle, loading, success, failure }

class CommandState {
  final CommandStatus status;
  final DateTime? timestamp;

  CommandState({required this.status, this.timestamp});
}

class BlocMainScreen extends StatefulWidget {
  const BlocMainScreen({super.key});

  @override
  State<BlocMainScreen> createState() => _BlocMainScreenState();
}

class _BlocMainScreenState extends State<BlocMainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Add these new fields for tracking command states
  final Map<String, CommandState> _commandStates = {};
  final Map<String, String> _commandResults = {};
  final Map<String, String> _pendingGets = {};
  final Map<String, String> _pendingSetLabels = {};
  List<int> _lastSubscriptions = [];
  final Map<int, bool> _overrideStates = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _autoConnect();
  }

  // Add this method to listen for console changes and parse responses
  void _listenToConsoleChanges() {
    // This would be called whenever the bloc state changes
    // You can add this logic in the BlocBuilder or use a BlocListener
    final state = context.read<provisioner.ProvisionerBloc>().state;

    if (state.consoleEntries.isNotEmpty) {
      final lastEntry = state.consoleEntries.last;
      if (lastEntry.type == provisioner.ConsoleEntryType.response) {
        _parseConsoleResponse(lastEntry.text);
      }
    }
  }

  // Add this method to parse console responses
  void _parseConsoleResponse(String response) {
    // Remove the ~> prefix if present
    final cleanResponse = response.startsWith('~>') ? response.substring(2) : response;

    // Check which command was last executed by looking at command states
    _commandStates.forEach((key, state) {
      if (state.status == CommandStatus.loading) {
        // Parse based on the command key
        if (key.contains('label_get')) {
          if (!cleanResponse.contains('\$error') && !cleanResponse.contains('\$ok')) {
            final label = cleanResponse.replaceAll('"', '');
            final address = key.split('_').last;
            final expected = _pendingSetLabels[address];
            setState(() {
              _commandResults['Device Label'] = label;
              _commandStates[key] = CommandState(
                status: expected == null || expected == label
                    ? CommandStatus.success
                    : CommandStatus.failure,
                timestamp: DateTime.now(),
              );
            });
            if (expected != null) {
              _pendingSetLabels.remove(address);
            }
          }
        } else if (key.contains('dali_idle_get')) {
          if (cleanResponse.contains(',')) {
            final parts = cleanResponse.split(',');
            if (parts.length == 2) {
              setState(() {
                _commandResults['DALI Idle Config'] = 'Arc: ${parts[0]}, Fade: ${parts[1]}';
              });
            }
          }
        } else if (key.contains('dali_trigger_get')) {
          if (cleanResponse.contains(',') && cleanResponse.split(',').length == 4) {
            final parts = cleanResponse.split(',');
            setState(() {
              _commandResults['DALI Trigger Config'] = 'Arc: ${parts[0]}, Fade In: ${parts[1]}, Fade Out: ${parts[2]}, Hold: ${parts[3]}s';
            });
          }
        } else if (key.contains('dali_identify_get')) {
          if (RegExp(r'^\d+$').hasMatch(cleanResponse)) {
            final time = int.tryParse(cleanResponse) ?? 0;
            String displayValue;
            if (time == 0) {
              displayValue = 'Inactive';
            } else if (time == 65535) {
              displayValue = 'Active until reboot';
            } else {
              displayValue = '${time}s remaining';
            }
            setState(() {
              _commandResults['DALI Identify Time'] = displayValue;
            });
          }
        } else if (key.contains('dali_override_get')) {
          if (cleanResponse.contains(',') && cleanResponse.split(',').length == 3) {
            final parts = cleanResponse.split(',');
            final arc = parts[0];
            final fade = parts[1];
            final duration = parts[2];
            String displayValue;
            if (duration == '0') {
              displayValue = 'Inactive';
            } else {
              displayValue = 'Arc: $arc, Fade: $fade, Duration: ${duration}s';
            }
            setState(() {
              _commandResults['DALI Override'] = displayValue;
            });
          }
        } else if (key.contains('radar_cfg_get')) {
          if (cleanResponse.contains(',') && cleanResponse.split(',').length == 4) {
            final parts = cleanResponse.split(',');
            setState(() {
              _commandResults['Radar Config'] = 'Band: ${parts[0]}mV, Cross: ${parts[1]}, Interval: ${parts[2]}ms, Depth: ${parts[3]}';
            });
          }
        } else if (key.contains('radar_enable_get')) {
          if (RegExp(r'^[01]$').hasMatch(cleanResponse)) {
            setState(() {
              _commandResults['Radar Enable'] = cleanResponse == '1' ? 'Enabled' : 'Disabled';
            });
          }
        } else if (key.contains('sub_get')) {
          // Handle subscription list - this comes as multiple lines
          // Store addresses as they come in, ignoring case differences
          if (cleanResponse.startsWith('0x')) {
            final normalized = cleanResponse.trim().toUpperCase();
            final current = _commandResults['Subscriptions'] ?? '';
            final addresses = current.isEmpty ? [] : current.split(', ');
            final existing = addresses.map((a) => a.toUpperCase());
            if (!existing.contains(normalized)) {
              addresses.add(normalized);
              setState(() {
                _commandResults['Subscriptions'] = addresses.join(', ');
              });
            }
          }
        }

        // Check for final status
        if (cleanResponse == "\$ok") {
          setState(() {
            _commandStates[key] = CommandState(
              status: CommandStatus.success,
              timestamp: DateTime.now(),
            );
          });
          final followUp = _pendingGets.remove(key);
          if (followUp != null) {
            final followKey = _stateKeyForCommand(followUp);
            _executeCommand(context, followUp, stateKey: followKey);
          }
        } else if (cleanResponse == "\$error" || cleanResponse == "\$unknown") {
          setState(() {
            _commandStates[key] = CommandState(
              status: CommandStatus.failure,
              timestamp: DateTime.now(),
            );
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _autoConnect() async {
    final service = serial.SerialPortService();
    final ports = await service.scanForPorts();

    if (ports.isNotEmpty) {
      final nrf52Port = ports.firstWhere(
        (port) => port.isNRF52Device,
        orElse: () => ports.first,
      );

      if (!mounted) return;
      context
          .read<provisioner.ProvisionerBloc>()
          .add(provisioner.ConnectToPort(nrf52Port));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<provisioner.ProvisionerBloc, provisioner.ProvisionerState>(
      builder: (context, state) {
        if (state.connectionStatus != provisioner.ConnectionStatus.connected) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (state.connectionStatus == provisioner.ConnectionStatus.connecting)
                    const CircularProgressIndicator(),
                  if (state.connectionStatus == provisioner.ConnectionStatus.error)
                    const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    state.connectionStatus == provisioner.ConnectionStatus.connecting
                        ? 'Connecting to NRF52 DK...'
                        : state.connectionStatus == provisioner.ConnectionStatus.error
                            ? 'Connection failed'
                            : 'Not connected',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please connect your device via USB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProvisionerConnectionScreen(),
                        ),
                      );
                    },
                    child: const Text('Connection Settings'),
                  ),
                  if (state.connectionStatus == provisioner.ConnectionStatus.error) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _autoConnect,
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        // Get the current action/error for display
        final latestAction = state.actionHistory.isNotEmpty
            ? state.actionHistory.last
            : null;
        final hasRecentActivity = latestAction != null &&
            DateTime.now().difference(latestAction.timestamp).inSeconds < 3;

        // Auto-clear error after 1.5 seconds
        if (state.currentError != null) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              context.read<provisioner.ProvisionerBloc>().add(provisioner.ClearError());
            }
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset(
                  'assets/images/remoticom_logo.png',
                  height: kToolbarHeight * 0.8,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 12),
                const Text('Bluetooth Mesh Provisioner'),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'factory_reset') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Factory Reset'),
                        content: const Text(
                          'This will clear all provisioned devices from the provisioner\'s database. Continue?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && mounted) {
                      context.read<provisioner.ProvisionerBloc>().add(
                        provisioner.SendConsoleCommand('mesh/factory_reset'),
                      );
                      // Refresh lists after reset
                      Future.delayed(const Duration(seconds: 1), () {
                        if (mounted) {
                          context.read<provisioner.ProvisionerBloc>()
                            ..add(provisioner.ScanDevices())
                            ..add(provisioner.RefreshDeviceList());
                        }
                      });
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'factory_reset',
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Factory Reset'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: [
                const Tab(text: 'Devices', icon: Icon(Icons.devices)),
                const Tab(text: 'Details', icon: Icon(Icons.info)),
                const Tab(text: 'Console', icon: Icon(Icons.terminal)),
                Tab(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ActionHistoryScreen(),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state.currentAction != null)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else if (state.currentError != null)
                            const Icon(Icons.error, color: Colors.red, size: 16)
                          else if (hasRecentActivity && latestAction != null)
                            Icon(
                              latestAction.success ? Icons.check_circle : Icons.cancel,
                              color: latestAction.success ? Colors.green : Colors.orange,
                              size: 16,
                            )
                          else
                            const Icon(Icons.history, size: 16),
                          const SizedBox(width: 4),
                          if (state.currentAction != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Action History',
                                  style: TextStyle(fontSize: 10),
                                ),
                                Text(
                                  state.currentAction!.action.length > 20
                                      ? '${state.currentAction!.action.substring(0, 20)}...'
                                      : state.currentAction!.action,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            )
                          else if (state.currentError != null ||
                              (hasRecentActivity && latestAction != null))
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Action History',
                                  style: TextStyle(fontSize: 10),
                                ),
                                Text(
                                  state.currentError != null
                                      ? 'Error'
                                      : latestAction!.action.length > 20
                                          ? '${latestAction.action.substring(0, 20)}...'
                                          : latestAction.action,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            )
                          else
                            const Text(
                              'Action History',
                              style: TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              onTap: (index) {
                if (index == 3) {
                  // Navigate to action history instead of switching tab
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ActionHistoryScreen(),
                    ),
                  );
                  // Reset tab to previous
                  _tabController.animateTo(_tabController.previousIndex);
                }
              },
            ),
          ),
          body: Column(
            children: [
              _buildStatusBar(state),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(), // Prevent swiping to action tab
                  children: [
                    _buildDevicesTab(state),
                    _buildDetailsTab(state),
                    const BlocConsoleWidget(),
                    const SizedBox(), // Empty placeholder for action tab
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBar(provisioner.ProvisionerState state) {
    Color indicatorColor;
    switch (state.connectionStatus) {
      case provisioner.ConnectionStatus.connecting:
        indicatorColor = Colors.orange;
        break;
      case provisioner.ConnectionStatus.connected:
        indicatorColor = Colors.green;
        break;
      case provisioner.ConnectionStatus.error:
        indicatorColor = Colors.red;
        break;
      default:
        indicatorColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.usb, size: 20),
            tooltip: 'Connection Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProvisionerConnectionScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Text('Provisioner (${state.connectedPort?.portName ?? 'N/A'})'),
          const SizedBox(width: 8),
          Icon(Icons.circle, color: indicatorColor, size: 12),
          const Spacer(),
          Chip(
            label: Text('${state.foundUuids.length} new'),
            avatar: const Icon(Icons.bluetooth_searching, size: 16),
          ),
          const SizedBox(width: 8),
          Chip(
            label: Text('${state.provisionedDevices.length} provisioned'),
            avatar: const Icon(Icons.check_circle, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesTab(provisioner.ProvisionerState state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<provisioner.ProvisionerBloc>()
          ..add(provisioner.ScanDevices())
          ..add(provisioner.RefreshDeviceList());
      },
      child: ListView(
        children: [

          // Unprovisioned devices section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Unprovisioned Devices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Row(
                  children: [
                    Checkbox(
                      value: state.autoProvision,
                      onChanged: (v) => context
                          .read<provisioner.ProvisionerBloc>()
                          .add(provisioner.ToggleAutoProvision(v ?? false)),
                    ),
                    const Text('Auto Provision'),
                  ],
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: state.isProvisioning || state.foundUuids.isEmpty
                      ? null
                      : () => context
                          .read<provisioner.ProvisionerBloc>()
                          .add(provisioner.ProvisionAll()),
                  child: const Text('Provision All'),
                ),
                const SizedBox(width: 8),
                Text(
                  '${state.foundUuids.length} devices',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  icon: state.isScanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: state.isScanning
                      ? null
                      : () => context
                          .read<provisioner.ProvisionerBloc>()
                          .add(provisioner.ScanDevices()),
                ),
              ],
            ),
          ),
          if (state.foundUuids.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No unprovisioned devices')),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DataTable(
                columnSpacing: 12,
                columns: const [
                  DataColumn(label: Text('UUID')),
                  DataColumn(label: Center(child: Text('Actions'))),
                ],
                rows: state.foundUuids.map((uuid) {
                  return DataRow(cells: [
                    DataCell(Row(
                      children: [
                        SelectableText(
                          uuid,
                          maxLines: 1,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copy UUID',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: uuid));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('UUID copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    )),
                    DataCell(Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton(
                          onPressed: state.isProvisioning &&
                                  state.provisioningUuid == uuid
                              ? null
                              : () => context
                                  .read<provisioner.ProvisionerBloc>()
                                  .add(provisioner.ProvisionDevice(uuid)),
                          child: state.isProvisioning &&
                                  state.provisioningUuid == uuid
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Provision'),
                        ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'If devices show as "already provisioned", use Menu → Factory Reset to clear the database.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 32),
          ],
          // Provisioned devices section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Provisioned Devices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${state.provisionedDevices.length} devices',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<provisioner.ProvisionerBloc>().add(provisioner.RefreshDeviceList()),
                ),
              ],
            ),
          ),
          if (state.provisionedDevices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No provisioned devices')),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DataTable(
                columnSpacing: 12,
                columns: const [
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Device')),
                  DataColumn(label: Text('Group')),
                  DataColumn(label: Text('UUID')),
                  DataColumn(label: Center(child: Text('Actions'))),
                ],
                rows: state.provisionedDevices.map((device) {
                  return DataRow(cells: [
                    _buildStatusIndicator(device),
                    DataCell(
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              device.addressHex,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                            if (device.label != null) Text(device.label!),
                          ],
                        ),
                      ),
                      onTap: () {
                        context.read<provisioner.ProvisionerBloc>().add(provisioner.SelectDevice(device));
                        _tabController.animateTo(1);
                      },
                    ),
                    _buildGroupCell(device),
                    DataCell(SizedBox(
                      width: 200,
                      child: SelectableText(
                        device.uuid,
                        maxLines: 1,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    )),
                    DataCell(Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings),
                          tooltip: 'Settings',
                          onPressed: () {
                            context.read<provisioner.ProvisionerBloc>().add(provisioner.SelectDevice(device));
                            _tabController.animateTo(1);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.highlight),
                          tooltip: 'Identify',
                          onPressed: () => _quickIdentify(context, device),
                        ),
                        IconButton(
                          icon: Icon(
                            _overrideStates[device.address] ?? false
                                ? Icons.wb_incandescent
                                : Icons.lightbulb_outline,
                          ),
                          tooltip: 'Override',
                          onPressed: () => _toggleOverride(context, device),
                        ),
                        IconButton(
                          icon: const Icon(Icons.radar),
                          tooltip: 'Radar Sensitivity',
                          onPressed: () => _showRadarSensitivityDialog(context, device),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Unprovision',
                          color: Colors.red,
                          onPressed: () => _confirmUnprovision(context, device),
                        ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(provisioner.ProvisionerState state) {
    final device = state.selectedDevice;
    if (device == null) {
      return const Center(
        child: Text('Select a device to view details'),
      );
    }

    return BlocListener<provisioner.ProvisionerBloc, provisioner.ProvisionerState>(
      listener: (context, state) {
        if (state.consoleEntries.isNotEmpty) {
          final lastEntry = state.consoleEntries.last;
          if (lastEntry.type == provisioner.ConsoleEntryType.response) {
            _parseConsoleResponse(lastEntry.text);
          }
        }

        // Update displayed subscriptions when they change
        if (!const ListEquality<int>().equals(_lastSubscriptions, state.selectedDeviceSubscriptions)) {
          _lastSubscriptions = List<int>.from(state.selectedDeviceSubscriptions);
          setState(() {
            _commandResults['Subscriptions'] =
                _lastSubscriptions.map((a) => '0x${a.toRadixString(16).padLeft(4, '0').toUpperCase()}').join(', ');
          });
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device Information Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Device Information',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    DataTable(
                      columnSpacing: 12,
                      columns: const [
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Address')),
                        DataColumn(label: Text('Group Address')),
                        DataColumn(label: Text('UUID')),
                      ],
                      rows: [
                        DataRow(cells: [
                          _buildStatusIndicator(device),
                          _buildCopyableCell('Address', device.addressHex),
                          _buildCopyableCell('Group Address', device.groupAddressHex),
                          _buildCopyableCell('UUID', device.uuid),
                        ]),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Current Subscriptions Display
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Current Subscriptions',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'Add subscription',
                          onPressed: () => _showAddSubscriptionDialog(context, device),
                        ),
                      ],
                    ),
                    const Divider(),
                    if (state.selectedDeviceSubscriptions.isEmpty)
                      const Text('None'),
                    if (state.selectedDeviceSubscriptions.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: state.selectedDeviceSubscriptions.map(
                          (addr) => Chip(
                            label: Text(
                              '0x${addr.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 18),
                            onDeleted: () {
                              _executeCommand(
                                context,
                                'mesh/device/sub/remove ${device.addressHex} 0x${addr.toRadixString(16)} 3000',
                                stateKey: 'sub_remove_${device.address}_$addr',
                              );
                              Future.delayed(const Duration(seconds: 1), () {
                                if (mounted) {
                                  context.read<provisioner.ProvisionerBloc>().add(
                                        provisioner.SelectDevice(device),
                                      );
                                }
                              });
                            },
                          ),
                        ).toList(),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Device Resources Table (Leshan-style)
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Device Resources',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.sync),
                          label: const Text('Read All'),
                          onPressed: () => _readAllParameters(context, device),
                        ),
                      ],
                    ),
                  ),

                  // Resource Table
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(3),
                      2: FlexColumnWidth(1),
                      3: FlexColumnWidth(2),
                      4: FlexColumnWidth(2),
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                    children: [
                      // Table Header
                      TableRow(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                        ),
                        children: const [
                          TableCell(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Resource',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Description',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Op',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Actions',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Value',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Device Management Section
                      _buildSectionHeader(context, 'Device Management'),
                      _buildResourceRow(
                        context,
                        'label',
                        'Device Label',
                        'R/W',
                        [
                          Tooltip(
                            message: 'Get the device label stored in the provisioner\'s database',
                            child: _buildActionButton(
                              context,
                              'GET',
                              Icons.download,
                              () => _executeCommand(
                                context,
                                'mesh/device/label/get ${device.addressHex} 3000',
                                stateKey: 'label_get_${device.address}',
                              ),
                              stateKey: 'label_get_${device.address}',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Set a label for the device (max 32 characters)',
                            child: _buildActionButton(
                              context,
                              'SET',
                              Icons.edit,
                              () => _showSetLabelDialog(context, device),
                              stateKey: 'label_set_${device.address}',
                            ),
                          ),
                        ],
                        'Device Label',
                      ),
                      _buildResourceRow(
                        context,
                        'reset',
                        'Reset Device',
                        'EXEC',
                        [
                          Tooltip(
                            message: 'Unprovision the device and remove it from the provisioner\'s database.\n'
                                    'The device will be reset to factory defaults.',
                            child: _buildActionButton(
                              context,
                              'EXEC',
                              Icons.restart_alt,
                              () => _confirmReset(context, device),
                              isDestructive: true,
                              stateKey: 'reset_${device.address}',
                            ),
                          ),
                        ],
                        null,
                      ),

                      // Subscription Management Section
                      _buildSectionHeader(context, 'Subscription Management'),
                      _buildResourceRow(
                        context,
                        'sub',
                        'Group Subscriptions',
                        'R/W',
                        [
                          Tooltip(
                            message: 'Get all subscribed group addresses from the provisioner database',
                            child: _buildActionButton(
                              context,
                              'GET',
                              Icons.download,
                              () => _executeCommand(
                                context,
                                'mesh/device/sub/get ${device.addressHex}',
                                stateKey: 'sub_get_${device.address}',
                              ),
                              stateKey: 'sub_get_${device.address}',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Add a group address to the device\'s subscribe list.\n'
                                    'Valid range: 0xC000-0xFEFF',
                            child: _buildActionButton(
                              context,
                              'ADD',
                              Icons.add,
                              () => _showAddSubscriptionDialog(context, device),
                              stateKey: 'sub_add_${device.address}',
                            ),
                          ),
                        ],
                        'Subscriptions',
                      ),

                      // DALI Light Control Section
                      _buildSectionHeader(context, 'DALI Light Control'),
                      _buildResourceRow(
                        context,
                        'identify',
                        'Light Identify',
                        'R/W',
                        [
                          Tooltip(
                            message: 'Get remaining identify time.\n'
                                    '0 = inactive, 1-65534 = seconds remaining,\n'
                                    '65535 = active until reboot',
                            child: _buildActionButton(
                              context,
                              'GET',
                              Icons.download,
                              () => _executeCommand(
                                context,
                                'mesh/dali_lc/identify/get ${device.addressHex} 3000',
                                stateKey: 'dali_identify_get_${device.address}',
                              ),
                              stateKey: 'dali_identify_get_${device.address}',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Make the light identify itself (highest priority).\n'
                                    '0 = off, 1-65534 = duration in seconds,\n'
                                    '65535 = identify until reboot',
                            child: _buildActionButton(
                              context,
                              'SET',
                              Icons.lightbulb,
                              () => _showDaliIdentifyDialog(context, device),
                              stateKey: 'dali_identify_set_${device.address}',
                            ),
                          ),
                        ],
                        'DALI Identify Time',
                      ),
                      _buildResourceRow(
                        context,
                        'override',
                        'Manual Override',
                        'R/W',
                        [
                          Tooltip(
                            message: 'Get current override status.\n'
                                    'Returns: arc, fade, remaining duration\n'
                                    'Arc/fade = 255 when inactive',
                            child: _buildActionButton(
                              context,
                              'GET',
                              Icons.download,
                              () => _executeCommand(
                                context,
                                'mesh/dali_lc/override/get ${device.addressHex} 3000',
                                stateKey: 'dali_override_get_${device.address}',
                              ),
                              stateKey: 'dali_override_get_${device.address}',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Manually override the light level.',
                            child: _buildActionButton(
                              context,
                              'SET',
                              Icons.pan_tool,
                              () => _showDaliOverrideDialog(context, device),
                              stateKey: 'dali_override_set_${device.address}',
                            ),
                          ),
                        ],
                        'DALI Override',
                      ),

                      // Radar Control Section
                      _buildSectionHeader(context, 'Motion Sensor Control'),
                      _buildResourceRow(
                        context,
                        'cfg',
                        'Radar Configuration',
                        'R/W',
                        [
                          Tooltip(
                            message: 'Get radar sensor configuration.\n'
                                    'Returns: threshold band (mV), cross count,\n'
                                    'sample interval (ms), buffer depth',
                            child: _buildActionButton(
                              context,
                              'GET',
                              Icons.download,
                              () => _executeCommand(
                                context,
                                'mesh/radar/cfg/get ${device.addressHex} 3000',
                                stateKey: 'radar_cfg_get_${device.address}',
                              ),
                              stateKey: 'radar_cfg_get_${device.address}',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Configure radar sensor parameters.',
                            child: _buildActionButton(
                              context,
                              'SET',
                              Icons.settings,
                              () => _showRadarConfigDialog(context, device),
                              stateKey: 'radar_cfg_set_${device.address}',
                            ),
                          ),
                        ],
                        'Radar Config',
                      ),
                      _buildResourceRow(
                        context,
                        'enable',
                        'Radar Enable State',
                        'R/W',
                        [
                          Tooltip(
                            message: 'Get radar module enable state.\n'
                                    '0 = disabled, 1 = enabled',
                            child: _buildActionButton(
                              context,
                              'GET',
                              Icons.download,
                              () => _executeCommand(
                                context,
                                'mesh/radar/enable/get ${device.addressHex} 3000',
                                stateKey: 'radar_enable_get_${device.address}',
                              ),
                              stateKey: 'radar_enable_get_${device.address}',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Enable or disable the radar sensor.',
                            child: _buildActionButton(
                              context,
                              'SET',
                              Icons.power_settings_new,
                              () => _showRadarEnableDialog(context, device),
                              stateKey: 'radar_enable_set_${device.address}',
                            ),
                          ),
                        ],
                        'Radar Enable',
                      ),
                      _buildResourceRow(
                        context,
                        'idle_cfg',
                        'DALI Idle Configuration',
                        'R/W',
                        [
                          Tooltip(
                            message: 'Get the DALI LC idle configuration.\n'
                                    'Returns: arc level (0-254) and fade time',
                            child: _buildActionButton(
                              context,
                              'GET',
                              Icons.download,
                              () => _executeCommand(
                                context,
                                'mesh/dali_lc/idle_cfg/get ${device.addressHex} 3000',
                                stateKey: 'dali_idle_get_${device.address}',
                              ),
                              stateKey: 'dali_idle_get_${device.address}',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Set the idle state configuration.',
                            child: _buildActionButton(
                              context,
                              'SET',
                              Icons.settings,
                              () => _showDaliIdleConfigDialog(context, device),
                              stateKey: 'dali_idle_set_${device.address}',
                            ),
                          ),
                        ],
                        'DALI Idle Config',
                      ),
                      _buildResourceRow(
                        context,
                        'trigger_cfg',
                        'DALI Trigger Configuration',
                        'R/W',
                        [
                          Tooltip(
                            message: 'Get the trigger configuration.\n'
                                    'Returns: arc, fade in, fade out, hold time',
                            child: _buildActionButton(
                              context,
                              'GET',
                              Icons.download,
                              () => _executeCommand(
                                context,
                                'mesh/dali_lc/trigger_cfg/get ${device.addressHex} 3000',
                                stateKey: 'dali_trigger_get_${device.address}',
                              ),
                              stateKey: 'dali_trigger_get_${device.address}',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Configure trigger behavior.',
                            child: _buildActionButton(
                              context,
                              'SET',
                              Icons.settings,
                              () => _showDaliTriggerConfigDialog(context, device),
                              stateKey: 'dali_trigger_set_${device.address}',
                            ),
                          ),
                        ],
                        'DALI Trigger Config',
                      ),
                    ],
                  ),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }

  // Helper method to build section headers
  TableRow _buildSectionHeader(BuildContext context, String title) {
    return TableRow(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5),
      ),
      children: [
        TableCell(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
        const TableCell(child: SizedBox.shrink()),
        const TableCell(child: SizedBox.shrink()),
        const TableCell(child: SizedBox.shrink()),
        const TableCell(child: SizedBox.shrink()),
      ],
    );
  }

  // Helper method to build resource rows
  TableRow _buildResourceRow(
    BuildContext context,
    String resource,
    String description,
    String operations,
    List<Widget> actions,
    String? resourceKey,
  ) {
    return TableRow(
      children: [
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              resource,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(description),
          ),
        ),
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              operations,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: actions,
            ),
          ),
        ),
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _commandResults[resourceKey] ?? '-',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Helper method to build action buttons with status indicators
  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed, {
    bool isDestructive = false,
    String? stateKey,
  }) {
    final state = stateKey != null ? _commandStates[stateKey] : null;
    final status = state?.status ?? CommandStatus.idle;

    Widget buttonContent;

    switch (status) {
      case CommandStatus.loading:
        buttonContent = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        break;
      case CommandStatus.success:
        buttonContent = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 16, color: Colors.green),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        );
        break;
      case CommandStatus.failure:
        buttonContent = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel, size: 16, color: Colors.red),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        );
        break;
      default:
        buttonContent = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        );
    }

    return SizedBox(
      height: 32,
      child: isDestructive
          ? FilledButton.tonal(
              onPressed: status == CommandStatus.loading ? null : onPressed,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
              child: buttonContent,
            )
          : OutlinedButton(
              onPressed: status == CommandStatus.loading ? null : onPressed,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: buttonContent,
            ),
    );
  }

  String? _followUpGetCommand(String command) {
    final parts = command.split(' ');
    if (parts.length < 2) return null;
    final addr = parts[1];
    if (command.startsWith('mesh/device/label/set')) {
      return 'mesh/device/label/get $addr 3000';
    } else if (command.startsWith('mesh/dali_lc/idle_cfg/set')) {
      return 'mesh/dali_lc/idle_cfg/get $addr 3000';
    } else if (command.startsWith('mesh/dali_lc/trigger_cfg/set')) {
      return 'mesh/dali_lc/trigger_cfg/get $addr 3000';
    } else if (command.startsWith('mesh/dali_lc/identify/set') ||
        command.startsWith('mesh/device/identify/set')) {
      return 'mesh/dali_lc/identify/get $addr 3000';
    } else if (command.startsWith('mesh/dali_lc/override/set')) {
      return 'mesh/dali_lc/override/get $addr 3000';
    } else if (command.startsWith('mesh/radar/cfg/set')) {
      return 'mesh/radar/cfg/get $addr 3000';
    } else if (command.startsWith('mesh/radar/enable/set')) {
      return 'mesh/radar/enable/get $addr 3000';
    }
    return null;
  }

  String _stateKeyForCommand(String command) {
    final parts = command.split(' ');
    if (parts.length < 2) return command;
    final addrStr = parts[1];
    final addr = int.tryParse(
        addrStr.startsWith('0x') ? addrStr.substring(2) : addrStr,
        radix: addrStr.startsWith('0x') ? 16 : 10);
    if (command.startsWith('mesh/device/label/get')) {
      return 'label_get_$addr';
    } else if (command.startsWith('mesh/dali_lc/idle_cfg/get')) {
      return 'dali_idle_get_$addr';
    } else if (command.startsWith('mesh/dali_lc/trigger_cfg/get')) {
      return 'dali_trigger_get_$addr';
    } else if (command.startsWith('mesh/dali_lc/identify/get')) {
      return 'dali_identify_get_$addr';
    } else if (command.startsWith('mesh/dali_lc/override/get')) {
      return 'dali_override_get_$addr';
    } else if (command.startsWith('mesh/radar/cfg/get')) {
      return 'radar_cfg_get_$addr';
    } else if (command.startsWith('mesh/radar/enable/get')) {
      return 'radar_enable_get_$addr';
    } else if (command.startsWith('mesh/device/sub/get')) {
      return 'sub_get_$addr';
    }
    return command;
  }

  // Helper method to execute commands with state tracking
  void _executeCommand(BuildContext context, String command, {String? stateKey}) {
    // Generate a state key if not provided
    final key = stateKey ?? command;

    // Update state to loading
    setState(() {
      _commandStates[key] = CommandState(status: CommandStatus.loading);
    });

    final followUp = _followUpGetCommand(command);
    if (followUp != null) {
      _pendingGets[key] = followUp;
    }

    // Send command
    context.read<provisioner.ProvisionerBloc>().add(
      provisioner.SendConsoleCommand(command),
    );

    if (!command.contains('sub/get')) {
      // Set up a timer to check for response
      Timer(const Duration(seconds: 3), () {
        if (mounted && _commandStates[key]?.status == CommandStatus.loading) {
          setState(() {
            _commandStates[key] = CommandState(
              status: CommandStatus.failure,
              timestamp: DateTime.now(),
            );
          });
        }
      });
    }
  }

  Future<void> _readAllParameters(
      BuildContext context, MeshDevice device) async {
    final addr = device.addressHex;
    final commands = <MapEntry<String, String>>[
      MapEntry('mesh/device/label/get $addr 3000',
          'label_get_${device.address}'),
      MapEntry('mesh/device/sub/get $addr', 'sub_get_${device.address}'),
      MapEntry('mesh/dali_lc/idle_cfg/get $addr 3000',
          'dali_idle_get_${device.address}'),
      MapEntry('mesh/dali_lc/trigger_cfg/get $addr 3000',
          'dali_trigger_get_${device.address}'),
      MapEntry('mesh/dali_lc/identify/get $addr 3000',
          'dali_identify_get_${device.address}'),
      MapEntry('mesh/dali_lc/override/get $addr 3000',
          'dali_override_get_${device.address}'),
      MapEntry('mesh/radar/cfg/get $addr 3000',
          'radar_cfg_get_${device.address}'),
      MapEntry('mesh/radar/enable/get $addr 3000',
          'radar_enable_get_${device.address}'),
    ];

    for (final cmd in commands) {
      _executeCommand(context, cmd.key, stateKey: cmd.value);
      // Wait for a response before sending the next command
      while (true) {
        await Future.delayed(const Duration(milliseconds: 100));
        final status = _commandStates[cmd.value]?.status;
        if (status != null && status != CommandStatus.loading) {
          break;
        }
      }
    }
  }

  // Dialog methods
  Future<void> _showIdentifyDialog(BuildContext context, MeshDevice device) async {
    final durationController = TextEditingController(text: '10');

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Device Identify'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Set identify duration in seconds (0-254):'),
              const SizedBox(height: 16),
              TextField(
                controller: durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration (seconds)',
                  hintText: '0 = off, 1-254 = seconds',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final duration = int.tryParse(durationController.text) ?? 5;
      _executeCommand(context, 'mesh/device/identify/set ${device.addressHex} $duration 3000');
    }
  }

  Future<void> _showDaliIdleConfigDialog(BuildContext context, MeshDevice device) async {
    final arcController = TextEditingController(text: '0');
    final fadeController = TextEditingController(text: '4');

    final result = await showDialog<bool>(
      context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('DALI Idle Configuration'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Idle arc level defines the light level when no trigger is active.'
                  '\nFade time controls how quickly the light transitions back to this level.'
                  '\nArc: 0-254, Fade: 0-30',
                ),
                const SizedBox(height: 16),
              SliderInput(
                label: 'Idle Arc Level',
                min: 0,
                max: 254,
                controller: arcController,
              ),
              const SizedBox(height: 16),
              SliderInput(
                label: 'Fade Time',
                min: 0,
                max: 30,
                controller: fadeController,
              ),
              ],
            ),
          ),
          actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final arc = int.tryParse(arcController.text) ?? 0;
      final fade = int.tryParse(fadeController.text) ?? 4;
      _executeCommand(context, 'mesh/dali_lc/idle_cfg/set ${device.addressHex} $arc $fade 3000');
    }
  }

  Future<void> _showDaliTriggerConfigDialog(BuildContext context, MeshDevice device) async {
    final arcController = TextEditingController(text: '254');
    final fadeInController = TextEditingController(text: '0');
    final fadeOutController = TextEditingController(text: '7');
    final holdTimeController = TextEditingController(text: '5');

    final result = await showDialog<bool>(
      context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('DALI Trigger Configuration'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trigger settings control how the light behaves when activated.'
                    '\nArc level is the brightness on trigger, fade in/out define the '
                    'transition durations, and hold time sets how long the trigger level '
                    'stays active.'
                    '\nArc: 0-254, Fade: 0-30, Hold: 0-65535',
                  ),
                  const SizedBox(height: 16),
                  SliderInput(
                    label: 'Trigger Arc Level',
                    min: 0,
                    max: 254,
                    controller: arcController,
                ),
                const SizedBox(height: 16),
                SliderInput(
                  label: 'Fade In Time',
                  min: 0,
                  max: 30,
                  controller: fadeInController,
                ),
                const SizedBox(height: 16),
                SliderInput(
                  label: 'Fade Out Time',
                  min: 0,
                  max: 30,
                  controller: fadeOutController,
                ),
                const SizedBox(height: 16),
                  SliderInput(
                    label: 'Hold Time (seconds)',
                    min: 0,
                    max: 65535,
                    sliderMax: 120,
                    controller: holdTimeController,
                  ),
                ],
              ),
            ),
          ),
          actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final arc = int.tryParse(arcController.text) ?? 254;
      final fadeIn = int.tryParse(fadeInController.text) ?? 0;
      final fadeOut = int.tryParse(fadeOutController.text) ?? 7;
      final holdTime = int.tryParse(holdTimeController.text) ?? 5;
      _executeCommand(context, 'mesh/dali_lc/trigger_cfg/set ${device.addressHex} $arc $fadeIn $fadeOut $holdTime 3000');
    }
  }

  Future<void> _showDaliIdentifyDialog(BuildContext context, MeshDevice device) async {
    final durationController = TextEditingController(text: '5');

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('DALI Light Identify'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Set light identify duration (0-65535 seconds):'),
              const SizedBox(height: 16),
              TextField(
                controller: durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration',
                  hintText: '0=off, 1-65534=seconds, 65535=until reboot',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final duration = int.tryParse(durationController.text) ?? 5;
      _executeCommand(context, 'mesh/dali_lc/identify/set ${device.addressHex} $duration 3000');
    }
  }

  Future<void> _showDaliOverrideDialog(BuildContext context, MeshDevice device) async {
    var overrideInfo = _latestOverride(device);
    overrideInfo ??= await _fetchOverrideState(device);
    final arcController = TextEditingController(
        text: overrideInfo?.arc.toString() ?? '254');
    final fadeController = TextEditingController(
        text: overrideInfo?.fade.value.toString() ?? '0');
    final durationController = TextEditingController(
        text: overrideInfo?.duration == 0 ? '5' : overrideInfo?.duration.toString() ?? '5');

    final result = await showDialog<bool>(
      context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('DALI Manual Override'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Override temporarily forces the light to a specific level.'
                  '\nDuration defines how long the override is active.'
                  '\nArc: 0-254, Fade: 0-30, Duration: 0-65535',
                ),
                const SizedBox(height: 16),
              SliderInput(
                label: 'Arc Level',
                min: 0,
                max: 254,
                controller: arcController,
              ),
              const SizedBox(height: 16),
              SliderInput(
                label: 'Fade Time',
                min: 0,
                max: 30,
                controller: fadeController,
              ),
              const SizedBox(height: 16),
              SliderInput(
                label: 'Duration',
                min: 1,
                max: 65535,
                sliderMax: 120,
                controller: durationController,
              ),
              ],
            ),
          ),
          actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final arc = int.tryParse(arcController.text) ?? 254;
      final fade = int.tryParse(fadeController.text) ?? 0;
      final duration = int.tryParse(durationController.text) ?? 5;
      _executeCommand(context, 'mesh/dali_lc/override/set ${device.addressHex} $arc $fade $duration 3000');
    }
  }

  Future<void> _showRadarConfigDialog(BuildContext context, MeshDevice device) async {
    var radar = _latestRadar(device);
    radar ??= await _fetchRadarConfig(device);
    final bandController = TextEditingController(
        text: radar?.bandThreshold.toString() ?? '210');
    final crossController = TextEditingController(
        text: radar?.crossCount.toString() ?? '31');
    final intervalController = TextEditingController(
        text: radar?.sampleInterval.toString() ?? '5');
    final depthController = TextEditingController(
        text: radar?.bufferDepth.toString() ?? '500');

    final result = await showDialog<bool>(
      context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Radar Configuration'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Radar parameters tune the motion sensor. Adjust the threshold '
                    'band to set sensitivity, cross count for detection confidence, '
                    'sample interval for polling rate, and buffer depth for history '
                    'size.'
                    '\n\nBandWidth: 0-1650mV, when there is no movement the measured '
                    'value is ~0mV, the badwidth indicates what signal offset there '
                    'needs to be before its considded for the cross count '
                    '\n\nCross Count: 1-500, sample count of signal crossing the '
                    'bandwidth threshold before its considerd a trigger '
                    '\n\nSample Interval: 1-2047ms, how often is the crossing of the '
                    'bandwidth is checked'
                    '\n\nBuffer Depth: 0-500, all samples are stored, the cross count '
                    'is calculated over this buffer.'
                  ),
                  const SizedBox(height: 16),
                  SliderInput(
                    label: 'Threshold Band (mV)',
                    min: 0,
                    max: 1650,
                    controller: bandController,
                ),
                const SizedBox(height: 16),
                SliderInput(
                  label: 'Cross Count Threshold',
                  min: 1,
                  max: 500,
                  controller: crossController,
                ),
                const SizedBox(height: 16),
                SliderInput(
                  label: 'Sample Interval (ms)',
                  min: 1,
                  max: 2047,
                  controller: intervalController,
                ),
                const SizedBox(height: 16),
                  SliderInput(
                    label: 'Buffer Depth',
                    min: 0,
                    max: 500,
                    controller: depthController,
                  ),
                ],
              ),
            ),
          ),
          actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final band = int.tryParse(bandController.text) ?? 210;
      final cross = int.tryParse(crossController.text) ?? 31;
      final interval = int.tryParse(intervalController.text) ?? 5;
      final depth = int.tryParse(depthController.text) ?? 500;
      _executeCommand(context, 'mesh/radar/cfg/set ${device.addressHex} $band $cross $interval $depth 3000');
    }
  }

  Future<void> _showRadarEnableDialog(BuildContext context, MeshDevice device) async {
    bool enable = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Radar Enable State'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Enable Radar'),
                  value: enable,
                  onChanged: (value) => setState(() => enable = value),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      _executeCommand(context, 'mesh/radar/enable/set ${device.addressHex} ${enable ? 1 : 0} 3000');
    }
  }

  void _quickIdentify(BuildContext context, MeshDevice device) {
    _executeCommand(
      context,
      'mesh/dali_lc/identify/set ${device.addressHex} 3 3000',
      stateKey: 'dali_identify_quick_${device.address}',
    );
  }

  void _toggleOverride(BuildContext context, MeshDevice device) {
    final isOn = _overrideStates[device.address] ?? false;
    final arc = isOn ? 0 : 254;
    final duration = isOn ? 0 : 65535;
    _executeCommand(
      context,
      'mesh/dali_lc/override/set ${device.addressHex} $arc 0 $duration 3000',
      stateKey: 'dali_override_toggle_${device.address}',
    );
    setState(() {
      _overrideStates[device.address] = !isOn;
    });
  }

  Future<void> _showRadarSensitivityDialog(
      BuildContext context, MeshDevice device) async {
    const presets = [10, 25, 50, 75, 100];
    final selection = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Radar Sensitivity'),
        children: presets
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, p),
                child: Text('$p%'),
              ),
            )
            .toList(),
      ),
    );

    if (selection != null && mounted) {
      final band = (1650 * selection / 100).round();
      const crossCounts = {
        10: 47,
        25: 118,
        50: 235,
        75: 352,
        100: 30,
      };
      final cross = crossCounts[selection] ?? 31;
      _executeCommand(
        context,
        'mesh/radar/cfg/set ${device.addressHex} $band $cross 5 500 3000',
        stateKey: 'radar_quick_${device.address}',
      );
    }
  }

  Future<void> _confirmReset(BuildContext context, MeshDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Device'),
        content: Text('Are you sure you want to reset device ${device.addressHex}? This will unprovision the device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _executeCommand(context, 'mesh/device/reset ${device.addressHex} 3000');
    }
  }

  Future<void> _showSetLabelDialog(BuildContext context, MeshDevice device) async {
    final controller = TextEditingController(text: device.label ?? '');
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set Device Label'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Label',
            hintText: 'Enter device label',
            helperText: 'Max 32 characters, no spaces',
          ),
          maxLength: 32,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (label != null && mounted) {
      _pendingSetLabels[device.addressHex] = label;
      _executeCommand(
        context,
        'mesh/device/label/set ${device.addressHex} $label',
        stateKey: 'label_set_${device.address}',
      );
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy $label',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$label copied to clipboard'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildInfoDataRow(String label, String value) {
    return DataRow(cells: [
      DataCell(Text(label)),
      DataCell(Row(
        children: [
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy $label',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied to clipboard'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      )),
    ]);
  }

  /// Small coloured dot representing the device status. If the device address
  /// is `0`, provisioning is in progress and a spinner is shown instead.
  DataCell _buildStatusIndicator(MeshDevice device) {
    if (device.address == 0) {
      return const DataCell(SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ));
    }

    Color color;
    switch (device.status) {
      case DeviceStatus.online:
        color = Colors.green;
        break;
      case DeviceStatus.stale:
        color = Colors.orange;
        break;
      case DeviceStatus.offline:
      default:
        color = Colors.red;
    }

    return DataCell(Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ));
  }

  /// Display the group address and other subscriptions.
  ///
  /// The device's own group address is shown in **bold** when multiple
  /// subscriptions exist. Tapping the cell opens the link management dialog.
  DataCell _buildGroupCell(MeshDevice device) {
    final bloc = context.read<provisioner.ProvisionerBloc>();

    return DataCell(
      FutureBuilder<List<int>>(
        future: bloc.fetchSubscriptions(device.address),
        builder: (context, snapshot) {
          final subs = snapshot.data ?? [device.groupAddress];
          if (!subs.contains(device.groupAddress)) subs.insert(0, device.groupAddress);

          final other = subs.where((a) => a != device.groupAddress).toList();
          final spanChildren = <TextSpan>[
            TextSpan(
              text: '0x${device.groupAddress.toRadixString(16).padLeft(4, '0').toUpperCase()}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: other.isEmpty ? FontWeight.normal : FontWeight.bold,
              ),
            ),
          ];

          if (other.isNotEmpty) {
            final rest = other
                .map((a) => '0x${a.toRadixString(16).padLeft(4, '0').toUpperCase()}')
                .join(', ');
            spanChildren.add(TextSpan(
              text: ', $rest',
              style: const TextStyle(fontFamily: 'monospace'),
            ));
          }

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text.rich(TextSpan(children: spanChildren)),
          );
        },
      ),
      onTap: () => _showManageLinksDialog(context, device),
    );
  }

  DataCell _buildCopyableCell(String label, String value) {
    return DataCell(Row(
      children: [
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 16),
          tooltip: 'Copy \$label',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('\$label copied to clipboard'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    ));
  }

  Widget _buildDaliInfoCard(provisioner.ProvisionerState state, MeshDevice device) {
    final info = state.daliInfo[device.address];
    if (info == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('DALI LC information unavailable'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DALI Light Control',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildInfoRow('Idle', '${info.idle.arc}, fade ${info.idle.fade}'),
            _buildInfoRow(
                'Trigger',
                '${info.trigger.arc}, in ${info.trigger.fadeIn}, out ${info.trigger.fadeOut}, hold ${info.trigger.holdTime}s'),
            _buildInfoRow('Identify Time', info.identifyRemaining.toString()),
            _buildInfoRow(
                'Override',
                '${info.override.arc}, fade ${info.override.fade}, ${info.override.duration}s'),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarInfoCard(provisioner.ProvisionerState state, MeshDevice device) {
    final radar = state.radarInfo[device.address];
    if (radar == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Radar information unavailable'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Radar Configuration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildInfoRow('Band Threshold', radar.bandThreshold.toString()),
            _buildInfoRow('Cross Count', radar.crossCount.toString()),
            _buildInfoRow('Sample Interval', '${radar.sampleInterval} ms'),
            _buildInfoRow('Buffer Depth', radar.bufferDepth.toString()),
            _buildInfoRow('Enabled', radar.enabled ? 'Yes' : 'No'),
          ],
        ),
      ),
    );
  }

  RadarInfo? _latestRadar(MeshDevice device) {
    final text = _commandResults['Radar Config'];
    final enableText = _commandResults['Radar Enable'];
    if (text != null) {
      final match = RegExp(r'Band: (\d+)mV, Cross: (\d+), Interval: (\d+)ms, Depth: (\d+)')
          .firstMatch(text);
      if (match != null) {
        return RadarInfo(
          bandThreshold: int.parse(match.group(1)!),
          crossCount: int.parse(match.group(2)!),
          sampleInterval: int.parse(match.group(3)!),
          bufferDepth: int.parse(match.group(4)!),
          enabled: enableText == 'Enabled',
        );
      }
    }
    return context.read<provisioner.ProvisionerBloc>()
        .state
        .radarInfo[device.address];
  }

  DaliOverrideState? _latestOverride(MeshDevice device) {
    final text = _commandResults['DALI Override'];
    if (text != null && text != 'Inactive') {
      final match =
          RegExp(r'Arc: (\d+), Fade: (\d+), Duration: (\d+)s').firstMatch(text);
      if (match != null) {
        final arc = int.parse(match.group(1)!);
        final fade = FadeTime.fromValue(int.parse(match.group(2)!));
        final dur = int.parse(match.group(3)!);
        return DaliOverrideState(arc, fade, dur);
      }
    }
    return context
        .read<provisioner.ProvisionerBloc>()
        .state
        .daliInfo[device.address]
        ?.override;
  }

  Future<RadarInfo?> _fetchRadarConfig(MeshDevice device) async {
    final key = 'radar_cfg_get_${device.address}';
    _executeCommand(context, 'mesh/radar/cfg/get ${device.addressHex} 3000',
        stateKey: key);
    while (true) {
      await Future.delayed(const Duration(milliseconds: 100));
      final status = _commandStates[key]?.status;
      if (status != null && status != CommandStatus.loading) {
        break;
      }
    }
    return _latestRadar(device);
  }

  Future<DaliOverrideState?> _fetchOverrideState(MeshDevice device) async {
    final key = 'dali_override_get_${device.address}';
    _executeCommand(context, 'mesh/dali_lc/override/get ${device.addressHex} 3000',
        stateKey: key);
    while (true) {
      await Future.delayed(const Duration(milliseconds: 100));
      final status = _commandStates[key]?.status;
      if (status != null && status != CommandStatus.loading) {
        break;
      }
    }
    return _latestOverride(device);
  }

  Future<void> _confirmUnprovision(BuildContext context, MeshDevice device) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Device Actions'),
        content: Text('Select action for device ${device.addressHex}:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'reset'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Reset Device'),
          ),
        ],
      ),
    );

    if (action == 'reset' && mounted) {
      context
          .read<provisioner.ProvisionerBloc>()
          .add(provisioner.UnprovisionDevice(device));
    }
  }

  Future<void> _showAddSubscriptionDialog(
    BuildContext context,
    MeshDevice device,
  ) async {
    final bloc = context.read<provisioner.ProvisionerBloc>();
    final others = bloc.state.provisionedDevices
        .where((d) => d.address != device.address)
        .toList();
    final selected = <int>{};
    var includeSelf = false;

    final result = await showDialog<List<int>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Link Device'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  CheckboxListTile(
                    title: const Text('This device'),
                    subtitle: Text('Group: ${device.groupAddressHex}'),
                    value: includeSelf,
                    onChanged: (v) => setState(() => includeSelf = v ?? false),
                  ),
                  ...others.map(
                    (d) => CheckboxListTile(
                      title: Text(d.label ?? d.addressHex),
                      subtitle: Text('Group: ${d.groupAddressHex}'),
                      secondary: IconButton(
                        icon: const Icon(Icons.lightbulb),
                        tooltip: 'Identify',
                        onPressed: () => _executeCommand(
                          context,
                          'mesh/dali_lc/identify/set ${d.addressHex} 5 3000',
                          stateKey: 'identify_set_${d.address}',
                        ),
                      ),
                      value: selected.contains(d.address),
                      onChanged: (v) => setState(() {
                        if (v ?? false) {
                          selected.add(d.address);
                        } else {
                          selected.remove(d.address);
                        }
                      }),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: (selected.isEmpty && !includeSelf)
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          <int>[
                            if (includeSelf) device.groupAddress,
                            ...selected
                                .map((addr) => others
                                    .firstWhere((d) => d.address == addr)
                                    .groupAddress)
                          ],
                        ),
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && mounted) {
      bloc.add(provisioner.AddSubscriptions(device.address, result));
    }
  }

  /// Manage which devices are subscribed to [device]'s group.
  Future<void> _showManageLinksDialog(
    BuildContext context,
    MeshDevice device,
  ) async {
    final bloc = context.read<provisioner.ProvisionerBloc>();
    final all = bloc.state.provisionedDevices;
    final group = device.groupAddress;

    // Fetch current subscriptions for all devices in parallel.
    final subs = await Future.wait(
        all.map((d) => bloc.fetchSubscriptions(d.address)));

    final initial = <int, bool>{};
    for (var i = 0; i < all.length; i++) {
      final d = all[i];
      initial[d.address] =
          d.address == device.address || subs[i].contains(group);
    }

    final selections = Map<int, bool>.from(initial);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Links for ${device.groupAddressHex}'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: all.map((d) {
                  final value = selections[d.address] ?? false;
                  return CheckboxListTile(
                    title: Text(d.label ?? d.addressHex),
                    subtitle: Text('Group: ${d.groupAddressHex}'),
                    value: value,
                    onChanged: d.address == device.address
                        ? null
                        : (v) => setState(() {
                              selections[d.address] = v ?? false;
                            }),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      for (final d in all) {
        final before = initial[d.address] ?? false;
        final after = selections[d.address] ?? false;
        if (after && !before) {
          bloc.add(provisioner.AddSubscriptions(d.address, [group]));
        } else if (!after && before) {
          bloc.add(provisioner.RemoveSubscription(d.address, group));
        }
      }
    }
  }

}

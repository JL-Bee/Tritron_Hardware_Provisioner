// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/provisioner_bloc.dart' as provisioner;
import '../protocols/rtm_console_protocol.dart';
import '../widgets/error_notification.dart';
import '../widgets/bloc_console_widget.dart';
import '../models/serial_port_info.dart';
import '../models/mesh_device.dart';
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
        if (!cleanResponse.contains('$error') && !cleanResponse.contains('$ok')) {
          setState(() {
            _commandResults['Device Label'] = cleanResponse;
            _commandStates[key] = CommandState(
              status: CommandStatus.success,
              timestamp: DateTime.now(),
            );
          });
          _clearStateAfterDelay(key);
        }
      } else if (key.contains('dali_idle_get')) {
        if (cleanResponse.contains(',')) {
          setState(() {
            _commandResults['DALI Idle Config'] = cleanResponse;
            _commandStates[key] = CommandState(
              status: CommandStatus.success,
              timestamp: DateTime.now(),
            );
          });
          _clearStateAfterDelay(key);
        }
      } else if (key.contains('dali_trigger_get')) {
        if (cleanResponse.contains(',') && cleanResponse.split(',').length == 4) {
          setState(() {
            _commandResults['DALI Trigger Config'] = cleanResponse;
            _commandStates[key] = CommandState(
              status: CommandStatus.success,
              timestamp: DateTime.now(),
            );
          });
          _clearStateAfterDelay(key);
        }
      } else if (key.contains('dali_identify_get')) {
        if (RegExp(r'^\d+$').hasMatch(cleanResponse)) {
          setState(() {
            _commandResults['DALI Identify Time'] = cleanResponse;
            _commandStates[key] = CommandState(
              status: CommandStatus.success,
              timestamp: DateTime.now(),
            );
          });
          _clearStateAfterDelay(key);
        }
      } else if (key.contains('dali_override_get')) {
        if (cleanResponse.contains(',') && cleanResponse.split(',').length == 3) {
          setState(() {
            _commandResults['DALI Override'] = cleanResponse;
            _commandStates[key] = CommandState(
              status: CommandStatus.success,
              timestamp: DateTime.now(),
            );
          });
          _clearStateAfterDelay(key);
        }
      } else if (key.contains('radar_cfg_get')) {
        if (cleanResponse.contains(',') && cleanResponse.split(',').length == 4) {
          setState(() {
            _commandResults['Radar Config'] = cleanResponse;
            _commandStates[key] = CommandState(
              status: CommandStatus.success,
              timestamp: DateTime.now(),
            );
          });
          _clearStateAfterDelay(key);
        }
      } else if (key.contains('radar_enable_get')) {
        if (RegExp(r'^[01]$').hasMatch(cleanResponse)) {
          setState(() {
            _commandResults['Radar Enable'] = cleanResponse == '1' ? 'Enabled' : 'Disabled';
            _commandStates[key] = CommandState(
              status: CommandStatus.success,
              timestamp: DateTime.now(),
            );
          });
          _clearStateAfterDelay(key);
        }
      }

      // Check for errors
      if (cleanResponse == '$error') {
        setState(() {
          _commandStates[key] = CommandState(
            status: CommandStatus.failure,
            timestamp: DateTime.now(),
          );
        });
        _clearStateAfterDelay(key);
      }
    }
  });
}

void _clearStateAfterDelay(String key) {
  Timer(const Duration(seconds: 2), () {
    if (mounted) {
      setState(() {
        _commandStates.remove(key);
      });
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
      context.read<provisioner.ProvisionerBloc>().add(provisioner.ConnectToPort(nrf52Port));
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
            title: const Text('Bluetooth Mesh Provisioner'),
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
        if (state.foundUuids.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Unprovisioned Devices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
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
                      : () => context.read<provisioner.ProvisionerBloc>().add(provisioner.ScanDevices()),
                ),
              ],
            ),
          ),
          ...state.foundUuids.map((uuid) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.bluetooth),
              ),
              title: const SelectableText('New Device'),
              subtitle: Row(
                children: [
                  const Text('UUID: '),
                  Expanded(
                    child: SelectableText(
                      uuid,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
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
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      context
                          .read<provisioner.ProvisionerBloc>()
                          .add(provisioner.SendConsoleCommand(
                              'mesh/device/identify $uuid'));
                    },
                    child: const Text('Identify'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: state.isProvisioning && state.provisioningUuid == uuid
                        ? null
                        : () => context.read<provisioner.ProvisionerBloc>().add(provisioner.ProvisionDevice(uuid)),
                    child: state.isProvisioning && state.provisioningUuid == uuid
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
              ),
            ),
          )),
          if (state.foundUuids.isNotEmpty)
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
            child: Center(
              child: Text('No provisioned devices'),
            ),
          )
        else
          ...state.provisionedDevices.map((device) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: SelectableText(
                  device.address.toRadixString(16).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              title: SelectableText('Device ${device.addressHex}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Group: '),
                      SelectableText(
                        device.groupAddressHex,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('UUID: '),
                      Expanded(
                        child: SelectableText(
                          device.uuid,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      context.read<provisioner.ProvisionerBloc>().add(provisioner.SelectDevice(device));
                      _tabController.animateTo(1);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmUnprovision(context, device),
                    color: Colors.red,
                  ),
                ],
              ),
              onTap: () {
                context.read<provisioner.ProvisionerBloc>().add(provisioner.SelectDevice(device));
                _tabController.animateTo(1);
              },
            ),
          )),
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
                  _buildInfoRow('Address', device.addressHex),
                  _buildInfoRow('Group Address', device.groupAddressHex),
                  _buildInfoRow('UUID', device.uuid),
                  if (device.label != null)
                    _buildInfoRow('Label', device.label!),
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
                  child: const Text(
                    'Device Resources',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),

                // Resource Table
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(3),
                    2: FlexColumnWidth(1),
                    3: FlexColumnWidth(2),
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
                              'mesh/device/label/get ${device.addressHex}',
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
                    ),
                    _buildResourceRow(
                      context,
                      'identify',
                      'Physical Identify',
                      'W',
                      [
                        Tooltip(
                          message: 'Make the device identify itself through the health model.\n'
                                  '0 = off, 1-255 = duration in seconds',
                          child: _buildActionButton(
                            context,
                            'SET',
                            Icons.lightbulb,
                            () => _showIdentifyDialog(context, device),
                            stateKey: 'identify_set_${device.address}',
                          ),
                        ),
                      ],
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
                    ),

                    // DALI Light Control Section
                    _buildSectionHeader(context, 'DALI Light Control'),
                    _buildResourceRow(
                      context,
                      'idle_cfg',
                      'Idle Configuration',
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
                              'mesh/dali_lc/idle_cfg/get ${device.addressHex}',
                              stateKey: 'dali_idle_get_${device.address}',
                            ),
                            stateKey: 'dali_idle_get_${device.address}',
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Set the idle state configuration.\n'
                                  'Arc: light level in idle state (0-254)\n'
                                  'Fade: transition time to idle state',
                          child: _buildActionButton(
                            context,
                            'SET',
                            Icons.settings,
                            () => _showDaliIdleConfigDialog(context, device),
                            stateKey: 'dali_idle_set_${device.address}',
                          ),
                        ),
                      ],
                    ),
                    _buildResourceRow(
                      context,
                      'trigger_cfg',
                      'Trigger Configuration',
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
                              'mesh/dali_lc/trigger_cfg/get ${device.addressHex}',
                              stateKey: 'dali_trigger_get_${device.address}',
                            ),
                            stateKey: 'dali_trigger_get_${device.address}',
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Configure trigger behavior (e.g., motion sensor).\n'
                                  'Arc: light level when triggered (0-254)\n'
                                  'Fade in/out: transition times\n'
                                  'Hold: seconds to stay in trigger state (0=disabled)',
                          child: _buildActionButton(
                            context,
                            'SET',
                            Icons.settings,
                            () => _showDaliTriggerConfigDialog(context, device),
                            stateKey: 'dali_trigger_set_${device.address}',
                          ),
                        ),
                      ],
                    ),
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
                              'mesh/dali_lc/identify/get ${device.addressHex}',
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
                              'mesh/dali_lc/override/get ${device.addressHex}',
                              stateKey: 'dali_override_get_${device.address}',
                            ),
                            stateKey: 'dali_override_get_${device.address}',
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Manually override the light level.\n'
                                  'Arc: override light level (0-254)\n'
                                  'Fade: transition time\n'
                                  'Duration: 0=off, 1-65534=seconds, 65535=until reboot',
                          child: _buildActionButton(
                            context,
                            'SET',
                            Icons.pan_tool,
                            () => _showDaliOverrideDialog(context, device),
                            stateKey: 'dali_override_set_${device.address}',
                          ),
                        ),
                      ],
                    ),

                    // Radar Control Section
                    _buildSectionHeader(context, 'Radar Control'),
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
                              'mesh/radar/cfg/get ${device.addressHex}',
                              stateKey: 'radar_cfg_get_${device.address}',
                            ),
                            stateKey: 'radar_cfg_get_${device.address}',
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Configure radar sensor parameters.\n'
                                  'Threshold: voltage from baseline (0-1650mV)\n'
                                  'Cross count: samples needed for detection (1-500)\n'
                                  'Sample interval: time between samples (1-2047ms)\n'
                                  'Buffer depth: number of samples (0-500)',
                          child: _buildActionButton(
                            context,
                            'SET',
                            Icons.settings,
                            () => _showRadarConfigDialog(context, device),
                            stateKey: 'radar_cfg_set_${device.address}',
                          ),
                        ),
                      ],
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
                              'mesh/radar/enable/get ${device.addressHex}',
                              stateKey: 'radar_enable_get_${device.address}',
                            ),
                            stateKey: 'radar_enable_get_${device.address}',
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Enable or disable the radar sensor.\n'
                                  'When disabled, no motion events are published',
                          child: _buildActionButton(
                            context,
                            'SET',
                            Icons.power_settings_new,
                            () => _showRadarEnableDialog(context, device),
                            stateKey: 'radar_enable_set_${device.address}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Retrieved Values Display
          if (_commandResults.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Retrieved Values',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            setState(() {
                              _commandResults.clear();
                            });
                          },
                          tooltip: 'Clear values',
                        ),
                      ],
                    ),
                    const Divider(),
                    ..._commandResults.entries.map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 200,
                            child: Text(
                              '${entry.key}:',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              entry.value,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ),
                        ],
                      ),
                    )).toList(),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Current Subscriptions Display
          if (state.selectedDeviceSubscriptions.isNotEmpty) ...[
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
                        const SizedBox(width: 16),
                        Tooltip(
                          message: 'Group addresses this device is subscribed to.\n'
                                  'The device will respond to messages sent to these addresses.',
                          child: Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: state.selectedDeviceSubscriptions.map((addr) => Chip(
                        label: Text(
                          '0x${addr.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        deleteIcon: addr == device.groupAddress ? null : const Icon(Icons.close, size: 18),
                        onDeleted: addr == device.groupAddress ? null : () {
                          _executeCommand(
                            context,
                            'mesh/device/sub/remove ${device.addressHex} 0x${addr.toRadixString(16)} 3000',
                            stateKey: 'sub_remove_${device.address}_$addr',
                          );
                          // Refresh subscriptions after removal
                          Future.delayed(const Duration(seconds: 1), () {
                            if (mounted) {
                              context.read<provisioner.ProvisionerBloc>().add(
                                provisioner.SelectDevice(device),
                              );
                            }
                          });
                        },
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// Helper method to build section headers
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

// Helper method to execute commands
// Helper method to execute commands with state tracking
void _executeCommand(BuildContext context, String command, {String? stateKey}) {
  // Generate a state key if not provided
  final key = stateKey ?? command;

  // Update state to loading
  setState(() {
    _commandStates[key] = CommandState(status: CommandStatus.loading);
  });

  // Send command
  context.read<provisioner.ProvisionerBloc>().add(
    provisioner.SendConsoleCommand(command),
  );

  // Set up a timer to check for response
  Timer(const Duration(seconds: 3), () {
    if (mounted && _commandStates[key]?.status == CommandStatus.loading) {
      setState(() {
        _commandStates[key] = CommandState(
          status: CommandStatus.failure,
          timestamp: DateTime.now(),
        );
      });

      // Clear the state after 2 seconds
      Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _commandStates.remove(key);
          });
        }
      });
    }
  });
}

// Dialog methods
Future<void> _showIdentifyDialog(BuildContext context, MeshDevice device) async {
  final durationController = TextEditingController(text: '10');

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Device Identify'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Set identify duration in seconds:'),
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
    final duration = int.tryParse(durationController.text) ?? 0;
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: arcController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Idle Arc Level',
              hintText: '0-254',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: fadeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Fade Time',
              hintText: '0-30 (see fade time table)',
            ),
          ),
        ],
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
  final holdTimeController = TextEditingController(text: '60');

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('DALI Trigger Configuration'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: arcController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Trigger Arc Level',
                hintText: '0-254',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: fadeInController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Fade In Time',
                hintText: '0-30',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: fadeOutController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Fade Out Time',
                hintText: '0-30',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: holdTimeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Hold Time (seconds)',
                hintText: '0-65535',
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
    final arc = int.tryParse(arcController.text) ?? 254;
    final fadeIn = int.tryParse(fadeInController.text) ?? 0;
    final fadeOut = int.tryParse(fadeOutController.text) ?? 7;
    final holdTime = int.tryParse(holdTimeController.text) ?? 60;
    _executeCommand(context, 'mesh/dali_lc/trigger_cfg/set ${device.addressHex} $arc $fadeIn $fadeOut $holdTime 3000');
  }
}

Future<void> _showDaliIdentifyDialog(BuildContext context, MeshDevice device) async {
  final durationController = TextEditingController(text: '60');

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('DALI Light Identify'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Set light identify duration:'),
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
    final duration = int.tryParse(durationController.text) ?? 0;
    _executeCommand(context, 'mesh/dali_lc/identify/set ${device.addressHex} $duration 3000');
  }
}

Future<void> _showDaliOverrideDialog(BuildContext context, MeshDevice device) async {
  final arcController = TextEditingController(text: '254');
  final fadeController = TextEditingController(text: '0');
  final durationController = TextEditingController(text: '60');

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('DALI Manual Override'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: arcController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Arc Level',
              hintText: '0-254',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: fadeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Fade Time',
              hintText: '0-30',
            ),
          ),
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
    final duration = int.tryParse(durationController.text) ?? 60;
    _executeCommand(context, 'mesh/dali_lc/override/set ${device.addressHex} $arc $fade $duration 3000');
  }
}

Future<void> _showRadarConfigDialog(BuildContext context, MeshDevice device) async {
  final bandController = TextEditingController(text: '210');
  final crossController = TextEditingController(text: '31');
  final intervalController = TextEditingController(text: '5');
  final depthController = TextEditingController(text: '500');

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Radar Configuration'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: bandController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Threshold Band (mV)',
                hintText: '0-1650',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: crossController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cross Count Threshold',
                hintText: '1-500',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: intervalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sample Interval (ms)',
                hintText: '1-2047',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: depthController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Buffer Depth',
                hintText: '0-500',
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
      content: StatefulBuilder(
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
        ),
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
    context.read<provisioner.ProvisionerBloc>().add(
      provisioner.SendConsoleCommand(
        'mesh/device/label/set ${device.addressHex} $label',
      ),
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
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'remove'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove from DB'),
          ),
        ],
      ),
    );

    if (action != null && mounted) {
      if (action == 'reset') {
        context.read<provisioner.ProvisionerBloc>().add(provisioner.UnprovisionDevice(device));
      } else if (action == 'remove') {
        // Just remove from database without resetting the device
        context.read<provisioner.ProvisionerBloc>().add(
          provisioner.SendConsoleCommand('mesh/device/remove 0x${device.address.toRadixString(16)}'),
        );
        // Refresh list after removal
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            context.read<provisioner.ProvisionerBloc>().add(provisioner.RefreshDeviceList());
          }
        });
      }
    }
  }

  Future<void> _showAddSubscriptionDialog(BuildContext context, MeshDevice device) async {
    final controller = TextEditingController();
    final groupAddr = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Group Subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter group address to subscribe to:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Group Address',
                hintText: 'C000-FEFF',
                prefixText: '0x',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(4),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final hex = controller.text;
              if (hex.length == 4) {
                final addr = int.tryParse(hex, radix: 16);
                if (addr != null && addr >= 0xC000 && addr <= 0xFEFF) {
                  Navigator.pop(dialogContext, addr);
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (groupAddr != null && mounted) {
      context.read<provisioner.ProvisionerBloc>().add(provisioner.AddSubscription(device.address, groupAddr));
    }
  }
}

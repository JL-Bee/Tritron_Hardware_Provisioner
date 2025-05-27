// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/provisioner_bloc.dart' as provisioner;
import '../protocols/rtm_console_protocol.dart';
import '../widgets/error_notification.dart';
import '../widgets/bloc_console_widget.dart';
import '../models/serial_port_info.dart';
import '../services/serial_port_service.dart' as serial;
import 'action_history_screen.dart';
import 'provisioner_connection_screen.dart';

class BlocMainScreen extends StatefulWidget {
  const BlocMainScreen({super.key});

  @override
  State<BlocMainScreen> createState() => _BlocMainScreenState();
}

class _BlocMainScreenState extends State<BlocMainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _autoConnect();
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
            actions: const [],
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
                            Icon(Icons.error, color: Colors.red, size: 16)
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
              _buildCurrentAction(state),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Group Subscriptions',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => _showAddSubscriptionDialog(context, device),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (state.selectedDeviceSubscriptions.isEmpty)
                    const Text('No subscriptions')
                  else
                    ...state.selectedDeviceSubscriptions.map((addr) => ListTile(
                      leading: const Icon(Icons.group),
                      title: SelectableText(
                        '0x${addr.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      trailing: addr == device.groupAddress
                          ? const Chip(label: Text('Own Group'))
                          : IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => context.read<provisioner.ProvisionerBloc>().add(
                                provisioner.RemoveSubscription(device.address, addr),
                              ),
                              color: Colors.red,
                            ),
                    )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

  Future<void> _confirmUnprovision(BuildContext context, MeshDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unprovision Device'),
        content: Text('Remove device ${device.addressHex} from the network?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Unprovision'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      context.read<provisioner.ProvisionerBloc>().add(provisioner.UnprovisionDevice(device));
    }
  }

  Future<void> _showAddSubscriptionDialog(BuildContext context, MeshDevice device) async {
    final controller = TextEditingController();
    final groupAddr = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final hex = controller.text;
              if (hex.length == 4) {
                final addr = int.tryParse(hex, radix: 16);
                if (addr != null && addr >= 0xC000 && addr <= 0xFEFF) {
                  Navigator.pop(context, addr);
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

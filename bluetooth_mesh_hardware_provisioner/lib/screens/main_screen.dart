// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/provisioner_bloc.dart';
import '../widgets/error_notification.dart';
import '../widgets/bloc_console_widget.dart';
import '../models/serial_port_info.dart';
import '../services/serial_port_service.dart';
import 'action_history_screen.dart';

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
    _tabController = TabController(length: 3, vsync: this);
    _autoConnect();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _autoConnect() async {
    final service = SerialPortService();
    final ports = await service.scanForPorts();

    if (ports.isNotEmpty) {
      final nrf52Port = ports.firstWhere(
        (port) => port.isNRF52Device,
        orElse: () => ports.first,
      );

      if (!mounted) return;
      context.read<ProvisionerBloc>().add(ConnectToPort(nrf52Port));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProvisionerBloc, ProvisionerState>(
      builder: (context, state) {
        if (state.connectionStatus != ConnectionStatus.connected) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (state.connectionStatus == ConnectionStatus.connecting)
                    const CircularProgressIndicator(),
                  if (state.connectionStatus == ConnectionStatus.error)
                    const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    state.connectionStatus == ConnectionStatus.connecting
                        ? 'Connecting to NRF52 DK...'
                        : state.connectionStatus == ConnectionStatus.error
                            ? 'Connection failed'
                            : 'Not connected',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please connect your device via USB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (state.connectionStatus == ConnectionStatus.error) ...[
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

        return Scaffold(
          appBar: AppBar(
            title: const Text('Bluetooth Mesh Provisioner'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Devices', icon: Icon(Icons.devices)),
                Tab(text: 'Details', icon: Icon(Icons.info)),
                Tab(text: 'Console', icon: Icon(Icons.terminal)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.history),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ActionHistoryScreen(),
                    ),
                  );
                },
                tooltip: 'Action History',
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  _buildStatusBar(state),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDevicesTab(state),
                        _buildDetailsTab(state),
                        const BlocConsoleWidget(),
                      ],
                    ),
                  ),
                ],
              ),
              // Error notification overlay
              const ErrorNotification(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBar(ProvisionerState state) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Row(
        children: [
          const Icon(Icons.usb, size: 20),
          const SizedBox(width: 8),
          Text(state.connectedPort?.displayName ?? 'Connected'),
          const Spacer(),
          if (state.isProvisioning) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                state.provisioningStatus,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
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
        ],
      ),
    );
  }

  Widget _buildDevicesTab(ProvisionerState state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<ProvisionerBloc>()
          ..add(ScanDevices())
          ..add(RefreshDeviceList());
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
                        : () => context.read<ProvisionerBloc>().add(ScanDevices()),
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
                title: const Text('New Device'),
                subtitle: Text('UUID: $uuid'),
                trailing: FilledButton(
                  onPressed: state.isProvisioning
                      ? null
                      : () => context.read<ProvisionerBloc>().add(ProvisionDevice(uuid)),
                  child: const Text('Provision'),
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
                  child: Text(
                    device.address.toRadixString(16).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                title: Text('Device ${device.addressHex}'),
                subtitle: Text(
                  'Group: ${device.groupAddressHex}\nUUID: ${device.uuid}',
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () {
                        context.read<ProvisionerBloc>().add(SelectDevice(device));
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
                  context.read<ProvisionerBloc>().add(SelectDevice(device));
                  _tabController.animateTo(1);
                },
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(ProvisionerState state) {
    if (state.selectedDevice == null) {
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
                  _buildInfoRow('Address', state.selectedDevice!.addressHex),
                  _buildInfoRow('Group Address', state.selectedDevice!.groupAddressHex),
                  _buildInfoRow('UUID', state.selectedDevice!.uuid),
                  if (state.selectedDevice!.label != null)
                    _buildInfoRow('Label', state.selectedDevice!.label!),
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
                        onPressed: () => _showAddSubscriptionDialog(context, state.selectedDevice!),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (state.selectedDeviceSubscriptions.isEmpty)
                    const Text('No subscriptions')
                  else
                    ...state.selectedDeviceSubscriptions.map((addr) => ListTile(
                      leading: const Icon(Icons.group),
                      title: Text('0x${addr.toRadixString(16).padLeft(4, '0').toUpperCase()}'),
                      trailing: addr == state.selectedDevice!.groupAddress
                          ? const Chip(label: Text('Own Group'))
                          : IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => context.read<ProvisionerBloc>().add(
                                RemoveSubscription(state.selectedDevice!.address, addr),
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
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
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
      context.read<ProvisionerBloc>().add(UnprovisionDevice(device));
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
      context.read<ProvisionerBloc>().add(AddSubscription(device.address, groupAddr));
    }
  }
}

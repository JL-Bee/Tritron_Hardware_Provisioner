// lib/screens/provisioner_connection_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/provisioner_bloc.dart' as provisioner;
import '../models/serial_port_info.dart';
import '../services/serial_port_service.dart' as serial;

class ProvisionerConnectionScreen extends StatefulWidget {
  const ProvisionerConnectionScreen({super.key});

  @override
  State<ProvisionerConnectionScreen> createState() => _ProvisionerConnectionScreenState();
}

class _ProvisionerConnectionScreenState extends State<ProvisionerConnectionScreen> {
  final serial.SerialPortService _service = serial.SerialPortService();
  List<SerialPortInfo> _ports = [];
  SerialPortInfo? _selectedPort;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scanPorts();
  }

  Future<void> _scanPorts() async {
    final ports = await _service.scanForPorts();
    if (!mounted) return;
    setState(() {
      _ports = ports;
      _selectedPort = ports.isNotEmpty ? ports.first : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provisioner Connection'),
      ),
      body: BlocBuilder<provisioner.ProvisionerBloc, provisioner.ProvisionerState>(
        builder: (context, state) {
          final status = state.connectionStatus;
          final portName = state.connectedPort?.portName ?? 'N/A';
          Color indicatorColor;
          switch (status) {
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

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Provisioner ($portName)'),
                    const SizedBox(width: 8),
                    Icon(Icons.circle, color: indicatorColor, size: 12),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_ports.isEmpty)
                  const Text('No serial ports found')
                else
                  DropdownButton<SerialPortInfo>(
                    value: _selectedPort,
                    hint: const Text('Select Port'),
                    items: _ports
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _selectedPort = val),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: status == provisioner.ConnectionStatus.connected
                          ? null
                          : _selectedPort == null
                              ? null
                              : () => context
                                  .read<provisioner.ProvisionerBloc>()
                                  .add(provisioner.ConnectToPort(_selectedPort!)),
                      child: const Text('Connect'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: status == provisioner.ConnectionStatus.connected
                          ? () => context
                              .read<provisioner.ProvisionerBloc>()
                              .add(provisioner.Disconnect())
                          : null,
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

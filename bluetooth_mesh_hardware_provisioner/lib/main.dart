import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:typed_data';

void main() {
  runApp(const TritronProvisionerApp());
}

class TritronProvisionerApp extends StatelessWidget {
  const TritronProvisionerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tritron Hardware Provisioner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SerialPortScannerPage(),
    );
  }
}

class SerialPortScannerPage extends StatefulWidget {
  const SerialPortScannerPage({super.key});

  @override
  State<SerialPortScannerPage> createState() => _SerialPortScannerPageState();
}

class _SerialPortScannerPageState extends State<SerialPortScannerPage> {
  final SerialPortService _serialService = SerialPortService();
  List<SerialPortInfo> _availablePorts = [];
  SerialPortInfo? _selectedPort;
  bool _isScanning = false;
  bool _isConnected = false;
  String _connectionStatus = 'Disconnected';
  final List<String> _receivedData = [];
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _startPeriodicScan();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _serialService.disconnect();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    // Request necessary permissions for different platforms
    if (Theme.of(context).platform == TargetPlatform.android) {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
    }
  }

  void _startPeriodicScan() {
    _scanForPorts();
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isConnected) {
        _scanForPorts();
      }
    });
  }

  Future<void> _scanForPorts() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
    });

    try {
      final ports = await _serialService.scanForPorts();
      setState(() {
        _availablePorts = ports;
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _connectionStatus = 'Error scanning: $e';
      });
    }
  }

  Future<void> _connectToPort(SerialPortInfo portInfo) async {
    setState(() {
      _connectionStatus = 'Connecting...';
    });

    try {
      await _serialService.connect(portInfo.portName);

      setState(() {
        _isConnected = true;
        _selectedPort = portInfo;
        _connectionStatus = 'Connected to ${portInfo.portName}';
        _receivedData.clear();
      });

      // Listen for incoming data
      _serialService.dataStream.listen((data) {
        setState(() {
          _receivedData.add('Received: $data');
          if (_receivedData.length > 100) {
            _receivedData.removeAt(0);
          }
        });
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _connectionStatus = 'Connection failed: $e';
      });
    }
  }

  Future<void> _disconnect() async {
    await _serialService.disconnect();
    setState(() {
      _isConnected = false;
      _selectedPort = null;
      _connectionStatus = 'Disconnected';
      _receivedData.clear();
    });
  }

  Future<void> _sendTestCommand() async {
    if (_isConnected) {
      try {
        await _serialService.sendCommand('TEST_COMMAND\n');
        setState(() {
          _receivedData.add('Sent: TEST_COMMAND');
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send command: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tritron Hardware Provisioner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
            onPressed: _isScanning ? null : _scanForPorts,
            tooltip: 'Scan for ports',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          Expanded(
            child: Row(
              children: [
                // Port list panel
                Expanded(
                  flex: 2,
                  child: _buildPortListPanel(),
                ),
                // Connection details panel
                Expanded(
                  flex: 3,
                  child: _buildConnectionPanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _isConnected ? Colors.green.shade100 : Colors.grey.shade200,
      child: Row(
        children: [
          Icon(
            _isConnected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: _isConnected ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            _connectionStatus,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _isConnected ? Colors.green.shade800 : Colors.grey.shade800,
            ),
          ),
          const Spacer(),
          if (_isScanning)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildPortListPanel() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Icon(Icons.usb),
                const SizedBox(width: 8),
                const Text(
                  'Available Ports',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${_availablePorts.length} found',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Expanded(
            child: _availablePorts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.usb_off, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No serial ports found',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Connect your NRF52 DK device',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _availablePorts.length,
                    itemBuilder: (context, index) {
                      final port = _availablePorts[index];
                      final isSelected = _selectedPort?.portName == port.portName;
                      final isNRF52 = port.description?.contains('nRF52') ?? false ||
                          port.manufacturer?.contains('Nordic') ?? false ||
                          port.vendorId == 0x1366; // Nordic Semi VID

                      return ListTile(
                        leading: Icon(
                          Icons.usb,
                          color: isNRF52 ? Colors.blue : Colors.grey,
                        ),
                        title: Text(port.portName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (port.description != null)
                              Text(port.description!),
                            if (port.manufacturer != null)
                              Text('Manufacturer: ${port.manufacturer}'),
                            if (port.productId != null || port.vendorId != null)
                              Text('VID:PID = ${port.vendorId?.toRadixString(16).padLeft(4, '0') ?? '????'}:'
                                  '${port.productId?.toRadixString(16).padLeft(4, '0') ?? '????'}'),
                            if (isNRF52)
                              const Text(
                                'NRF52 Device Detected',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                        selected: isSelected,
                        onTap: _isConnected
                            ? null
                            : () => _connectToPort(port),
                        tileColor: isSelected ? Colors.blue.shade50 : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal),
              const SizedBox(width: 8),
              const Text(
                'Connection Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_isConnected) ...[
                ElevatedButton.icon(
                  onPressed: _sendTestCommand,
                  icon: const Icon(Icons.send),
                  label: const Text('Send Test'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.close),
                  label: const Text('Disconnect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (_selectedPort != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('Port', _selectedPort!.portName),
                    if (_selectedPort!.description != null)
                      _buildInfoRow('Description', _selectedPort!.description!),
                    if (_selectedPort!.manufacturer != null)
                      _buildInfoRow('Manufacturer', _selectedPort!.manufacturer!),
                    if (_selectedPort!.serialNumber != null)
                      _buildInfoRow('Serial Number', _selectedPort!.serialNumber!),
                    _buildInfoRow('Baud Rate', '115200'),
                    _buildInfoRow('Data Bits', '8'),
                    _buildInfoRow('Stop Bits', '1'),
                    _buildInfoRow('Parity', 'None'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'Data Log:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: _receivedData.isEmpty
                  ? Center(
                      child: Text(
                        _isConnected
                            ? 'Waiting for data...'
                            : 'Connect to a device to see data',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: _receivedData.length,
                      itemBuilder: (context, index) {
                        final reversedIndex = _receivedData.length - 1 - index;
                        final data = _receivedData[reversedIndex];
                        final isSent = data.startsWith('Sent:');

                        return Text(
                          data,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: isSent ? Colors.blue.shade300 : Colors.green.shade300,
                          ),
                        );
                      },
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
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

// Serial Port Information Model
class SerialPortInfo {
  final String portName;
  final String? description;
  final String? manufacturer;
  final String? serialNumber;
  final int? vendorId;
  final int? productId;

  SerialPortInfo({
    required this.portName,
    this.description,
    this.manufacturer,
    this.serialNumber,
    this.vendorId,
    this.productId,
  });
}

// Serial Port Service
class SerialPortService {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamController<String>? _dataController;

  Stream<String> get dataStream => _dataController?.stream ?? const Stream.empty();

  Future<List<SerialPortInfo>> scanForPorts() async {
    final ports = <SerialPortInfo>[];

    for (final portName in SerialPort.availablePorts) {
      try {
        final port = SerialPort(portName);
        final config = SerialPortConfig();

        ports.add(SerialPortInfo(
          portName: portName,
          description: port.description,
          manufacturer: port.manufacturer,
          serialNumber: port.serialNumber,
          vendorId: port.vendorId,
          productId: port.productId,
        ));

        port.dispose();
      } catch (e) {
        // Skip ports that can't be accessed
        print('Error accessing port $portName: $e');
      }
    }

    return ports;
  }

  Future<void> connect(String portName) async {
    try {
      _port = SerialPort(portName);

      if (!_port!.openReadWrite()) {
        throw Exception('Failed to open port $portName');
      }

      // Configure port settings for NRF52 DK
      final config = SerialPortConfig()
        ..baudRate = 115200
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);

      _port!.config = config;

      // Set up data reader
      _reader = SerialPortReader(_port!);
      _dataController = StreamController<String>.broadcast();

      // Listen for incoming data
      _reader!.stream.listen((data) {
        final text = String.fromCharCodes(data);
        _dataController?.add(text);
      });
    } catch (e) {
      await disconnect();
      rethrow;
    }
  }

  Future<void> sendCommand(String command) async {
    if (_port == null || !_port!.isOpen) {
      throw Exception('Port is not connected');
    }

    final data = Uint8List.fromList(command.codeUnits);
    final bytesWritten = _port!.write(data);

    if (bytesWritten != data.length) {
      throw Exception('Failed to write all bytes');
    }
  }

  Future<void> disconnect() async {
    _reader?.close();
    _dataController?.close();
    _port?.close();
    _port?.dispose();

    _reader = null;
    _dataController = null;
    _port = null;
  }
}

// lib/services/serial_port_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../models/serial_port_info.dart';

/// Simplified serial port service that handles raw communication only
class SerialPortService {
  SerialPort? _port;
  StreamController<String>? _dataController;
  StreamController<SerialConnectionStatus>? _statusController;
  Timer? _readTimer;

  // Public streams
  Stream<String> get dataStream => _dataController?.stream ?? const Stream.empty();
  Stream<SerialConnectionStatus> get statusStream => _statusController?.stream ?? const Stream.empty();

  // Connection state
  bool get isConnected => _port != null && _port!.isOpen;
  String? get connectedPortName => _port?.name;

  // NRF52 configuration
  static const int defaultBaudRate = 115200;
  static const int readTimeout = 100; // ms

  SerialPortService() {
    _dataController = StreamController<String>.broadcast();
    _statusController = StreamController<SerialConnectionStatus>.broadcast();
  }

  /// Scan for available serial ports
  Future<List<SerialPortInfo>> scanForPorts() async {
    final ports = <SerialPortInfo>[];

    for (final portName in SerialPort.availablePorts) {
      try {
        final port = SerialPort(portName);

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

    // Sort to prioritize NRF52 devices
    ports.sort((a, b) {
      if (a.isNRF52Device && !b.isNRF52Device) return -1;
      if (!a.isNRF52Device && b.isNRF52Device) return 1;
      return a.portName.compareTo(b.portName);
    });

    return ports;
  }

  /// Connect to a serial port
  Future<void> connect(String portName, {int baudRate = defaultBaudRate}) async {
    try {
      // Clean up any existing connection
      await disconnect();

      _statusController?.add(SerialConnectionStatus.connecting);

      // Open the port
      _port = SerialPort(portName);

      if (!_port!.openReadWrite()) {
        throw SerialPortException('Failed to open port $portName');
      }

      // Configure the port
      final config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);

      _port!.config = config;

      _startReading();

      _statusController?.add(SerialConnectionStatus.connected);

    } catch (e) {
      _statusController?.add(SerialConnectionStatus.error);
      await disconnect();
      rethrow;
    }
  }

  /// Send data to the serial port
  Future<void> sendData(String data) async {
    if (!isConnected) {
      throw SerialPortException('Port is not connected');
    }

    try {
      final bytes = Uint8List.fromList(data.codeUnits);
      final written = _port!.write(bytes);

      if (written != bytes.length) {
        throw SerialPortException('Failed to write all bytes: $written/${bytes.length}');
      }

      // Ensure data is flushed
      _port!.drain();

    } catch (e) {
      print('Error sending data: $e');
      rethrow;
    }
  }

  /// Send raw bytes to the serial port
  Future<void> sendBytes(Uint8List bytes) async {
    if (!isConnected) {
      throw SerialPortException('Port is not connected');
    }

    try {
      final written = _port!.write(bytes);

      if (written != bytes.length) {
        throw SerialPortException('Failed to write all bytes: $written/${bytes.length}');
      }

      // Ensure data is flushed
      _port!.drain();

    } catch (e) {
      print('Error sending bytes: $e');
      rethrow;
    }
  }

  void _startReading() {
    _readTimer?.cancel();
    _readTimer = Timer.periodic(const Duration(milliseconds: readTimeout), (_) {
      if (!isConnected) return;
      try {
        final available = _port!.bytesAvailable;
        if (available > 0) {
          final bytes = _port!.read(available);
          if (bytes.isNotEmpty) {
            final text = String.fromCharCodes(bytes);
            print(
              'SerialPort: Received ${bytes.length} bytes: '
              '${text.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}',
            );
            _dataController?.add(text);
          }
        }
      } catch (e) {
        print('Serial read error: $e');
        _statusController?.add(SerialConnectionStatus.error);
        unawaited(disconnect());
      }
    });
  }

  /// Disconnect from the serial port
  Future<void> disconnect() async {
    try {
      // Stop background reader
      _readTimer?.cancel();
      _readTimer = null;

      // Close and dispose port
      if (_port != null) {
        _port!.close();
        _port!.dispose();
        _port = null;
      }

      _statusController?.add(SerialConnectionStatus.disconnected);

    } catch (e) {
      print('Error during disconnect: $e');
    }
  }

  /// Clean up resources
  void dispose() {
    disconnect();
    _dataController?.close();
    _statusController?.close();
  }
}

/// Connection status enum
enum SerialConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Serial port exception
class SerialPortException implements Exception {
  final String message;

  SerialPortException(this.message);

  @override
  String toString() => 'SerialPortException: $message';
}

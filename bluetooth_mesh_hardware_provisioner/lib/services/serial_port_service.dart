// lib/services/serial_port_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../models/serial_port_info.dart';

class SerialPortService {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamController<String>? _dataController;
  StreamController<ConnectionStatus>? _statusController;

  // Configuration for NRF52 DK communication
  static const int defaultBaudRate = 115200;
  static const int dataBits = 8;
  static const int stopBits = 1;

  Stream<String> get dataStream => _dataController?.stream ?? const Stream.empty();
  Stream<ConnectionStatus> get statusStream => _statusController?.stream ?? const Stream.empty();

  bool get isConnected => _port != null && _port!.isOpen;
  String? get connectedPortName => _port?.name;

  SerialPortService() {
    _statusController = StreamController<ConnectionStatus>.broadcast();
  }

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

    // Sort ports to prioritize NRF52 devices
    ports.sort((a, b) {
      if (a.isNRF52Device && !b.isNRF52Device) return -1;
      if (!a.isNRF52Device && b.isNRF52Device) return 1;
      return a.portName.compareTo(b.portName);
    });

    return ports;
  }

  Future<void> connect(String portName, {int baudRate = defaultBaudRate}) async {
    try {
      // Disconnect from any existing connection
      await disconnect();

      _statusController?.add(ConnectionStatus.connecting);

      _port = SerialPort(portName);

      if (!_port!.openReadWrite()) {
        throw SerialPortException('Failed to open port $portName');
      }

      // Configure port settings for NRF52 DK
      final config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = dataBits
        ..stopBits = stopBits
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);

      _port!.config = config;

      // Set up data reader
      _reader = SerialPortReader(_port!);
      _dataController = StreamController<String>.broadcast();

      // Listen for incoming data
      _reader!.stream.listen(
        (data) {
          final text = String.fromCharCodes(data);
          _dataController?.add(text);
        },
        onError: (error) {
          print('Serial port read error: $error');
          _statusController?.add(ConnectionStatus.error);
          disconnect();
        },
        onDone: () {
          print('Serial port reader done');
          _statusController?.add(ConnectionStatus.disconnected);
          disconnect();
        },
      );

      _statusController?.add(ConnectionStatus.connected);

      // Send initial handshake or identification command
      await sendCommand('AT\r\n'); // Common AT command for testing
    } catch (e) {
      _statusController?.add(ConnectionStatus.error);
      await disconnect();
      rethrow;
    }
  }

  Future<void> sendCommand(String command) async {
    if (_port == null || !_port!.isOpen) {
      throw SerialPortException('Port is not connected');
    }

    final data = Uint8List.fromList(command.codeUnits);
    final bytesWritten = _port!.write(data);

    if (bytesWritten != data.length) {
      throw SerialPortException('Failed to write all bytes');
    }
  }

  Future<void> sendBytes(Uint8List data) async {
    if (_port == null || !_port!.isOpen) {
      throw SerialPortException('Port is not connected');
    }

    final bytesWritten = _port!.write(data);

    if (bytesWritten != data.length) {
      throw SerialPortException('Failed to write all bytes');
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

    _statusController?.add(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _statusController?.close();
  }
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class SerialPortException implements Exception {
  final String message;

  SerialPortException(this.message);

  @override
  String toString() => 'SerialPortException: $message';
}

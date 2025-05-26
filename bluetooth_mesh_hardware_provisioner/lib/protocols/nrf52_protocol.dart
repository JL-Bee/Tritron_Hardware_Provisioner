// lib/protocols/nrf52_protocol.dart

import 'dart:convert';
import 'dart:typed_data';

/// Protocol handler for NRF52 DK communication
/// Implements a simple command-response protocol for mesh provisioning
class NRF52Protocol {
  static const String commandPrefix = 'CMD:';
  static const String responsePrefix = 'RSP:';
  static const String errorPrefix = 'ERR:';
  static const String eventPrefix = 'EVT:';

  // Command terminator
  static const String terminator = '\r\n';

  // Common commands
  static const String cmdPing = 'PING';
  static const String cmdGetInfo = 'GET_INFO';
  static const String cmdScanDevices = 'SCAN_DEVICES';
  static const String cmdProvisionDevice = 'PROVISION_DEVICE';
  static const String cmdGetMeshStatus = 'GET_MESH_STATUS';
  static const String cmdReset = 'RESET';

  /// Build a command string with proper formatting
  static String buildCommand(String command, [Map<String, dynamic>? params]) {
    final cmd = StringBuffer(commandPrefix);
    cmd.write(command);

    if (params != null && params.isNotEmpty) {
      cmd.write(':');
      cmd.write(jsonEncode(params));
    }

    cmd.write(terminator);
    return cmd.toString();
  }

  /// Parse a response from the NRF52 DK
  static ProtocolMessage? parseResponse(String data) {
    if (data.isEmpty) return null;

    // Remove terminator if present
    final cleanData = data.replaceAll(terminator, '');

    if (cleanData.startsWith(responsePrefix)) {
      return _parseMessage(cleanData.substring(responsePrefix.length), MessageType.response);
    } else if (cleanData.startsWith(errorPrefix)) {
      return _parseMessage(cleanData.substring(errorPrefix.length), MessageType.error);
    } else if (cleanData.startsWith(eventPrefix)) {
      return _parseMessage(cleanData.substring(eventPrefix.length), MessageType.event);
    }

    // Unknown format, return as raw data
    return ProtocolMessage(
      type: MessageType.raw,
      command: '',
      data: cleanData,
    );
  }

  static ProtocolMessage _parseMessage(String content, MessageType type) {
    final colonIndex = content.indexOf(':');

    if (colonIndex == -1) {
      // No data, just command
      return ProtocolMessage(
        type: type,
        command: content,
        data: null,
      );
    }

    final command = content.substring(0, colonIndex);
    final dataStr = content.substring(colonIndex + 1);

    // Try to parse as JSON
    dynamic data;
    try {
      data = jsonDecode(dataStr);
    } catch (e) {
      // Not JSON, keep as string
      data = dataStr;
    }

    return ProtocolMessage(
      type: type,
      command: command,
      data: data,
    );
  }

  /// Convert a provisioning configuration to bytes
  static Uint8List buildProvisioningData({
    required String deviceKey,
    required int unicastAddress,
    required String networkKey,
    String? deviceName,
  }) {
    final config = {
      'device_key': deviceKey,
      'unicast_addr': unicastAddress,
      'net_key': networkKey,
      if (deviceName != null) 'name': deviceName,
    };

    final jsonStr = jsonEncode(config);
    return Uint8List.fromList(utf8.encode(jsonStr));
  }
}

/// Message types in the protocol
enum MessageType {
  response,
  error,
  event,
  raw,
}

/// Parsed protocol message
class ProtocolMessage {
  final MessageType type;
  final String command;
  final dynamic data;

  ProtocolMessage({
    required this.type,
    required this.command,
    required this.data,
  });

  bool get isError => type == MessageType.error;
  bool get isResponse => type == MessageType.response;
  bool get isEvent => type == MessageType.event;

  @override
  String toString() {
    return 'ProtocolMessage{type: $type, command: $command, data: $data}';
  }
}

/// Device information from NRF52
class NRF52DeviceInfo {
  final String firmwareVersion;
  final String hardwareVersion;
  final String serialNumber;
  final bool meshEnabled;
  final int? nodeAddress;

  NRF52DeviceInfo({
    required this.firmwareVersion,
    required this.hardwareVersion,
    required this.serialNumber,
    required this.meshEnabled,
    this.nodeAddress,
  });

  factory NRF52DeviceInfo.fromJson(Map<String, dynamic> json) {
    return NRF52DeviceInfo(
      firmwareVersion: json['fw_version'] ?? 'Unknown',
      hardwareVersion: json['hw_version'] ?? 'Unknown',
      serialNumber: json['serial'] ?? 'Unknown',
      meshEnabled: json['mesh_enabled'] ?? false,
      nodeAddress: json['node_addr'],
    );
  }
}

/// Mesh device found during scanning
class MeshDevice {
  final String uuid;
  final int rssi;
  final String? name;
  final bool provisioned;

  MeshDevice({
    required this.uuid,
    required this.rssi,
    this.name,
    required this.provisioned,
  });

  factory MeshDevice.fromJson(Map<String, dynamic> json) {
    return MeshDevice(
      uuid: json['uuid'],
      rssi: json['rssi'],
      name: json['name'],
      provisioned: json['provisioned'] ?? false,
    );
  }
}

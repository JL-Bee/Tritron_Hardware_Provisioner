// lib/protocols/rtm_console_protocol.dart

import 'dart:async';

/// RTM Console protocol handler for the NRF52 provisioner
class RTMConsoleProtocol {
  static const String responsePrefix = '~>';
  static const String okSuffix = '~>\$ok';
  static const String terminator = '\r\n';

  // Mesh commands
  static const String cmdFactoryReset = 'mesh/factory_reset';
  static const String cmdScanGet = 'mesh/provision/scan/get';
  static const String cmdProvision = 'mesh/provision/provision'; // + uuid
  static const String cmdProvisionResult = 'mesh/provision/result/get';
  static const String cmdProvisionStatus = 'mesh/provision/status/get';
  static const String cmdLastAddr = 'mesh/provision/last_addr/get';
  static const String cmdDeviceReset = 'mesh/device/reset'; // + addr
  static const String cmdDeviceRemove = 'mesh/device/remove'; // + addr
  static const String cmdDeviceList = 'mesh/device/list';
  static const String cmdDeviceLabel = 'mesh/device/label'; // get/set + addr [label]
  static const String cmdSubAdd = 'mesh/device/sub/add'; // + node_addr + sub_addr
  static const String cmdSubRemove = 'mesh/device/sub/remove'; // + node_addr + sub_addr
  static const String cmdSubReset = 'mesh/device/sub/reset'; // + node_addr
  static const String cmdSubGet = 'mesh/device/sub/get'; // + node_addr

  /// Parse a response from RTM console
  static ConsoleResponse parseResponse(String data) {
    // Clean up the data
    final lines = data.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    if (lines.isEmpty) {
      return ConsoleResponse(type: ResponseType.empty);
    }

    // Check for async log messages (new node found)
    for (final line in lines) {
      if (line.contains('New node found:')) {
        final match = RegExp(r'New node found:\s*([0-9a-fA-F]{32})').firstMatch(line);
        if (match != null) {
          return ConsoleResponse(
            type: ResponseType.nodeFound,
            data: match.group(1),
          );
        }
      }
    }

    // Parse command responses
    final responseLines = <String>[];
    bool isResponse = false;
    bool hasOk = false;

    for (final line in lines) {
      if (line.startsWith(responsePrefix)) {
        isResponse = true;
        final content = line.substring(responsePrefix.length);
        if (content == '\$ok') {
          hasOk = true;
        } else {
          responseLines.add(content);
        }
      }
    }

    if (isResponse) {
      return ConsoleResponse(
        type: ResponseType.commandResponse,
        data: responseLines,
        success: hasOk,
      );
    }

    // Return raw data if not recognized
    return ConsoleResponse(
      type: ResponseType.raw,
      data: data,
    );
  }

  /// Parse device list response
  static List<MeshDevice> parseDeviceList(List<String> lines) {
    final devices = <MeshDevice>[];

    for (final line in lines) {
      // Format: 0x0002:0c305584745b4c09b3cfaa7b8ba483f6
      final match = RegExp(r'0x([0-9a-fA-F]+):([0-9a-fA-F]{32})').firstMatch(line);
      if (match != null) {
        devices.add(MeshDevice(
          address: int.parse(match.group(1)!, radix: 16),
          uuid: match.group(2)!,
        ));
      }
    }

    return devices;
  }

  /// Parse scan result
  static List<String> parseScanResult(List<String> lines) {
    final uuids = <String>[];

    for (final line in lines) {
      // Just UUIDs, one per line
      if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(line)) {
        uuids.add(line);
      }
    }

    return uuids;
  }

  /// Parse subscribe addresses
  static List<int> parseSubscribeAddresses(List<String> lines) {
    final addresses = <int>[];

    for (final line in lines) {
      // Format: 0xc003
      if (line.startsWith('0x')) {
        final addr = int.tryParse(line.substring(2), radix: 16);
        if (addr != null) {
          addresses.add(addr);
        }
      }
    }

    return addresses;
  }

  /// Parse provisioning result
  static int? parseProvisionResult(List<String> lines) {
    if (lines.isEmpty) return null;
    return int.tryParse(lines.first);
  }

  /// Parse last address
  static int? parseLastAddress(List<String> lines) {
    if (lines.isEmpty) return null;
    final line = lines.first;
    if (line.startsWith('0x')) {
      return int.tryParse(line.substring(2), radix: 16);
    }
    return int.tryParse(line);
  }

  /// Get group address for a node
  static int getGroupAddress(int nodeAddress) {
    return nodeAddress + 0xC000;
  }
}

/// Response types from RTM console
enum ResponseType {
  empty,
  raw,
  nodeFound,
  commandResponse,
}

/// Console response wrapper
class ConsoleResponse {
  final ResponseType type;
  final dynamic data;
  final bool success;

  ConsoleResponse({
    required this.type,
    this.data,
    this.success = false,
  });

  bool get isCommandResponse => type == ResponseType.commandResponse;
  bool get isNodeFound => type == ResponseType.nodeFound;

  List<String> get lines => data is List<String> ? data : [];
  String get nodeUuid => type == ResponseType.nodeFound ? data as String : '';
}

/// Simple mesh device info
class MeshDevice {
  final int address;
  final String uuid;
  final String? label;

  MeshDevice({
    required this.address,
    required this.uuid,
    this.label,
  });

  String get addressHex => '0x${address.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  int get groupAddress => RTMConsoleProtocol.getGroupAddress(address);
  String get groupAddressHex => '0x${groupAddress.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}

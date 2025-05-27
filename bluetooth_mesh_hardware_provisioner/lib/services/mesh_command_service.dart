// lib/services/mesh_command_service.dart

import 'dart:async';
import 'command_processor.dart';
import '../protocols/rtm_console_protocol.dart';

/// Service for executing mesh-specific commands
class MeshCommandService {
  final Future<void> Function(String) _sendData;
  final CommandProcessor _processor;

  // Stream controllers for specific events
  final _nodeFoundController = StreamController<String>.broadcast();

  // Public streams
  Stream<String> get nodeFoundStream => _nodeFoundController.stream;

  // Track active commands for timeout handling
  Timer? _commandTimer;
  final List<ProcessedLine> _responseBuffer = [];
  Completer<CommandResult>? _activeCommand;

  MeshCommandService({
    required Future<void> Function(String) sendData,
    required CommandProcessor processor,
  }) : _sendData = sendData,
       _processor = processor {
    _listenToProcessor();
  }

  void _listenToProcessor() {
    _processor.lineStream.listen((line) {
      // Handle async node discovery
      if (line.type == LineType.nodeFound) {
        _nodeFoundController.add(line.content);
      }

      // Buffer responses for active command
      if (_activeCommand != null && !_activeCommand!.isCompleted) {
        if (line.type == LineType.response || line.type == LineType.status) {
          _responseBuffer.add(line);

          // Check if response is complete
          if (line.type == LineType.status) {
            _completeCommand();
          } else {
            // Reset timeout for multi-line responses
            _resetCommandTimeout();
          }
        }
      }
    });
  }

  void _resetCommandTimeout() {
    _commandTimer?.cancel();
    _commandTimer = Timer(const Duration(milliseconds: 300), () {
      _completeCommand();
    });
  }

  void _completeCommand() {
    _commandTimer?.cancel();

    if (_activeCommand == null || _activeCommand!.isCompleted) return;

    // Parse response buffer
    final lines = <String>[];
    bool success = false;
    String? error;

    for (final line in _responseBuffer) {
      if (line.type == LineType.status) {
        success = line.content == 'ok';
        if (!success) {
          error = line.content;
        }
      } else if (line.type == LineType.response) {
        lines.add(line.content);
      }
    }

    _activeCommand!.complete(CommandResult(
      success: success,
      lines: lines,
      error: error,
    ));

    _responseBuffer.clear();
    _activeCommand = null;
  }

  /// Execute a command and wait for response
  Future<CommandResult> executeCommand(String command) async {
    // Wait for any active command to complete
    if (_activeCommand != null && !_activeCommand!.isCompleted) {
      await _activeCommand!.future.catchError((_) {});
    }

    _responseBuffer.clear();
    _activeCommand = Completer<CommandResult>();

    try {
      // Send command with line terminator
      await _sendData('$command\r\n');

      // Start timeout
      _resetCommandTimeout();

      // Wait for response with overall timeout
      return await _activeCommand!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => CommandResult(
          success: false,
          lines: [],
          error: 'timeout',
        ),
      ).catchError((e) => CommandResult(
        success: false,
        lines: [],
        error: e.toString(),
      ));
    } catch (e) {
      _activeCommand = null;
      rethrow;
    }
  }

  /// Send a command without waiting for response
  Future<void> sendCommand(String command) async {
    await _sendData('$command\r\n');
  }

  // High-level mesh commands

  /// Scan for unprovisioned devices
  Future<List<String>> scanForDevices() async {
    final result = await executeCommand('mesh/provision/scan/get');

    if (!result.success) {
      return [];
    }

    // Parse UUIDs from response
    final uuids = <String>[];
    for (final line in result.lines) {
      if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(line)) {
        uuids.add(line);
      }
    }

    return uuids;
  }

  /// Get list of provisioned devices
  Future<List<MeshDevice>> getProvisionedDevices() async {
    final result = await executeCommand('mesh/device/list');

    if (!result.success) {
      return [];
    }

    // Parse device list
    final devices = <MeshDevice>[];
    for (final line in result.lines) {
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

  /// Start provisioning a device
  Future<bool> provisionDevice(String uuid) async {
    final result = await executeCommand('mesh/provision/provision $uuid');
    return result.success;
  }

  /// Get provisioning status
  Future<String> getProvisioningStatus() async {
    final result = await executeCommand('mesh/provision/status/get');
    return result.lines.join(' ');
  }

  /// Get last provisioning result
  Future<int?> getProvisioningResult() async {
    final result = await executeCommand('mesh/provision/result/get');
    if (result.success && result.lines.isNotEmpty) {
      return int.tryParse(result.lines.first);
    }
    return null;
  }

  /// Reset (unprovision) a device
  Future<bool> resetDevice(int address) async {
    final result = await executeCommand('mesh/device/reset 0x${address.toRadixString(16)}');
    return result.success;
  }

  /// Add group subscription
  Future<bool> addSubscription(int nodeAddr, int groupAddr) async {
    final result = await executeCommand(
      'mesh/device/sub/add 0x${nodeAddr.toRadixString(16)} 0x${groupAddr.toRadixString(16)}'
    );
    return result.success;
  }

  /// Remove group subscription
  Future<bool> removeSubscription(int nodeAddr, int groupAddr) async {
    final result = await executeCommand(
      'mesh/device/sub/remove 0x${nodeAddr.toRadixString(16)} 0x${groupAddr.toRadixString(16)}'
    );
    return result.success;
  }

  /// Get device subscriptions
  Future<List<int>> getSubscriptions(int nodeAddr) async {
    final result = await executeCommand('mesh/device/sub/get 0x${nodeAddr.toRadixString(16)}');

    if (!result.success) {
      return [];
    }

    // Parse addresses
    final addresses = <int>[];
    for (final line in result.lines) {
      if (line.startsWith('0x')) {
        final addr = int.tryParse(line.substring(2), radix: 16);
        if (addr != null) {
          addresses.add(addr);
        }
      }
    }

    return addresses;
  }

  /// Factory reset the provisioner
  Future<bool> factoryReset() async {
    final result = await executeCommand('mesh/factory_reset');
    return result.success;
  }

  void dispose() {
    _commandTimer?.cancel();
    _nodeFoundController.close();
    _activeCommand?.completeError('Service disposed');
  }
}

/// Result of a command execution
class CommandResult {
  final bool success;
  final List<String> lines;
  final String? error;

  CommandResult({
    required this.success,
    required this.lines,
    this.error,
  });
}

// lib/services/mesh_command_service.dart

import 'dart:async';
import 'command_processor.dart';
import '../protocols/rtm_console_protocol.dart';
import '../models/mesh_device.dart';
import '../models/dali_lc.dart';
import '../models/radar_info.dart';
import '../models/fade_time.dart';

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
  Future<CommandResult> executeCommand(
    String command, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
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
        timeout,
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

  /// Perform a simple health check on the provisioner.
  ///
  /// Sends a lightweight command and verifies that a status line
  /// (\$ok, \$error or \$unknown) is received within [timeout].
  /// Returns `true` when a status response was received, otherwise `false`.
  Future<bool> healthCheck({Duration timeout = const Duration(seconds: 5)}) async {
    final result = await executeCommand('mesh/device/list', timeout: timeout);
    if (result.error == 'timeout') return false;
    if (result.success) return true;
    return result.error == 'error' || result.error == 'unknown';
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

/// Get list of provisioned devices.
///
/// Returns `null` if the command fails so callers can decide
/// whether to keep the existing list or handle the error.
Future<List<MeshDevice>?> getProvisionedDevices() async {
  final result = await executeCommand('mesh/device/list');

  if (!result.success) {
    return null;
  }

  // Parse device list
  final devices = <MeshDevice>[];
  for (final line in result.lines) {
    // New format with heartbeat info where `time_since_last_hb` is `-1`
    // when the provisioner has not yet received a heartbeat from the node.
    // Format: "0x0002,uuid,n_hops,rssi,time_since_last_hb"
    final fullMatch = RegExp(
            r'0x([0-9a-fA-F]+),([0-9a-fA-F]{32}),(\d+),(-?\d+),(-?\d+)')
        .firstMatch(line);
    if (fullMatch != null) {
      devices.add(MeshDevice(
        address: int.parse(fullMatch.group(1)!, radix: 16),
        uuid: fullMatch.group(2)!,
        nHops: int.parse(fullMatch.group(3)!),
        rssi: int.parse(fullMatch.group(4)!),
        timeSinceLastHb: int.parse(fullMatch.group(5)!),
      ));
      continue;
    }

    // Legacy format without heartbeat info
    final legacyMatch =
        RegExp(r'0x([0-9a-fA-F]+)[:, ]([0-9a-fA-F]{32})').firstMatch(line);
    if (legacyMatch != null) {
      devices.add(MeshDevice(
        address: int.parse(legacyMatch.group(1)!, radix: 16),
        uuid: legacyMatch.group(2)!,
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
    final result =
        await executeCommand('mesh/device/reset 0x${address.toRadixString(16)} 3000');
    return result.success;
  }

  /// Remove a device from the provisioner's database.
  Future<bool> removeDevice(int address) async {
    final result =
        await executeCommand('mesh/device/remove 0x${address.toRadixString(16)}');
    return result.success;
  }

  /// Add group subscription
  Future<bool> addSubscription(int nodeAddr, int groupAddr) async {
    final result = await executeCommand(
      'mesh/device/sub/add 0x${nodeAddr.toRadixString(16)} 0x${groupAddr.toRadixString(16)} 3000'
    );
    return result.success;
  }

  /// Remove group subscription
  Future<bool> removeSubscription(int nodeAddr, int groupAddr) async {
    final result = await executeCommand(
      'mesh/device/sub/remove 0x${nodeAddr.toRadixString(16)} 0x${groupAddr.toRadixString(16)} 3000'
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

  /// Get the DALI LC idle configuration.
  Future<DaliIdleConfig?> getDaliIdleConfig(int address) async {
    final result =
        await executeCommand('mesh/dali_lc/idle_cfg/get $address 3000');
    if (!result.success || result.lines.isEmpty) return null;
    final parts = result.lines.first.split(',');
    if (parts.length != 2) return null;
    final arc = int.tryParse(parts[0]);
    final fadeVal = int.tryParse(parts[1]);
    if (arc == null || fadeVal == null) return null;
    return DaliIdleConfig(arc, FadeTime.fromValue(fadeVal));
  }

  /// Get the DALI LC trigger configuration.
  Future<DaliTriggerConfig?> getDaliTriggerConfig(int address) async {
    final result =
        await executeCommand('mesh/dali_lc/trigger_cfg/get $address 3000');
    if (!result.success || result.lines.isEmpty) return null;
    final parts = result.lines.first.split(',');
    if (parts.length != 4) return null;
    final arc = int.tryParse(parts[0]);
    final fadeInVal = int.tryParse(parts[1]);
    final fadeOutVal = int.tryParse(parts[2]);
    final hold = int.tryParse(parts[3]);
    if (arc == null || fadeInVal == null || fadeOutVal == null || hold == null) {
      return null;
    }
    return DaliTriggerConfig(
      arc,
      FadeTime.fromValue(fadeInVal),
      FadeTime.fromValue(fadeOutVal),
      hold,
    );
  }

  /// Set the DALI LC idle configuration.
  Future<bool> setDaliIdleConfig(
      int address, int arc, FadeTime fade) async {
    final result = await executeCommand(
        'mesh/dali_lc/idle_cfg/set $address $arc ${fade.value} 3000');
    return result.success;
  }

  /// Set the DALI LC trigger configuration.
  Future<bool> setDaliTriggerConfig(
      int address, int arc, FadeTime fadeIn, FadeTime fadeOut, int hold) async {
    final result = await executeCommand(
        'mesh/dali_lc/trigger_cfg/set $address $arc ${fadeIn.value} ${fadeOut.value} $hold 3000');
    return result.success;
  }

  /// Get the remaining DALI LC identify time in seconds.
  Future<int?> getDaliIdentifyTime(int address) async {
    final result =
        await executeCommand('mesh/dali_lc/identify/get $address 3000');
    if (!result.success || result.lines.isEmpty) return null;
    return int.tryParse(result.lines.first);
  }

  /// Get the active DALI LC override state.
  Future<DaliOverrideState?> getDaliOverrideState(int address) async {
    final result =
        await executeCommand('mesh/dali_lc/override/get $address 3000');
    if (!result.success || result.lines.isEmpty) return null;
    final parts = result.lines.first.split(',');
    if (parts.length != 3) return null;
    final arc = int.tryParse(parts[0]);
    final fadeVal = int.tryParse(parts[1]);
    final dur = int.tryParse(parts[2]);
    if (arc == null || fadeVal == null || dur == null) return null;
    return DaliOverrideState(arc, FadeTime.fromValue(fadeVal), dur);
  }

  /// Get the radar configuration.
  Future<RadarInfo?> getRadarConfig(int address) async {
    final cfgResult = await executeCommand('mesh/radar/cfg/get $address 3000');
    if (!cfgResult.success || cfgResult.lines.isEmpty) return null;
    final parts = cfgResult.lines.first.split(',');
    if (parts.length != 4) return null;
    final band = int.tryParse(parts[0]);
    final cross = int.tryParse(parts[1]);
    final interval = int.tryParse(parts[2]);
    final depth = int.tryParse(parts[3]);
    if (band == null || cross == null || interval == null || depth == null) {
      return null;
    }

    final enableResult =
        await executeCommand('mesh/radar/enable/get $address 3000');
    bool enabled = false;
    if (enableResult.success && enableResult.lines.isNotEmpty) {
      enabled = enableResult.lines.first.trim() == '1';
    }

    return RadarInfo(
      bandThreshold: band,
      crossCount: cross,
      sampleInterval: interval,
      bufferDepth: depth,
      enabled: enabled,
    );
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

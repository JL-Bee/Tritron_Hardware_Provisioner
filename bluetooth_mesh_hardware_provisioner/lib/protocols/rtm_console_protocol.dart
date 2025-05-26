// lib/services/rtm_console_service.dart

import 'dart:async';
import '../protocols/rtm_console_protocol.dart';

/// Service for communicating with RTM console on NRF52
class RTMConsoleService {
  final Future<void> Function(String) _sendCommand;
  final Stream<String> _dataStream;

  final _responseController = StreamController<ConsoleResponse>.broadcast();
  final _nodeFoundController = StreamController<String>.broadcast();
  final _commandCompleters = <String, Completer<ConsoleResponse>>{};

  final StringBuffer _lineBuffer = StringBuffer();
  final List<String> _responseLines = [];
  Timer? _responseTimer;

  Stream<ConsoleResponse> get responseStream => _responseController.stream;
  Stream<String> get nodeFoundStream => _nodeFoundController.stream;

  RTMConsoleService({
    required Future<void> Function(String) sendCommand,
    required Stream<String> dataStream,
  })  : _sendCommand = sendCommand,
        _dataStream = dataStream {
    _listenToData();
  }

  void _listenToData() {
    _dataStream.listen((data) {
      // Add data to line buffer
      _lineBuffer.write(data);

      // Process complete lines
      final bufferContent = _lineBuffer.toString();
      final lines = bufferContent.split('\n');

      // Keep incomplete line in buffer
      _lineBuffer.clear();
      if (lines.isNotEmpty && !bufferContent.endsWith('\n')) {
        _lineBuffer.write(lines.removeLast());
      }

      // Process complete lines
      for (final line in lines) {
        final trimmed = _stripAnsiCodes(line.trim());
        if (trimmed.isEmpty) continue;

        // Check for async messages
        if (trimmed.contains('New node found:')) {
          final match = RegExp(r'New node found:\s*([0-9a-fA-F]{32})').firstMatch(trimmed);
          if (match != null) {
            _nodeFoundController.add(match.group(1)!);
          }
        }

        // Collect response lines
        if (trimmed.startsWith('~>')) {
          _responseLines.add(trimmed);

          // Check if response is complete
          if (trimmed == '~>\$ok') {
            _completeResponse(true);
          } else if (trimmed == '~>\$unknown') {
            // Handle unknown command response
            _completeResponse(false, isUnknown: true);
          } else {
            // Reset timer for more response lines
            _responseTimer?.cancel();
            _responseTimer = Timer(const Duration(milliseconds: 200), () {
              _completeResponse(false);
            });
          }
        }
      }
    });
  }

  /// Strip ANSI escape codes from string
  String _stripAnsiCodes(String text) {
    // Remove ANSI escape sequences (color codes, cursor movements, etc)
    return text.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
  }

  void _completeResponse(bool hasOk, {bool isUnknown = false}) {
    if (_commandCompleters.isEmpty) return;

    // Build response
    final lines = <String>[];
    final rawLines = <String>[];

    for (final line in _responseLines) {
      rawLines.add(line);
      if (line.startsWith('~>') && line != '~>\$ok' && line != '~>\$unknown') {
        lines.add(line.substring(2)); // Remove ~> prefix
      }
    }

    // Check if we have a multiline response that needs to be combined
    if (lines.length > 1 && _looksLikeUuid(lines)) {
      // Combine lines that look like they form a UUID
      final combined = lines.join('');
      if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(combined)) {
        lines.clear();
        lines.add(combined);
      }
    }

    final response = ConsoleResponse(
      type: ResponseType.commandResponse,
      data: lines,
      success: hasOk && !isUnknown,
    );

    // Complete the first waiting command
    final entry = _commandCompleters.entries.first;

    // Log detailed response for debugging
    if (!response.success || isUnknown) {
      print('Command failed: ${entry.key}');
      print('Raw response lines: $rawLines');
      print('Processed lines: $lines');
      print('Success: ${response.success}, Unknown: $isUnknown');
    }

    entry.value.complete(response);
    _commandCompleters.remove(entry.key);

    // Clear response buffer
    _responseLines.clear();
    _responseTimer?.cancel();
  }

  /// Check if lines look like they form a UUID split across multiple lines
  bool _looksLikeUuid(List<String> lines) {
    final combined = lines.join('');
    return combined.length <= 32 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(combined);
  }

  /// Execute a command and wait for response
  Future<ConsoleResponse> execute(String command) async {
    final completer = Completer<ConsoleResponse>();

    // Strip any ANSI codes from the command before sending
    final cleanCommand = _stripAnsiCodes(command);
    _commandCompleters[cleanCommand] = completer;

    try {
      // Send command without ANSI codes
      await _sendCommand('$cleanCommand\r\n');

      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('Command timed out: $cleanCommand');
          return ConsoleResponse(
            type: ResponseType.empty,
            success: false,
          );
        },
      );
    } catch (e) {
      _commandCompleters.remove(cleanCommand);
      rethrow;
    }
  }

  /// Scan for unprovisioned devices
  Future<List<String>> scanDevices() async {
    final response = await execute(RTMConsoleProtocol.cmdScanGet);
    if (!response.success) return [];

    return RTMConsoleProtocol.parseScanResult(response.lines);
  }

  /// List provisioned devices
  Future<List<MeshDevice>> listDevices() async {
    final response = await execute(RTMConsoleProtocol.cmdDeviceList);
    if (!response.success) return [];

    return RTMConsoleProtocol.parseDeviceList(response.lines);
  }

  /// Provision a device
  Future<bool> provisionDevice(String uuid) async {
    final response = await execute('${RTMConsoleProtocol.cmdProvision} $uuid');
    return response.success;
  }

  /// Get provisioning result
  Future<int?> getProvisionResult() async {
    final response = await execute(RTMConsoleProtocol.cmdProvisionResult);
    if (!response.success) return null;

    return RTMConsoleProtocol.parseProvisionResult(response.lines);
  }

  /// Get provisioning status
  Future<String> getProvisionStatus() async {
    final response = await execute(RTMConsoleProtocol.cmdProvisionStatus);
    if (!response.success) return 'Unknown';

    return response.lines.join(' ');
  }

  /// Get last provisioned address
  Future<int?> getLastAddress() async {
    final response = await execute(RTMConsoleProtocol.cmdLastAddr);
    if (!response.success) return null;

    return RTMConsoleProtocol.parseLastAddress(response.lines);
  }

  /// Reset (unprovision) a device
  Future<bool> resetDevice(int address) async {
    final response = await execute('${RTMConsoleProtocol.cmdDeviceReset} 0x${address.toRadixString(16)}');
    return response.success;
  }

  /// Remove device from database
  Future<bool> removeDevice(int address) async {
    final response = await execute('${RTMConsoleProtocol.cmdDeviceRemove} 0x${address.toRadixString(16)}');
    return response.success;
  }

  /// Add subscribe address
  Future<bool> addSubscribe(int nodeAddr, int groupAddr) async {
    final nodeHex = '0x${nodeAddr.toRadixString(16)}';
    final groupHex = '0x${groupAddr.toRadixString(16)}';
    final response = await execute('${RTMConsoleProtocol.cmdSubAdd} $nodeHex $groupHex');
    return response.success;
  }

  /// Remove subscribe address
  Future<bool> removeSubscribe(int nodeAddr, int groupAddr) async {
    final nodeHex = '0x${nodeAddr.toRadixString(16)}';
    final groupHex = '0x${groupAddr.toRadixString(16)}';
    final response = await execute('${RTMConsoleProtocol.cmdSubRemove} $nodeHex $groupHex');
    return response.success;
  }

  /// Get subscribe addresses
  Future<List<int>> getSubscribeAddresses(int nodeAddr) async {
    final nodeHex = '0x${nodeAddr.toRadixString(16)}';
    final response = await execute('${RTMConsoleProtocol.cmdSubGet} $nodeHex');
    if (!response.success) return [];

    return RTMConsoleProtocol.parseSubscribeAddresses(response.lines);
  }

  /// Reset subscribe addresses to default
  Future<bool> resetSubscribe(int nodeAddr) async {
    final nodeHex = '0x${nodeAddr.toRadixString(16)}';
    final response = await execute('${RTMConsoleProtocol.cmdSubReset} $nodeHex');
    return response.success;
  }

  /// Factory reset
  Future<bool> factoryReset() async {
    final response = await execute(RTMConsoleProtocol.cmdFactoryReset);
    return response.success;
  }

  /// Set device label
  Future<bool> setDeviceLabel(int address, String label) async {
    final addrHex = '0x${address.toRadixString(16)}';
    final response = await execute('${RTMConsoleProtocol.cmdDeviceLabel}/set $addrHex $label');
    return response.success;
  }

  /// Get device label
  Future<String?> getDeviceLabel(int address) async {
    final addrHex = '0x${address.toRadixString(16)}';
    final response = await execute('${RTMConsoleProtocol.cmdDeviceLabel}/get $addrHex');
    if (!response.success || response.lines.isEmpty) return null;

    return response.lines.first;
  }

  void dispose() {
    _responseTimer?.cancel();
    _responseController.close();
    _nodeFoundController.close();

    for (final completer in _commandCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError('Service disposed');
      }
    }
    _commandCompleters.clear();
  }
}

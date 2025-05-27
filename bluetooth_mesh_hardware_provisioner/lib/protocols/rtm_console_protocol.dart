// lib/protocols/rtm_protocol_v2.dart

import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

/// RTM Console Protocol Handler V2
/// Handles command/response cycles with proper queuing and timeouts
class RTMProtocolV2 {
  final Future<void> Function(String) _sendCommand;
  final Stream<Uint8List> _dataStream;

  // Response handling
  final _responseBuffer = StringBuffer();
  final _commandQueue = <_CommandRequest>[];
  _CommandRequest? _activeCommand;
  Timer? _responseTimer;
  StreamSubscription? _dataSubscription;

  // Event streams
  final _logController = StreamController<LogEntry>.broadcast();
  final _nodeFoundController = StreamController<String>.broadcast();

  Stream<LogEntry> get logStream => _logController.stream;
  Stream<String> get nodeFoundStream => _nodeFoundController.stream;

  RTMProtocolV2({
    required Future<void> Function(String) sendCommand,
    required Stream<Uint8List> dataStream,
  }) : _sendCommand = sendCommand,
       _dataStream = dataStream {
    _startListening();
  }

  void _startListening() {
    _dataSubscription = _dataStream.listen((data) {
      final text = utf8.decode(data, allowMalformed: true);
      _processIncomingData(text);
    });
  }

  void _processIncomingData(String data) {
    _responseBuffer.write(data);

    // Process complete lines
    final buffer = _responseBuffer.toString();
    final lines = buffer.split('\n');

    // Keep incomplete line in buffer
    _responseBuffer.clear();
    if (lines.isNotEmpty && !buffer.endsWith('\n')) {
      _responseBuffer.write(lines.removeLast());
    }

    // Process each complete line
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Log all received data
      _logController.add(LogEntry(
        text: trimmed,
        type: LogType.rx,
        timestamp: DateTime.now(),
      ));

      // Check for async messages
      if (trimmed.contains('New node found:')) {
        final match = RegExp(r'New node found:\s*([0-9a-fA-F]{32})').firstMatch(trimmed);
        if (match != null) {
          _nodeFoundController.add(match.group(1)!);
        }
      }

      // Handle command responses
      if (_activeCommand != null && trimmed.startsWith('~>')) {
        _handleResponseLine(trimmed);
      }
    }
  }

  void _handleResponseLine(String line) {
    if (_activeCommand == null) return;

    _activeCommand!.responseLines.add(line);

    // Reset response timer
    _responseTimer?.cancel();

    // Check if response is complete
    if (line == '~>\$ok' || line == '~>\$error' || line == '~>\$unknown') {
      _completeActiveCommand();
    } else {
      // Wait for more lines or timeout
      _responseTimer = Timer(const Duration(milliseconds: 100), () {
        _completeActiveCommand();
      });
    }
  }

  void _completeActiveCommand() {
    if (_activeCommand == null) return;

    _responseTimer?.cancel();

    // Parse response
    final response = _parseResponse(_activeCommand!.responseLines);
    _activeCommand!.completer.complete(response);

    _activeCommand = null;

    // Process next command in queue
    _processNextCommand();
  }

  CommandResponse _parseResponse(List<String> lines) {
    if (lines.isEmpty) {
      return CommandResponse(success: false, data: []);
    }

    bool success = false;
    final data = <String>[];

    for (final line in lines) {
      if (line == '~>\$ok') {
        success = true;
      } else if (line == '~>\$error' || line == '~>\$unknown') {
        success = false;
      } else if (line.startsWith('~>') && line.length > 2) {
        data.add(line.substring(2));
      }
    }

    return CommandResponse(success: success, data: data);
  }

  void _processNextCommand() {
    if (_activeCommand != null || _commandQueue.isEmpty) return;

    _activeCommand = _commandQueue.removeAt(0);

    // Send command
    _sendCommand(_activeCommand!.command).then((_) {
      _logController.add(LogEntry(
        text: _activeCommand!.command.trim(),
        type: LogType.tx,
        timestamp: DateTime.now(),
      ));

      // Start timeout timer
      _activeCommand!.timeoutTimer = Timer(const Duration(seconds: 5), () {
        if (_activeCommand != null) {
          _activeCommand!.completer.complete(
            CommandResponse(success: false, data: [], timedOut: true)
          );
          _activeCommand = null;
          _processNextCommand();
        }
      });
    }).catchError((error) {
      _activeCommand!.completer.completeError(error);
      _activeCommand = null;
      _processNextCommand();
    });
  }

  /// Execute a command and wait for response
  Future<CommandResponse> execute(String command) async {
    final request = _CommandRequest(
      command: '$command\r\n',
      completer: Completer<CommandResponse>(),
    );

    _commandQueue.add(request);
    _processNextCommand();

    return request.completer.future;
  }

  /// Send a command without waiting for response
  Future<void> sendRaw(String command) async {
    await _sendCommand('$command\r\n');
    _logController.add(LogEntry(
      text: command,
      type: LogType.tx,
      timestamp: DateTime.now(),
    ));
  }

  void dispose() {
    _responseTimer?.cancel();
    _dataSubscription?.cancel();
    _logController.close();
    _nodeFoundController.close();

    // Cancel all pending commands
    if (_activeCommand != null) {
      _activeCommand!.timeoutTimer?.cancel();
      _activeCommand!.completer.completeError('Disposed');
    }

    for (final cmd in _commandQueue) {
      cmd.completer.completeError('Disposed');
    }
  }
}

class _CommandRequest {
  final String command;
  final Completer<CommandResponse> completer;
  final List<String> responseLines = [];
  Timer? timeoutTimer;

  _CommandRequest({
    required this.command,
    required this.completer,
  });
}

class CommandResponse {
  final bool success;
  final List<String> data;
  final bool timedOut;

  CommandResponse({
    required this.success,
    required this.data,
    this.timedOut = false,
  });
}

class LogEntry {
  final String text;
  final LogType type;
  final DateTime timestamp;

  LogEntry({
    required this.text,
    required this.type,
    required this.timestamp,
  });
}

enum LogType { tx, rx, info, error }

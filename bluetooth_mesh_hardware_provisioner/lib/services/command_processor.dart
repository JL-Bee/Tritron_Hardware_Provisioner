// lib/services/command_processor.dart

import 'dart:async';

/// Simple command processor that handles line-based protocols.
///
/// Incoming data may contain ANSI escape sequences produced by the device's
/// logging system. These sequences are stripped before further processing so
/// higher level components receive clean text lines.
class CommandProcessor {
  final Stream<String> _dataStream;
  final StringBuffer _lineBuffer = StringBuffer();
  final _lineController = StreamController<ProcessedLine>.broadcast();

  StreamSubscription? _dataSubscription;

  // Output stream of processed lines
  Stream<ProcessedLine> get lineStream => _lineController.stream;

  CommandProcessor(this._dataStream) {
    _startProcessing();
  }

  void _startProcessing() {
    _dataSubscription = _dataStream.listen((data) {
      // Debug: Print raw data
      print(
        'CommandProcessor: Received data: '
        '${data.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}',
      );

      _lineBuffer.write(data);
      _processBuffer();
    });
  }

  void _processBuffer() {
    final content = _lineBuffer.toString();
    final lines = content.split('\n');

    // Keep last incomplete line in buffer
    _lineBuffer.clear();
    if (lines.isNotEmpty && !content.endsWith('\n')) {
      _lineBuffer.write(lines.removeLast());
    }

    // Process complete lines
    for (final line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Remove ANSI escape sequences
      trimmed = trimmed.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');

      // Determine line type and emit only if relevant
      final processed = _processLine(trimmed);
      if (processed != null) {
        _lineController.add(processed);
      }
    }
  }

  ProcessedLine? _processLine(String line) {
    // Check for RTM console response prefix
    if (line.startsWith('~>')) {
      final content = line.substring(2);

      // Check for status markers
      if (content == '\$ok') {
        return ProcessedLine(
          raw: line,
          type: LineType.status,
          content: 'ok',
        );
      } else if (content == '\$error') {
        return ProcessedLine(
          raw: line,
          type: LineType.status,
          content: 'error',
        );
      } else if (content == '\$unknown') {
        return ProcessedLine(
          raw: line,
          type: LineType.status,
          content: 'unknown',
        );
      } else {
        return ProcessedLine(
          raw: line,
          type: LineType.response,
          content: content,
        );
      }
    }

    // Check for async notifications
    if (line.contains('New node found:')) {
      final match = RegExp(r'New node found:\s*([0-9a-fA-F]{32})').firstMatch(line);
      if (match != null) {
        return ProcessedLine(
          raw: line,
          type: LineType.nodeFound,
          content: match.group(1)!,
        );
      }
    }

    // Check for log levels
    if (line.contains('<err>')) {
      return null; // Ignore error logs
    } else if (line.contains('<wrn>')) {
      return null; // Ignore warning logs
    } else if (line.contains('<inf>')) {
      return null; // Ignore info logs
    }

    // Default to raw line
    return null; // Ignore any other lines
  }

  void dispose() {
    _dataSubscription?.cancel();
    _lineController.close();
  }
}

/// Processed line data
class ProcessedLine {
  final String raw;
  final LineType type;
  final String content;
  final DateTime timestamp;

  ProcessedLine({
    required this.raw,
    required this.type,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Line types
enum LineType {
  response,    // RTM console response (~>data)
  status,      // RTM status (~>$ok, ~>$error, ~>$unknown)
  nodeFound,   // Async node discovery
  error,       // Error log
  warning,     // Warning log
  info,        // Info log
  other,       // Anything else
}

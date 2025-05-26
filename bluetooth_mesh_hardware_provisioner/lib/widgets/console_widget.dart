// lib/widgets/console_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class ConsoleWidget extends StatefulWidget {
  final Stream<String> dataStream;
  final Function(String) onCommand;

  const ConsoleWidget({
    super.key,
    required this.dataStream,
    required this.onCommand,
  });

  @override
  State<ConsoleWidget> createState() => _ConsoleWidgetState();
}

class _ConsoleWidgetState extends State<ConsoleWidget> {
  final List<ConsoleEntry> _entries = [];
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _commandFocus = FocusNode();

  String _rxBuffer = '';
  Timer? _rxTimer;

  @override
  void initState() {
    super.initState();
    _listenToData();
  }

  @override
  void dispose() {
    _rxTimer?.cancel();
    _commandController.dispose();
    _scrollController.dispose();
    _commandFocus.dispose();
    super.dispose();
  }

  void _listenToData() {
    widget.dataStream.listen((data) {
      _rxBuffer += data;

      // Cancel existing timer
      _rxTimer?.cancel();

      // Set a new timer to process buffer after a short delay
      _rxTimer = Timer(const Duration(milliseconds: 50), () {
        _processBuffer();
      });
    });
  }

  void _processBuffer() {
    if (_rxBuffer.isEmpty) return;

    // Split by newlines but keep track of incomplete lines
    final lines = _rxBuffer.split('\n');

    // If buffer doesn't end with newline, keep last part for next time
    if (!_rxBuffer.endsWith('\n')) {
      _rxBuffer = lines.removeLast();
    } else {
      _rxBuffer = '';
    }

    // Process complete lines
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        _addEntry(ConsoleEntry(
          text: trimmed,
          type: EntryType.received,
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  void _addEntry(ConsoleEntry entry) {
    setState(() {
      _entries.add(entry);
      // Keep only last 1000 entries
      if (_entries.length > 1000) {
        _entries.removeRange(0, _entries.length - 1000);
      }
    });

    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendCommand() {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;

    _commandController.clear();

    // Add command to console
    _addEntry(ConsoleEntry(
      text: command,
      type: EntryType.command,
      timestamp: DateTime.now(),
    ));

    // Send command
    widget.onCommand(command);
  }

  void _copyToClipboard() {
    final text = _entries.map((e) => '[${e.typePrefix}] ${e.text}').join('\n');
    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Console output copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clearConsole() {
    setState(() {
      _entries.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Text('Console', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                onPressed: _copyToClipboard,
                tooltip: 'Copy all',
              ),
              IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: _clearConsole,
                tooltip: 'Clear console',
              ),
            ],
          ),
        ),

        // Console output
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: _entries.isEmpty
                ? const Center(
                    child: Text(
                      'Console output will appear here...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        return _ConsoleEntryWidget(entry: entry);
                      },
                    ),
                  ),
          ),
        ),

        // Command input
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.chevron_right, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _commandController,
                  focusNode: _commandFocus,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'Enter command (e.g., mesh/device/list)',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendCommand(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sendCommand,
                child: const Text('Send'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConsoleEntryWidget extends StatelessWidget {
  final ConsoleEntry entry;

  const _ConsoleEntryWidget({required this.entry});

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '[${entry.timeString}] ',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          TextSpan(
            text: '[${entry.typePrefix}] ',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: entry.prefixColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: entry.text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: entry.textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class ConsoleEntry {
  final String text;
  final EntryType type;
  final DateTime timestamp;

  ConsoleEntry({
    required this.text,
    required this.type,
    required this.timestamp,
  });

  String get typePrefix {
    switch (type) {
      case EntryType.command:
        return 'TX';
      case EntryType.received:
        return 'RX';
      case EntryType.info:
        return 'INFO';
      case EntryType.error:
        return 'ERROR';
    }
  }

  Color get prefixColor {
    switch (type) {
      case EntryType.command:
        return Colors.blue.shade300;
      case EntryType.received:
        return Colors.green.shade300;
      case EntryType.info:
        return Colors.yellow.shade300;
      case EntryType.error:
        return Colors.red.shade300;
    }
  }

  Color get textColor {
    switch (type) {
      case EntryType.command:
        return Colors.blue.shade100;
      case EntryType.received:
        return Colors.green.shade100;
      case EntryType.info:
        return Colors.white70;
      case EntryType.error:
        return Colors.red.shade100;
    }
  }

  String get timeString {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}';
  }
}

enum EntryType {
  command,
  received,
  info,
  error,
}

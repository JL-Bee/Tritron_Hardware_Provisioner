// lib/widgets/bloc_console_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/provisioner_bloc.dart';
import '../services/rtm_console_service.dart';

class BlocConsoleWidget extends StatefulWidget {
  const BlocConsoleWidget({super.key});

  @override
  State<BlocConsoleWidget> createState() => _BlocConsoleWidgetState();
}

class _BlocConsoleWidgetState extends State<BlocConsoleWidget> {
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _commandFocus = FocusNode();

  @override
  void dispose() {
    _commandController.dispose();
    _scrollController.dispose();
    _commandFocus.dispose();
    super.dispose();
  }

  void _sendCommand() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;

    _commandController.clear();

    // Send command through BLoC
    context
        .read<ProvisionerBloc>()
        .add(SendConsoleCommand(command));
  }

  void _copyToClipboard(List<ConsoleEntry> entries) {
    final text = entries.map((e) =>
      '[${_formatTime(e.timestamp)}] [${_getTypePrefix(e.type)}] ${e.text}'
    ).join('\n');

    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Console output copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProvisionerBloc, ProvisionerState>(
      builder: (context, state) {
        // Auto-scroll when new entries are added
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });

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
                  Text(
                    '${state.consoleEntries.length} entries',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () => _copyToClipboard(state.consoleEntries),
                    tooltip: 'Copy all',
                  ),
                ],
              ),
            ),

            // Console output - using SelectionArea for better multi-line selection
            Expanded(
              child: Container(
                color: const Color(0xFF1E1E1E),
                child: state.consoleEntries.isEmpty
                    ? const Center(
                        child: Text(
                          'Console output will appear here...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : SelectionArea(
                        child: Scrollbar(
                          controller: _scrollController,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(8),
                            itemCount: state.consoleEntries.length,
                            itemBuilder: (context, index) {
                              final entry = state.consoleEntries[index];
                              return _ConsoleEntryWidget(entry: entry);
                            },
                          ),
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
      },
    );
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}';
  }

  String _getTypePrefix(ConsoleEntryType type) {
    switch (type) {
      case ConsoleEntryType.command:
        return 'TX';
      case ConsoleEntryType.response:
        return 'RX';
      case ConsoleEntryType.info:
        return 'INFO';
      case ConsoleEntryType.error:
        return 'ERROR';
    }
  }
}

class _ConsoleEntryWidget extends StatelessWidget {
  final ConsoleEntry entry;

  const _ConsoleEntryWidget({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.0),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '[${_formatTime(entry.timestamp)}] ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            TextSpan(
              text: '[${_getTypePrefix(entry.type)}] ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: _getPrefixColor(entry),
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: entry.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: _getTextColor(entry.type),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}';
  }

  String _getTypePrefix(ConsoleEntryType type) {
    switch (type) {
      case ConsoleEntryType.command:
        return 'TX';
      case ConsoleEntryType.response:
        return 'RX';
      case ConsoleEntryType.info:
        return 'INFO';
      case ConsoleEntryType.error:
        return 'ERROR';
    }
  }

  Color _getPrefixColor(ConsoleEntry entry) {
    if (entry.type == ConsoleEntryType.response && entry.timedOut) {
      return Colors.red.shade300;
    }

    switch (entry.type) {
      case ConsoleEntryType.command:
        return Colors.blue.shade300;
      case ConsoleEntryType.response:
        return Colors.green.shade300;
      case ConsoleEntryType.info:
        return Colors.yellow.shade300;
      case ConsoleEntryType.error:
        return Colors.red.shade300;
    }
  }

  Color _getTextColor(ConsoleEntryType type) {
    switch (type) {
      case ConsoleEntryType.command:
        return Colors.blue.shade100;
      case ConsoleEntryType.response:
        return Colors.green.shade100;
      case ConsoleEntryType.info:
        return Colors.white70;
      case ConsoleEntryType.error:
        return Colors.red.shade100;
    }
  }
}

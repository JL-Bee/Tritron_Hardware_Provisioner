// lib/screens/action_history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/provisioner_bloc.dart';

class ActionHistoryScreen extends StatelessWidget {
  const ActionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Action History'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: BlocBuilder<ProvisionerBloc, ProvisionerState>(
        builder: (context, state) {
          if (state.actionHistory.isEmpty) {
            return const Center(
              child: Text('No actions performed yet'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.actionHistory.length,
            itemBuilder: (context, index) {
              // Show most recent first
              final action = state.actionHistory[state.actionHistory.length - 1 - index];

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: action.success ? Colors.green : Colors.red,
                    child: Icon(
                      action.success ? Icons.check : Icons.close,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(action.action),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (action.message != null)
                        Text(
                          action.message!,
                          style: TextStyle(
                            color: action.success ? null : Colors.red,
                          ),
                        ),
                      Text(
                        _formatTimestamp(action.timestamp),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Action', action.action),
                          _buildDetailRow('Status', action.success ? 'Success' : 'Failed'),
                          _buildDetailRow('Timestamp', action.timestamp.toIso8601String()),
                          if (action.message != null)
                            _buildDetailRow('Message', action.message!),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copy Details'),
                                onPressed: () {
                                  final details = '''
Action: ${action.action}
Status: ${action.success ? 'Success' : 'Failed'}
Timestamp: ${action.timestamp.toIso8601String()}
Message: ${action.message ?? 'N/A'}
''';
                                  Clipboard.setData(ClipboardData(text: details));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Action details copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.hour.toString().padLeft(2, '0')}:'
             '${timestamp.minute.toString().padLeft(2, '0')} '
             '${timestamp.day}/${timestamp.month}';
    }
  }
}

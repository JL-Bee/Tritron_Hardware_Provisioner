// lib/screens/action_history_screen.dart

import 'package:flutter/material.dart';
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
                child: ListTile(
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
                        Text(action.message!),
                      Text(
                        _formatTimestamp(action.timestamp),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  isThreeLine: action.message != null,
                ),
              );
            },
          );
        },
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

// lib/widgets/error_notification.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/provisioner_bloc.dart';

class ErrorNotification extends StatelessWidget {
  const ErrorNotification({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProvisionerBloc, ProvisionerState>(
      builder: (context, state) {
        if (state.currentError == null) {
          return const SizedBox.shrink();
        }

        return Positioned(
          top: 16,
          right: 16,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: _getBackgroundColor(state.currentError!.severity),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _getBorderColor(state.currentError!.severity),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getIcon(state.currentError!.severity),
                      color: _getIconColor(state.currentError!.severity),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTitle(state.currentError!.severity),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _getTextColor(state.currentError!.severity),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.currentError!.message,
                            style: TextStyle(
                              fontSize: 13,
                              color: _getTextColor(state.currentError!.severity),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: _getTextColor(state.currentError!.severity),
                      ),
                      onPressed: () {
                        context.read<ProvisionerBloc>().add(ClearError());
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getBackgroundColor(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return Colors.blue.shade50;
      case ErrorSeverity.warning:
        return Colors.orange.shade50;
      case ErrorSeverity.error:
        return Colors.red.shade50;
    }
  }

  Color _getBorderColor(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return Colors.blue.shade200;
      case ErrorSeverity.warning:
        return Colors.orange.shade200;
      case ErrorSeverity.error:
        return Colors.red.shade200;
    }
  }

  Color _getIconColor(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return Colors.blue;
      case ErrorSeverity.warning:
        return Colors.orange;
      case ErrorSeverity.error:
        return Colors.red;
    }
  }

  Color _getTextColor(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return Colors.blue.shade900;
      case ErrorSeverity.warning:
        return Colors.orange.shade900;
      case ErrorSeverity.error:
        return Colors.red.shade900;
    }
  }

  IconData _getIcon(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return Icons.info_outline;
      case ErrorSeverity.warning:
        return Icons.warning_amber;
      case ErrorSeverity.error:
        return Icons.error_outline;
    }
  }

  String _getTitle(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return 'Info';
      case ErrorSeverity.warning:
        return 'Warning';
      case ErrorSeverity.error:
        return 'Error';
    }
  }
}

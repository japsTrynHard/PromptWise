import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/progress_controller.dart';
import '../../core/utils/constants.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProgressController>();
    final message = controller.errorMessage;

    if (controller.isLoading ||
        controller.syncState == ProgressSyncState.syncing) {
      return const _Banner(
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        message: 'Saving your progress...',
      );
    }

    if (message != null || controller.syncState == ProgressSyncState.error) {
      return _Banner(
        icon: Icon(
          Icons.offline_pin_outlined,
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
        message:
            message ??
            'Your progress is saved on this device and will update online when you reconnect.',
        isWarning: true,
        trailing: Wrap(
          children: [
            TextButton(
              onPressed: controller.retryInit,
              child: const Text('Try again'),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: controller.clearError,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      );
    }

    if (controller.syncState == ProgressSyncState.synced) {
      return const _Banner(
        icon: Icon(Icons.check_circle_outline_rounded),
        message: 'Progress saved to your account.',
      );
    }

    return const _Banner(
      icon: Icon(Icons.phone_android_rounded),
      message: 'Progress is saved on this device.',
    );
  }
}

class _Banner extends StatelessWidget {
  final Widget icon;
  final String message;
  final bool isWarning;
  final Widget? trailing;

  const _Banner({
    required this.icon,
    required this.message,
    this.isWarning = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isWarning ? scheme.tertiaryContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isWarning
                    ? scheme.onTertiaryContainer
                    : scheme.onPrimaryContainer,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

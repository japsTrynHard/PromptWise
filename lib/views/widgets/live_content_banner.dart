import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/content_controller.dart';
import '../../utils/constants.dart';

class LiveContentBanner extends StatelessWidget {
  final bool compact;

  const LiveContentBanner({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentController>();
    final scheme = Theme.of(context).colorScheme;

    if (content.isLoading && !content.hasLoaded) {
      return _Banner(
        icon: Icons.refresh_rounded,
        message: 'Updating learning content...',
        color: scheme.primary,
        trailing: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        compact: compact,
      );
    }

    if (content.isUsingSavedContent) {
      return _Banner(
        icon: Icons.offline_pin_outlined,
        message:
            content.errorMessage ??
            'You appear to be offline. Showing saved learning content.',
        color: scheme.tertiary,
        trailing: TextButton.icon(
          onPressed: content.isLoading ? null : content.refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
        compact: compact,
      );
    }

    if (content.errorMessage != null) {
      return _Banner(
        icon: Icons.wifi_off_rounded,
        message: content.errorMessage!,
        color: scheme.error,
        trailing: TextButton.icon(
          onPressed: content.isLoading ? null : content.refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
        compact: compact,
      );
    }

    if (content.isLive) {
      return _Banner(
        icon: Icons.check_circle_outline_rounded,
        message: 'Learning content is up to date.',
        color: scheme.primary,
        trailing: IconButton(
          tooltip: 'Refresh',
          onPressed: content.isLoading ? null : content.refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        compact: compact,
      );
    }

    return _Banner(
      icon: Icons.info_outline_rounded,
      message: 'Learning content is temporarily unavailable.',
      color: scheme.tertiary,
      trailing: IconButton(
        tooltip: 'Try again',
        onPressed: content.isLoading ? null : content.refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      compact: compact,
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Widget trailing;
  final bool compact;

  const _Banner({
    required this.icon,
    required this.message,
    required this.color,
    required this.trailing,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: compact ? AppSpacing.sm : AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              maxLines: compact ? 1 : 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          trailing,
        ],
      ),
    );
  }
}

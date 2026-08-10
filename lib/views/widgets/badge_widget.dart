import 'package:flutter/material.dart';

import '../../utils/constants.dart';

class BadgeWidget extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool earned;

  const BadgeWidget({
    super.key,
    required this.icon,
    required this.label,
    required this.earned,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: '$label badge, ${earned ? 'earned' : 'locked'}',
      child: AnimatedOpacity(
        duration: AppMotion.normal,
        opacity: earned ? 1 : 0.52,
        child: Container(
          width: 144,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: earned
                ? colorScheme.primaryContainer.withValues(alpha: 0.55)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: earned
                    ? AppColors.primary
                    : colorScheme.outlineVariant,
                foregroundColor: earned
                    ? Colors.white
                    : colorScheme.onSurfaceVariant,
                child: Icon(icon),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                earned ? 'Earned' : 'Locked',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

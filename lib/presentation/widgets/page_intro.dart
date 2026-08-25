import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';

/// Strong, reusable page heading for learner and admin screens.
///
/// On phones the trailing action moves below the copy instead of squeezing the
/// title. On wider screens it stays aligned to the upper-right.
class PageIntro extends StatelessWidget {
  final String title;
  final String description;
  final Widget? trailing;
  final String? eyebrow;

  const PageIntro({
    super.key,
    required this.title,
    required this.description,
    this.trailing,
    this.eyebrow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.violet, AppColors.teal],
                    ),
                  ),
                ),
                if (eyebrow != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    eyebrow!.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.75,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: (compact
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.headlineMedium)
                  ?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: compact ? -0.6 : -0.9,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        );

        if (compact || trailing == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              copy,
              if (trailing != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Align(alignment: Alignment.centerLeft, child: trailing!),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.xl),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: trailing!,
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';

/// Compact reusable page heading.
///
/// On phones this intentionally behaves like a modern social/consumer app:
/// short hierarchy, small vertical gaps, and actions aligned with the title
/// instead of creating a second tall header block.
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
        final compact = MediaQuery.sizeOf(context).shortestSide < AppBreakpoints.compact ||
            constraints.maxWidth < AppBreakpoints.compact;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null && eyebrow!.trim().isNotEmpty) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.55,
                        height: 1.12,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    trailing!,
                  ],
                ],
              ),
              if (description.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          );
        }

        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null && eyebrow!.trim().isNotEmpty) ...[
              Text(
                eyebrow!.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.75,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.65,
              ),
            ),
            if (description.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ],
        );

        if (trailing == null) return copy;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.xl),
            trailing!,
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../../utils/constants.dart';
import 'app_card.dart';

class ModuleCard extends StatelessWidget {
  final Module module;
  final VoidCallback onTap;
  final bool compact;

  const ModuleCard({
    super.key,
    required this.module,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final totalMinutes = module.lessons.fold<int>(
      0,
      (total, lesson) => total + lesson.estimatedMinutes,
    );

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 46 : 54,
                height: compact ? 46 : 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primaryContainer,
                      AppColors.teal.withValues(alpha: 0.13),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  AppIcons.module(module.icon),
                  color: Theme.of(context).colorScheme.primary,
                  size: compact ? 24 : 28,
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(module.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            module.description,
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _Meta(
                icon: Icons.menu_book_outlined,
                label: '${module.lessons.length} lessons',
              ),
              const SizedBox(width: AppSpacing.md),
              _Meta(icon: Icons.schedule_rounded, label: '$totalMinutes min'),
              const Spacer(),
              Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Meta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

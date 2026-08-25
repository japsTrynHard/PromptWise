import 'package:flutter/material.dart';

import '../../data/models/prompt_coach.dart';
import '../../core/utils/constants.dart';
import './app_card.dart';

class PromptScoreWidget extends StatelessWidget {
  final PromptRubricScore scores;
  final PromptRubricScore? previousScores;

  const PromptScoreWidget({
    super.key,
    required this.scores,
    this.previousScores,
  });

  @override
  Widget build(BuildContext context) {
    final overall = scores.overallPercent;
    final previous = previousScores?.overallPercent;
    final improvement = previous == null ? null : overall - previous;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Prompt quality',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'PromptWise uses the same rubric every time so revisions can be compared consistently.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$overall',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _scoreColor(overall / 100),
                    ),
                  ),
                  Text(
                    '/ 100',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (improvement != null && improvement != 0) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${improvement > 0 ? '+' : ''}$improvement from last revision',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: improvement > 0
                            ? AppColors.success
                            : AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final itemWidth = width >= 700 ? (width - AppSpacing.lg) / 2 : width;
              return Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.md,
                children: [
                  for (final dimension in PromptRubricDimension.values)
                    SizedBox(
                      width: itemWidth,
                      child: _ScoreBar(
                        label: dimension.label,
                        value: scores.valueFor(dimension),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Color _scoreColor(double value) {
    if (value >= 0.8) return AppColors.success;
    if (value >= 0.5) return AppColors.warning;
    return AppColors.danger;
  }
}

class _ScoreBar extends StatelessWidget {
  final String label;
  final double value;

  const _ScoreBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0.0, 1.0).toDouble();
    final percent = (safeValue * 100).round();
    final color = safeValue >= 0.8
        ? AppColors.success
        : safeValue >= 0.5
        ? AppColors.warning
        : AppColors.danger;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: safeValue,
            minHeight: 8,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ),
      ],
    );
  }
}

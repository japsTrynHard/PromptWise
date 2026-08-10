import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import 'app_card.dart';

class PromptScoreWidget extends StatelessWidget {
  final double clarity;
  final double context;
  final double specificity;
  final double responsibility;
  final double overall;

  const PromptScoreWidget({
    super.key,
    required this.clarity,
    required this.context,
    required this.specificity,
    required this.responsibility,
    required this.overall,
  });

  @override
  Widget build(BuildContext context) {
    final safeOverall = overall.clamp(0.0, 1.0).toDouble();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Prompt Review',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${(safeOverall * 100).round()}%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _scoreColor(safeOverall),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This score is a learning guide, not a single correct judgment.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _ScoreBar(label: 'Clarity', value: clarity),
          _ScoreBar(label: 'Context', value: this.context),
          _ScoreBar(label: 'Specificity', value: specificity),
          _ScoreBar(label: 'Responsible Use', value: responsibility),
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
    final color = safeValue >= 0.8
        ? AppColors.success
        : safeValue >= 0.5
        ? AppColors.warning
        : AppColors.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                '${(safeValue * 100).round()}%',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
              value: safeValue,
              minHeight: 10,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class PromptScoreWidget extends StatelessWidget {
  final double clarity;
  final double context; // This is a double
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Prompt Score',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${(overall * 100).toInt()}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: overall >= 0.8 ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < (overall * 5).round() ? Icons.star : Icons.star_border,
                color: Colors.amber,
                size: 24,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _ScoreBar(label: 'Clarity', value: clarity),
          _ScoreBar(
            label: 'Context',
            value: this.context, // FIXED: Explicitly use the class property
          ),
          _ScoreBar(label: 'Specificity', value: specificity),
          _ScoreBar(label: 'Responsible Use', value: responsibility),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final String label;
  final double value;
  const _ScoreBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: value > 0.7
                    ? Colors.green
                    : value > 0.4
                    ? Colors.orange
                    : Colors.red,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 35,
            child: Text(
              '${(value * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

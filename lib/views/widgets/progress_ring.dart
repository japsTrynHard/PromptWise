import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/progress_controller.dart';

class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressController>().progress;

    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress.completionRatio,
            strokeWidth: 10,
            backgroundColor: Colors.grey.shade200,
            color: Theme.of(context).colorScheme.primary,
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${progress.completedLessons}/${progress.totalLessons}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  'Lessons',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

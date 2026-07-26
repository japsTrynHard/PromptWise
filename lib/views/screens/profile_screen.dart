import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/progress_controller.dart';
import '../widgets/progress_ring.dart';
import '../widgets/badge_widget.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressController>().progress;

    return Scaffold(
      appBar: AppBar(title: const Text('Your Progress')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Center(child: ProgressRing()),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      'Knowledge Level',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(
                        progress.knowledgeLevel,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(
                          label: 'Lessons',
                          value:
                              '${progress.completedLessons}/${progress.totalLessons}',
                        ),
                        _StatItem(
                          label: 'Quiz Score',
                          value: '${progress.quizScore}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Badges',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                BadgeWidget(
                  emoji: '🏆',
                  label: 'AI Explorer',
                  earned:
                      progress.badges.contains('🏆 AI Explorer') ||
                      progress.completedLessons >= 1,
                ),
                BadgeWidget(
                  emoji: '✍️',
                  label: 'Prompt Improver',
                  earned: progress.badges.contains('✍️ Prompt Improver'),
                ),
                BadgeWidget(
                  emoji: '🕵️',
                  label: 'AI Detective',
                  earned: progress.badges.contains('🕵️ AI Detective'),
                ),
                BadgeWidget(
                  emoji: '⚡',
                  label: 'Quiz Ace',
                  earned: progress.badges.contains('🏆 Quiz Ace'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

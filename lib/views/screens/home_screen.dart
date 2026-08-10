import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/content_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../models/lesson.dart';
import '../../routes/app_routes.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/live_content_banner.dart';
import '../widgets/page_intro.dart';
import '../widgets/progress_ring.dart';
import '../widgets/section_header.dart';
import '../widgets/sync_status_banner.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final progressController = context.watch<ProgressController>();
    final progress = progressController.progress;
    final content = context.watch<ContentController>();
    final modules = content.modules;
    final awareness = content.awarenessItems;
    final nextLesson = _findNextLesson(
      modules,
      progress.completedLessonIds.toSet(),
    );
    final recommendation = _buildRecommendation(content, progressController);

    return AdaptiveBody(
      child: SingleChildScrollView(
        padding: AdaptiveLayout.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageIntro(
              title: 'Welcome back, ${auth.displayName}',
              description:
                  'Continue learning, strengthen a weak area, or check a new AI awareness update.',
              trailing: Wrap(
                spacing: AppSpacing.sm,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Sign out',
                    onPressed: auth.isLoading
                        ? null
                        : () => _signOut(context, auth),
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SyncStatusBanner(),
            const SizedBox(height: AppSpacing.md),
            const LiveContentBanner(),
            const SizedBox(height: AppSpacing.xxl),
            _ContinueLearningCard(
              lesson: nextLesson,
              completion: progress.completionRatio,
              onTap: nextLesson == null
                  ? null
                  : () => Navigator.pushNamed(
                      context,
                      AppRoutes.lesson,
                      arguments: nextLesson,
                    ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            LayoutBuilder(
              builder: (context, constraints) {
                final masteryCard = _MasteryCard(
                  completed: progress.completedLessons,
                  total: progress.totalLessons,
                  level: progress.knowledgeLevel,
                );
                final actionCard = _RecommendedActionCard(
                  recommendation: recommendation,
                  onTap: () => Navigator.pushNamed(
                    context,
                    recommendation.route,
                    arguments: recommendation.arguments,
                  ),
                );

                if (constraints.maxWidth >= 760) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: masteryCard),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(child: actionCard),
                    ],
                  );
                }

                return Column(
                  children: [
                    masteryCard,
                    const SizedBox(height: AppSpacing.lg),
                    actionCard,
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.section),
            SectionHeader(
              title: 'Current awareness update',
              subtitle: 'Review new risks and verification guidance.',
              actionLabel: 'View all',
              onAction: () => Navigator.pushNamed(context, AppRoutes.awareness),
            ),
            const SizedBox(height: AppSpacing.md),
            awareness.isEmpty
                ? const AppCard(
                    child: Text(
                      'Reviewed awareness updates will appear here when available.',
                    ),
                  )
                : _AwarenessPreview(
                    title: awareness.first.title,
                    summary: awareness.first.summary,
                    date: awareness.first.date,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.awareness),
                  ),
          ],
        ),
      ),
    );
  }

  _Recommendation _buildRecommendation(
    ContentController content,
    ProgressController progress,
  ) {
    for (final quiz in content.quizzes) {
      if (progress.bestScoreForQuiz(quiz.id) < 100) {
        return _Recommendation(
          title: 'Complete ${quiz.displayTitle}',
          description:
              'This knowledge check has not been completed with a correct answer yet.',
          actionLabel: 'Open knowledge check',
          icon: Icons.quiz_outlined,
          route: AppRoutes.quiz,
          arguments: quiz,
        );
      }
    }

    if (content.activities.isNotEmpty &&
        !progress.hasBadge(ProgressBadges.aiDetective)) {
      return const _Recommendation(
        title: 'Try a verification activity',
        description:
            'Inspect Real or AI comparison rounds and review the explanation after each choice.',
        actionLabel: 'Open verification activity',
        icon: Icons.image_search_outlined,
        route: AppRoutes.game,
      );
    }

    return const _Recommendation(
      title: 'Improve a prompt with the Coach',
      description:
          'Practice writing a clear prompt, review guided feedback, and revise it using your own words.',
      actionLabel: 'Open Prompt Coach',
      icon: Icons.edit_note_rounded,
      route: AppRoutes.sandbox,
    );
  }

  Future<void> _signOut(BuildContext context, AuthController auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your saved progress will remain connected to this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final success = await auth.signOut();
    if (!context.mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage ?? 'Sign out failed.')),
      );
      return;
    }

    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.root, (_) => false);
  }

  Lesson? _findNextLesson(
    List<Module> modules,
    Set<String> completedLessonIds,
  ) {
    for (final module in modules) {
      for (final lesson in module.lessons) {
        if (!completedLessonIds.contains(lesson.id)) return lesson;
      }
    }
    if (modules.isNotEmpty && modules.first.lessons.isNotEmpty) {
      return modules.first.lessons.first;
    }
    return null;
  }
}

class _ContinueLearningCard extends StatelessWidget {
  final Lesson? lesson;
  final double completion;
  final VoidCallback? onTap;

  const _ContinueLearningCard({
    required this.lesson,
    required this.completion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer
          .withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.28
                : 0.52,
          ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Continue learning',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                lesson?.title ?? 'All current lessons completed',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                lesson == null
                    ? 'Review a completed lesson or practice a weak topic.'
                    : '${lesson!.estimatedMinutes} min lesson · Pick up where you left off.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: completion,
                  minHeight: 9,
                  color: AppColors.primary,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${(completion * 100).round()}% of current lessons completed',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          );

          if (constraints.maxWidth >= 620) {
            return Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: AppSpacing.xxl),
                FilledButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Continue'),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              content,
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MasteryCard extends StatelessWidget {
  final int completed;
  final int total;
  final String level;

  const _MasteryCard({
    required this.completed,
    required this.total,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Learning progress',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '$completed of $total lessons completed',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Chip(
                avatar: const Icon(Icons.school_outlined, size: 18),
                label: Text(level),
              ),
            ],
          );

          if (constraints.maxWidth < 340) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: ProgressRing()),
                const SizedBox(height: AppSpacing.xl),
                details,
              ],
            );
          }

          return Row(
            children: [
              const ProgressRing(),
              const SizedBox(width: AppSpacing.xl),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _Recommendation {
  final String title;
  final String description;
  final String actionLabel;
  final IconData icon;
  final String route;
  final Object? arguments;

  const _Recommendation({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.icon,
    required this.route,
    this.arguments,
  });
}

class _RecommendedActionCard extends StatelessWidget {
  final _Recommendation recommendation;
  final VoidCallback onTap;

  const _RecommendedActionCard({
    required this.recommendation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(recommendation.icon, color: AppColors.teal),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Recommended next step',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            recommendation.title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            recommendation.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text(
                recommendation.actionLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AwarenessPreview extends StatelessWidget {
  final String title;
  final String summary;
  final String date;
  final VoidCallback onTap;

  const _AwarenessPreview({
    required this.title,
    required this.summary,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              Icons.campaign_outlined,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(date, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

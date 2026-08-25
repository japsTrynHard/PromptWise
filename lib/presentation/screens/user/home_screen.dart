import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/awareness_feed_controller.dart';
import '../../controllers/content_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../../data/models/learning_topic.dart';
import '../../../data/models/lesson.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/live_content_banner.dart';
import '../../widgets/page_intro.dart';
import '../../widgets/progress_ring.dart';
import '../../widgets/section_header.dart';
import '../../widgets/sync_status_banner.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final progressController = context.watch<ProgressController>();
    final progress = progressController.progress;
    final content = context.watch<ContentController>();
    final awarenessFeed = context.watch<AwarenessFeedController>();
    final adaptive = context.watch<AdaptiveLearningController>();
    final modules = content.modules;
    final awareness = awarenessFeed.articles;
    final nextLesson = _findNextLesson(
      modules,
      progress.completedLessonIds.toSet(),
      preferredTopic: adaptive.recommendedTopic,
    );
    final recommendation = _buildRecommendation(
      content,
      progressController,
      adaptive,
    );

    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.tablet;

    return AdaptiveBody(
      child: SingleChildScrollView(
        padding: AdaptiveLayout.pageInsets(
          context,
          top: compact ? AppSpacing.lg : AppSpacing.page,
          bottom: AppSpacing.section,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact)
              _CompactHomeHero(displayName: auth.displayName)
            else
              PageIntro(
                eyebrow: 'Home',
                title: 'Welcome back, ${auth.displayName}',
                description:
                    'Pick up where you left off, follow your learning path, or see what is new with AI.',
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
                  adaptiveMastery: adaptive.overallMastery,
                  diagnosticCompleted: adaptive.diagnosticCompleted,
                  weakestTopic: adaptive.weakestTopic?.label,
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.adaptiveLearning,
                  ),
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
              title: 'AI updates right now',
              subtitle: 'Fresh AI, deepfake, AI scam, and AI misinformation updates.',
              actionLabel: 'View all',
              onAction: () => Navigator.pushNamed(context, AppRoutes.awareness),
            ),
            const SizedBox(height: AppSpacing.md),
            awareness.isEmpty
                ? const AppCard(
                    child: Text(
                      'Fresh trusted AI awareness updates will appear here when available.',
                    ),
                  )
                : _AwarenessPreview(
                    title: awareness.first.title,
                    summary: awareness.first.summary,
                    date: '${awareness.first.sourceName} · ${_awarenessDate(awareness.first.publishedAt)}',
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
    AdaptiveLearningController adaptive,
  ) {
    if (!adaptive.diagnosticCompleted) {
      return const _Recommendation(
        title: 'Set up your learning path',
        description:
            'Answer five quick questions so PromptWise can suggest where to start and what to practice next.',
        actionLabel: 'Start check',
        icon: Icons.assignment_outlined,
        route: AppRoutes.diagnostic,
      );
    }

    final topic = adaptive.recommendedTopic;
    if (topic != null) {
      final dueForReview = adaptive.masteryFor(topic).isDueForReview;

      if (dueForReview) {
        for (final quiz in content.quizzes) {
          if (quiz.topic == topic) {
            return _Recommendation(
              title: 'Review ${topic.label}',
              description:
                  '${adaptive.recommendationReason} This check can update your progress and next review.',
              actionLabel: 'Open review check',
              icon: Icons.quiz_outlined,
              route: AppRoutes.quiz,
              arguments: quiz,
            );
          }
        }
        if (topic == LearningTopic.verification && content.activities.isNotEmpty) {
          return _Recommendation(
            title: 'Review verification',
            description:
                '${adaptive.recommendationReason} Try a Compare Images round for a quick review.',
            actionLabel: 'Open verification activity',
            icon: Icons.image_search_outlined,
            route: AppRoutes.imageCompare,
          );
        }
      }

      for (final module in content.modules) {
        for (final lesson in module.lessons) {
          if (lesson.topic != topic || !progress.isLessonCompleted(lesson.id)) {
            continue;
          }
          final linkedQuiz = content.findQuizById(lesson.quizId);
          if (linkedQuiz != null &&
              progress.bestScoreForQuiz(linkedQuiz.id) < 100 &&
              adaptive.canCountEvidenceNow(
                itemId: linkedQuiz.id,
                topic: topic,
              )) {
            return _Recommendation(
              title: 'Check ${topic.label}',
              description:
                  '${adaptive.recommendationReason} You finished the lesson. Try its quick check next.',
              actionLabel: 'Open linked check',
              icon: Icons.quiz_outlined,
              route: AppRoutes.quiz,
              arguments: linkedQuiz,
            );
          }
        }
      }

      for (final module in content.modules) {
        for (final lesson in module.lessons) {
          if (lesson.topic == topic && !progress.isLessonCompleted(lesson.id)) {
            return _Recommendation(
              title: 'Strengthen ${topic.label}',
              description:
                  '${adaptive.recommendationReason} Continue with ${lesson.title}. Your progress updates after the related knowledge check.',
              actionLabel: 'Open recommended lesson',
              icon: Icons.route_outlined,
              route: AppRoutes.lesson,
              arguments: lesson,
            );
          }
        }
      }

      for (final quiz in content.quizzes) {
        if (quiz.topic == topic &&
            progress.bestScoreForQuiz(quiz.id) < 100 &&
            adaptive.canCountEvidenceNow(itemId: quiz.id, topic: topic)) {
          return _Recommendation(
            title: 'Practice ${topic.label}',
            description:
                '${adaptive.recommendationReason} This quick check matches that skill.',
            actionLabel: 'Open recommended check',
            icon: Icons.quiz_outlined,
            route: AppRoutes.quiz,
            arguments: quiz,
          );
        }
      }

      if (topic == LearningTopic.verification &&
          content.activities.any(
            (activity) => adaptive.canCountEvidenceNow(
              itemId: activity.id,
              topic: LearningTopic.verification,
              attemptType: 'verification_activity',
            ),
          )) {
        return _Recommendation(
          title: 'Practice verification',
          description:
              '${adaptive.recommendationReason} Try Compare Images for a quick verification practice round.',
          actionLabel: 'Open verification activity',
          icon: Icons.image_search_outlined,
          route: AppRoutes.imageCompare,
        );
      }
    }

    for (final quiz in content.quizzes) {
      final quizTopic = quiz.topic;
      final canUseNow = quizTopic == null ||
          adaptive.canCountEvidenceNow(itemId: quiz.id, topic: quizTopic);
      if (progress.bestScoreForQuiz(quiz.id) < 100 && canUseNow) {
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

    if (content.activities.any(
          (activity) => adaptive.canCountEvidenceNow(
            itemId: activity.id,
            topic: LearningTopic.verification,
            attemptType: 'verification_activity',
          ),
        ) &&
        !progress.hasBadge(ProgressBadges.aiDetective)) {
      return const _Recommendation(
        title: 'Try a verification activity',
        description:
            'Compare two images, make a quick choice, then review the source information after each answer.',
        actionLabel: 'Open verification activity',
        icon: Icons.image_search_outlined,
        route: AppRoutes.imageCompare,
      );
    }

    return const _Recommendation(
      title: 'Review your learning path',
      description:
          'See your topic progress, upcoming reviews, and the next area PromptWise recommends.',
      actionLabel: 'View learning path',
      icon: Icons.route_outlined,
      route: AppRoutes.adaptiveLearning,
    );
  }

  Lesson? _findNextLesson(
    List<Module> modules,
    Set<String> completedLessonIds, {
    LearningTopic? preferredTopic,
  }) {
    if (preferredTopic != null) {
      for (final module in modules) {
        for (final lesson in module.lessons) {
          if (lesson.topic == preferredTopic &&
              !completedLessonIds.contains(lesson.id)) {
            return lesson;
          }
        }
      }
    }
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
  final int adaptiveMastery;
  final bool diagnosticCompleted;
  final String? weakestTopic;
  final VoidCallback onTap;

  const _MasteryCard({
    required this.completed,
    required this.total,
    required this.level,
    required this.adaptiveMastery,
    required this.diagnosticCompleted,
    required this.weakestTopic,
    required this.onTap,
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
              const SizedBox(height: AppSpacing.sm),
              Text(
                diagnosticCompleted
                    ? 'Learning progress: $adaptiveMastery%${weakestTopic == null ? '' : ' · Focus: $weakestTopic'}'
                    : 'Take the starting check to unlock personalized learning progress.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.route_outlined),
                label: const Text('View my learning path'),
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

class _CompactHomeHero extends StatelessWidget {
  final String displayName;

  const _CompactHomeHero({required this.displayName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = displayName.trim().isEmpty
        ? 'Learner'
        : displayName.trim().split(' ').first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.1),
                AppColors.teal.withValues(alpha: 0.07),
              ],
            ),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.teal],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'HOME',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.85,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Welcome back, $firstName',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.9,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Continue where you left off, check your progress, and stay updated with AI.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
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

String _awarenessDate(DateTime? value) {
  if (value == null) return 'Recent';
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} min ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${value.month}/${value.day}/${value.year}';
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

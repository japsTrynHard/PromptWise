import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/content_controller.dart';
import '../../controllers/learning_progression_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../../data/models/adaptive_learning.dart';
import '../../../data/models/learning_progression.dart';
import '../../../data/models/learning_topic.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/quiz.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_intro.dart';
import '../../widgets/promptwise_app_bar.dart';
import '../../widgets/section_header.dart';
import './adaptive_knowledge_check_screen.dart';

class AdaptiveLearningScreen extends StatefulWidget {
  const AdaptiveLearningScreen({super.key});

  @override
  State<AdaptiveLearningScreen> createState() => _AdaptiveLearningScreenState();
}

class _AdaptiveLearningScreenState extends State<AdaptiveLearningScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<LearningProgressionController>().ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final adaptive = context.watch<AdaptiveLearningController>();
    final content = context.watch<ContentController>();
    final progress = context.watch<ProgressController>();
    final progression = context.watch<LearningProgressionController>();
    final recommendedTopic = adaptive.recommendedTopic;
    final recommendedContent = recommendedTopic == null
        ? null
        : _findRecommendation(
            content: content,
            progress: progress,
            topic: recommendedTopic,
            dueForReview: adaptive.masteryFor(recommendedTopic).isDueForReview,
            adaptive: adaptive,
          );

    return Scaffold(
      appBar: const PromptWiseAppBar(
        eyebrow: 'LEARN · PERSONAL PATH',
        title: 'My Learning Path',
        subtitle: 'See what to focus on next and how your skills are improving.',
        backTooltip: 'Back to Learn',
      ),
      body: AdaptiveBody(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait<void>([
              content.refresh(),
              progress.refreshFromCloud(),
              adaptive.refreshFromCloud(),
              progression.refresh(),
            ]);
            await adaptive.synchronizeExistingProgress(
              quizzes: content.quizzes,
              bestScores: progress.progress.quizBestScores,
            );
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: AdaptiveLayout.pageInsets(context),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (!AdaptiveLayout.isPhone(context))
                      const PageIntro(
                        eyebrow: 'Learning path',
                        title: 'Your learning path',
                        description:
                            'PromptWise uses your starting check and recent practice to show what to focus on next.',
                      ),
                    if (adaptive.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppCard(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withValues(alpha: 0.45),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.cloud_off_outlined),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: Text(adaptive.errorMessage!)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    _OverviewCard(
                      adaptive: adaptive,
                      progression: progression,
                    ),
                    if (!adaptive.diagnosticCompleted) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _DiagnosticCard(
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.diagnostic,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.section),
                    const SectionHeader(
                      title: 'Your skill progress',
                      subtitle:
                          'Your progress updates from your starting check and meaningful practice. Repeating the same activity right away will not raise it twice.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ...LearningTopic.values.map(
                      (topic) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _TopicMasteryCard(
                          mastery: adaptive.masteryFor(topic),
                          rank: progression.rankFor(topic),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.section),
                    const SectionHeader(
                      title: 'Recommended next step',
                      subtitle:
                          'PromptWise shows reviews that are due first, then the area that needs the most practice.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _RecommendationCard(
                      adaptive: adaptive,
                      progression: progression,
                      recommendation: recommendedContent,
                    ),
                    if (adaptive.dueReviews.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.section),
                      const SectionHeader(
                        title: 'Due for review',
                        subtitle:
                            'Topics that need more practice come back sooner. Stronger topics come back later.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ...adaptive.dueReviews.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppCard(
                            child: Row(
                              children: [
                                const Icon(Icons.event_repeat_outlined),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Text(
                                    '${item.topic.label} is ready for review.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _AdaptiveRecommendation? _findRecommendation({
    required ContentController content,
    required ProgressController progress,
    required LearningTopic topic,
    required bool dueForReview,
    required AdaptiveLearningController adaptive,
  }) {
    // Due reviews should produce assessment evidence, not another reading-only
    // step. This makes the recommendation visibly capable of changing mastery.
    if (dueForReview) {
      for (final quiz in content.quizzes) {
        if (quiz.topic == topic) {
          return _AdaptiveRecommendation.quiz(quiz, review: true);
        }
      }
      if (topic == LearningTopic.verification && content.activities.isNotEmpty) {
        return const _AdaptiveRecommendation.verification();
      }
    }

    // After a learner completes a lesson, prioritize its linked knowledge check
    // before moving them to another lesson in the same topic.
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
          return _AdaptiveRecommendation.quiz(linkedQuiz);
        }
      }
    }

    for (final module in content.modules) {
      for (final lesson in module.lessons) {
        if (lesson.topic == topic && !progress.isLessonCompleted(lesson.id)) {
          return _AdaptiveRecommendation.lesson(lesson);
        }
      }
    }

    for (final quiz in content.quizzes) {
      if (quiz.topic == topic &&
          progress.bestScoreForQuiz(quiz.id) < 100 &&
          adaptive.canCountEvidenceNow(itemId: quiz.id, topic: topic)) {
        return _AdaptiveRecommendation.quiz(quiz);
      }
    }

    if (topic == LearningTopic.verification) {
      final hasEligibleActivity = content.activities.any(
        (activity) => adaptive.canCountEvidenceNow(
          itemId: activity.id,
          topic: LearningTopic.verification,
          attemptType: 'verification_activity',
        ),
      );
      if (hasEligibleActivity) {
        return const _AdaptiveRecommendation.verification();
      }
    }

    // Everything currently available for this topic has already contributed
    // evidence and the review window is not due yet. Do not recommend a retry
    // that the mastery engine will intentionally ignore.
    return null;
  }

}

class _OverviewCard extends StatelessWidget {
  final AdaptiveLearningController adaptive;
  final LearningProgressionController progression;

  const _OverviewCard({
    required this.adaptive,
    required this.progression,
  });

  @override
  Widget build(BuildContext context) {
    final weakest = adaptive.weakestTopic;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.5,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final score = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Overall progress',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${adaptive.overallMastery}%',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'AI literacy rank: ${progression.overallRankLabel}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                adaptive.diagnosticCompleted
                    ? weakest == null
                          ? 'Complete a learning activity to start building your progress.'
                          : 'Current focus: ${weakest.label}'
                    : 'Starting check not completed yet.',
              ),
            ],
          );

          final status = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusLine(
                icon: adaptive.diagnosticCompleted
                    ? Icons.check_circle_outline_rounded
                    : Icons.assignment_outlined,
                text: adaptive.diagnosticCompleted
                    ? 'Starting check completed'
                    : 'Starting check pending',
              ),
              const SizedBox(height: AppSpacing.sm),
              _StatusLine(
                icon: Icons.event_repeat_outlined,
                text:
                    '${adaptive.dueReviews.length} topic${adaptive.dueReviews.length == 1 ? '' : 's'} due for review',
              ),
              const SizedBox(height: AppSpacing.sm),
              _StatusLine(
                icon: Icons.route_outlined,
                text: adaptive.recommendationReason,
              ),
            ],
          );

          if (constraints.maxWidth >= 620) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: score),
                const SizedBox(width: AppSpacing.xxl),
                Expanded(child: status),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              score,
              const SizedBox(height: AppSpacing.xl),
              status,
            ],
          );
        },
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _StatusLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  final VoidCallback onTap;

  const _DiagnosticCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: const Icon(Icons.assignment_outlined),
          ),
          const SizedBox(width: AppSpacing.lg),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Take the starting check',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  'Answer five short questions so PromptWise can understand your starting level in each topic.',
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _TopicMasteryCard extends StatelessWidget {
  final TopicMastery mastery;
  final LearnerTopicRank rank;

  const _TopicMasteryCard({
    required this.mastery,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_topicIcon(mastery.topic), color: colorScheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  mastery.topic.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    mastery.attempts == 0 ? 'Not started' : '${mastery.mastery}%',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rank.displayLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            mastery.topic.shortDescription,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: mastery.attempts == 0 ? 0 : mastery.mastery / 100,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            mastery.attempts == 0
                ? 'Complete the starting check or a related quick check.'
                : 'Practice: ${mastery.attempts} counted · ${mastery.correctAnswers} correct · ${_reviewLabel(mastery.nextReviewAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Level progress: ${rank.progress}% · Lessons covered: ${rank.objectiveCoverage}% · Highest difficulty completed: ${rank.highestDifficultyPassed}/5',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final AdaptiveLearningController adaptive;
  final LearningProgressionController progression;
  final _AdaptiveRecommendation? recommendation;

  const _RecommendationCard({
    required this.adaptive,
    required this.progression,
    required this.recommendation,
  });

  @override
  Widget build(BuildContext context) {
    if (!adaptive.diagnosticCompleted) {
      return AppCard(
        onTap: () => Navigator.pushNamed(context, AppRoutes.diagnostic),
        child: const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.assignment_outlined),
          title: Text('Complete your starting check'),
          subtitle: Text(
            'PromptWise needs a short starting check before it can recommend the right learning content.',
          ),
          trailing: Icon(Icons.chevron_right_rounded),
        ),
      );
    }

    final topic = adaptive.recommendedTopic ?? adaptive.weakestTopic;
    if (topic == null) {
      return AppCard(
        child: const Text(
          'Complete a quick check so PromptWise has enough recent progress to suggest your next step.',
        ),
      );
    }

    final mastery = adaptive.masteryFor(topic);
    final rank = progression.rankFor(topic);
    final isDue = mastery.isDueForReview;
    final legacy = recommendation;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.38,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                child: Icon(isDue ? Icons.event_repeat_rounded : Icons.route_rounded),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDue ? '${topic.label} review is ready' : 'Strengthen ${topic.label}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${rank.displayLabel} · ${mastery.mastery}% progress',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            isDue
                ? 'Your spaced review is due. PromptWise will select fresh questions around this competency and adjust their difficulty to your current rank.'
                : '${topic.label} is the area that needs the most practice right now. Start a focused set instead of repeating one fixed quiz.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              Chip(label: Text('Rank ${rank.displayLabel}')),
              Chip(label: Text('${rank.objectiveCoverage}% objectives covered')),
              Chip(label: Text(isDue ? 'Review due' : _reviewLabel(mastery.nextReviewAt))),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.pushNamed(
                  context,
                  AppRoutes.adaptiveKnowledgeCheck,
                  arguments: AdaptiveKnowledgeCheckArgs(
                    focusTopic: topic,
                    mode: isDue ? 'review' : 'adaptive',
                    questionCount: isDue ? 8 : 10,
                  ),
                ),
                icon: Icon(isDue ? Icons.event_repeat_rounded : Icons.play_arrow_rounded),
                label: Text(isDue ? 'Start Review' : 'Start Practice'),
              ),
              if (legacy != null && legacy.route == AppRoutes.lesson)
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    legacy.route,
                    arguments: legacy.arguments,
                  ),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Review Learning Material'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdaptiveRecommendation {
  final String title;
  final String route;
  final Object? arguments;
  final IconData icon;
  final bool review;

  const _AdaptiveRecommendation({
    required this.title,
    required this.route,
    this.arguments,
    required this.icon,
    required this.review,
  });


  const _AdaptiveRecommendation.verification()
    : title = 'Practice image verification',
      route = AppRoutes.imageCompare,
      arguments = null,
      icon = Icons.image_search_outlined,
      review = false;

  factory _AdaptiveRecommendation.lesson(Lesson lesson, {bool review = false}) {
    return _AdaptiveRecommendation(
      title: review ? 'Review ${lesson.title}' : 'Continue with ${lesson.title}',
      route: AppRoutes.lesson,
      arguments: lesson,
      icon: Icons.menu_book_outlined,
      review: review,
    );
  }

  factory _AdaptiveRecommendation.quiz(Quiz quiz, {bool review = false}) {
    return _AdaptiveRecommendation(
      title: review ? 'Retry ${quiz.displayTitle}' : 'Try ${quiz.displayTitle}',
      route: AppRoutes.quiz,
      arguments: quiz,
      icon: Icons.quiz_outlined,
      review: review,
    );
  }
}

IconData _topicIcon(LearningTopic topic) => switch (topic) {
  LearningTopic.promptClarity => Icons.chat_bubble_outline_rounded,
  LearningTopic.context => Icons.subject_rounded,
  LearningTopic.specificity => Icons.tune_rounded,
  LearningTopic.responsibleUse => Icons.shield_outlined,
  LearningTopic.verification => Icons.fact_check_outlined,
};

String _reviewLabel(DateTime? value) {
  if (value == null) return 'Next review: not scheduled';
  final now = DateTime.now();
  final difference = value.difference(now);
  if (difference.inMinutes <= 0) return 'Review due now';
  if (difference.inHours < 24) {
    return 'Next review: ${difference.inHours + 1}h';
  }
  final days = difference.inDays + 1;
  return 'Next review: $days day${days == 1 ? '' : 's'}';
}

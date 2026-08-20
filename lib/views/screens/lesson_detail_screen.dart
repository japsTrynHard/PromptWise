import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/content_controller.dart';
import '../../controllers/learning_progression_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../models/learning_progression.dart';
import '../../models/lesson.dart';
import '../../models/learning_topic.dart';
import '../../routes/app_routes.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/lesson_dictionary_panel.dart';
import '../widgets/state_message.dart';
import 'adaptive_knowledge_check_screen.dart';

class LessonDetailScreen extends StatefulWidget {
  final Lesson lesson;

  const LessonDetailScreen({super.key, required this.lesson});

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen> {
  bool _isSaving = false;

  Future<void> _completeAndPractice() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    await context.read<ProgressController>().completeLesson(widget.lesson.id);

    if (!mounted) return;
    setState(() => _isSaving = false);

    final topic = widget.lesson.topic;
    if (topic != null) {
      await Navigator.pushNamed(
        context,
        AppRoutes.adaptiveKnowledgeCheck,
        arguments: AdaptiveKnowledgeCheckArgs(
          focusTopic: topic,
          questionCount: 6,
        ),
      );
      return;
    }

    final quiz = context.read<ContentController>().findQuizById(
      widget.lesson.quizId,
    );
    if (quiz != null && mounted) {
      await Navigator.pushNamed(context, AppRoutes.quiz, arguments: quiz);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final progression = context.watch<LearningProgressionController>();
    final objectives = progression.objectivesForContent(lesson.id);
    final isCompleted = context.watch<ProgressController>().isLessonCompleted(
      lesson.id,
    );

    if (lesson.content.trim().isEmpty) {
      return const Scaffold(
        body: StateMessage.error(
          title: 'Lesson unavailable',
          message: 'This lesson does not contain readable content.',
        ),
      );
    }

    final document = _LessonDocument.parse(lesson.content);
    final rank = LearningRankX.fromLevel(lesson.learningLevel);
    final topicLabel = lesson.topic?.label ?? 'AI literacy';

    return Scaffold(
      appBar: AppBar(title: Text(topicLabel)),
      body: AdaptiveBody(
        maxWidth: 1180,
        child: SingleChildScrollView(
          padding: AdaptiveLayout.pageInsets(
            context,
            top: AppSpacing.lg,
            bottom: AppSpacing.section,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LessonHero(
                lesson: lesson,
                rank: rank,
                topicLabel: topicLabel,
                isCompleted: isCompleted,
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (objectives.isNotEmpty) ...[
                _ObjectivesCard(objectives: objectives),
                const SizedBox(height: AppSpacing.xxl),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final main = _LessonReadingColumn(
                    document: document,
                    topicLabel: topicLabel,
                    lessonTitle: lesson.title,
                    lessonContent: lesson.content,
                    isSaving: _isSaving,
                    isCompleted: isCompleted,
                    onPractice: _completeAndPractice,
                  );

                  if (constraints.maxWidth < 920) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LessonRoadmapCard(document: document),
                        const SizedBox(height: AppSpacing.xxl),
                        main,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 270,
                        child: _LessonRoadmapCard(document: document),
                      ),
                      const SizedBox(width: AppSpacing.xxl),
                      Expanded(child: main),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonHero extends StatelessWidget {
  final Lesson lesson;
  final LearningRank rank;
  final String topicLabel;
  final bool isCompleted;

  const _LessonHero({
    required this.lesson,
    required this.rank,
    required this.topicLabel,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: 0.82),
            colors.secondaryContainer.withValues(alpha: 0.48),
          ],
        ),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _MetaPill(icon: Icons.school_outlined, label: topicLabel),
                  _MetaPill(
                    icon: Icons.trending_up_rounded,
                    label: '${rank.label} · Level ${rank.level}',
                  ),
                  _MetaPill(
                    icon: Icons.schedule_rounded,
                    label: '${lesson.estimatedMinutes} min read',
                  ),
                  _MetaPill(
                    icon: isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.play_circle_outline_rounded,
                    label: isCompleted ? 'Completed' : 'In progress',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                lesson.title,
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Learn the idea in short sections, apply it to a realistic situation, then prove your understanding in an adaptive check.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );

          if (constraints.maxWidth < 760) return text;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: text),
              const SizedBox(width: AppSpacing.xxl),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: 52,
                  color: colors.primary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: colors.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ObjectivesCard extends StatelessWidget {
  final List<LearningObjective> objectives;

  const _ObjectivesCard({required this.objectives});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.14 : 0.34,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.track_changes_rounded, color: colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'What you should be able to do',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'These objectives define what the Knowledge Check can assess.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            runSpacing: AppSpacing.md,
            children: [
              for (var index = 0; index < objectives.length; index++)
                SizedBox(
                  width: double.infinity,
                  child: _ObjectiveRow(
                    number: index + 1,
                    objective: objectives[index],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ObjectiveRow extends StatelessWidget {
  final int number;
  final LearningObjective objective;

  const _ObjectiveRow({required this.number, required this.objective});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                objective.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (objective.description.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  objective.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LessonRoadmapCard extends StatelessWidget {
  final _LessonDocument document;

  const _LessonRoadmapCard({required this.document});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final concepts = document.sections
        .where((section) => section.type == _LessonSectionType.concept)
        .toList(growable: false);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Lesson map',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (document.intro.isNotEmpty)
            _RoadmapLine(
              number: 0,
              label: 'Overview',
              emphasized: true,
            ),
          for (var index = 0; index < concepts.length; index++)
            _RoadmapLine(number: index + 1, label: concepts[index].title),
          if (document.hasScenario)
            const _RoadmapLine(
              number: -1,
              label: 'Applied scenario',
              icon: Icons.lightbulb_outline_rounded,
            ),
          if (document.hasTakeaways)
            const _RoadmapLine(
              number: -1,
              label: 'Key takeaways',
              icon: Icons.bookmark_added_outlined,
            ),
          const Divider(height: AppSpacing.xxl),
          Text(
            'Tip',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Do not memorize the wording. Focus on why each idea works and when you would apply it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadmapLine extends StatelessWidget {
  final int number;
  final String label;
  final IconData? icon;
  final bool emphasized;

  const _RoadmapLine({
    required this.number,
    required this.label,
    this.icon,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: icon != null
                ? Icon(icon, size: 19, color: theme.colorScheme.primary)
                : Text(
                    number == 0 ? '•' : '$number',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonReadingColumn extends StatelessWidget {
  final _LessonDocument document;
  final String topicLabel;
  final String lessonTitle;
  final String lessonContent;
  final bool isSaving;
  final bool isCompleted;
  final VoidCallback onPractice;

  const _LessonReadingColumn({
    required this.document,
    required this.topicLabel,
    required this.lessonTitle,
    required this.lessonContent,
    required this.isSaving,
    required this.isCompleted,
    required this.onPractice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Learn the concepts',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Text(
              '${document.conceptCount} core concepts',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Each section is intentionally short. Read one idea, understand the example, then move to the next.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (document.intro.isNotEmpty) ...[
          _IntroCard(text: document.intro),
          const SizedBox(height: AppSpacing.lg),
        ],
        for (var index = 0; index < document.sections.length; index++) ...[
          _LessonSectionCard(section: document.sections[index], index: index),
          if (index != document.sections.length - 1)
            const SizedBox(height: AppSpacing.lg),
        ],
        const SizedBox(height: AppSpacing.xxl),
        LessonDictionaryPanel(
          lessonTitle: lessonTitle,
          lessonContent: lessonContent,
        ),
        const SizedBox(height: AppSpacing.xxl),
        _ReflectionCard(topicLabel: topicLabel),
        const SizedBox(height: AppSpacing.xxl),
        _LessonActionCard(
          isSaving: isSaving,
          isCompleted: isCompleted,
          onPressed: onPractice,
        ),
      ],
    );
  }
}

class _IntroCard extends StatelessWidget {
  final String text;

  const _IntroCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.explore_outlined, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why this matters',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.65),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonSectionCard extends StatelessWidget {
  final _LessonSection section;
  final int index;

  const _LessonSectionCard({required this.section, required this.index});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (section.type == _LessonSectionType.scenario) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.18 : 0.52,
          ),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded, color: colors.tertiary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Applied scenario',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SelectableText(
              section.body,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.68),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Ask yourself: what changed between the simple request and the stronger one?',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    if (section.type == _LessonSectionType.takeaways) {
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        backgroundColor: colors.secondaryContainer.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.14 : 0.36,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bookmark_added_outlined, color: colors.secondary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Key takeaways',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final item in section.items) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: colors.secondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CORE CONCEPT',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        section.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              0,
              AppSpacing.xxl,
              AppSpacing.xxl,
            ),
            child: SelectableText(
              section.body,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.72,
                letterSpacing: 0.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReflectionCard extends StatelessWidget {
  final String topicLabel;

  const _ReflectionCard({required this.topicLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      backgroundColor: AppColors.teal.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.10 : 0.08,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.psychology_outlined, color: AppColors.teal),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pause and explain it',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Before the Knowledge Check, explain the main $topicLabel idea in your own words and apply it to a situation that was not shown in the lesson.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonActionCard extends StatelessWidget {
  final bool isSaving;
  final bool isCompleted;
  final VoidCallback onPressed;

  const _LessonActionCard({
    required this.isSaving,
    required this.isCompleted,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCompleted ? 'Ready for another challenge?' : 'Ready to prove it?',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'PromptWise will choose questions based on this topic, your current mastery, and the difficulty you have already demonstrated.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.86),
                  height: 1.45,
                ),
              ),
            ],
          );

          final button = FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.surface,
              foregroundColor: theme.colorScheme.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.lg,
              ),
            ),
            onPressed: isSaving ? null : onPressed,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_rounded),
            label: Text(
              isCompleted ? 'Practice again' : 'Start Knowledge Check',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          );

          if (constraints.maxWidth >= 620) {
            return Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: AppSpacing.xl),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: AppSpacing.lg),
              button,
            ],
          );
        },
      ),
    );
  }
}

enum _LessonSectionType { concept, scenario, takeaways }

class _LessonSection {
  final _LessonSectionType type;
  final String title;
  final String body;
  final List<String> items;

  const _LessonSection.concept({required this.title, required this.body})
      : type = _LessonSectionType.concept,
        items = const [];

  const _LessonSection.scenario(this.body)
      : type = _LessonSectionType.scenario,
        title = 'Applied scenario',
        items = const [];

  const _LessonSection.takeaways(this.items)
      : type = _LessonSectionType.takeaways,
        title = 'Key takeaways',
        body = '';
}

class _LessonDocument {
  final String intro;
  final List<_LessonSection> sections;

  const _LessonDocument({required this.intro, required this.sections});

  int get conceptCount =>
      sections.where((section) => section.type == _LessonSectionType.concept).length;

  bool get hasScenario =>
      sections.any((section) => section.type == _LessonSectionType.scenario);

  bool get hasTakeaways =>
      sections.any((section) => section.type == _LessonSectionType.takeaways);

  static _LessonDocument parse(String content) {
    final normalized = content.replaceAll('\r\n', '\n').trim();
    final chunks = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((chunk) => chunk.trim())
        .where((chunk) => chunk.isNotEmpty)
        .toList(growable: false);

    var intro = '';
    final sections = <_LessonSection>[];
    String? pendingHeading;

    for (final chunk in chunks) {
      final lines = chunk
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;

      if (RegExp(r'^LEVEL\s+\d+\s*:', caseSensitive: false)
          .hasMatch(lines.first)) {
        if (lines.length == 1) continue;
        lines.removeAt(0);
        if (lines.isEmpty) continue;
      }

      final first = lines.first;
      final lower = first.toLowerCase();

      if (lower == 'applied scenario') {
        final body = lines.skip(1).join(' ').trim();
        if (body.isNotEmpty) {
          sections.add(_LessonSection.scenario(body));
        } else {
          pendingHeading = 'applied scenario';
        }
        continue;
      }

      if (lower == 'key takeaways') {
        final items = _extractBullets(lines.skip(1));
        if (items.isNotEmpty) {
          sections.add(_LessonSection.takeaways(items));
        } else {
          pendingHeading = 'key takeaways';
        }
        continue;
      }

      if (pendingHeading != null) {
        if (pendingHeading == 'applied scenario') {
          sections.add(_LessonSection.scenario(lines.join(' ')));
        } else if (pendingHeading == 'key takeaways') {
          sections.add(_LessonSection.takeaways(_extractBullets(lines)));
        } else {
          sections.add(
            _LessonSection.concept(
              title: pendingHeading,
              body: lines.join(' '),
            ),
          );
        }
        pendingHeading = null;
        continue;
      }

      if (lines.length > 1 && _looksLikeHeading(first)) {
        final bodyLines = lines.skip(1).toList(growable: false);
        if (first.toLowerCase() == 'key takeaways') {
          sections.add(_LessonSection.takeaways(_extractBullets(bodyLines)));
        } else if (first.toLowerCase() == 'applied scenario') {
          sections.add(_LessonSection.scenario(bodyLines.join(' ')));
        } else {
          sections.add(
            _LessonSection.concept(
              title: first,
              body: bodyLines.join(' '),
            ),
          );
        }
        continue;
      }

      if (lines.length == 1 && _looksLikeHeading(first)) {
        pendingHeading = first;
        continue;
      }

      final isBulletChunk = lines.every(
        (line) => line.startsWith('- ') || line.startsWith('• '),
      );
      if (isBulletChunk) {
        sections.add(_LessonSection.takeaways(_extractBullets(lines)));
        continue;
      }

      if (intro.isEmpty) {
        intro = lines.join(' ');
      } else {
        sections.add(
          _LessonSection.concept(
            title: 'Build the idea',
            body: lines.join(' '),
          ),
        );
      }
    }

    if (pendingHeading != null && pendingHeading.trim().isNotEmpty) {
      sections.add(
        _LessonSection.concept(
          title: pendingHeading,
          body: 'Review this idea and connect it to the lesson objective above.',
        ),
      );
    }

    return _LessonDocument(
      intro: intro,
      sections: List.unmodifiable(sections),
    );
  }

  static List<String> _extractBullets(Iterable<String> lines) {
    final result = <String>[];
    for (final line in lines) {
      final cleaned = line
          .replaceFirst(RegExp(r'^[-•]\s*'), '')
          .trim();
      if (cleaned.isNotEmpty) result.add(cleaned);
    }
    return result;
  }

  static bool _looksLikeHeading(String value) {
    final text = value.trim();
    if (text.isEmpty || text.length > 72) return false;
    if (text.endsWith('.') || text.endsWith('?') || text.endsWith('!')) {
      return false;
    }
    if (text.startsWith('- ') || text.startsWith('• ')) return false;
    final words = text.split(RegExp(r'\s+'));
    return words.length <= 10;
  }
}

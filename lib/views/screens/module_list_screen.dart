import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/learning_progression_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../models/learning_progression.dart';
import '../../models/lesson.dart';
import '../../routes/app_routes.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/page_intro.dart';
import '../widgets/state_message.dart';

class ModuleListScreen extends StatelessWidget {
  final Module module;

  const ModuleListScreen({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    final progressController = context.watch<ProgressController>();
    final progression = context.watch<LearningProgressionController>();
    final completed = module.lessons
        .where((lesson) => progressController.isLessonCompleted(lesson.id))
        .length;
    final ratio = module.lessons.isEmpty
        ? 0.0
        : (completed / module.lessons.length).clamp(0, 1).toDouble();
    final totalMinutes = module.lessons.fold<int>(
      0,
      (total, lesson) => total + lesson.estimatedMinutes,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Learning Module')),
      body: module.lessons.isEmpty
          ? const StateMessage.empty(
              title: 'No lessons available',
              message: 'This module does not contain any lessons yet.',
            )
          : AdaptiveBody(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: AdaptiveLayout.pageInsets(
                      context,
                      top: AppSpacing.sm,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        PageIntro(
                          title: module.title,
                          description: module.description,
                          trailing: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Icon(
                              AppIcons.module(module.icon),
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        AppCard(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(
                                alpha:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? 0.22
                                    : 0.48,
                              ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Module progress',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  Text(
                                    '$completed/${module.lessons.length}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  minHeight: 9,
                                  color: AppColors.primary,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.surface.withValues(alpha: 0.75),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Wrap(
                                spacing: AppSpacing.lg,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  _ModuleMeta(
                                    icon: Icons.schedule_rounded,
                                    text: '$totalMinutes minutes total',
                                  ),
                                  _ModuleMeta(
                                    icon: Icons.menu_book_outlined,
                                    text: '${module.lessons.length} lessons',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.section),
                        Text(
                          'Lessons',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ]),
                    ),
                  ),
                  SliverPadding(
                    padding: AdaptiveLayout.pageInsets(context, top: 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final lesson = module.lessons[index];
                        final isCompleted = progressController
                            .isLessonCompleted(lesson.id);
                        final topic = lesson.topic ?? module.topic;
                        final topicRank = topic == null
                            ? null
                            : progression.rankFor(topic);
                        final unlocked = topicRank == null ||
                            lesson.learningLevel <= topicRank.rank.level + 1;

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == module.lessons.length - 1
                                ? 0
                                : AppSpacing.md,
                          ),
                          child: AppCard(
                            onTap: unlocked
                                ? () => Navigator.pushNamed(
                                      context,
                                      AppRoutes.lesson,
                                      arguments: lesson,
                                    )
                                : null,
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isCompleted
                                        ? AppColors.success.withValues(
                                            alpha: 0.13,
                                          )
                                        : Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                  ),
                                  child: Center(
                                    child: isCompleted
                                        ? const Icon(
                                            Icons.check_rounded,
                                            color: AppColors.success,
                                          )
                                        : Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              lesson.title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Chip(
                                            visualDensity: VisualDensity.compact,
                                            label: Text(
                                              LearningRankX.fromLevel(
                                                lesson.learningLevel,
                                              ).label,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        !unlocked
                                            ? 'Locked until your current rank is ready for this challenge.'
                                            : isCompleted
                                                ? '${lesson.estimatedMinutes} min · Completed'
                                                : '${lesson.estimatedMinutes} min · ${topicRank?.displayLabel ?? 'Open level'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  unlocked
                                      ? Icons.chevron_right_rounded
                                      : Icons.lock_outline_rounded,
                                ),
                              ],
                            ),
                          ),
                        );
                      }, childCount: module.lessons.length),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ModuleMeta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ModuleMeta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.xs),
        Text(text),
      ],
    );
  }
}

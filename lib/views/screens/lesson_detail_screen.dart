import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/content_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../models/lesson.dart';
import '../../routes/app_routes.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/state_message.dart';
import '../widgets/lesson_dictionary_panel.dart';

class LessonDetailScreen extends StatefulWidget {
  final Lesson lesson;

  const LessonDetailScreen({super.key, required this.lesson});

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen> {
  bool _isSaving = false;

  Future<void> _completeAndOpenQuiz() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    await context.read<ProgressController>().completeLesson(widget.lesson.id);

    if (!mounted) return;

    final quiz = context.read<ContentController>().findQuizById(
      widget.lesson.quizId,
    );

    setState(() => _isSaving = false);

    if (quiz == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The lesson was completed, but its quiz is currently unavailable.',
          ),
        ),
      );
      return;
    }

    await Navigator.pushNamed(context, AppRoutes.quiz, arguments: quiz);
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final isCompleted = context.watch<ProgressController>().isLessonCompleted(
      lesson.id,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Lesson')),
      body: lesson.content.trim().isEmpty
          ? const StateMessage.error(
              title: 'Lesson unavailable',
              message: 'This lesson does not contain readable content.',
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
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.sm,
                                  children: [
                                    Chip(
                                      avatar: const Icon(
                                        Icons.schedule_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        '${lesson.estimatedMinutes} min read',
                                      ),
                                    ),
                                    Chip(
                                      avatar: Icon(
                                        isCompleted
                                            ? Icons.check_circle_outline_rounded
                                            : Icons
                                                  .radio_button_unchecked_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        isCompleted
                                            ? 'Completed'
                                            : 'In progress',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                Text(
                                  lesson.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'Read the explanation, identify the main idea, then take the short knowledge check.',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        height: 1.5,
                                      ),
                                ),
                                const SizedBox(height: AppSpacing.xxl),
                                AppCard(
                                  padding: const EdgeInsets.all(28),
                                  child: SelectableText(
                                    lesson.content,
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(height: 1.75),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                LessonDictionaryPanel(
                                  lessonTitle: lesson.title,
                                  lessonContent: lesson.content,
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                AppCard(
                                  backgroundColor: AppColors.teal.withValues(
                                    alpha:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.1
                                        : 0.08,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.lightbulb_outline_rounded,
                                        color: AppColors.teal,
                                      ),
                                      const SizedBox(width: AppSpacing.md),
                                      Expanded(
                                        child: Text(
                                          'Learning check: Can you explain the key idea without copying the lesson wording, and can you identify what still needs verification?',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(height: 1.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.section),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isSaving
                                        ? null
                                        : _completeAndOpenQuiz,
                                    icon: _isSaving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(
                                            isCompleted
                                                ? Icons.quiz_outlined
                                                : Icons
                                                      .check_circle_outline_rounded,
                                          ),
                                    label: Text(
                                      _isSaving
                                          ? 'Saving progress...'
                                          : isCompleted
                                          ? 'Retake Knowledge Check'
                                          : 'Complete Lesson and Continue',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

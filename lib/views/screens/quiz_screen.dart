import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../models/learning_topic.dart';
import '../../models/quiz.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/page_intro.dart';
import '../widgets/state_message.dart';

class QuizScreen extends StatefulWidget {
  final Quiz quiz;

  const QuizScreen({super.key, required this.quiz});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int? _selectedIndex;
  bool _answered = false;
  bool _isSubmitting = false;
  bool _scoreAdded = false;
  bool _masteryCounted = false;

  bool get _isCorrect => _selectedIndex == widget.quiz.correctIndex;

  Future<void> _submitAnswer() async {
    if (_selectedIndex == null || _answered || _isSubmitting) return;

    setState(() {
      _answered = true;
      _isSubmitting = true;
    });

    // Record adaptive evidence before updating the legacy best-score map.
    // Otherwise the progress provider can observe the new 100% score first and
    // mistakenly import it as pre-Phase-6 legacy evidence, double-counting the
    // same answer.
    final topic = widget.quiz.topic;
    var masteryCounted = false;
    if (topic != null) {
      masteryCounted = await context
          .read<AdaptiveLearningController>()
          .recordPracticeAttempt(
            itemId: widget.quiz.id,
            topic: topic,
            isCorrect: _isCorrect,
            attemptType: 'quiz',
          );
    }
    if (!mounted) return;

    final scoreAdded = await context
        .read<ProgressController>()
        .recordQuizResult(quizId: widget.quiz.id, isCorrect: _isCorrect);

    if (!mounted) return;
    setState(() {
      _scoreAdded = scoreAdded;
      _masteryCounted = masteryCounted;
      _isSubmitting = false;
    });
  }

  void _tryAgain() {
    setState(() {
      _selectedIndex = null;
      _answered = false;
      _isSubmitting = false;
      _scoreAdded = false;
      _masteryCounted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final quiz = widget.quiz;

    return Scaffold(
      appBar: AppBar(title: const Text('Knowledge Check')),
      body: !quiz.isValid
          ? const StateMessage.error(
              title: 'Quiz unavailable',
              message: 'This quiz contains missing or invalid question data.',
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
                            constraints: const BoxConstraints(maxWidth: 780),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const PageIntro(
                                  title: 'Check your understanding',
                                  description:
                                      'Choose one answer. After submitting, review why it is correct or what needs reconsideration.',
                                ),
                                const SizedBox(height: AppSpacing.xxl),
                                if (widget.quiz.topic != null) ...[
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Chip(
                                      avatar: const Icon(
                                        Icons.track_changes_outlined,
                                        size: 18,
                                      ),
                                      label: Text(widget.quiz.topic!.label),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                ],
                                AppCard(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(
                                        alpha:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? 0.22
                                            : 0.5,
                                      ),
                                  child: Text(
                                    quiz.question,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(height: 1.35),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                RadioGroup<int>(
                                  groupValue: _selectedIndex,
                                  onChanged: (value) {
                                    if (_answered || value == null) return;
                                    setState(() => _selectedIndex = value);
                                  },
                                  child: Column(
                                    children: List.generate(
                                      quiz.options.length,
                                      (index) => _AnswerOption(
                                        index: index,
                                        text: quiz.options[index],
                                        selectedIndex: _selectedIndex,
                                        correctIndex: quiz.correctIndex,
                                        answered: _answered,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_answered) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  AppCard(
                                    backgroundColor:
                                        (_isCorrect
                                                ? AppColors.success
                                                : AppColors.warning)
                                            .withValues(
                                              alpha:
                                                  Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? 0.13
                                                  : 0.08,
                                            ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              _isCorrect
                                                  ? Icons.check_circle_rounded
                                                  : Icons.info_outline_rounded,
                                              color: _isCorrect
                                                  ? AppColors.success
                                                  : AppColors.warning,
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                            Expanded(
                                              child: Text(
                                                _feedbackTitle,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        Text(
                                          quiz.explanation,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(height: 1.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.section),
                                _buildAction(context),
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

  String get _feedbackTitle {
    if (_isSubmitting) return 'Checking and saving your result...';
    final hasAdaptiveTopic = widget.quiz.topic != null;
    final evidenceText = !hasAdaptiveTopic
        ? ''
        : _masteryCounted
            ? ' Mastery evidence was counted.'
            : ' This retry did not add new mastery evidence.';
    if (!_isCorrect) {
      return 'Review the explanation, then decide whether to try again.$evidenceText';
    }
    final scoreText = _scoreAdded
        ? 'Correct. Your best score was recorded.'
        : 'Correct. Your best score for this quiz was already recorded.';
    return '$scoreText$evidenceText';
  }

  Widget _buildAction(BuildContext context) {
    if (!_answered) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _selectedIndex == null ? null : _submitAnswer,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Submit Answer'),
        ),
      );
    }

    if (!_isCorrect) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _tryAgain,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to Lessons'),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isSubmitting ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_rounded),
        label: Text(_isSubmitting ? 'Saving result...' : 'Back to Lessons'),
      ),
    );
  }
}

class _AnswerOption extends StatelessWidget {
  final int index;
  final String text;
  final int? selectedIndex;
  final int correctIndex;
  final bool answered;

  const _AnswerOption({
    required this.index,
    required this.text,
    required this.selectedIndex,
    required this.correctIndex,
    required this.answered,
  });

  @override
  Widget build(BuildContext context) {
    final isCorrect = index == correctIndex;
    final isSelected = selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color background = colorScheme.surface;
    Color border = colorScheme.outlineVariant;
    IconData? statusIcon;
    Color? statusColor;

    if (answered) {
      if (isCorrect) {
        background = AppColors.success.withValues(alpha: isDark ? 0.14 : 0.08);
        border = AppColors.success;
        statusIcon = Icons.check_circle_rounded;
        statusColor = AppColors.success;
      } else if (isSelected) {
        background = AppColors.danger.withValues(alpha: isDark ? 0.14 : 0.07);
        border = AppColors.danger;
        statusIcon = Icons.cancel_rounded;
        statusColor = AppColors.danger;
      }
    } else if (isSelected) {
      background = colorScheme.primaryContainer.withValues(alpha: 0.55);
      border = colorScheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: border,
            width: isSelected || (answered && isCorrect) ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: RadioListTile<int>(
            value: index,
            enabled: !answered,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            title: Text(text, style: Theme.of(context).textTheme.bodyLarge),
            secondary: statusIcon == null
                ? CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    child: Text(
                      String.fromCharCode(65 + index),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  )
                : Icon(statusIcon, color: statusColor),
          ),
        ),
      ),
    );
  }
}

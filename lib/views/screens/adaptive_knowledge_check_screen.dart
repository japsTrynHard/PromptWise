import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/learning_progression_controller.dart';
import '../../models/learning_progression.dart';
import '../../models/learning_topic.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/state_message.dart';

class AdaptiveKnowledgeCheckArgs {
  final LearningTopic? focusTopic;
  final String mode;
  final int questionCount;

  const AdaptiveKnowledgeCheckArgs({
    this.focusTopic,
    this.mode = 'adaptive',
    this.questionCount = 10,
  });
}

class AdaptiveKnowledgeCheckScreen extends StatefulWidget {
  final AdaptiveKnowledgeCheckArgs args;

  const AdaptiveKnowledgeCheckScreen({
    super.key,
    this.args = const AdaptiveKnowledgeCheckArgs(),
  });

  @override
  State<AdaptiveKnowledgeCheckScreen> createState() =>
      _AdaptiveKnowledgeCheckScreenState();
}

class _AdaptiveKnowledgeCheckScreenState
    extends State<AdaptiveKnowledgeCheckScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final controller = context.read<LearningProgressionController>();
    final success = await controller.startAdaptiveSession(
      questionCount: widget.args.questionCount,
      focusTopic: widget.args.focusTopic,
      mode: widget.args.mode,
    );
    if (!mounted || success) return;
    final message = controller.errorMessage;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _submit(int selectedIndex) async {
    final controller = context.read<LearningProgressionController>();
    await controller.submitAnswer(selectedIndex);
  }

  Future<void> _next() async {
    final progression = context.read<LearningProgressionController>();
    final wasLast = progression.session != null &&
        progression.questionIndex == progression.session!.questions.length - 1;
    final success = await progression.nextQuestionOrComplete();
    if (!mounted || !success || !wasLast) return;
    await context.read<AdaptiveLearningController>().refreshFromCloud();
    await progression.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final progression = context.watch<LearningProgressionController>();

    return PopScope(
      canPop: progression.isSessionComplete || progression.session == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || progression.isSessionComplete) return;
        _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.args.mode == 'review'
                ? 'Mastery Review'
                : 'Adaptive Knowledge Check',
          ),
        ),
        body: AdaptiveBody(
          child: _buildBody(context, progression),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LearningProgressionController progression,
  ) {
    if (progression.isStartingSession && progression.session == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.page),
          child: _PreparingState(),
        ),
      );
    }

    if (progression.summary != null) {
      return _SummaryView(
        summary: progression.summary!,
        onDone: () {
          progression.clearSession();
          Navigator.pop(context);
        },
      );
    }

    final session = progression.session;
    final question = progression.currentQuestion;
    if (session == null || question == null) {
      return StateMessage.error(
        title: 'Knowledge check unavailable',
        message: progression.errorMessage ??
            'PromptWise could not prepare an eligible question set.',
        actionLabel: 'Try again',
        onAction: _start,
      );
    }

    final feedback = progression.feedback[question.id];
    final selected = progression.selectedAnswers[question.id];
    final progress = (progression.questionIndex + (feedback == null ? 0 : 1)) /
        session.questions.length;

    return SingleChildScrollView(
      padding: AdaptiveLayout.pageInsets(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SessionHeader(
                session: session,
                question: question,
                currentIndex: progression.questionIndex,
                progress: progress.clamp(0, 1).toDouble(),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      question.stem,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    for (var index = 0;
                        index < question.options.length;
                        index++) ...[
                      _AnswerOption(
                        index: index,
                        text: question.options[index],
                        selected: selected == index,
                        feedback: feedback,
                        onTap: feedback != null || progression.isSubmittingAnswer
                            ? null
                            : () => _submit(index),
                      ),
                      if (index != question.options.length - 1)
                        const SizedBox(height: AppSpacing.sm),
                    ],
                    if (progression.isSubmittingAnswer) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const LinearProgressIndicator(),
                    ],
                    if (feedback != null) ...[
                      const SizedBox(height: AppSpacing.xl),
                      _FeedbackPanel(feedback: feedback),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: progression.questionIndex > 0
                        ? progression.previousQuestion
                        : null,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Previous'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: feedback == null || progression.isCompletingSession
                        ? null
                        : _next,
                    icon: progression.isCompletingSession
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            progression.questionIndex ==
                                    session.questions.length - 1
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded,
                          ),
                    label: Text(
                      progression.isCompletingSession
                          ? 'Finishing...'
                          : progression.questionIndex ==
                                  session.questions.length - 1
                              ? 'Finish'
                              : 'Next',
                    ),
                  ),
                ],
              ),
              if (progression.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  progression.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave knowledge check?'),
        content: const Text(
          'Your submitted answers are saved, but this session will remain incomplete until you finish the remaining questions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (!mounted || shouldExit != true) return;
    await context.read<LearningProgressionController>().abandonSession();
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class _PreparingState extends StatelessWidget {
  const _PreparingState();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Building your knowledge check',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'PromptWise is balancing weak topics, due reviews, unseen questions, and your current difficulty level.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  final KnowledgeCheckSession session;
  final KnowledgeCheckQuestion question;
  final int currentIndex;
  final double progress;

  const _SessionHeader({
    required this.session,
    required this.question,
    required this.currentIndex,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final rankLabel = question.difficulty.label;
    return AppCard(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.48,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question.topic.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      question.objectiveTitle.isEmpty
                          ? question.type.label
                          : question.objectiveTitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Chip(label: Text(rankLabel)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(value: progress, minHeight: 8),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '${currentIndex + 1}/${session.questions.length}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerOption extends StatelessWidget {
  final int index;
  final String text;
  final bool selected;
  final KnowledgeAnswerFeedback? feedback;
  final VoidCallback? onTap;

  const _AnswerOption({
    required this.index,
    required this.text,
    required this.selected,
    required this.feedback,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAnswered = feedback != null;
    final isCorrect = isAnswered && feedback!.correctIndex == index;
    final isWrongSelection = isAnswered && selected && !isCorrect;

    Color? background;
    Color? border;
    IconData? icon;
    if (isCorrect) {
      background = AppColors.success.withValues(alpha: 0.1);
      border = AppColors.success;
      icon = Icons.check_circle_outline_rounded;
    } else if (isWrongSelection) {
      background = Theme.of(context).colorScheme.errorContainer.withValues(
            alpha: 0.55,
          );
      border = Theme.of(context).colorScheme.error;
      icon = Icons.cancel_outlined;
    } else if (selected) {
      background = Theme.of(context).colorScheme.primaryContainer;
      border = Theme.of(context).colorScheme.primary;
    }

    return Material(
      color: background ?? Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: border ?? Theme.of(context).colorScheme.outlineVariant,
              width: selected || isCorrect ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: icon == null
                    ? Text(
                        String.fromCharCode(65 + index),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      )
                    : Icon(icon, size: 20, color: border),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.45,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  final KnowledgeAnswerFeedback feedback;

  const _FeedbackPanel({required this.feedback});

  @override
  Widget build(BuildContext context) {
    final color = feedback.isCorrect
        ? AppColors.success
        : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                feedback.isCorrect
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                feedback.isCorrect ? 'Strong reasoning' : 'Review this idea',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            feedback.explanation,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            feedback.countedForMastery
                ? 'This answer was counted as new mastery evidence.'
                : 'This answer was saved as practice, but did not add duplicate mastery evidence.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  final KnowledgeCheckSummary summary;
  final VoidCallback onDone;

  const _SummaryView({required this.summary, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final percent = summary.total == 0
        ? 0
        : ((summary.correct / summary.total) * 100).round();
    return SingleChildScrollView(
      padding: AdaptiveLayout.pageInsets(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.22
                              : 0.5,
                        ),
                child: Column(
                  children: [
                    const Icon(Icons.insights_rounded, size: 44),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Knowledge Check Complete',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${summary.correct}/${summary.total} correct · $percent%',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'PromptWise used each answer as topic-level evidence and refreshed your learning progression.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Topic performance',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              for (final topicResult in summary.topics) ...[
                AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              topicResult.topic.label,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${topicResult.correct}/${topicResult.total} correct',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      if (summary.ranks[topicResult.topic] != null)
                        Chip(
                          label: Text(
                            summary.ranks[topicResult.topic]!.displayLabel,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onDone,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Continue learning'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

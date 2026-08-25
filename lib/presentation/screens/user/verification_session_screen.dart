import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import '../../../data/models/learning_progression.dart';
import '../../../data/models/verification.dart';
import '../../controllers/verification_controller.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/state_message.dart';
import '../../widgets/promptwise_app_bar.dart';

class VerificationSessionScreen extends StatefulWidget {
  const VerificationSessionScreen({super.key});

  @override
  State<VerificationSessionScreen> createState() =>
      _VerificationSessionScreenState();
}

class _VerificationSessionScreenState extends State<VerificationSessionScreen> {
  VerificationDecision? _decision;
  String? _caseId;

  void _syncCase(VerificationCase? current) {
    if (_caseId == current?.id) return;
    _caseId = current?.id;
    _decision = null;
  }

  Future<void> _submit(VerificationController controller) async {
    final selected = _decision;
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick one answer first.')),
      );
      return;
    }
    final result = await controller.submitCurrentGuess(decision: selected);
    if (!mounted || result != null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.errorMessage ?? 'Your answer could not be saved.',
        ),
      ),
    );
  }

  Future<void> _next(VerificationController controller) async {
    final moved = await controller.nextCaseOrComplete();
    if (!mounted || moved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.errorMessage ?? 'The next item could not be opened.',
        ),
      ),
    );
  }

  Future<bool> _confirmLeave(VerificationController controller) async {
    if (controller.isComplete) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this quick check?'),
        content: const Text(
          'Answers you already submitted stay saved. You can start a new set later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await controller.abandonSession();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerificationController>();
    final current = controller.currentCase;
    _syncCase(current);

    return PopScope(
      canPop: controller.isComplete,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canLeave = await _confirmLeave(controller);
        if (!context.mounted || !canLeave) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: const PromptWiseAppBar(
          eyebrow: 'VERIFY · QUICK CHECK',
          title: 'Quick Check',
          subtitle: 'Check the clue, choose carefully, then review the source.',
          backTooltip: 'Back to Verify',
        ),
        body: AdaptiveBody(
          child: controller.summary != null
              ? _SummaryView(summary: controller.summary!)
              : current == null
                  ? StateMessage.error(
                      title: 'This check could not open',
                      message: controller.errorMessage ??
                          'There is no item to show right now.',
                      actionLabel: 'Go back',
                      onAction: () => Navigator.pop(context),
                    )
                  : _QuestionView(
                      current: current,
                      controller: controller,
                      decision: _decision,
                      onChanged: (value) => setState(() => _decision = value),
                      onSubmit: () => _submit(controller),
                      onNext: () => _next(controller),
                    ),
        ),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  final VerificationCase current;
  final VerificationController controller;
  final VerificationDecision? decision;
  final ValueChanged<VerificationDecision> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onNext;

  const _QuestionView({
    required this.current,
    required this.controller,
    required this.decision,
    required this.onChanged,
    required this.onSubmit,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feedback = controller.feedback[current.id];
    final total = controller.session?.cases.length ?? 1;
    final index = controller.caseIndex + 1;
    final choices = _choicesFor(current);
    final mainText = current.claim.trim().isNotEmpty
        ? current.claim.trim()
        : current.scenario.trim();
    final contextText = current.claim.trim().isNotEmpty
        ? _shorten(current.scenario.trim(), 240)
        : '';

    return SingleChildScrollView(
      padding: AdaptiveLayout.pageInsets(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Question $index of $total',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Text(_difficultyText(current.difficulty.level)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(value: index / total),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                backgroundColor: theme.colorScheme.surfaceContainerLow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_caseIcon(current.caseType)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            current.subskill.learnerLabel,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      mainText,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    if (contextText.isNotEmpty && contextText != mainText) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        contextText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (current.mediaDescription.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Text(_shorten(current.mediaDescription, 180)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'What would you say?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...choices.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _AnswerChoice(
                    label: item.label,
                    selected: decision == item,
                    enabled: feedback == null,
                    onTap: () => onChanged(item),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (feedback == null)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: controller.isSubmitting ? null : onSubmit,
                    icon: controller.isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Check my answer'),
                  ),
                )
              else ...[
                _FeedbackCard(feedback: feedback),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: controller.isCompleting ? null : onNext,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(index == total ? 'See results' : 'Next question'),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.section),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnswerChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _AnswerChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.65)
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

class _FeedbackCard extends StatelessWidget {
  final VerificationCaseFeedback feedback;

  const _FeedbackCard({required this.feedback});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final correct = feedback.decisionCorrect;
    return AppCard(
      backgroundColor: (correct ? AppColors.success : AppColors.warning)
          .withValues(alpha: theme.brightness == Brightness.dark ? 0.14 : 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correct ? Icons.check_circle_rounded : Icons.lightbulb_rounded,
                color: correct ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  correct ? 'Nice — that is the best answer.' : 'Not quite — here is why.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (!correct)
            Text(
              'Best answer: ${feedback.correctDecision.label}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          if (!correct) const SizedBox(height: AppSpacing.sm),
          Text(feedback.explanation, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
          if (feedback.learningPoint.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Simple tip: ${feedback.learningPoint}',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            feedback.countedForMastery
                ? 'This answer helped update your Verify progress.'
                : 'This was saved as practice. Repeating the same item right away will not increase progress twice.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  final VerificationSessionSummary summary;

  const _SummaryView({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = summary.subskillScores.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final focus = entries.isEmpty ? null : entries.first.key;

    return SingleChildScrollView(
      padding: AdaptiveLayout.pageInsets(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                child: Column(
                  children: [
                    Icon(Icons.fact_check_rounded, size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Quick check complete',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${summary.averageScore}%',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('${summary.completedCases} questions answered'),
                  ],
                ),
              ),
              if (focus != null) ...[
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Text(
                    'A good next skill to practice is “${focus.learnerLabel}”. PromptWise can bring back different examples that train the same habit.',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to Verify'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pushNamed(context, AppRoutes.adaptiveLearning),
                    icon: const Icon(Icons.route_outlined),
                    label: const Text('Open my learning path'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<VerificationDecision> _choicesFor(VerificationCase item) {
  final base = <VerificationDecision>[];
  switch (item.caseType) {
    case VerificationCaseType.image:
    case VerificationCaseType.video:
    case VerificationCaseType.audio:
      base.addAll([
        VerificationDecision.supported,
        VerificationDecision.aiGenerated,
        VerificationDecision.manipulated,
        VerificationDecision.insufficientEvidence,
      ]);
      break;
    case VerificationCaseType.claim:
      base.addAll([
        VerificationDecision.supported,
        VerificationDecision.misleadingContext,
        VerificationDecision.unsupportedClaim,
        VerificationDecision.insufficientEvidence,
      ]);
      break;
    case VerificationCaseType.citation:
      base.addAll([
        VerificationDecision.supported,
        VerificationDecision.unsupportedClaim,
        VerificationDecision.unverified,
        VerificationDecision.insufficientEvidence,
      ]);
      break;
    case VerificationCaseType.scam:
      base.addAll([
        VerificationDecision.supported,
        VerificationDecision.misleadingContext,
        VerificationDecision.unsupportedClaim,
        VerificationDecision.insufficientEvidence,
      ]);
      break;
  }
  if (!base.contains(item.correctDecision)) {
    base[base.length - 1] = item.correctDecision;
  }
  if (item.difficulty.level >= 4 && !base.contains(VerificationDecision.unverified)) {
    base.add(VerificationDecision.unverified);
  }
  return List<VerificationDecision>.unmodifiable(base.toSet());
}

String _difficultyText(int level) => switch (level.clamp(1, 5)) {
      1 => 'Easy',
      2 => 'Easy+',
      3 => 'Medium',
      4 => 'Hard',
      _ => 'Challenge',
    };

String _shorten(String value, int max) {
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= max) return text;
  return '${text.substring(0, max).trimRight()}…';
}

IconData _caseIcon(VerificationCaseType type) => switch (type) {
      VerificationCaseType.image => Icons.image_outlined,
      VerificationCaseType.video => Icons.videocam_outlined,
      VerificationCaseType.audio => Icons.graphic_eq_rounded,
      VerificationCaseType.claim => Icons.chat_bubble_outline_rounded,
      VerificationCaseType.citation => Icons.menu_book_outlined,
      VerificationCaseType.scam => Icons.gpp_maybe_outlined,
    };

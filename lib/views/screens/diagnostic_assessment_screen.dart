import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/adaptive_learning_controller.dart';
import '../../models/adaptive_learning.dart';
import '../../models/learning_topic.dart';
import '../../routes/app_routes.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/page_intro.dart';

class DiagnosticAssessmentScreen extends StatefulWidget {
  const DiagnosticAssessmentScreen({super.key});

  @override
  State<DiagnosticAssessmentScreen> createState() =>
      _DiagnosticAssessmentScreenState();
}

class _DiagnosticAssessmentScreenState
    extends State<DiagnosticAssessmentScreen> {
  final Map<String, int> _answers = {};
  int _currentIndex = 0;

  DiagnosticQuestion get _current => diagnosticQuestions[_currentIndex];

  @override
  Widget build(BuildContext context) {
    final adaptive = context.watch<AdaptiveLearningController>();

    if (adaptive.diagnosticCompleted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Diagnostic Assessment')),
        body: AdaptiveBody(
          child: SingleChildScrollView(
            padding: AdaptiveLayout.pageInsets(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 38),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Diagnostic already completed',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Your starting assessment is already part of your mastery profile. Continue with lessons and knowledge checks to update it.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton.icon(
                        onPressed: () => Navigator.pushReplacementNamed(
                          context,
                          AppRoutes.adaptiveLearning,
                        ),
                        icon: const Icon(Icons.route_outlined),
                        label: const Text('View learning path'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final selected = _answers[_current.id];

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostic Assessment')),
      body: AdaptiveBody(
        child: SingleChildScrollView(
          padding: AdaptiveLayout.pageInsets(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageIntro(
                    title: 'Question ${_currentIndex + 1} of ${diagnosticQuestions.length}',
                    description:
                        'This short diagnostic establishes a starting mastery profile. It does not affect your regular quiz score.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  LinearProgressIndicator(
                    value: (_currentIndex + 1) / diagnosticQuestions.length,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  AppCard(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.45),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Chip(label: Text(_current.topic.label)),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _current.question,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ...List.generate(
                    _current.options.length,
                    (index) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _DiagnosticOption(
                        label: String.fromCharCode(65 + index),
                        text: _current.options[index],
                        selected: selected == index,
                        onTap: adaptive.isSubmittingDiagnostic
                            ? null
                            : () => setState(() => _answers[_current.id] = index),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      if (_currentIndex > 0)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: adaptive.isSubmittingDiagnostic
                                ? null
                                : () => setState(() => _currentIndex--),
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: const Text('Previous'),
                          ),
                        ),
                      if (_currentIndex > 0)
                        const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: selected == null || adaptive.isSubmittingDiagnostic
                              ? null
                              : _currentIndex < diagnosticQuestions.length - 1
                              ? () => setState(() => _currentIndex++)
                              : _submit,
                          icon: Icon(
                            _currentIndex < diagnosticQuestions.length - 1
                                ? Icons.arrow_forward_rounded
                                : Icons.check_rounded,
                          ),
                          label: Text(
                            adaptive.isSubmittingDiagnostic
                                ? 'Saving...'
                                : _currentIndex < diagnosticQuestions.length - 1
                                ? 'Next'
                                : 'Finish Diagnostic',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final adaptive = context.read<AdaptiveLearningController>();
    try {
      final result = await adaptive.submitDiagnostic(_answers);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.route_outlined),
          title: const Text('Learning path ready'),
          content: Text(
            'You answered ${result.correctAnswers} of ${result.totalQuestions} questions correctly (${result.score}%). PromptWise will now prioritize weaker topics and schedule reviews as you continue learning.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('View my learning path'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.adaptiveLearning);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete every question before submitting.'),
        ),
      );
    }
  }
}

class _DiagnosticOption extends StatelessWidget {
  final String label;
  final String text;
  final bool selected;
  final VoidCallback? onTap;

  const _DiagnosticOption({
    required this.label,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.fast,
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.6)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: selected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: selected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                child: Text(label),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(text)),
              if (selected)
                Icon(Icons.check_circle_rounded, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

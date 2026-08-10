import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/progress_controller.dart';
import '../../controllers/sandbox_controller.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/page_intro.dart';
import '../widgets/prompt_score_widget.dart';

class SandboxScreen extends StatefulWidget {
  const SandboxScreen({super.key});

  @override
  State<SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends State<SandboxScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SandboxController>().init();
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _promptFocusNode.dispose();
    super.dispose();
  }

  Future<void> _reviewPrompt() async {
    setState(() => _submitted = true);
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      _promptFocusNode.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    final sandboxController = context.read<SandboxController>();
    final progressController = context.read<ProgressController>();
    final reviewed = await sandboxController.reviewPrompt(
      _promptController.text,
    );

    if (!mounted) return;
    if (reviewed && sandboxController.overall >= 0.8) {
      await progressController.addSandboxBadge();
    }
  }

  void _reset() {
    context.read<SandboxController>().reset();
    _formKey.currentState?.reset();
    _promptController.clear();
    setState(() => _submitted = false);
    _promptFocusNode.requestFocus();
  }

  void _insertExample() {
    const example =
        'Explain how phishing works for senior high school students in three short paragraphs. Use simple language, list two warning signs, and identify facts that should be verified using trusted cybersecurity sources.';
    _promptController.text = example;
    _promptController.selection = TextSelection.collapsed(
      offset: example.length,
    );
    context.read<SandboxController>().clearValidationMessage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompt Coach'),
        actions: [
          IconButton(
            tooltip: 'Start over',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reset,
          ),
        ],
      ),
      body: Consumer<SandboxController>(
        builder: (context, state, _) {
          return AdaptiveBody(
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
                          constraints: const BoxConstraints(maxWidth: 920),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const PageIntro(
                                title: 'Improve your own prompt',
                                description:
                                    'The Coach identifies strengths, questions, and risks. It does not rewrite the prompt or answer the task for you.',
                              ),
                              const SizedBox(height: AppSpacing.xl),
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
                                child: const Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.school_outlined),
                                    SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Text(
                                        'Your role: decide which feedback is useful, revise with your own wording, and verify important information independently.',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _CoachStatusCard(state: state),
                              const SizedBox(height: AppSpacing.xxl),
                              Text(
                                'Your prompt',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Describe the task, context, audience, expected output, and verification needs.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Form(
                                key: _formKey,
                                autovalidateMode: _submitted
                                    ? AutovalidateMode.onUserInteraction
                                    : AutovalidateMode.disabled,
                                child: TextFormField(
                                  controller: _promptController,
                                  focusNode: _promptFocusNode,
                                  minLines: 7,
                                  maxLines: 12,
                                  maxLength:
                                      SandboxController.maximumPromptLength,
                                  textInputAction: TextInputAction.newline,
                                  onChanged: (_) =>
                                      state.clearValidationMessage(),
                                  validator: (value) =>
                                      state.validatePrompt(value?.trim() ?? ''),
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Type or paste a prompt. Avoid passwords, account details, private emails, and confidential information.',
                                    alignLabelWithHint: true,
                                  ),
                                ),
                              ),
                              if (state.validationMessage != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  state.validationMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.md),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final buttons = [
                                    OutlinedButton.icon(
                                      onPressed: _reset,
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Clear'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _insertExample,
                                      icon: const Icon(
                                        Icons.description_outlined,
                                      ),
                                      label: const Text('Use Example'),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: state.isLoading
                                          ? null
                                          : _reviewPrompt,
                                      icon: const Icon(
                                        Icons.analytics_outlined,
                                      ),
                                      label: Text(
                                        state.isLoading
                                            ? 'Getting feedback...'
                                            : state.evaluated
                                            ? 'Review Revision'
                                            : 'Get Feedback',
                                      ),
                                    ),
                                  ];

                                  if (constraints.maxWidth >= 620) {
                                    return Row(
                                      children: [
                                        Expanded(child: buttons[0]),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(child: buttons[1]),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(child: buttons[2]),
                                      ],
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      buttons[2],
                                      const SizedBox(height: AppSpacing.sm),
                                      buttons[1],
                                      const SizedBox(height: AppSpacing.sm),
                                      buttons[0],
                                    ],
                                  );
                                },
                              ),
                              if (state.evaluated) ...[
                                const SizedBox(height: AppSpacing.section),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        state.usedBasicFeedback
                                            ? 'Basic feedback'
                                            : 'AI Coach feedback',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                    ),
                                    Chip(
                                      label: Text(
                                        'Attempt ${state.attemptCount}',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                PromptScoreWidget(
                                  clarity: state.clarity,
                                  context: state.context,
                                  specificity: state.specificity,
                                  responsibility: state.responsibility,
                                  overall: state.overall,
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                _FeedbackPanel(
                                  icon: Icons.check_circle_outline_rounded,
                                  title: 'Strengths',
                                  description: 'What is already working well.',
                                  items: state.strengths.isEmpty
                                      ? const [
                                          'No clear strength was detected yet. Review the areas below.',
                                        ]
                                      : state.strengths,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _FeedbackPanel(
                                  icon: Icons.tune_rounded,
                                  title: 'Areas to consider',
                                  description:
                                      'Reminders that may improve your prompt.',
                                  items: state.suggestions.isEmpty
                                      ? const [
                                          'Review whether the prompt is clear, necessary, verifiable, and safe.',
                                        ]
                                      : state.suggestions,
                                ),
                                if (state.guidingQuestions.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  _FeedbackPanel(
                                    icon: Icons.help_outline_rounded,
                                    title: 'Questions to think about',
                                    description:
                                        'Use these questions to guide your own revision.',
                                    items: state.guidingQuestions,
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.md),
                                AppCard(
                                  backgroundColor: AppColors.warning.withValues(
                                    alpha:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.13
                                        : 0.08,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.privacy_tip_outlined,
                                        color: AppColors.warning,
                                      ),
                                      const SizedBox(width: AppSpacing.md),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Privacy reminder',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.xs,
                                            ),
                                            Text(state.safetyReminder),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                AppCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        state.feedbackSummary,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge,
                                      ),
                                      const SizedBox(height: AppSpacing.lg),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _promptFocusNode.requestFocus(),
                                        icon: const Icon(Icons.edit_rounded),
                                        label: const Text('Revise It Myself'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CoachStatusCard extends StatelessWidget {
  final SandboxController state;

  const _CoachStatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = state.coachChecked && state.coachAvailable;
    final checking = !state.coachChecked;
    final background = ready
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = ready
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          if (checking)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              ready ? Icons.auto_awesome_outlined : Icons.offline_bolt_outlined,
              color: foreground,
            ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              checking
                  ? 'Preparing AI Coach...'
                  : ready
                  ? 'AI Coach is ready.'
                  : state.serviceMessage ??
                        'Basic feedback is available on this device.',
              style: TextStyle(color: foreground),
            ),
          ),
          if (!checking && !ready)
            TextButton(
              onPressed: state.checkCoachAvailability,
              child: const Text('Try again'),
            ),
        ],
      ),
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<String> items;

  const _FeedbackPanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

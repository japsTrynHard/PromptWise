import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/learning_progression_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../controllers/sandbox_controller.dart';
import '../../../data/models/learning_topic.dart';
import '../../../data/models/prompt_coach.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_intro.dart';
import '../../widgets/promptwise_app_bar.dart';
import '../../widgets/prompt_score_widget.dart';

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
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      _promptFocusNode.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    final adaptive = context.read<AdaptiveLearningController>();
    final progression = context.read<LearningProgressionController>();
    final coach = context.read<SandboxController>();
    final progress = context.read<ProgressController>();

    final masteryContext = {
      for (final topic in LearningTopic.values)
        topic.id: adaptive.masteryFor(topic).mastery,
    };
    final focusTopic = _promptFocusTopic(adaptive);

    final reviewed = await coach.reviewPrompt(
      _promptController.text,
      masteryContext: masteryContext,
      learnerRank: progression.overallRankLabel,
      focusTopic: focusTopic,
    );

    if (!mounted || !reviewed) return;
    final score = coach.analysis?.scores.overallPercent ?? 0;
    final followUps = <Future<void>>[];
    if (coach.masteryEvidenceCount > 0) {
      followUps.add(adaptive.refreshFromCloud());
      followUps.add(progression.refresh());
    }
    if (score >= 80) {
      followUps.add(progress.addSandboxBadge());
    }
    if (followUps.isNotEmpty) await Future.wait<void>(followUps);
  }

  LearningTopic? _promptFocusTopic(AdaptiveLearningController adaptive) {
    const topics = [
      LearningTopic.promptClarity,
      LearningTopic.context,
      LearningTopic.specificity,
      LearningTopic.responsibleUse,
    ];
    LearningTopic? weakest;
    var lowest = 101;
    for (final topic in topics) {
      final mastery = adaptive.masteryFor(topic);
      final score = mastery.attempts == 0 ? 0 : mastery.mastery;
      if (score < lowest) {
        lowest = score;
        weakest = topic;
      }
    }
    return weakest;
  }

  void _reset() {
    context.read<SandboxController>().startNewSession();
    _formKey.currentState?.reset();
    _promptController.clear();
    setState(() => _submitted = false);
    _promptFocusNode.requestFocus();
  }

  void _insertExample() {
    const example =
        'Explain how phishing works for senior high school students. Give three warning signs in a short table, then provide a four-step verification checklist. Use simple language, avoid invented statistics, and clearly mark claims that should be checked against trusted cybersecurity sources.';
    _promptController.text = example;
    _promptController.selection = TextSelection.collapsed(
      offset: example.length,
    );
    final state = context.read<SandboxController>();
    state.clearValidationMessage();
    state.inspectPrompt(example);
  }

  Future<void> _openHistory(PromptCoachSessionSummary session) async {
    final coach = context.read<SandboxController>();
    final revisions = await coach.fetchSessionRevisions(session.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(session.title),
        content: SizedBox(
          width: 680,
          child: revisions.isEmpty
              ? const Text('No saved revisions were found for this session.')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final revision in revisions) ...[
                        _HistoryRevisionCard(revision: revision),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adaptive = context.watch<AdaptiveLearningController>();
    final progression = context.watch<LearningProgressionController>();
    final focusTopic = _promptFocusTopic(adaptive);

    return Scaffold(
      appBar: PromptWiseAppBar(
        eyebrow: 'COACH · PRACTICE',
        title: 'Prompt Coach',
        subtitle:
            'Improve your own prompt with guided feedback, one revision at a time.',
        backTooltip: 'Back',
        actions: [
          PromptWiseHeaderIconButton(
            tooltip: 'Start a new coaching session',
            icon: Icons.add_comment_rounded,
            onPressed: _reset,
          ),
        ],
      ),
      body: Consumer<SandboxController>(
        builder: (context, state, _) {
          return AdaptiveBody(
            maxWidth: 1120,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: AdaptiveLayout.pageInsets(
                    context,
                    top: AppSpacing.sm,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (!AdaptiveLayout.isPhone(context)) ...[
                        PageIntro(
                          title:
                              'Build better prompts by revising them yourself',
                          description:
                              'PromptWise scores the same eight prompt skills every time, asks guiding questions, and tracks your improvement. AI Coach adds contextual guidance but never rewrites the prompt or completes the task for you.',
                          trailing: _RankBadge(
                            label: progression.overallRankLabel,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      _CoachModeSelector(state: state),
                      const SizedBox(height: AppSpacing.md),
                      _LearningContextCard(
                        focusTopic: focusTopic,
                        mastery: focusTopic == null
                            ? null
                            : adaptive.masteryFor(focusTopic).mastery,
                        rankLabel: progression.overallRankLabel,
                      ),
                      if (state.serviceMessage != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _InlineNotice(
                          icon: Icons.info_outline_rounded,
                          message: state.serviceMessage!,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      _PromptEditorCard(
                        formKey: _formKey,
                        controller: _promptController,
                        focusNode: _promptFocusNode,
                        submitted: _submitted,
                        state: state,
                        onChanged: (value) {
                          state.clearValidationMessage();
                          state.inspectPrompt(value);
                        },
                        onClear: _reset,
                        onExample: _insertExample,
                        onReview: _reviewPrompt,
                      ),
                      if (state.livePrivacyFindings.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        _PrivacyWarningCard(
                          findings: state.livePrivacyFindings,
                        ),
                      ],
                      if (state.evaluated && state.analysis != null) ...[
                        const SizedBox(height: AppSpacing.section),
                        PromptScoreWidget(
                          scores: state.analysis!.scores,
                          previousScores: state.previousAnalysis?.scores,
                        ),
                        if (state.previousAnalysis != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _RevisionProgressCard(
                            revisionNumber: state.revisionNumber,
                            previous: state.previousAnalysis!.scores,
                            current: state.analysis!.scores,
                            masteryEvidenceCount: state.masteryEvidenceCount,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        _StandardFeedbackGrid(analysis: state.analysis!),
                        if (state.aiGuidance != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _AiGuidanceCard(guidance: state.aiGuidance!),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        _RevisionCallToAction(
                          onRevise: () => _promptFocusNode.requestFocus(),
                          onNewSession: _reset,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.section),
                      _HistorySection(
                        state: state,
                        onOpen: _openHistory,
                        onRefresh: state.refreshHistory,
                      ),
                      const SizedBox(height: AppSpacing.section),
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

class _CoachModeSelector extends StatelessWidget {
  final SandboxController state;

  const _CoachModeSelector({required this.state});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 760
            ? (constraints.maxWidth - AppSpacing.md) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            SizedBox(
              width: cardWidth,
              child: _ModeCard(
                selected: state.mode == PromptCoachMode.standard,
                icon: Icons.rule_folder_outlined,
                title: 'Standard Coach',
                badge: 'Unlimited',
                description:
                    'Uses PromptWise’s consistent eight-part rubric. Fast, deterministic, and available without AI quota.',
                onTap: () => state.setMode(PromptCoachMode.standard),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _ModeCard(
                selected: state.mode == PromptCoachMode.ai,
                icon: Icons.auto_awesome_outlined,
                title: 'AI Coach',
                badge: state.coachChecked
                    ? '${state.usage.remaining}/${state.usage.limit} left today'
                    : 'Checking availability',
                description:
                    'Adds guidance based on your prompt and current learning progress. Limited to protect free-tier usage.',
                enabled: state.canUseAi,
                onTap: () => state.setMode(PromptCoachMode.ai),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ModeCard extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final IconData icon;
  final String title;
  final String badge;
  final String description;
  final VoidCallback onTap;

  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.badge,
    required this.description,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: enabled ? onTap : null,
      backgroundColor: selected
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : null,
      border: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
        width: selected ? 1.6 : 1,
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, color: scheme.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    badge,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LearningContextCard extends StatelessWidget {
  final LearningTopic? focusTopic;
  final int? mastery;
  final String rankLabel;

  const _LearningContextCard({
    required this.focusTopic,
    required this.mastery,
    required this.rankLabel,
  });

  @override
  Widget build(BuildContext context) {
    final topic = focusTopic;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.route_outlined),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personalized coaching context',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  topic == null
                      ? 'PromptWise will use your current $rankLabel progression level when shaping challenges.'
                      : 'Current prompt-writing focus: ${topic.label} (${mastery ?? 0}% progress). AI Coach can emphasize this area, while Standard Coach keeps scoring rules consistent.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptEditorCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitted;
  final SandboxController state;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onExample;
  final Future<void> Function() onReview;

  const _PromptEditorCard({
    required this.formKey,
    required this.controller,
    required this.focusNode,
    required this.submitted,
    required this.state,
    required this.onChanged,
    required this.onClear,
    required this.onExample,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final ai = state.mode == PromptCoachMode.ai;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.revisionNumber > 0
                          ? 'Revise your prompt'
                          : 'Write your prompt',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      state.revisionNumber > 0
                          ? 'Revision ${state.revisionNumber + 1}: make your own changes using the feedback below.'
                          : 'Include enough context to make the task understandable, but do not add unnecessary detail.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.revisionNumber > 0)
                Chip(label: Text('Revision ${state.revisionNumber} saved')),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Form(
            key: formKey,
            autovalidateMode: submitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              minLines: 8,
              maxLines: 14,
              maxLength: SandboxController.maximumPromptLength,
              onChanged: onChanged,
              validator: (value) => state.validatePrompt(value?.trim() ?? ''),
              decoration: InputDecoration(
                hintText:
                    'Example: Explain [topic] for [audience]. Include [requirements]. Use [format]. Verify [important claims].',
                alignLabelWithHint: true,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              ),
            ),
          ),
          if (state.validationMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.validationMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final secondary = Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: state.isLoading ? null : onClear,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Clear'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.isLoading ? null : onExample,
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Use example'),
                  ),
                ],
              );
              final primary = FilledButton.icon(
                onPressed: state.isLoading ? null : () => onReview(),
                icon: Icon(
                  ai ? Icons.auto_awesome_outlined : Icons.analytics_outlined,
                ),
                label: Text(
                  state.isLoading
                      ? 'Reviewing...'
                      : ai
                      ? 'Use AI Coach (${state.usage.remaining} left)'
                      : state.revisionNumber > 0
                      ? 'Review Revision'
                      : 'Get Standard Feedback',
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    secondary,
                    const SizedBox(height: AppSpacing.md),
                    primary,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: secondary),
                  const SizedBox(width: AppSpacing.md),
                  primary,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PrivacyWarningCard extends StatelessWidget {
  final List<PromptPrivacyFinding> findings;

  const _PrivacyWarningCard({required this.findings});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      backgroundColor: scheme.errorContainer.withValues(alpha: 0.4),
      border: BorderSide(color: scheme.error.withValues(alpha: 0.45)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: scheme.error),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Privacy check',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final finding in findings)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _BulletLine(
                icon: Icons.warning_amber_rounded,
                title: finding.label,
                text: finding.message,
              ),
            ),
          Text(
            'Standard Coach can still evaluate prompt structure locally. AI Coach will not receive the prompt until blocking findings are removed.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RevisionProgressCard extends StatelessWidget {
  final int revisionNumber;
  final PromptRubricScore previous;
  final PromptRubricScore current;
  final int masteryEvidenceCount;

  const _RevisionProgressCard({
    required this.revisionNumber,
    required this.previous,
    required this.current,
    required this.masteryEvidenceCount,
  });

  @override
  Widget build(BuildContext context) {
    final before = previous.overallPercent;
    final after = current.overallPercent;
    final delta = after - before;
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Revision progress',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                delta > 0
                    ? 'Your latest revision improved by $delta points.'
                    : delta == 0
                    ? 'The overall score stayed the same. Focus on one weak dimension instead of adding more words.'
                    : 'The score changed by $delta points. Re-check whether the revision removed useful context or constraints.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (masteryEvidenceCount > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '$masteryEvidenceCount progress ${masteryEvidenceCount == 1 ? 'update was' : 'updates were'} earned from demonstrated improvement.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          );
          final numbers = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ScorePill(label: 'Before', value: before),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(Icons.arrow_forward_rounded, size: 18),
              ),
              _ScorePill(label: 'Now', value: after),
            ],
          );
          if (constraints.maxWidth < 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: AppSpacing.md),
                numbers,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: AppSpacing.xl),
              numbers,
            ],
          );
        },
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  final String label;
  final int value;

  const _ScorePill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _StandardFeedbackGrid extends StatelessWidget {
  final PromptCoachAnalysis analysis;

  const _StandardFeedbackGrid({required this.analysis});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 760
            ? (constraints.maxWidth - AppSpacing.md) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            SizedBox(
              width: width,
              child: _FeedbackCard(
                icon: Icons.check_circle_outline_rounded,
                title: 'What already works',
                items: analysis.strengths,
                emptyText: 'No strong signal yet. Start with a clearer task.',
              ),
            ),
            SizedBox(
              width: width,
              child: _FeedbackCard(
                icon: Icons.tune_rounded,
                title: 'Improve next',
                items: analysis.suggestions,
                emptyText: 'No major structural issue was detected.',
              ),
            ),
            SizedBox(
              width: width,
              child: _FeedbackCard(
                icon: Icons.help_outline_rounded,
                title: 'Guiding questions',
                items: analysis.guidingQuestions,
                emptyText:
                    'Use the score breakdown to choose one area to refine.',
              ),
            ),
            SizedBox(
              width: width,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.summarize_outlined),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Coach summary',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      analysis.summary,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;
  final String emptyText;

  const _FeedbackCard({
    required this.icon,
    required this.title,
    required this.items,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (items.isEmpty)
            Text(emptyText)
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _BulletLine(icon: Icons.arrow_right_rounded, text: item),
              ),
        ],
      ),
    );
  }
}

class _AiGuidanceCard extends StatelessWidget {
  final PromptAiGuidance guidance;

  const _AiGuidanceCard({required this.guidance});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: scheme.secondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'AI Coach perspective',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Chip(label: Text('Guidance only')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            guidance.summary,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          if (guidance.focusAreas.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Focus areas',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final item in guidance.focusAreas) Chip(label: Text(item)),
              ],
            ),
          ],
          if (guidance.reasoningNotes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            for (final note in guidance.reasoningNotes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _BulletLine(
                  icon: Icons.lightbulb_outline_rounded,
                  text: note,
                ),
              ),
          ],
          if (guidance.guidingQuestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Questions to answer in your revision',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final question in guidance.guidingQuestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _BulletLine(
                  icon: Icons.help_outline_rounded,
                  text: question,
                ),
              ),
          ],
          if (guidance.nextChallenge.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _InlineNotice(
              icon: Icons.flag_outlined,
              message: 'Next challenge: ${guidance.nextChallenge}',
            ),
          ],
          if (guidance.responsibleUseReminder.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              guidance.responsibleUseReminder,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _RevisionCallToAction extends StatelessWidget {
  final VoidCallback onRevise;
  final VoidCallback onNewSession;

  const _RevisionCallToAction({
    required this.onRevise,
    required this.onNewSession,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.38),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your turn: revise it yourself',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Use one or two pieces of feedback, make the changes in your own words, then review the next revision. PromptWise intentionally does not provide a finished rewritten prompt.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
            ],
          );
          final actions = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: onRevise,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Revise Prompt'),
              ),
              OutlinedButton(
                onPressed: onNewSession,
                child: const Text('New Prompt'),
              ),
            ],
          );
          if (constraints.maxWidth < 650) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy,
                const SizedBox(height: AppSpacing.md),
                actions,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: AppSpacing.xl),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  final SandboxController state;
  final ValueChanged<PromptCoachSessionSummary> onOpen;
  final Future<void> Function() onRefresh;

  const _HistorySection({
    required this.state,
    required this.onOpen,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Revision history',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Compare how your own prompts improve across coaching sessions.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh history',
              onPressed: state.isHistoryLoading ? null : () => onRefresh(),
              icon: state.isHistoryLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (state.historyMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _InlineNotice(
            icon: Icons.cloud_off_outlined,
            message: state.historyMessage!,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (state.recentSessions.isEmpty)
          AppCard(
            child: Text(
              'Your saved coaching sessions will appear here after you review a prompt.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 760
                  ? (constraints.maxWidth - AppSpacing.md) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final session in state.recentSessions)
                    SizedBox(
                      width: width,
                      child: AppCard(
                        onTap: () => onOpen(session),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              children: [
                                Chip(
                                  label: Text(
                                    '${session.revisionCount} revisions',
                                  ),
                                ),
                                if (session.focusTopic != null)
                                  Chip(label: Text(session.focusTopic!.label)),
                                Chip(
                                  label: Text(
                                    session.improvement > 0
                                        ? '+${session.improvement} points'
                                        : '${session.latestScore}/100 latest',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _HistoryRevisionCard extends StatelessWidget {
  final PromptCoachRevision revision;

  const _HistoryRevisionCard({required this.revision});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Revision ${revision.revisionNumber}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text('${revision.scores.overallPercent}/100'),
              const SizedBox(width: AppSpacing.sm),
              Chip(label: Text(revision.mode.label)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            revision.promptText,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final String label;

  const _RankBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final String message;

  const _InlineNotice({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? title;

  const _BulletLine({required this.icon, required this.text, this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: title == null
              ? Text(
                  text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.4),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

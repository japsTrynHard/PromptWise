import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/verification_controller.dart';
import '../../controllers/content_automation_controller.dart';
import '../../controllers/awareness_feed_controller.dart';
import '../../../data/models/learning_progression.dart';
import '../../../data/models/verification.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_intro.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_message.dart';
import '../../widgets/studio_generation_widgets.dart';

class AdminVerificationStudioScreen extends StatefulWidget {
  const AdminVerificationStudioScreen({super.key});

  @override
  State<AdminVerificationStudioScreen> createState() =>
      _AdminVerificationStudioScreenState();
}

class _AdminVerificationStudioScreenState
    extends State<AdminVerificationStudioScreen> {
  bool _initialLoadRequested = false;
  bool _preparingGeneration = false;
  String _query = '';
  VerificationSubskill? _subskillFilter;
  int? _levelFilter;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerificationStudioController>();
    final automation = context.watch<ContentAutomationController>();

    if (controller.isAdministrator &&
        !controller.hasLoaded &&
        !controller.isLoading &&
        !_initialLoadRequested) {
      _initialLoadRequested = true;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        await controller.refresh();

        if (mounted) {
          _initialLoadRequested = false;
        }
      });
    }

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AdaptiveLayout.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageIntro(
              title: 'Verification Studio',
              description:
                  'Create focused verification cases, review the evidence, and grow your case library.',
            ),
            const SizedBox(height: AppSpacing.xl),
            if (!controller.isAdministrator)
              const StateMessage.error(
                title: 'Administrator access required',
                message:
                    'Verification Studio is only available to administrator accounts.',
              )
            else ...[
              _StatusCard(controller: controller),
              const SizedBox(height: AppSpacing.md),
              _FreshDraftPanel(
                studio: controller,
                automation: automation,
                preparing: _preparingGeneration,
                onGenerate: () async {
                  if (_preparingGeneration) return;
                  setState(() => _preparingGeneration = true);
                  try {
                    final chosen = await showDialog<List<VerificationSubskill>>(
                      context: context,
                      builder: (_) => StudioFocusDialog<VerificationSubskill>(
                        title: 'Create verification drafts',
                        description:
                            'Choose skills for this run only. Generation stays within your selected skills and existing limits.',
                        options: VerificationSubskill.values
                            .map(
                              (skill) => StudioFocusOption(
                                skill,
                                skill.label,
                                skill.shortDescription,
                                switch (skill) {
                                  VerificationSubskill.sourceVerification =>
                                    Icons.travel_explore_rounded,
                                  VerificationSubskill.claimVerification =>
                                    Icons.fact_check_outlined,
                                  VerificationSubskill.mediaProvenance =>
                                    Icons.perm_media_outlined,
                                  VerificationSubskill.manipulationDetection =>
                                    Icons.image_search_outlined,
                                  VerificationSubskill.citationVerification =>
                                    Icons.format_quote_rounded,
                                  VerificationSubskill.uncertaintyJudgment =>
                                    Icons.help_outline_rounded,
                                },
                              ),
                            )
                            .toList(),
                      ),
                    );
                    if (chosen == null || !context.mounted) return;
                    final messenger = ScaffoldMessenger.of(context);
                    final awareness = context.read<AwarenessFeedController>();

                    // Remove a stale Learning Studio result before a Verify-only run.
                    automation.clearMessages();

                    final awarenessReady = await awareness
                        .ensureCurrentSources();
                    if (!mounted) return;

                    // A failed live refresh must not block generation when recent
                    // trusted Awareness rows are already cached in Supabase. The
                    // content-automation function performs the authoritative source
                    // query and will return the exact reason if nothing is eligible.
                    if (!awarenessReady) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            awareness.errorMessage ??
                                'Live source refresh was unavailable. Trying the saved trusted source cache instead.',
                          ),
                        ),
                      );
                    }

                    await automation.runVerificationDraftsNow(
                      focusSkills: chosen,
                    );
                    if (!mounted) return;
                    // Partial or failed runs may still consume budget or save
                    // drafts. Keep the displayed availability authoritative.
                    await controller.refresh();
                  } finally {
                    if (mounted) setState(() => _preparingGeneration = false);
                  }
                },
              ),
              if (controller.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                StateMessage.error(
                  title: 'Some Verification Studio data could not load',
                  message: controller.errorMessage!,
                  actionLabel: 'Retry',
                  onAction: controller.refresh,
                ),
              ],
              if (controller.successMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  backgroundColor: AppColors.success.withValues(alpha: 0.09),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: Text(controller.successMessage!)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.section),
              const SectionHeader(
                title: 'Verification case health',
                subtitle:
                    'See whether each Verify skill has enough easy-to-challenging cases, so learners do not keep seeing one type of question.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (controller.isLoading && controller.health.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (controller.health.isEmpty)
                const StateMessage.empty(
                  title: 'No verification health data',
                  message: 'Refresh your workspace to check case coverage.',
                )
              else
                _HealthGrid(items: controller.health),
              const SizedBox(height: AppSpacing.section),
              SectionHeader(
                title: 'AI draft queue',
                subtitle:
                    '${controller.drafts.length} draft${controller.drafts.length == 1 ? '' : 's'} waiting for fact/evidence review. Nothing is auto-published.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (controller.drafts.isEmpty)
                const AppCard(
                  child: Text(
                    'Your review queue is clear. Choose verification skills above to create new case drafts.',
                  ),
                )
              else
                ...controller.drafts.map(
                  (draft) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _DraftCard(
                      draft: draft,
                      busy: controller.isMutating,
                      onApprove: () =>
                          _confirmApprove(context, controller, draft),
                      onReject: () =>
                          _confirmReject(context, controller, draft),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.section),
              SectionHeader(
                title: 'Published verification case bank',
                subtitle:
                    '${controller.cases.length} published case${controller.cases.length == 1 ? '' : 's'}. Search and filter the bank to spot gaps or archive outdated cases.',
              ),
              const SizedBox(height: AppSpacing.md),
              _Filters(
                query: _query,
                subskill: _subskillFilter,
                level: _levelFilter,
                onQueryChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                },
                onSubskillChanged: (value) {
                  setState(() {
                    _subskillFilter = value;
                  });
                },
                onLevelChanged: (value) {
                  setState(() {
                    _levelFilter = value;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              ..._filteredCases(controller.cases)
                  .take(100)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _CaseBankCard(
                        item: item,
                        busy: controller.isMutating,
                        onEdit: () => _editCase(context, controller, item),
                        onArchive: () =>
                            _confirmArchive(context, controller, item),
                      ),
                    ),
                  ),
              const SizedBox(height: AppSpacing.section),
            ],
          ],
        ),
      ),
    );
  }

  Iterable<VerificationCase> _filteredCases(List<VerificationCase> source) {
    final query = _query.trim().toLowerCase();

    return source.where((item) {
      if (_subskillFilter != null && item.subskill != _subskillFilter) {
        return false;
      }

      if (_levelFilter != null && item.difficulty.level != _levelFilter) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      return '${item.title} ${item.scenario} ${item.caseType.label} ${item.subskill.label}'
          .toLowerCase()
          .contains(query);
    });
  }

  Future<void> _confirmApprove(
    BuildContext context,
    VerificationStudioController controller,
    VerificationCaseDraft draft,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve verification case?'),
        content: Text(
          'Approve “${draft.title}” only after checking that its source, evidence, keyed decision, and explanation are accurate. The case becomes learner-eligible after approval.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.approveDraft(draft.id);
    }
  }

  Future<void> _confirmReject(
    BuildContext context,
    VerificationStudioController controller,
    VerificationCaseDraft draft,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject draft?'),
        content: Text('Reject “${draft.title}”?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.rejectDraft(draft.id);
    }
  }

  Future<void> _editCase(
    BuildContext context,
    VerificationStudioController controller,
    VerificationCase item,
  ) async {
    final title = TextEditingController(text: item.title);

    final scenario = TextEditingController(text: item.scenario);

    final claim = TextEditingController(text: item.claim);

    final explanation = TextEditingController(text: item.explanation);

    final learningPoint = TextEditingController(text: item.learningPoint);

    var subskill = item.subskill;
    var caseType = item.caseType;
    var level = item.difficulty.level;
    var decision = item.correctDecision;
    var confidence = item.expectedConfidence;

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit verification case'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: scenario,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Scenario'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: claim,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Claim to verify',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      DropdownButton<VerificationSubskill>(
                        value: subskill,
                        items: VerificationSubskill.values
                            .map(
                              (value) => DropdownMenuItem<VerificationSubskill>(
                                value: value,
                                child: Text(value.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              subskill = value;
                            });
                          }
                        },
                      ),
                      DropdownButton<VerificationCaseType>(
                        value: caseType,
                        items: VerificationCaseType.values
                            .map(
                              (value) => DropdownMenuItem<VerificationCaseType>(
                                value: value,
                                child: Text(value.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              caseType = value;
                            });
                          }
                        },
                      ),
                      DropdownButton<int>(
                        value: level,
                        items: [
                          for (var i = 1; i <= 5; i++)
                            DropdownMenuItem<int>(
                              value: i,
                              child: Text(_levelLabel(i)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              level = value;
                            });
                          }
                        },
                      ),
                      DropdownButton<VerificationDecision>(
                        value: decision,
                        items: VerificationDecision.values
                            .map(
                              (value) => DropdownMenuItem<VerificationDecision>(
                                value: value,
                                child: Text(value.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              decision = value;
                            });
                          }
                        },
                      ),
                      DropdownButton<VerificationConfidence>(
                        value: confidence,
                        items: VerificationConfidence.values
                            .map(
                              (value) =>
                                  DropdownMenuItem<VerificationConfidence>(
                                    value: value,
                                    child: Text(value.label),
                                  ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              confidence = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: explanation,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(labelText: 'Explanation'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: learningPoint,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Learning point',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Evidence items and verification-tool actions remain unchanged here. Archive and replace the case if those evidence keys need a structural rewrite.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      await controller.updateCase(
        item: item,
        title: title.text,
        scenario: scenario.text,
        claimText: claim.text,
        subskill: subskill,
        caseType: caseType,
        difficulty: level,
        correctDecision: decision,
        expectedConfidence: confidence,
        explanation: explanation.text,
        learningPoint: learningPoint.text,
      );
    }

    title.dispose();
    scenario.dispose();
    claim.dispose();
    explanation.dispose();
    learningPoint.dispose();
  }

  Future<void> _confirmArchive(
    BuildContext context,
    VerificationStudioController controller,
    VerificationCase item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive verification case?'),
        content: Text(
          'Archive “${item.title}”? Historical learner attempts remain, but the case will stop appearing in new sessions.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.archiveCase(item.id);
    }
  }
}

class _FreshDraftPanel extends StatelessWidget {
  final VerificationStudioController studio;
  final ContentAutomationController automation;
  final Future<void> Function() onGenerate;
  final bool preparing;

  const _FreshDraftPanel({
    required this.studio,
    required this.automation,
    required this.onGenerate,
    required this.preparing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limits = studio.automationOverview;
    final queueFull = limits.pendingDrafts >= limits.maxPendingDrafts;
    final cooldown = studio.generationCooldownMinutes;
    final onCooldown = cooldown > 0;
    final budgetEmpty =
        limits.remainingToday <= 0 ||
        limits.remainingThisMonth <= 0 ||
        limits.groqRequestsRemaining <= 0 ||
        queueFull ||
        onCooldown;
    final busy =
        preparing ||
        automation.isMutating ||
        studio.isMutating ||
        studio.isLoading;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fresh AI drafts for Verify',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose a focus. Generate a draft. Review before publishing.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          StudioMetricRow(
            children: [
              StudioMetric(
                value: '${limits.pendingDrafts}/${limits.maxPendingDrafts}',
                label: 'Drafts in review',
                icon: Icons.description_outlined,
              ),
              StudioMetric(
                value: '${limits.remainingToday}',
                label: 'Drafts left today',
                icon: Icons.today_outlined,
              ),
              StudioMetric(
                value: '${limits.remainingThisMonth}',
                label: 'Drafts left this month',
                icon: Icons.calendar_month_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(
                  limits.enabled ? Icons.schedule : Icons.pause_rounded,
                  size: 16,
                ),
                label: Text(
                  limits.enabled ? 'Schedule enabled' : 'Schedule paused',
                ),
              ),
              const Chip(
                avatar: Icon(Icons.lock_outline, size: 16),
                label: Text('Review required'),
              ),
            ],
          ),
          if (budgetEmpty || !limits.enabled) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              !limits.enabled
                  ? 'Enable automation in settings to generate drafts.'
                  : queueFull
                  ? 'Review pending drafts to make room for more.'
                  : onCooldown
                  ? 'Next generation available in about $cooldown min. This wait applies to all verification skills.'
                  : 'Your generation budget has been reached. Check limits in settings.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (automation.actionErrorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            StudioNotice(
              title: 'Generation could not complete',
              message: automation.actionErrorMessage!,
              isError: true,
              onDismiss: automation.clearMessages,
            ),
          ],
          if (automation.successMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            StudioNotice(
              title: 'Generation result',
              message: automation.successMessage!,
              onDismiss: automation.clearMessages,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: busy || !limits.enabled || budgetEmpty
                    ? null
                    : onGenerate,
                icon: Icon(
                  automation.isMutating
                      ? Icons.hourglass_top_rounded
                      : Icons.auto_awesome_outlined,
                  size: 18,
                ),
                label: Text(
                  automation.isMutating
                      ? 'Generating...'
                      : preparing
                      ? 'Checking sources...'
                      : onCooldown
                      ? 'Ready in $cooldown min'
                      : 'Generate drafts',
                ),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _openSettings(context),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Automation settings'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Limits & queue details'),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Up to ${limits.maxArticlesPerRun} sources and ${limits.maxDraftsPerRun} drafts per run. Monthly AI requests: ${limits.groqRequestsThisMonth}/${limits.monthlyGroqRequestCap}. Topic choices apply to this run only.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    final result = await showDialog<_VerifyAutomationSettingsValue>(
      context: context,
      builder: (context) =>
          _VerifyAutomationSettingsDialog(settings: studio.automationOverview),
    );
    if (result == null || !context.mounted) return;

    await studio.saveAutomationSettings(
      enabled: result.enabled,
      maxArticlesPerRun: result.maxArticlesPerRun,
      maxDraftsPerRun: result.maxDraftsPerRun,
      maxDraftsPerDay: result.maxDraftsPerDay,
      monthlyDraftCap: result.monthlyDraftCap,
      monthlyGroqRequestCap: result.monthlyGroqRequestCap,
      maxPendingDrafts: result.maxPendingDrafts,
      manualCooldownMinutes: result.manualCooldownMinutes,
    );
  }
}

class _VerifyAutomationSettingsValue {
  final bool enabled;
  final int maxArticlesPerRun;
  final int maxDraftsPerRun;
  final int maxDraftsPerDay;
  final int monthlyDraftCap;
  final int monthlyGroqRequestCap;
  final int maxPendingDrafts;
  final int manualCooldownMinutes;

  const _VerifyAutomationSettingsValue({
    required this.enabled,
    required this.maxArticlesPerRun,
    required this.maxDraftsPerRun,
    required this.maxDraftsPerDay,
    required this.monthlyDraftCap,
    required this.monthlyGroqRequestCap,
    required this.maxPendingDrafts,
    required this.manualCooldownMinutes,
  });
}

class _VerifyAutomationSettingsDialog extends StatefulWidget {
  final VerificationAutomationOverview settings;

  const _VerifyAutomationSettingsDialog({required this.settings});

  @override
  State<_VerifyAutomationSettingsDialog> createState() =>
      _VerifyAutomationSettingsDialogState();
}

class _VerifyAutomationSettingsDialogState
    extends State<_VerifyAutomationSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late bool _enabled;
  late final TextEditingController _articles;
  late final TextEditingController _perRun;
  late final TextEditingController _daily;
  late final TextEditingController _monthly;
  late final TextEditingController _monthlyGroq;
  late final TextEditingController _pending;
  late final TextEditingController _cooldown;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _enabled = settings.enabled;
    _articles = TextEditingController(text: '${settings.maxArticlesPerRun}');
    _perRun = TextEditingController(text: '${settings.maxDraftsPerRun}');
    _daily = TextEditingController(text: '${settings.maxDraftsPerDay}');
    _monthly = TextEditingController(text: '${settings.monthlyDraftCap}');
    _monthlyGroq = TextEditingController(
      text: '${settings.monthlyGroqRequestCap}',
    );
    _pending = TextEditingController(text: '${settings.maxPendingDrafts}');
    _cooldown = TextEditingController(
      text: '${settings.manualCooldownMinutes}',
    );
  }

  @override
  void dispose() {
    _articles.dispose();
    _perRun.dispose();
    _daily.dispose();
    _monthly.dispose();
    _monthlyGroq.dispose();
    _pending.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify automation settings'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                  title: const Text('Verify AI draft generation'),
                  subtitle: const Text(
                    'Turning this off prevents new Verify drafts. Existing approved cases remain available.',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _numberField(
                  controller: _articles,
                  label: 'Maximum Awareness articles checked per run',
                  helper: 'Range: 1–20',
                  min: 1,
                  max: 20,
                ),
                const SizedBox(height: AppSpacing.md),
                _numberField(
                  controller: _perRun,
                  label: 'Maximum Verify drafts per run',
                  helper: 'Range: 1–10',
                  min: 1,
                  max: 10,
                ),
                const SizedBox(height: AppSpacing.md),
                _numberField(
                  controller: _daily,
                  label: 'Maximum Verify drafts per day',
                  helper: 'Range: 1–50',
                  min: 1,
                  max: 50,
                ),
                const SizedBox(height: AppSpacing.md),
                _numberField(
                  controller: _monthly,
                  label: 'Monthly Verify draft cap',
                  helper:
                      'Maximum successfully created Verify drafts each month. Range: 1–1000',
                  min: 1,
                  max: 1000,
                ),
                const SizedBox(height: AppSpacing.md),
                _numberField(
                  controller: _monthlyGroq,
                  label: 'Monthly Groq generation request cap for Verify',
                  helper:
                      'Hard request guard, including failed/fallback model calls. Range: 1–5000',
                  min: 1,
                  max: 5000,
                ),
                const SizedBox(height: AppSpacing.md),
                _numberField(
                  controller: _pending,
                  label: 'Maximum pending Verify drafts',
                  helper:
                      'Generation pauses while the review queue is full. Range: 5–200',
                  min: 5,
                  max: 200,
                ),
                const SizedBox(height: AppSpacing.md),
                _numberField(
                  controller: _cooldown,
                  label: 'Manual successful-run cooldown',
                  helper:
                      'Minutes between successful manual runs. Range: 1–120',
                  min: 1,
                  max: 120,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Current usage: ${widget.settings.draftsThisMonth}/${widget.settings.monthlyDraftCap} drafts and ${widget.settings.groqRequestsThisMonth}/${widget.settings.monthlyGroqRequestCap} Groq generation requests this month. AI content always remains draft-only until an administrator approves it.',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save settings')),
      ],
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String helper,
    required int min,
    required int max,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, helperText: helper),
      validator: (value) {
        final number = int.tryParse(value?.trim() ?? '');
        if (number == null || number < min || number > max) {
          return 'Enter a whole number from $min to $max.';
        }
        return null;
      },
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      _VerifyAutomationSettingsValue(
        enabled: _enabled,
        maxArticlesPerRun: int.parse(_articles.text.trim()),
        maxDraftsPerRun: int.parse(_perRun.text.trim()),
        maxDraftsPerDay: int.parse(_daily.text.trim()),
        monthlyDraftCap: int.parse(_monthly.text.trim()),
        monthlyGroqRequestCap: int.parse(_monthlyGroq.text.trim()),
        maxPendingDrafts: int.parse(_pending.text.trim()),
        manualCooldownMinutes: int.parse(_cooldown.text.trim()),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final VerificationStudioController controller;

  const _StatusCard({required this.controller});

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Row(
      children: [
        Icon(
          Icons.fact_check_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            controller.isLoading
                ? 'Refreshing your workspace...'
                : 'Your verification workspace',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton(
          tooltip: 'Refresh data',
          onPressed: controller.isLoading ? null : controller.refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
  );
}

class _HealthGrid extends StatelessWidget {
  final List<VerificationCaseHealth> items;

  const _HealthGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;

        final width =
            (constraints.maxWidth - (columns - 1) * AppSpacing.md) / columns;

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: items
              .map((item) {
                return SizedBox(
                  width: width,
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.subskill.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text('${item.publishedCases} published cases'),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (var level = 1; level <= 5; level++)
                              Chip(
                                label: Text(
                                  '${_levelLabel(level)}: ${item.byLevel[level] ?? 0}',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }
}

class _DraftCard extends StatelessWidget {
  final VerificationCaseDraft draft;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _DraftCard({
    required this.draft,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Chip(label: Text('DRAFT')),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${draft.subskill.label} · ${_levelLabel(draft.difficulty)} · ${draft.caseType.label} · ${draft.sourceName}',
          ),
          const SizedBox(height: AppSpacing.md),
          Text(draft.summary),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: busy ? null : onReject,
                child: const Text('Reject'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onApprove,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Approve case'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final String query;
  final VerificationSubskill? subskill;
  final int? level;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<VerificationSubskill?> onSubskillChanged;
  final ValueChanged<int?> onLevelChanged;

  const _Filters({
    required this.query,
    required this.subskill,
    required this.level,
    required this.onQueryChanged,
    required this.onSubskillChanged,
    required this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search cases',
            ),
          );
          final subskillFilter = DropdownButtonFormField<VerificationSubskill?>(
            key: ValueKey(subskill),
            isExpanded: true,
            initialValue: subskill,
            decoration: const InputDecoration(labelText: 'Verify skill'),
            items: [
              const DropdownMenuItem<VerificationSubskill?>(
                value: null,
                child: Text('All subskills'),
              ),
              ...VerificationSubskill.values.map(
                (item) => DropdownMenuItem<VerificationSubskill?>(
                  value: item,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: onSubskillChanged,
          );
          final levelFilter = DropdownButtonFormField<int?>(
            key: ValueKey(level),
            isExpanded: true,
            initialValue: level,
            decoration: const InputDecoration(labelText: 'Challenge level'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('All levels'),
              ),
              for (var i = 1; i <= 5; i++)
                DropdownMenuItem<int?>(value: i, child: Text(_levelLabel(i))),
            ],
            onChanged: onLevelChanged,
          );

          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: AppSpacing.md),
                subskillFilter,
                const SizedBox(height: AppSpacing.md),
                levelFilter,
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 2, child: search),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: subskillFilter),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: levelFilter),
            ],
          );
        },
      ),
    );
  }
}

class _CaseBankCard extends StatelessWidget {
  final VerificationCase item;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const _CaseBankCard({
    required this.item,
    required this.busy,
    required this.onEdit,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(child: Icon(_caseIcon(item.caseType), size: 18)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${item.subskill.label} · ${item.difficulty.label} · ${item.caseType.label}${item.generated ? ' · AI-assisted' : ' · PromptWise curated'}',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.scenario,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit case',
            onPressed: busy ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Archive case',
            onPressed: busy ? null : onArchive,
            icon: const Icon(Icons.archive_outlined),
          ),
        ],
      ),
    );
  }
}

String _levelLabel(int level) {
  return switch (level.clamp(1, 5)) {
    1 => 'Foundation',
    2 => 'Developing',
    3 => 'Proficient',
    4 => 'Advanced',
    _ => 'Expert',
  };
}

IconData _caseIcon(VerificationCaseType type) {
  return switch (type) {
    VerificationCaseType.image => Icons.image_outlined,
    VerificationCaseType.video => Icons.video_file_outlined,
    VerificationCaseType.audio => Icons.graphic_eq_rounded,
    VerificationCaseType.claim => Icons.fact_check_outlined,
    VerificationCaseType.citation => Icons.menu_book_outlined,
    VerificationCaseType.scam => Icons.gpp_maybe_outlined,
  };
}

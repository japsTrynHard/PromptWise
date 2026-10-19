import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/content_automation_controller.dart';
import '../../../data/models/content_automation.dart';
import '../../../data/models/learning_progression.dart';
import '../../../data/models/learning_topic.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_intro.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_message.dart';
import '../../widgets/studio_generation_widgets.dart';
import '../../widgets/draft_queue_widgets.dart';

class AdminLearningStudioScreen extends StatefulWidget {
  const AdminLearningStudioScreen({super.key});

  @override
  State<AdminLearningStudioScreen> createState() =>
      _AdminLearningStudioScreenState();
}

class _AdminLearningStudioScreenState extends State<AdminLearningStudioScreen> {
  bool _initialLoadRequested = false;
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
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AdaptiveLayout.pageInsets(context),
        child: Consumer<ContentAutomationController>(
          builder: (context, controller, _) {
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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageIntro(
                  title: 'Learning Studio',
                  description:
                      'Create focused lessons, review drafts, and grow your learning library.',
                ),
                const SizedBox(height: AppSpacing.xl),
                _buildStudioContent(context, controller),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStudioContent(
    BuildContext context,
    ContentAutomationController controller,
  ) {
    final errorMessage = controller.loadErrorMessage;
    final successMessage = controller.successMessage;

    if (!controller.isAdministrator) {
      return const StateMessage.error(
        title: 'Administrator access required',
        message:
            'Learning Studio is only available to administrator accounts. If you just signed in, wait a moment and refresh this page.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(controller),
        if (errorMessage != null) ...[
          const SizedBox(height: AppSpacing.lg),
          StudioNotice(
            title: 'Some sections could not refresh',
            message: errorMessage,
            isError: true,
          ),
        ],
        if (successMessage != null) ...[
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            backgroundColor: AppColors.success.withValues(alpha: 0.09),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: AppColors.success,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(successMessage)),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        _AutomationCard(controller: controller),
        const SizedBox(height: AppSpacing.section),
        const SectionHeader(
          title: 'Learning-content health',
          subtitle:
              'Check whether every topic has enough lessons, objectives, and questions across Foundation to Expert.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (controller.isLoading && controller.health.isEmpty)
          const AppCard(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (controller.health.isEmpty)
          const StateMessage.empty(
            title: 'No content-health data yet',
            message:
                'Content coverage is not available yet. Refresh your workspace to check again.',
          )
        else
          _HealthGrid(items: controller.health),
        const SizedBox(height: AppSpacing.section),
        SectionHeader(
          title: 'AI-generated drafts',
          subtitle:
              '${controller.drafts.length} draft${controller.drafts.length == 1 ? '' : 's'} waiting for review. Nothing is auto-published.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (controller.drafts.isEmpty)
          const AppCard(
            child: Text(
              'Your review queue is clear. Choose a topic above to create new lesson drafts.',
            ),
          )
        else
          DraftQueue<GeneratedContentDraft>(
            items: controller.drafts,
            itemId: (draft) => draft.id,
            busy: controller.isMutating,
            itemBuilder: (draft) => _DraftCard(
              draft: draft,
              busy: controller.isMutating,
              onPublish: () => _confirmPublish(context, draft),
              onReject: () => _confirmReject(context, draft),
            ),
          ),
        const SizedBox(height: AppSpacing.section),
        SectionHeader(
          title: 'Question review queue',
          subtitle:
              '${controller.questionReviewQueue.length} AI-generated question${controller.questionReviewQueue.length == 1 ? '' : 's'} require administrator verification before learners can receive them.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (controller.questionReviewQueue.isEmpty)
          const AppCard(
            child: Text(
              'No questions are waiting for verification. Generated questions stay blocked until an administrator reviews the answer key and quality.',
            ),
          )
        else
          ...controller.questionReviewQueue
              .take(20)
              .map(
                (question) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _QuestionReviewCard(
                    question: question,
                    busy: controller.isMutating,
                    onReview: () => _reviewQuestion(context, question),
                    onReject: () => _rejectQuestion(context, question),
                  ),
                ),
              ),
        const SizedBox(height: AppSpacing.section),
        SectionHeader(
          title: 'Approved question bank',
          subtitle:
              '${controller.approvedQuestions.length} verified question${controller.approvedQuestions.length == 1 ? '' : 's'} are available for published learning content and adaptive Knowledge Checks.',
        ),
        const SizedBox(height: AppSpacing.md),
        _ApprovedQuestionBankBrowser(items: controller.approvedQuestions),
        const SizedBox(height: AppSpacing.section),
        const SectionHeader(
          title: 'Trusted sources',
          subtitle:
              'Only enabled sources can be scanned. New information still becomes a draft and requires administrator approval.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (controller.sources.isEmpty)
          const AppCard(
            child: Text(
              'No trusted sources are available yet. Refresh your workspace to check again.',
            ),
          )
        else
          ...controller.sources.map(
            (source) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _SourceCard(
                key: ValueKey(source.id),
                source: source,
                onChanged: (value) =>
                    controller.setSourceEnabled(source.id, value),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.section),
      ],
    );
  }

  Widget _buildStatusCard(ContentAutomationController controller) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(
            controller.isLoading ? Icons.sync_rounded : Icons.school_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              controller.isLoading
                  ? 'Refreshing your workspace...'
                  : 'Your learning workspace',
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

  Future<void> _confirmPublish(
    BuildContext context,
    GeneratedContentDraft draft,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve draft to Content Management?'),
        content: Text(
          '“${draft.title}” will be converted into an editable DRAFT lesson, draft learning objectives, and question drafts. Nothing becomes learner-visible until final content and question review are completed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve draft'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    await context.read<ContentAutomationController>().publishDraft(draft.id);
  }

  Future<void> _reviewQuestion(
    BuildContext context,
    QuestionBankReviewItem question,
  ) async {
    final reviewed = await showDialog<QuestionBankReviewItem>(
      context: context,
      builder: (context) => _QuestionReviewDialog(question: question),
    );
    if (!context.mounted || reviewed == null) return;
    await context.read<ContentAutomationController>().verifyQuestion(reviewed);
  }

  Future<void> _rejectQuestion(
    BuildContext context,
    QuestionBankReviewItem question,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject question draft?'),
        content: Text(
          '“${question.stem}” will be archived and cannot appear in learner Knowledge Checks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject question'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    await context.read<ContentAutomationController>().rejectQuestion(
      question.id,
    );
  }

  Future<void> _confirmReject(
    BuildContext context,
    GeneratedContentDraft draft,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject draft?'),
        content: Text(
          '“${draft.title}” will remain in the audit history but will not be available to learners.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    await context.read<ContentAutomationController>().rejectDraft(draft.id);
  }
}

class _AutomationCard extends StatelessWidget {
  final ContentAutomationController controller;

  const _AutomationCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = controller.settings;
    final queue = controller.queueHealth;
    final cooldown = settings.cooldownRemainingMinutes;
    final queueFull =
        queue.pendingDrafts >= queue.maxPendingDrafts ||
        queue.pendingQuestions >= queue.maxPendingQuestions;
    final busy = controller.isMutating || controller.isLoading;
    final generating =
        controller.isMutating && controller.generationScope == 'learning';
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
                      'Continuous content automation',
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
                value: '${queue.pendingDrafts}/${queue.maxPendingDrafts}',
                label: 'Drafts in review',
                icon: Icons.description_outlined,
              ),
              StudioMetric(
                value: '${settings.maxDraftsPerDay}',
                label: 'Daily draft limit',
                icon: Icons.today_outlined,
              ),
              StudioMetric(
                value: '${settings.monthlyDraftCap}',
                label: 'Monthly draft limit',
                icon: Icons.calendar_month_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'SCHEDULED FOCUS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(
                  settings.enabled ? Icons.schedule : Icons.pause_rounded,
                  size: 16,
                ),
                label: Text(
                  settings.enabled ? 'Schedule enabled' : 'Schedule paused',
                ),
              ),
              ...settings.focusTopics.map(
                (topic) => Chip(label: Text(topic.label)),
              ),
              const Chip(
                avatar: Icon(Icons.lock_outline, size: 16),
                label: Text('Review required'),
              ),
            ],
          ),
          if (controller.warningMessage != null &&
              controller.generationScope != 'verification') ...[
            const SizedBox(height: AppSpacing.md),
            StudioNotice(
              title: 'Drafts saved; some requests need retry',
              message: controller.warningMessage!,
              isWarning: true,
              onDismiss: controller.clearMessages,
            ),
          ],
          if (controller.actionErrorMessage != null &&
              controller.generationScope != 'verification') ...[
            const SizedBox(height: AppSpacing.md),
            StudioNotice(
              title: 'Generation could not complete',
              message: controller.actionErrorMessage!,
              isError: true,
              onDismiss: controller.clearMessages,
            ),
          ],
          if (cooldown > 0 || queueFull || !settings.enabled) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              queueFull
                  ? 'Review pending drafts or questions to make room for more.'
                  : !settings.enabled
                  ? 'Enable automation in settings to generate drafts.'
                  : 'Next generation available in about $cooldown min. This wait applies to all learning topics.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed:
                    busy || !settings.enabled || cooldown > 0 || queueFull
                    ? null
                    : () => _openManualFocusDialog(context),
                icon: generating
                    ? const StudioGenerationSpinner()
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(
                  generating
                      ? 'Generating...'
                      : cooldown > 0
                      ? 'Ready in $cooldown min'
                      : 'Choose topics to generate',
                ),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _openAutomationSettings(context),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Automation settings'),
              ),
            ],
          ),
          if (generating) ...[
            const SizedBox(height: AppSpacing.md),
            const StudioGenerationProgress(),
          ],
          const SizedBox(height: AppSpacing.md),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Limits & queue details'),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Scheduled runs target up to ${settings.maxArticlesPerRun} drafts. Manual runs target one lesson per selected topic, subject to daily/monthly and review-queue capacity. Question queue: ${queue.pendingQuestions}/${queue.maxPendingQuestions}. Pending drafts archive after ${queue.draftArchiveDays} days.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openManualFocusDialog(BuildContext context) async {
    final chosen = await showDialog<List<LearningTopic>>(
      context: context,
      builder: (dialogContext) => StudioFocusDialog<LearningTopic>(
        title: 'Create lesson drafts',
        description:
            'Choose topics for this run only. Each selected topic requests one lesson draft. Daily/monthly limits and review-queue capacity must fit the whole selection. Your saved scheduled focus areas will not change.',
        initial: controller.settings.focusTopics,
        options: LearningTopic.values
            .map(
              (topic) => StudioFocusOption(
                topic,
                topic.label,
                topic.shortDescription,
                switch (topic) {
                  LearningTopic.promptClarity =>
                    Icons.chat_bubble_outline_rounded,
                  LearningTopic.context => Icons.layers_outlined,
                  LearningTopic.specificity =>
                    Icons.center_focus_strong_outlined,
                  LearningTopic.responsibleUse => Icons.shield_outlined,
                  LearningTopic.verification => Icons.fact_check_outlined,
                },
              ),
            )
            .toList(),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await controller.runNow(chosen);
  }

  Future<void> _openAutomationSettings(BuildContext context) async {
    final settings = controller.settings;
    final result = await showDialog<_AutomationSettingsValue>(
      context: context,
      builder: (context) => _AutomationSettingsDialog(settings: settings),
    );
    if (result == null || !context.mounted) return;
    await controller.saveSettings(
      manualCooldownMinutes: result.manualCooldownMinutes,
      enabled: result.enabled,
      maxArticlesPerRun: result.maxArticlesPerRun,
      maxDraftsPerDay: result.maxDraftsPerDay,
      monthlyDraftCap: result.monthlyDraftCap,
      maxPendingDrafts: result.maxPendingDrafts,
      maxPendingQuestions: result.maxPendingQuestions,
      draftArchiveDays: result.draftArchiveDays,
      focusTopics: result.focusTopics,
    );
  }
}

class _AutomationSettingsValue {
  final int manualCooldownMinutes;
  final bool enabled;
  final int maxArticlesPerRun;
  final int maxDraftsPerDay;
  final int monthlyDraftCap;
  final int maxPendingDrafts;
  final int maxPendingQuestions;
  final int draftArchiveDays;
  final List<LearningTopic> focusTopics;

  const _AutomationSettingsValue({
    required this.manualCooldownMinutes,
    required this.enabled,
    required this.maxArticlesPerRun,
    required this.maxDraftsPerDay,
    required this.monthlyDraftCap,
    required this.maxPendingDrafts,
    required this.maxPendingQuestions,
    required this.draftArchiveDays,
    required this.focusTopics,
  });
}

class _AutomationSettingsDialog extends StatefulWidget {
  final AutomationSettings settings;

  const _AutomationSettingsDialog({required this.settings});

  @override
  State<_AutomationSettingsDialog> createState() =>
      _AutomationSettingsDialogState();
}

class _AutomationSettingsDialogState extends State<_AutomationSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late bool _enabled;
  late Set<LearningTopic> _focusTopics;
  bool _showFocusError = false;
  late final TextEditingController _articles;
  late final TextEditingController _cooldown;
  late final TextEditingController _dailyDrafts;
  late final TextEditingController _monthlyDrafts;
  late final TextEditingController _pendingDrafts;
  late final TextEditingController _pendingQuestions;
  late final TextEditingController _archiveDays;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.enabled;
    _focusTopics = widget.settings.focusTopics.toSet();
    _cooldown = TextEditingController(
      text: widget.settings.manualCooldownMinutes.toString(),
    );
    _articles = TextEditingController(
      text: widget.settings.maxArticlesPerRun.toString(),
    );
    _dailyDrafts = TextEditingController(
      text: widget.settings.maxDraftsPerDay.toString(),
    );
    _monthlyDrafts = TextEditingController(
      text: widget.settings.monthlyDraftCap.toString(),
    );
    _pendingDrafts = TextEditingController(
      text: widget.settings.maxPendingDrafts.toString(),
    );
    _pendingQuestions = TextEditingController(
      text: widget.settings.maxPendingQuestions.toString(),
    );
    _archiveDays = TextEditingController(
      text: widget.settings.draftArchiveDays.toString(),
    );
  }

  @override
  void dispose() {
    _cooldown.dispose();
    _articles.dispose();
    _dailyDrafts.dispose();
    _monthlyDrafts.dispose();
    _pendingDrafts.dispose();
    _pendingQuestions.dispose();
    _archiveDays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Automation settings'),
      content: SizedBox(
        width: 520,
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
                  title: const Text('Continuous content automation'),
                  subtitle: const Text(
                    'Turning this off stops new automated discovery runs. Existing published learning content is unaffected.',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Scheduled generation focus areas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Select topics for scheduled AI generation. Select at least one before enabling automation.',
                ),
                ...LearningTopic.values.map(
                  (topic) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(topic.label),
                    subtitle: Text(topic.shortDescription),
                    value: _focusTopics.contains(topic),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _focusTopics.add(topic);
                      } else {
                        _focusTopics.remove(topic);
                      }
                      _showFocusError = false;
                    }),
                  ),
                ),
                if (_showFocusError)
                  Text(
                    'Select at least one scheduled focus area.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _cooldown,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Manual generation cooldown',
                    suffixText: 'minutes',
                    helperText: '0 disables the wait for demos. Range: 0-1440.',
                  ),
                  validator: (value) => _validateInt(value, 0, 1440),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _articles,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum articles per run',
                    helperText: 'Allowed range: 1–10',
                  ),
                  validator: (value) => _validateInt(value, 1, 10),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _dailyDrafts,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum drafts per day',
                    helperText: 'Allowed range: 1–20',
                  ),
                  validator: (value) => _validateInt(value, 1, 20),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _monthlyDrafts,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Monthly draft cap',
                    helperText: 'Allowed range: 1–1000',
                  ),
                  validator: (value) => _validateInt(value, 1, 1000),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _pendingDrafts,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum pending AI lesson drafts',
                    helperText:
                        'Automation pauses when this queue is full. Range: 5–200',
                  ),
                  validator: (value) => _validateInt(value, 5, 200),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _pendingQuestions,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum pending AI questions',
                    helperText:
                        'Prevents the review queue from growing without limit. Range: 20–1000',
                  ),
                  validator: (value) => _validateInt(value, 20, 1000),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _archiveDays,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Auto-archive untouched pending content after',
                    suffixText: 'days',
                    helperText: 'Default: 30 days. Range: 7–180',
                  ),
                  validator: (value) => _validateInt(value, 7, 180),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Generated material always remains draft-only until an administrator reviews it. Auto-publish stays disabled. Approved/published content is never auto-deleted.',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _restoreDefaults,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Restore tipid defaults'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save settings')),
      ],
    );
  }

  void _restoreDefaults() {
    final defaults = AutomationSettings.defaults();
    setState(() {
      _articles.text = defaults.maxArticlesPerRun.toString();
      _dailyDrafts.text = defaults.maxDraftsPerDay.toString();
      _monthlyDrafts.text = defaults.monthlyDraftCap.toString();
      _pendingDrafts.text = defaults.maxPendingDrafts.toString();
      _pendingQuestions.text = defaults.maxPendingQuestions.toString();
      _archiveDays.text = defaults.draftArchiveDays.toString();
      _cooldown.text = defaults.manualCooldownMinutes.toString();
    });
  }

  String? _validateInt(String? raw, int min, int max) {
    final value = int.tryParse(raw?.trim() ?? '');
    if (value == null || value < min || value > max) {
      return 'Enter a whole number from $min to $max.';
    }
    return null;
  }

  void _save() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_enabled && _focusTopics.isEmpty) {
      setState(() => _showFocusError = true);
      return;
    }
    Navigator.pop(
      context,
      _AutomationSettingsValue(
        manualCooldownMinutes: int.parse(_cooldown.text.trim()),
        enabled: _enabled,
        maxArticlesPerRun: int.parse(_articles.text.trim()),
        maxDraftsPerDay: int.parse(_dailyDrafts.text.trim()),
        monthlyDraftCap: int.parse(_monthlyDrafts.text.trim()),
        maxPendingDrafts: int.parse(_pendingDrafts.text.trim()),
        maxPendingQuestions: int.parse(_pendingQuestions.text.trim()),
        draftArchiveDays: int.parse(_archiveDays.text.trim()),
        focusTopics: LearningTopic.values
            .where(_focusTopics.contains)
            .toList(growable: false),
      ),
    );
  }
}

class _HealthGrid extends StatelessWidget {
  final List<LearningContentHealth> items;

  const _HealthGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 3
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _HealthCard(item: items[i]),
                if (i != items.length - 1)
                  const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        }
        final spacing = AppSpacing.md;
        final totalSpacing = spacing * (columns - 1);
        final itemWidth = (constraints.maxWidth - totalSpacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _HealthCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _HealthCard extends StatelessWidget {
  final LearningContentHealth item;

  const _HealthCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.topic.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${item.lessons} lessons · ${item.objectives} objectives · ${item.publishedQuestions} published questions',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var level = 1; level <= 5; level++)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '${LearningRankX.fromLevel(level).label}: ${item.questionsByLevel[level] ?? 0}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  final GeneratedContentDraft draft;
  final bool busy;
  final VoidCallback onPublish;
  final VoidCallback onReject;

  const _DraftCard({
    required this.draft,
    required this.busy,
    required this.onPublish,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${draft.topic.label} · ${LearningRankX.fromLevel(draft.targetLevel).label} · ${draft.sourceName}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Chip(label: Text(draft.status.toUpperCase())),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DraftTimestamp(createdAt: draft.createdAt),
          const SizedBox(height: AppSpacing.sm),
          Text(
            draft.summary,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              Chip(label: Text('${draft.objectives.length} objectives')),
              Chip(label: Text('${draft.lessonSections.length} sections')),
              Chip(label: Text('${draft.questionCount} question drafts')),
            ],
          ),
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
                onPressed: busy ? null : onPublish,
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: const Text('Approve to Content Management'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionReviewCard extends StatelessWidget {
  final QuestionBankReviewItem question;
  final bool busy;
  final VoidCallback onReview;
  final VoidCallback onReject;

  const _QuestionReviewCard({
    required this.question,
    required this.busy,
    required this.onReview,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Chip(label: Text(question.topic.label)),
              Chip(
                label: Text(LearningRankX.fromLevel(question.difficulty).label),
              ),
              Chip(label: Text(question.questionType.replaceAll('_', ' '))),
              if (question.generatedBy != 'manual')
                const Chip(label: Text('AI draft')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(question.stem, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Answer key and explanation must be checked by a human before this question can enter the adaptive bank.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
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
                onPressed: busy ? null : onReview,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review question'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionReviewDialog extends StatefulWidget {
  final QuestionBankReviewItem question;

  const _QuestionReviewDialog({required this.question});

  @override
  State<_QuestionReviewDialog> createState() => _QuestionReviewDialogState();
}

class _QuestionReviewDialogState extends State<_QuestionReviewDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _stem;
  late final List<TextEditingController> _options;
  late final TextEditingController _explanation;
  late int _correctIndex;
  late int _difficulty;
  late String _questionType;

  @override
  void initState() {
    super.initState();
    _stem = TextEditingController(text: widget.question.stem);
    _options = List.generate(
      4,
      (index) => TextEditingController(
        text: index < widget.question.options.length
            ? widget.question.options[index]
            : '',
      ),
    );
    _explanation = TextEditingController(text: widget.question.explanation);
    _correctIndex = widget.question.correctIndex.clamp(0, 3);
    _difficulty = widget.question.difficulty.clamp(1, 5);
    _questionType =
        const [
          'concept',
          'scenario',
          'best_response',
          'evaluation',
        ].contains(widget.question.questionType)
        ? widget.question.questionType
        : 'scenario';
  }

  @override
  void dispose() {
    _stem.dispose();
    for (final controller in _options) {
      controller.dispose();
    }
    _explanation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verify question',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${widget.question.topic.label} · Human answer-key review required',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _stem,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Question',
                          helperText:
                              'Check that the question is rigorous, unambiguous, and appropriate for the selected level.',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 12
                            ? 'Enter a complete question.'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: _difficulty,
                              decoration: const InputDecoration(
                                labelText: 'Challenge level',
                              ),
                              items: [
                                for (var level = 1; level <= 5; level++)
                                  DropdownMenuItem(
                                    value: level,
                                    child: Text(
                                      LearningRankX.fromLevel(level).label,
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _difficulty = value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _questionType,
                              decoration: const InputDecoration(
                                labelText: 'Question type',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'concept',
                                  child: Text('Concept'),
                                ),
                                DropdownMenuItem(
                                  value: 'scenario',
                                  child: Text('Scenario'),
                                ),
                                DropdownMenuItem(
                                  value: 'best_response',
                                  child: Text('Best response'),
                                ),
                                DropdownMenuItem(
                                  value: 'evaluation',
                                  child: Text('Evaluation'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _questionType = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Answer options',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      RadioGroup<int>(
                        groupValue: _correctIndex,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _correctIndex = value);
                          }
                        },
                        child: Column(
                          children: [
                            for (var index = 0; index < 4; index++) ...[
                              RadioListTile<int>(
                                value: index,
                                contentPadding: EdgeInsets.zero,
                                title: TextFormField(
                                  controller: _options[index],
                                  decoration: InputDecoration(
                                    labelText:
                                        'Option ${String.fromCharCode(65 + index)}${_correctIndex == index ? ' · correct answer' : ''}',
                                  ),
                                  validator: (value) =>
                                      (value?.trim().isEmpty ?? true)
                                      ? 'Enter an answer option.'
                                      : null,
                                ),
                              ),
                              if (index != 3)
                                const SizedBox(height: AppSpacing.xs),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _explanation,
                        minLines: 3,
                        maxLines: 7,
                        decoration: const InputDecoration(
                          labelText: 'Answer explanation',
                          helperText:
                              'Verify why the selected answer is best. This feedback is shown after the learner answers.',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 20
                            ? 'Add a meaningful explanation.'
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Verify and save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final options = _options
        .map((controller) => controller.text.trim())
        .toList();
    final normalized = options.map((value) => value.toLowerCase()).toSet();
    if (normalized.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All four answer options must be different.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      widget.question.copyWith(
        stem: _stem.text.trim(),
        options: options,
        correctIndex: _correctIndex,
        explanation: _explanation.text.trim(),
        difficulty: _difficulty,
        questionType: _questionType,
      ),
    );
  }
}

class _ApprovedQuestionBankBrowser extends StatefulWidget {
  final List<QuestionBankReviewItem> items;

  const _ApprovedQuestionBankBrowser({required this.items});

  @override
  State<_ApprovedQuestionBankBrowser> createState() =>
      _ApprovedQuestionBankBrowserState();
}

class _ApprovedQuestionBankBrowserState
    extends State<_ApprovedQuestionBankBrowser> {
  final TextEditingController _searchController = TextEditingController();
  LearningTopic? _topic;
  int? _difficulty;
  bool _showAnswerKeys = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.items
        .where((item) {
          if (_topic != null && item.topic != _topic) return false;
          if (_difficulty != null && item.difficulty != _difficulty) {
            return false;
          }
          if (query.isEmpty) return true;
          return item.stem.toLowerCase().contains(query) ||
              item.questionCode.toLowerCase().contains(query) ||
              item.topic.label.toLowerCase().contains(query) ||
              item.generatedBy.toLowerCase().contains(query);
        })
        .toList(growable: false);

    if (widget.items.isEmpty) {
      return const AppCard(
        child: Text(
          'No verified questions are available yet. Approve questions from the review queue and they will appear here.',
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search approved questions',
                    hintText: 'Question text, code, topic, or source',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: DropdownButtonFormField<LearningTopic?>(
                  isExpanded: true,
                  initialValue: _topic,
                  decoration: const InputDecoration(labelText: 'Topic'),
                  items: [
                    const DropdownMenuItem<LearningTopic?>(
                      value: null,
                      child: Text('All topics'),
                    ),
                    ...LearningTopic.values.map(
                      (topic) => DropdownMenuItem<LearningTopic?>(
                        value: topic,
                        child: Text(topic.label),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _topic = value),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _difficulty,
                  decoration: const InputDecoration(labelText: 'Level'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All levels'),
                    ),
                    for (var level = 1; level <= 5; level++)
                      DropdownMenuItem<int?>(
                        value: level,
                        child: Text(QuestionDifficultyX.fromLevel(level).label),
                      ),
                  ],
                  onChanged: (value) => setState(() => _difficulty = value),
                ),
              ),
              FilterChip(
                selected: _showAnswerKeys,
                avatar: Icon(
                  _showAnswerKeys
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 18,
                ),
                label: const Text('Show answer keys'),
                onSelected: (value) => setState(() => _showAnswerKeys = value),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '${filtered.length} matching question${filtered.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text('No approved questions match these filters.'),
            )
          else
            DraftQueue<QuestionBankReviewItem>(
              key: ValueKey('questions:$_topic:$_difficulty:$query'),
              items: filtered,
              itemLabel: 'questions',
              itemId: (item) => item.id,
              itemBuilder: (item) => _ApprovedQuestionCard(
                item: item,
                showAnswerKey: _showAnswerKeys,
              ),
            ),
        ],
      ),
    );
  }
}

class _ApprovedQuestionCard extends StatelessWidget {
  final QuestionBankReviewItem item;
  final bool showAnswerKey;

  const _ApprovedQuestionCard({
    required this.item,
    required this.showAnswerKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final level = QuestionDifficultyX.fromLevel(item.difficulty).label;
    final answer =
        item.correctIndex >= 0 && item.correctIndex < item.options.length
        ? item.options[item.correctIndex]
        : 'Answer key unavailable';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _QuestionMetaPill(label: item.topic.label),
              _QuestionMetaPill(label: level),
              _QuestionMetaPill(label: item.questionType.replaceAll('_', ' ')),
              _QuestionMetaPill(
                label: item.generatedBy.startsWith('phase7_')
                    ? 'PromptWise curated'
                    : item.generatedBy == 'manual'
                    ? 'Manual'
                    : 'AI-assisted',
              ),
              _QuestionMetaPill(
                label: item.status == 'published' ? 'Published' : 'Verified',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DraftTimestamp(createdAt: item.approvedAt, eventLabel: 'Approved'),
          const SizedBox(height: AppSpacing.sm),
          Text(item.stem, style: theme.textTheme.titleSmall),
          if (item.questionCode.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.questionCode,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (showAnswerKey) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Correct answer',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(answer),
                  if (item.explanation.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      item.explanation,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionMetaPill extends StatelessWidget {
  final String label;

  const _QuestionMetaPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

class _SourceCard extends StatefulWidget {
  final ContentSource source;
  final Future<bool> Function(bool enabled) onChanged;

  const _SourceCard({super.key, required this.source, required this.onChanged});

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.source.enabled;
  }

  @override
  void didUpdateWidget(covariant _SourceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving && oldWidget.source.enabled != widget.source.enabled) {
      _enabled = widget.source.enabled;
    }
  }

  Future<void> _toggle(bool value) async {
    if (_saving) return;

    final previous = _enabled;
    setState(() {
      _enabled = value;
      _saving = true;
    });

    final saved = await widget.onChanged(value);
    if (!mounted) return;

    setState(() {
      _saving = false;
      _enabled = saved ? value : previous;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Text('${widget.source.trustLevel}'),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.source.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Trust ${widget.source.trustLevel}/5 · ${widget.source.sourceType.toUpperCase()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: _saving
                ? SizedBox(
                    key: const ValueKey('saving'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : const SizedBox(key: ValueKey('idle'), width: 18, height: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch(value: _enabled, onChanged: _saving ? null : _toggle),
        ],
      ),
    );
  }
}

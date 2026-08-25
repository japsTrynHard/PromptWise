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

class AdminLearningStudioScreen extends StatefulWidget {
  const AdminLearningStudioScreen({super.key});

  @override
  State<AdminLearningStudioScreen> createState() =>
      _AdminLearningStudioScreenState();
}

class _AdminLearningStudioScreenState
    extends State<AdminLearningStudioScreen> {
  bool _initialLoadRequested = false;

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
                      'Monitor learning depth, review AI-generated content, control trusted sources, and keep every automated update behind administrator approval.',
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
    final errorMessage = controller.errorMessage;
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
          StateMessage.error(
            title: 'Some Learning Studio data could not load',
            message: errorMessage,
            actionLabel: 'Retry',
            onAction: controller.refresh,
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
                'The page is working, but no Phase 7 health rows were returned. Check the Phase 7 SQL/RLS setup and press Retry.',
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
              'No lesson drafts are waiting for review. Run a manual trusted-source check after the Edge Function is deployed.',
            ),
          )
        else
          ...controller.drafts.map(
            (draft) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _DraftCard(
                draft: draft,
                busy: controller.isMutating,
                onPublish: () => _confirmPublish(context, draft),
                onReject: () => _confirmReject(context, draft),
              ),
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
          ...controller.questionReviewQueue.take(20).map(
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
              'No trusted sources were returned. The Learning Studio itself is available; verify the content_sources table and its administrator RLS policy.',
            ),
          )
        else
          ...controller.sources.map(
            (source) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _SourceCard(
                key: ValueKey(source.id),
                source: source,
                onChanged: (value) => controller.setSourceEnabled(
                  source.id,
                  value,
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.section),
      ],
    );
  }

  Widget _buildStatusCard(ContentAutomationController controller) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ready = controller.hasLoaded && controller.errorMessage == null;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      backgroundColor: ready
          ? AppColors.success.withValues(alpha: 0.07)
          : colors.surfaceContainerHighest.withValues(alpha: 0.45),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final status = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ready
                      ? AppColors.success.withValues(alpha: 0.14)
                      : colors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  controller.isLoading
                      ? Icons.sync_rounded
                      : ready
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_sync_outlined,
                  color: ready ? AppColors.success : colors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.isLoading
                          ? 'Loading Learning Studio data…'
                          : ready
                              ? 'Learning Studio connected'
                              : 'Learning Studio is available',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      controller.isLoading
                          ? 'PromptWise is reading the Phase 7 tables from Supabase.'
                          : ready
                              ? 'The Phase 7 administrator data loaded successfully.'
                              : 'If an online section fails, it will show its error here instead of leaving this page blank.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final refresh = OutlinedButton.icon(
            onPressed: controller.isLoading ? null : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh data'),
          );

          if (constraints.maxWidth < 650) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                const SizedBox(height: AppSpacing.md),
                refresh,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: AppSpacing.lg),
              refresh,
            ],
          );
        },
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
    await context.read<ContentAutomationController>().rejectQuestion(question.id);
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
    final settings = controller.settings;
    final queue = controller.queueHealth;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.4,
          ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Continuous content automation',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                settings.enabled
                    ? 'Enabled. PromptWise can discover relevant AI-literacy updates from trusted sources and save structured drafts for review.'
                    : 'Disabled. Existing learning content continues to work, but no automated discovery runs should create drafts.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  Chip(
                    label: Text(
                      'Max ${settings.maxArticlesPerRun} articles/run',
                    ),
                  ),
                  Chip(
                    label: Text('Max ${settings.maxDraftsPerDay} drafts/day'),
                  ),
                  Chip(
                    label: Text('${settings.monthlyDraftCap} drafts/month cap'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                    label: Text(
                      'Draft queue ${queue.pendingDrafts}/${queue.maxPendingDrafts}',
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.fact_check_outlined, size: 16),
                    label: Text(
                      'Question queue ${queue.pendingQuestions}/${queue.maxPendingQuestions}',
                    ),
                  ),
                  const Chip(label: Text('Auto-publish OFF')),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Queue protection: untouched AI drafts/questions auto-archive after ${queue.draftArchiveDays} days; rejected items are removed after ${queue.rejectedDeleteDays} days; archived pending AI content is removed after ${queue.archivedDeleteDays} days.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.45,
                    ),
              ),
              if (queue.expiringDraftsSoon > 0 ||
                  queue.expiringQuestionsSoon > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${queue.expiringDraftsSoon} lesson draft${queue.expiringDraftsSoon == 1 ? '' : 's'} and ${queue.expiringQuestionsSoon} question${queue.expiringQuestionsSoon == 1 ? '' : 's'} will auto-archive within about 5 days unless reviewed.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          );

          final runAction = FilledButton.icon(
            onPressed: controller.isMutating || !settings.enabled
                ? null
                : controller.runNow,
            icon: controller.isMutating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              controller.isMutating ? 'Checking...' : 'Check for updates now',
            ),
          );
          final settingsAction = OutlinedButton.icon(
            onPressed: controller.isMutating
                ? null
                : () => _openAutomationSettings(context),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Automation settings'),
          );

          if (constraints.maxWidth >= 720) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: info),
                const SizedBox(width: AppSpacing.xxl),
                SizedBox(
                  width: 240,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      settingsAction,
                      const SizedBox(height: AppSpacing.sm),
                      runAction,
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              info,
              const SizedBox(height: AppSpacing.xl),
              settingsAction,
              const SizedBox(height: AppSpacing.sm),
              runAction,
            ],
          );
        },
      ),
    );
  }

  Future<void> _openAutomationSettings(BuildContext context) async {
    final settings = controller.settings;
    final result = await showDialog<_AutomationSettingsValue>(
      context: context,
      builder: (context) => _AutomationSettingsDialog(settings: settings),
    );
    if (result == null || !context.mounted) return;
    await controller.saveSettings(
      enabled: result.enabled,
      maxArticlesPerRun: result.maxArticlesPerRun,
      maxDraftsPerDay: result.maxDraftsPerDay,
      monthlyDraftCap: result.monthlyDraftCap,
      maxPendingDrafts: result.maxPendingDrafts,
      maxPendingQuestions: result.maxPendingQuestions,
      draftArchiveDays: result.draftArchiveDays,
    );
  }
}

class _AutomationSettingsValue {
  final bool enabled;
  final int maxArticlesPerRun;
  final int maxDraftsPerDay;
  final int monthlyDraftCap;
  final int maxPendingDrafts;
  final int maxPendingQuestions;
  final int draftArchiveDays;

  const _AutomationSettingsValue({
    required this.enabled,
    required this.maxArticlesPerRun,
    required this.maxDraftsPerDay,
    required this.monthlyDraftCap,
    required this.maxPendingDrafts,
    required this.maxPendingQuestions,
    required this.draftArchiveDays,
  });
}

class _AutomationSettingsDialog extends StatefulWidget {
  final AutomationSettings settings;

  const _AutomationSettingsDialog({required this.settings});

  @override
  State<_AutomationSettingsDialog> createState() =>
      _AutomationSettingsDialogState();
}

class _AutomationSettingsDialogState
    extends State<_AutomationSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late bool _enabled;
  late final TextEditingController _articles;
  late final TextEditingController _dailyDrafts;
  late final TextEditingController _monthlyDrafts;
  late final TextEditingController _pendingDrafts;
  late final TextEditingController _pendingQuestions;
  late final TextEditingController _archiveDays;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.enabled;
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
                    helperText: 'Automation pauses when this queue is full. Range: 5–200',
                  ),
                  validator: (value) => _validateInt(value, 5, 200),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _pendingQuestions,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum pending AI questions',
                    helperText: 'Prevents the review queue from growing without limit. Range: 20–1000',
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save settings'),
        ),
      ],
    );
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
    Navigator.pop(
      context,
      _AutomationSettingsValue(
        enabled: _enabled,
        maxArticlesPerRun: int.parse(_articles.text.trim()),
        maxDraftsPerDay: int.parse(_dailyDrafts.text.trim()),
        monthlyDraftCap: int.parse(_monthlyDrafts.text.trim()),
        maxPendingDrafts: int.parse(_pendingDrafts.text.trim()),
        maxPendingQuestions: int.parse(_pendingQuestions.text.trim()),
        draftArchiveDays: int.parse(_archiveDays.text.trim()),
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
          Text(item.topic.label,
              style: Theme.of(context).textTheme.titleMedium),
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
                    Text(draft.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${draft.topic.label} · ${LearningRankX.fromLevel(draft.targetLevel).label} · ${draft.sourceName}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Chip(label: Text(draft.status.toUpperCase())),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            draft.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: busy ? null : onReject,
                child: const Text('Reject'),
              ),
              const SizedBox(width: AppSpacing.sm),
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
                label: Text(
                  LearningRankX.fromLevel(question.difficulty).label,
                ),
              ),
              Chip(label: Text(question.questionType.replaceAll('_', ' '))),
              if (question.generatedBy != 'manual')
                const Chip(label: Text('AI draft')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            question.stem,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Answer key and explanation must be checked by a human before this question can enter the adaptive bank.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: busy ? null : onReject,
                child: const Text('Reject'),
              ),
              const SizedBox(width: AppSpacing.sm),
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
    _questionType = const [
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
    final options = _options.map((controller) => controller.text.trim()).toList();
    final normalized = options.map((value) => value.toLowerCase()).toSet();
    if (normalized.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All four answer options must be different.')),
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
    final filtered = widget.items.where((item) {
      if (_topic != null && item.topic != _topic) return false;
      if (_difficulty != null && item.difficulty != _difficulty) return false;
      if (query.isEmpty) return true;
      return item.stem.toLowerCase().contains(query) ||
          item.questionCode.toLowerCase().contains(query) ||
          item.topic.label.toLowerCase().contains(query) ||
          item.generatedBy.toLowerCase().contains(query);
    }).toList(growable: false);

    final visible = filtered.take(40).toList(growable: false);

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
              SizedBox(
                width: 320,
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
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<LearningTopic?>(
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
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<int?>(
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
                        child: Text(
                          QuestionDifficultyX.fromLevel(level).label,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _difficulty = value),
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
                onSelected: (value) =>
                    setState(() => _showAnswerKeys = value),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            filtered.length > visible.length
                ? 'Showing ${visible.length} of ${filtered.length} matching questions'
                : '${filtered.length} matching question${filtered.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text('No approved questions match these filters.'),
            )
          else
            ...visible.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ApprovedQuestionCard(
                  item: item,
                  showAnswerKey: _showAnswerKeys,
                ),
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
    final answer = item.correctIndex >= 0 &&
            item.correctIndex < item.options.length
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
      child: Text(
        label,
        style: theme.textTheme.labelSmall,
      ),
    );
  }
}

class _SourceCard extends StatefulWidget {
  final ContentSource source;
  final Future<bool> Function(bool enabled) onChanged;

  const _SourceCard({
    super.key,
    required this.source,
    required this.onChanged,
  });

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
                Text(
                  widget.source.name,
                  style: theme.textTheme.titleMedium,
                ),
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
                : const SizedBox(
                    key: ValueKey('idle'),
                    width: 18,
                    height: 18,
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch(
            value: _enabled,
            onChanged: _saving ? null : _toggle,
          ),
        ],
      ),
    );
  }
}

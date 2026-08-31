import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/content_controller.dart';
import '../../../data/models/content_item.dart';
import '../../../data/models/learning_topic.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_intro.dart';
import '../../widgets/state_message.dart';

class AdminContentManagementScreen extends StatefulWidget {
  const AdminContentManagementScreen({super.key});

  @override
  State<AdminContentManagementScreen> createState() =>
      _AdminContentManagementScreenState();
}

class _AdminContentManagementScreenState
    extends State<AdminContentManagementScreen> {
  final _searchController = TextEditingController();

  String _query = '';
  ContentType? _typeFilter;
  ContentStatus? _statusFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentController>();

    final items = content.items
        .where((item) {
          final query = _query.trim().toLowerCase();

          final matchesQuery =
              query.isEmpty ||
              item.displayTitle.toLowerCase().contains(query) ||
              item.description.toLowerCase().contains(query) ||
              item.id.toLowerCase().contains(query);

          final matchesType = _typeFilter == null || item.type == _typeFilter;

          final matchesStatus =
              _statusFilter == null || item.status == _statusFilter;

          return matchesQuery && matchesType && matchesStatus;
        })
        .toList(growable: false);

    return AdaptiveBody(
      useSafeArea: false,
      maxWidth: 1440,
      child: RefreshIndicator(
        onRefresh: content.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: AdaptiveLayout.pageInsets(context),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const PageIntro(
                    title: 'Content management',
                    description:
                        'Create, edit, publish, archive, and review version history for learner content.',
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  if (content.errorMessage != null) ...[
                    _ContentErrorBanner(
                      message: content.errorMessage!,
                      onRetry: content.refresh,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  _ContentSummary(items: content.items),

                  const SizedBox(height: AppSpacing.xl),

                  _ContentToolbar(
                    searchController: _searchController,
                    query: _query,
                    typeFilter: _typeFilter,
                    statusFilter: _statusFilter,
                    onQueryChanged: (value) {
                      setState(() => _query = value);
                    },
                    onClearSearch: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    onTypeChanged: (value) {
                      setState(() => _typeFilter = value);
                    },
                    onStatusChanged: (value) {
                      setState(() => _statusFilter = value);
                    },
                    onCreate: content.isMutating ? null : () => _openEditor(),
                    onRefresh: content.isLoading ? null : content.refresh,
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  if (content.isLoading && content.items.isEmpty)
                    const AppCard(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (items.isEmpty)
                    StateMessage.empty(
                      title: 'No matching content',
                      message:
                          _query.isEmpty &&
                              _typeFilter == null &&
                              _statusFilter == null
                          ? 'Create the first content item for PromptWise.'
                          : 'Change the search or filters to see other content.',
                      actionLabel: 'Create content',
                      onAction: content.isMutating ? null : () => _openEditor(),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth >= 900) {
                          return _ContentDataTable(
                            items: items,
                            disabled: content.isMutating,
                            onEdit: _openEditor,
                            onPublish: (item) =>
                                _setStatus(item, ContentStatus.published),
                            onArchive: (item) =>
                                _setStatus(item, ContentStatus.archived),
                            onDraft: (item) =>
                                _setStatus(item, ContentStatus.draft),
                            onVersions: _showVersions,
                            onDelete: _deleteItem,
                          );
                        }

                        return Column(
                          children: [
                            for (
                              var index = 0;
                              index < items.length;
                              index++
                            ) ...[
                              _ContentCard(
                                item: items[index],
                                disabled: content.isMutating,
                                onEdit: () => _openEditor(items[index]),
                                onPublish: () => _setStatus(
                                  items[index],
                                  ContentStatus.published,
                                ),
                                onArchive: () => _setStatus(
                                  items[index],
                                  ContentStatus.archived,
                                ),
                                onDraft: () => _setStatus(
                                  items[index],
                                  ContentStatus.draft,
                                ),
                                onVersions: () => _showVersions(items[index]),
                                onDelete: () => _deleteItem(items[index]),
                              ),
                              if (index != items.length - 1)
                                const SizedBox(height: AppSpacing.md),
                            ],
                          ],
                        );
                      },
                    ),

                  const SizedBox(height: AppSpacing.xxl),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor([ContentItem? existing]) async {
    final controller = context.read<ContentController>();

    final result = await showDialog<ContentItem>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ContentEditorDialog(
        existing: existing,
        availableItems: controller.items,
      ),
    );

    if (!mounted || result == null) return;

    final success = existing == null
        ? await controller.createItem(result)
        : await controller.updateItem(result);

    if (!mounted) return;

    _showResult(
      success,
      success
          ? existing == null
                ? 'Content created.'
                : 'Content updated and a previous version was saved.'
          : controller.errorMessage ?? 'Unable to save content.',
    );
  }

  Future<void> _setStatus(ContentItem item, ContentStatus status) async {
    if (item.status == status) return;

    final controller = context.read<ContentController>();
    final success = await controller.setStatus(item, status);

    if (!mounted) return;

    _showResult(
      success,
      success
          ? '“${item.displayTitle}” is now ${status.label.toLowerCase()}.'
          : controller.errorMessage ?? 'Unable to update status.',
    );
  }

  Future<void> _deleteItem(ContentItem item) async {
    final dependencies = context
        .read<ContentController>()
        .items
        .where(
          (candidate) =>
              candidate.id != item.id &&
              (candidate.parentId == item.id || candidate.quizId == item.id),
        )
        .toList(growable: false);

    if (dependencies.isNotEmpty) {
      _showResult(
        false,
        'This content is still linked to ${dependencies.length} other item${dependencies.length == 1 ? '' : 's'}. Update those links before deleting it.',
      );
      return;
    }

    if (item.status != ContentStatus.draft) {
      _showResult(
        false,
        'Only draft content can be permanently deleted. Archive published content instead.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete draft permanently?'),
        content: Text(
          '“${item.displayTitle}” will be removed. Its last snapshot remains in version history for audit purposes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete draft'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final controller = context.read<ContentController>();
    final success = await controller.deleteItem(item);

    if (!mounted) return;

    _showResult(
      success,
      success
          ? 'Draft deleted.'
          : controller.errorMessage ?? 'Unable to delete draft.',
    );
  }

  Future<void> _showVersions(ContentItem item) async {
    final controller = context.read<ContentController>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _VersionHistoryDialog(
        item: item,
        versionsFuture: controller.loadVersions(item.id),
      ),
    );
  }

  void _showResult(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }
}

class _ContentSummary extends StatelessWidget {
  final List<ContentItem> items;

  const _ContentSummary({required this.items});

  @override
  Widget build(BuildContext context) {
    final published = items
        .where((item) => item.status == ContentStatus.published)
        .length;

    final draft = items
        .where((item) => item.status == ContentStatus.draft)
        .length;

    final archived = items
        .where((item) => item.status == ContentStatus.archived)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _SummaryMetric(
            label: 'All content',
            value: '${items.length}',
            icon: Icons.library_books_outlined,
          ),
          _SummaryMetric(
            label: 'Published',
            value: '$published',
            icon: Icons.public_rounded,
          ),
          _SummaryMetric(
            label: 'Drafts',
            value: '$draft',
            icon: Icons.edit_note_rounded,
          ),
          _SummaryMetric(
            label: 'Archived',
            value: '$archived',
            icon: Icons.archive_outlined,
          ),
        ];

        final columns = constraints.maxWidth >= 920
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: columns == 1 ? constraints.maxWidth / 104 : 2.5,
          children: cards,
        );
      },
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.primary,
            child: Icon(icon),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _ContentToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final String query;
  final ContentType? typeFilter;
  final ContentStatus? statusFilter;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<ContentType?> onTypeChanged;
  final ValueChanged<ContentStatus?> onStatusChanged;
  final VoidCallback? onCreate;
  final VoidCallback? onRefresh;

  const _ContentToolbar({
    required this.searchController,
    required this.query,
    required this.typeFilter,
    required this.statusFilter,
    required this.onQueryChanged,
    required this.onClearSearch,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onCreate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              labelText: 'Search content',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: onClearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          );

          final type = DropdownButtonFormField<ContentType?>(
            isExpanded: true,
            initialValue: typeFilter,
            decoration: const InputDecoration(labelText: 'Content type'),
            items: [
              const DropdownMenuItem<ContentType?>(
                value: null,
                child: Text('All types'),
              ),
              ...ContentType.values.map(
                (value) => DropdownMenuItem<ContentType?>(
                  value: value,
                  child: Text(value.label),
                ),
              ),
            ],
            onChanged: onTypeChanged,
          );

          final status = DropdownButtonFormField<ContentStatus?>(
            isExpanded: true,
            initialValue: statusFilter,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              const DropdownMenuItem<ContentStatus?>(
                value: null,
                child: Text('All statuses'),
              ),
              ...ContentStatus.values.map(
                (value) => DropdownMenuItem<ContentStatus?>(
                  value: value,
                  child: Text(value.label),
                ),
              ),
            ],
            onChanged: onStatusChanged,
          );

          final actions = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              IconButton.outlined(
                tooltip: 'Refresh content',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create content'),
              ),
            ],
          );

          if (constraints.maxWidth >= 960) {
            return Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: type),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: status),
                const SizedBox(width: AppSpacing.md),
                actions,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: AppSpacing.md),

              if (constraints.maxWidth >= 560)
                Row(
                  children: [
                    Expanded(child: type),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: status),
                  ],
                )
              else ...[
                type,
                const SizedBox(height: AppSpacing.md),
                status,
              ],

              const SizedBox(height: AppSpacing.md),

              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _ContentDataTable extends StatelessWidget {
  final List<ContentItem> items;
  final bool disabled;
  final ValueChanged<ContentItem> onEdit;
  final ValueChanged<ContentItem> onPublish;
  final ValueChanged<ContentItem> onArchive;
  final ValueChanged<ContentItem> onDraft;
  final ValueChanged<ContentItem> onVersions;
  final ValueChanged<ContentItem> onDelete;

  const _ContentDataTable({
    required this.items,
    required this.disabled,
    required this.onEdit,
    required this.onPublish,
    required this.onArchive,
    required this.onDraft,
    required this.onVersions,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Title')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Adaptive topic')),
            DataColumn(label: Text('Version')),
            DataColumn(label: Text('Published')),
            DataColumn(label: Text('Review')),
            DataColumn(label: Text('Actions')),
          ],
          rows: items
              .map(
                (item) => DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 260,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              item.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(Text(item.type.label)),
                    DataCell(_ContentStatusChip(status: item.status)),
                    DataCell(Text(item.adaptiveTopic?.label ?? 'Automatic')),
                    DataCell(Text('v${item.version}')),
                    DataCell(Text(_shortDate(item.publicationDate))),
                    DataCell(Text(_shortDate(item.reviewDate))),
                    DataCell(
                      _ContentActions(
                        item: item,
                        disabled: disabled,
                        onEdit: () => onEdit(item),
                        onPublish: () => onPublish(item),
                        onArchive: () => onArchive(item),
                        onDraft: () => onDraft(item),
                        onVersions: () => onVersions(item),
                        onDelete: () => onDelete(item),
                      ),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  final ContentItem item;
  final bool disabled;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onArchive;
  final VoidCallback onDraft;
  final VoidCallback onVersions;
  final VoidCallback onDelete;

  const _ContentCard({
    required this.item,
    required this.disabled,
    required this.onEdit,
    required this.onPublish,
    required this.onArchive,
    required this.onDraft,
    required this.onVersions,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(_contentIcon(item.type)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${item.type.label} · ${item.adaptiveTopic?.label ?? 'Automatic topic'} · ${item.id}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _ContentActions(
                item: item,
                disabled: disabled,
                onEdit: onEdit,
                onPublish: onPublish,
                onArchive: onArchive,
                onDraft: onDraft,
                onVersions: onVersions,
                onDelete: onDelete,
              ),
            ],
          ),

          if (item.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              item.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ContentStatusChip(status: item.status),
              Chip(label: Text('Version ${item.version}')),
              Chip(
                label: Text('Published ${_shortDate(item.publicationDate)}'),
              ),
              Chip(label: Text('Review ${_shortDate(item.reviewDate)}')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContentActions extends StatelessWidget {
  final ContentItem item;
  final bool disabled;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onArchive;
  final VoidCallback onDraft;
  final VoidCallback onVersions;
  final VoidCallback onDelete;

  const _ContentActions({
    required this.item,
    required this.disabled,
    required this.onEdit,
    required this.onPublish,
    required this.onArchive,
    required this.onDraft,
    required this.onVersions,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: !disabled,
      tooltip: 'Content actions',
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
            break;
          case 'publish':
            onPublish();
            break;
          case 'archive':
            onArchive();
            break;
          case 'draft':
            onDraft();
            break;
          case 'versions':
            onVersions();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit'),
          ),
        ),

        if (item.status != ContentStatus.published)
          const PopupMenuItem(
            value: 'publish',
            child: ListTile(
              leading: Icon(Icons.public_rounded),
              title: Text('Publish'),
            ),
          ),

        if (item.status != ContentStatus.draft)
          const PopupMenuItem(
            value: 'draft',
            child: ListTile(
              leading: Icon(Icons.edit_note_rounded),
              title: Text('Move to draft'),
            ),
          ),

        if (item.status != ContentStatus.archived)
          const PopupMenuItem(
            value: 'archive',
            child: ListTile(
              leading: Icon(Icons.archive_outlined),
              title: Text('Archive'),
            ),
          ),

        const PopupMenuItem(
          value: 'versions',
          child: ListTile(
            leading: Icon(Icons.history_rounded),
            title: Text('Version history'),
          ),
        ),

        if (item.status == ContentStatus.draft)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline_rounded),
              title: Text('Delete draft'),
            ),
          ),
      ],
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

class _ContentEditorDialog extends StatefulWidget {
  final ContentItem? existing;
  final List<ContentItem> availableItems;

  const _ContentEditorDialog({
    required this.existing,
    required this.availableItems,
  });

  @override
  State<_ContentEditorDialog> createState() => _ContentEditorDialogState();
}

class _ContentEditorDialogState extends State<_ContentEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  late ContentType _type;
  late ContentStatus _status;

  late final TextEditingController _id;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _body;
  late final TextEditingController _icon;
  late final TextEditingController _estimatedMinutes;
  late final TextEditingController _question;
  late final TextEditingController _options;
  late final TextEditingController _correctOption;
  late final TextEditingController _explanation;
  late final TextEditingController _imageA;
  late final TextEditingController _imageB;
  late final TextEditingController _sortOrder;
  late final TextEditingController _sourceUrl;

  String? _parentId;
  String? _quizId;

  LearningTopic? _adaptiveTopic;

  int _learningLevel = 1;
  bool _isAAI = false;

  DateTime? _publicationDate;
  DateTime? _reviewDate;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final item = widget.existing;

    _type = item?.type ?? ContentType.module;
    _status = item?.status ?? ContentStatus.draft;

    _id = TextEditingController(text: item?.id ?? '');

    _title = TextEditingController(text: item?.title ?? '');

    _description = TextEditingController(text: item?.description ?? '');

    _body = TextEditingController(text: item?.body ?? '');

    _icon = TextEditingController(text: item?.icon ?? 'ai');

    _estimatedMinutes = TextEditingController(
      text: '${item?.estimatedMinutes ?? 5}',
    );

    _question = TextEditingController(text: item?.question ?? '');

    _options = TextEditingController(text: item?.options.join('\n') ?? '');

    _correctOption = TextEditingController(
      text: item?.correctIndex == null ? '1' : '${item!.correctIndex! + 1}',
    );

    _explanation = TextEditingController(text: item?.explanation ?? '');

    _imageA = TextEditingController(text: item?.imagePathA ?? '');

    _imageB = TextEditingController(text: item?.imagePathB ?? '');

    _sortOrder = TextEditingController(text: '${item?.sortOrder ?? 0}');

    _sourceUrl = TextEditingController(text: item?.sourceUrl ?? '');

    _parentId = item?.parentId;
    _quizId = item?.quizId;

    _adaptiveTopic = item?.type == ContentType.activity
        ? LearningTopic.verification
        : item?.adaptiveTopic;

    _learningLevel = (item?.learningLevel ?? 1).clamp(1, 5);

    _isAAI = item?.isAAI ?? false;

    _publicationDate = item?.publicationDate;
    _reviewDate = item?.reviewDate;
  }

  @override
  void dispose() {
    for (final controller in [
      _id,
      _title,
      _description,
      _body,
      _icon,
      _estimatedMinutes,
      _question,
      _options,
      _correctOption,
      _explanation,
      _imageA,
      _imageB,
      _sortOrder,
      _sourceUrl,
    ]) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modules = widget.availableItems
        .where((item) => item.type == ContentType.module)
        .toList(growable: false);

    final quizzes = widget.availableItems
        .where((item) => item.type == ContentType.quiz)
        .toList(growable: false);

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
                    child: Text(
                      _isEditing ? 'Edit content' : 'Create content',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final type = DropdownButtonFormField<ContentType>(
                            isExpanded: true,
                            initialValue: _type,
                            decoration: const InputDecoration(
                              labelText: 'Content type',
                            ),
                            items: ContentType.values
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value.label),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: _isEditing
                                ? null
                                : (value) {
                                    if (value == null) {
                                      return;
                                    }

                                    final previousType = _type;

                                    setState(() {
                                      _type = value;
                                      _parentId = null;
                                      _quizId = null;

                                      if (value == ContentType.activity) {
                                        _adaptiveTopic =
                                            LearningTopic.verification;
                                      } else if (previousType ==
                                          ContentType.activity) {
                                        _adaptiveTopic = null;
                                      }
                                    });
                                  },
                          );

                          final status = DropdownButtonFormField<ContentStatus>(
                            isExpanded: true,
                            initialValue: _status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                            ),
                            items: ContentStatus.values
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value.label),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _status = value);
                              }
                            },
                          );

                          if (constraints.maxWidth >= 540) {
                            return Row(
                              children: [
                                Expanded(child: type),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(child: status),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              type,
                              const SizedBox(height: AppSpacing.md),
                              status,
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: AppSpacing.md),

                      TextFormField(
                        controller: _id,
                        readOnly: _isEditing,
                        decoration: InputDecoration(
                          labelText: _isEditing
                              ? 'Content ID'
                              : 'Content ID (optional)',
                          helperText: _isEditing
                              ? 'IDs remain stable after creation.'
                              : 'Leave blank to generate an ID automatically.',
                        ),
                        validator: (value) {
                          final id = value?.trim() ?? '';

                          if (id.isEmpty && !_isEditing) {
                            return null;
                          }

                          return RegExp(r'^[a-z0-9_\-]+$').hasMatch(id)
                              ? null
                              : 'Use lowercase letters, numbers, hyphens, or underscores.';
                        },
                      ),

                      const SizedBox(height: AppSpacing.md),

                      TextFormField(
                        controller: _title,
                        decoration: const InputDecoration(labelText: 'Title'),
                        validator: _required('Enter a title.'),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      DropdownButtonFormField<LearningTopic?>(
                        isExpanded: true,
                        initialValue: _adaptiveTopic,
                        decoration: InputDecoration(
                          labelText: 'Adaptive learning topic',
                          helperText: _type == ContentType.activity
                              ? 'Verification activities always contribute to Verification mastery.'
                              : _type == ContentType.quiz
                              ? 'Required for stable mastery tracking and recommendations.'
                              : 'Used for mastery tracking and personalized recommendations. Automatic inference is allowed for modules and lessons.',
                        ),
                        items: [
                          if (_type != ContentType.quiz &&
                              _type != ContentType.activity)
                            const DropdownMenuItem<LearningTopic?>(
                              value: null,
                              child: Text('Automatic'),
                            ),

                          ...LearningTopic.values.map(
                            (topic) => DropdownMenuItem<LearningTopic?>(
                              value: topic,
                              child: Text(topic.label),
                            ),
                          ),
                        ],
                        validator: (_) {
                          if ((_type == ContentType.quiz ||
                                  _type == ContentType.activity) &&
                              _adaptiveTopic == null) {
                            return 'Choose an adaptive learning topic.';
                          }

                          return null;
                        },
                        onChanged: _type == ContentType.activity
                            ? null
                            : (value) {
                                setState(() => _adaptiveTopic = value);
                              },
                      ),

                      const SizedBox(height: AppSpacing.md),

                      if (_type == ContentType.module ||
                          _type == ContentType.lesson ||
                          _type == ContentType.quiz) ...[
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: _learningLevel,
                          decoration: const InputDecoration(
                            labelText: 'Learning challenge level',
                            helperText:
                                'Controls progression: 1 Foundation, 2 Developing, 3 Proficient, 4 Advanced, 5 Expert.',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 1,
                              child: Text('Foundation'),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text('Developing'),
                            ),
                            DropdownMenuItem(
                              value: 3,
                              child: Text('Proficient'),
                            ),
                            DropdownMenuItem(value: 4, child: Text('Advanced')),
                            DropdownMenuItem(value: 5, child: Text('Expert')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _learningLevel = value);
                            }
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      ..._typeSpecificFields(modules, quizzes),

                      const SizedBox(height: AppSpacing.lg),

                      Text(
                        'Publishing information',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),

                      const SizedBox(height: AppSpacing.md),

                      TextFormField(
                        controller: _sourceUrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Source URL',
                          helperText:
                              'Add the original or supporting reference when applicable.',
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';

                          if (text.isEmpty) {
                            return null;
                          }

                          final uri = Uri.tryParse(text);

                          return uri != null &&
                                  (uri.scheme == 'https' ||
                                      uri.scheme == 'http')
                              ? null
                              : 'Enter a complete web link.';
                        },
                      ),

                      const SizedBox(height: AppSpacing.md),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final publication = _DateField(
                            label: 'Publication date',
                            value: _publicationDate,
                            onChanged: (value) {
                              setState(() => _publicationDate = value);
                            },
                          );

                          final review = _DateField(
                            label: 'Review date',
                            value: _reviewDate,
                            onChanged: (value) {
                              setState(() => _reviewDate = value);
                            },
                          );

                          if (constraints.maxWidth >= 540) {
                            return Row(
                              children: [
                                Expanded(child: publication),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(child: review),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              publication,
                              const SizedBox(height: AppSpacing.md),
                              review,
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: AppSpacing.md),

                      TextFormField(
                        controller: _sortOrder,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Sort order',
                          helperText:
                              'Lower numbers appear first within the same content type.',
                        ),
                        validator: (value) => int.tryParse(value ?? '') == null
                            ? 'Enter a whole number.'
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
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_isEditing ? 'Save changes' : 'Create'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _typeSpecificFields(
    List<ContentItem> modules,
    List<ContentItem> quizzes,
  ) {
    switch (_type) {
      case ContentType.module:
        return [
          TextFormField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Module description'),
            validator: _required('Enter a module description.'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _icon,
            decoration: const InputDecoration(
              labelText: 'Icon key',
              helperText: 'Examples: ai, prompt, ethics, privacy, verify',
            ),
          ),
        ];

      case ContentType.lesson:
        return [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: modules.any((item) => item.id == _parentId)
                ? _parentId
                : null,
            decoration: const InputDecoration(labelText: 'Parent module'),
            items: modules
                .map(
                  (item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              setState(() => _parentId = value);
            },
            validator: (value) => value == null || value.isEmpty
                ? 'Select the module that contains this lesson.'
                : null,
          ),

          const SizedBox(height: AppSpacing.md),

          TextFormField(
            controller: _body,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(labelText: 'Lesson content'),
            validator: _required('Enter the lesson content.'),
          ),

          const SizedBox(height: AppSpacing.md),

          LayoutBuilder(
            builder: (context, constraints) {
              final minutes = TextFormField(
                controller: _estimatedMinutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Estimated minutes',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');

                  return parsed == null || parsed < 1
                      ? 'Enter at least 1 minute.'
                      : null;
                },
              );

              final quiz = DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: quizzes.any((item) => item.id == _quizId)
                    ? _quizId
                    : null,
                decoration: const InputDecoration(labelText: 'Linked quiz'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No linked quiz'),
                  ),
                  ...quizzes.map(
                    (item) => DropdownMenuItem<String?>(
                      value: item.id,
                      child: Text(
                        item.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _quizId = value);
                },
              );

              if (constraints.maxWidth >= 540) {
                return Row(
                  children: [
                    Expanded(child: minutes),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: quiz),
                  ],
                );
              }

              return Column(
                children: [
                  minutes,
                  const SizedBox(height: AppSpacing.md),
                  quiz,
                ],
              );
            },
          ),
        ];

      case ContentType.quiz:
        return [
          TextFormField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Quiz description'),
          ),

          const SizedBox(height: AppSpacing.md),

          TextFormField(
            controller: _question,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Question'),
            validator: _required('Enter the quiz question.'),
          ),

          const SizedBox(height: AppSpacing.md),

          TextFormField(
            controller: _options,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Answer options',
              helperText: 'Enter one option per line.',
            ),
            validator: (value) {
              final options = _splitOptions(value ?? '');

              return options.length < 2
                  ? 'Enter at least two answer options.'
                  : null;
            },
          ),

          const SizedBox(height: AppSpacing.md),

          TextFormField(
            controller: _correctOption,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Correct option number',
              helperText:
                  'Use 1 for the first option, 2 for the second, and so on.',
            ),
            validator: (value) {
              final optionNumber = int.tryParse(value ?? '');

              final options = _splitOptions(_options.text);

              return optionNumber == null ||
                      optionNumber < 1 ||
                      optionNumber > options.length
                  ? 'Enter a number from 1 to ${options.isEmpty ? 1 : options.length}.'
                  : null;
            },
          ),

          const SizedBox(height: AppSpacing.md),

          TextFormField(
            controller: _explanation,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Answer explanation'),
            validator: _required('Explain why the answer is correct.'),
          ),
        ];

      case ContentType.activity:
        return [
          TextFormField(
            controller: _imageA,
            decoration: const InputDecoration(
              labelText: 'Image A path or URL',
              helperText: 'Use an app image path or a complete image link.',
            ),
            validator: _required('Enter the first image asset path.'),
          ),

          const SizedBox(height: AppSpacing.md),

          TextFormField(
            controller: _imageB,
            decoration: const InputDecoration(labelText: 'Image B path or URL'),
            validator: _required('Enter the second image asset path.'),
          ),

          const SizedBox(height: AppSpacing.md),

          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Image A is the AI-generated answer'),
            subtitle: Text(
              _isAAI
                  ? 'Learners should select Image A.'
                  : 'Learners should select Image B.',
            ),
            value: _isAAI,
            onChanged: (value) {
              setState(() => _isAAI = value);
            },
          ),

          const SizedBox(height: AppSpacing.md),

          TextFormField(
            controller: _explanation,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Evidence and uncertainty explanation',
            ),
            validator: _required('Enter the activity explanation.'),
          ),
        ];

      case ContentType.awareness:
        return [
          TextFormField(
            controller: _description,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Awareness summary and guidance',
            ),
            validator: _required('Enter the awareness guidance.'),
          ),
        ];
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_publicationDate != null &&
        _reviewDate != null &&
        _reviewDate!.isBefore(_publicationDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review date cannot be earlier than publication date.'),
        ),
      );
      return;
    }

    final title = _title.text.trim();

    final id = _id.text.trim().isEmpty
        ? _generateId(_type, title)
        : _id.text.trim();

    final options = _splitOptions(_options.text);

    final correctNumber = int.tryParse(_correctOption.text.trim());

    final existing = widget.existing;

    Navigator.pop(
      context,
      ContentItem(
        id: id,
        type: _type,
        parentId: _type == ContentType.lesson ? _parentId : null,
        title: title,
        description: _description.text.trim(),
        body: _type == ContentType.lesson ? _body.text.trim() : '',
        icon: _type == ContentType.module ? _icon.text.trim() : '',
        estimatedMinutes: _type == ContentType.lesson
            ? int.parse(_estimatedMinutes.text.trim())
            : 0,
        quizId: _type == ContentType.lesson ? _quizId : null,
        question: _type == ContentType.quiz ? _question.text.trim() : '',
        options: _type == ContentType.quiz ? options : const [],
        correctIndex: _type == ContentType.quiz
            ? (correctNumber ?? 1) - 1
            : null,
        explanation: _type == ContentType.quiz || _type == ContentType.activity
            ? _explanation.text.trim()
            : '',
        imagePathA: _type == ContentType.activity ? _imageA.text.trim() : '',
        imagePathB: _type == ContentType.activity ? _imageB.text.trim() : '',
        isAAI: _type == ContentType.activity ? _isAAI : null,
        sortOrder: int.parse(_sortOrder.text.trim()),
        learningLevel: _learningLevel,
        adaptiveTopic: _adaptiveTopic,
        status: _status,
        version: existing?.version ?? 1,
        sourceUrl: _sourceUrl.text.trim().isEmpty
            ? null
            : _sourceUrl.text.trim(),
        publicationDate:
            _status == ContentStatus.published && _publicationDate == null
            ? DateTime.now()
            : _publicationDate,
        reviewDate: _reviewDate,
        createdAt: existing?.createdAt,
        updatedAt: existing?.updatedAt,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(child: Text(_shortDate(value))),

          if (value != null)
            IconButton(
              tooltip: 'Clear $label',
              onPressed: () {
                onChanged(null);
              },
              icon: const Icon(Icons.close_rounded),
            ),

          IconButton(
            tooltip: 'Select $label',
            onPressed: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );

              if (selected != null) {
                onChanged(selected);
              }
            },
            icon: const Icon(Icons.calendar_today_outlined),
          ),
        ],
      ),
    );
  }
}

class _VersionHistoryDialog extends StatelessWidget {
  final ContentItem item;
  final Future<List<ContentVersion>> versionsFuture;

  const _VersionHistoryDialog({
    required this.item,
    required this.versionsFuture,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Version history · ${item.displayTitle}'),
      content: SizedBox(
        width: 620,
        child: FutureBuilder<List<ContentVersion>>(
          future: versionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return StateMessage.error(
                title: 'Unable to load versions',
                message: snapshot.error.toString(),
              );
            }

            final versions = snapshot.data ?? const <ContentVersion>[];

            if (versions.isEmpty) {
              return const StateMessage.empty(
                title: 'No previous versions',
                message:
                    'A snapshot is created when this content is updated or deleted.',
              );
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: versions.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final version = versions[index];

                  return ListTile(
                    leading: CircleAvatar(child: Text('v${version.version}')),
                    title: Text(version.snapshot.displayTitle),
                    subtitle: Text(
                      '${version.operation} · ${version.snapshot.status.label} · ${_shortDateTime(version.changedAt)}',
                    ),
                    trailing: _ContentStatusChip(
                      status: version.snapshot.status,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ContentStatusChip extends StatelessWidget {
  final ContentStatus status;

  const _ContentStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ContentStatus.published => AppColors.success,
      ContentStatus.draft => AppColors.warning,
      ContentStatus.archived => Theme.of(context).colorScheme.onSurfaceVariant,
    };

    return Chip(
      label: Text(status.label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}

class _ContentErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ContentErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),

          const SizedBox(width: AppSpacing.md),

          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

FormFieldValidator<String> _required(String message) {
  return (value) => value == null || value.trim().isEmpty ? message : null;
}

List<String> _splitOptions(String value) {
  return value
      .split('\n')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _generateId(ContentType type, String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  final suffix = DateTime.now().millisecondsSinceEpoch.toString();

  final shortSuffix = suffix.substring(suffix.length - 6);

  return '${type.name}_${slug.isEmpty ? 'content' : slug}_$shortSuffix';
}

String _shortDate(DateTime? date) {
  if (date == null) {
    return 'Not set';
  }

  final month = date.month.toString().padLeft(2, '0');

  final day = date.day.toString().padLeft(2, '0');

  return '${date.year}-$month-$day';
}

String _shortDateTime(DateTime? date) {
  if (date == null) {
    return 'Date unavailable';
  }

  final local = date.toLocal();

  final hour = local.hour.toString().padLeft(2, '0');

  final minute = local.minute.toString().padLeft(2, '0');

  return '${_shortDate(local)} $hour:$minute';
}

IconData _contentIcon(ContentType type) => switch (type) {
  ContentType.module => Icons.menu_book_outlined,
  ContentType.lesson => Icons.article_outlined,
  ContentType.quiz => Icons.quiz_outlined,
  ContentType.activity => Icons.image_search_outlined,
  ContentType.awareness => Icons.campaign_outlined,
};

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/models/app_profile.dart';
import '../../../data/models/content_item.dart';
import '../../../data/models/learning_topic.dart';
import '../../controllers/content_controller.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/admin_record_browser.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_intro.dart';
import 'admin_content_insights.dart';

class AdminOverviewPage extends StatelessWidget {
  final ValueChanged<AdminContentFilter> onOpenContent;
  final ValueChanged<int> onOpenStudio;
  const AdminOverviewPage({
    super.key,
    required this.onOpenContent,
    required this.onOpenStudio,
  });

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentController>();
    final items = content.items;
    final now = DateTime.now();
    final published = items
        .where((i) => i.status == ContentStatus.published)
        .length;
    final drafts = items.where((i) => i.status == ContentStatus.draft).length;
    final due = items.where((i) => contentReviewDue(i, now)).toList()
      ..sort((a, b) => a.reviewDate!.compareTo(b.reviewDate!));
    final recent = [...items]
      ..sort(
        (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(1970)).compareTo(
          a.updatedAt ?? a.createdAt ?? DateTime(1970),
        ),
      );
    return _WorkspacePage(
      title: 'Overview',
      description:
          'Your content workspace. Spot gaps, review priorities, and pick up where you left off.',
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => onOpenContent(const AdminContentFilter()),
              icon: const Icon(Icons.library_books_outlined),
              label: const Text('Manage content'),
            ),
            OutlinedButton.icon(
              onPressed: content.isLoading ? null : content.refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh overview'),
            ),
          ],
        ),
        if (content.isLoading) const LinearProgressIndicator(),
        if (content.errorMessage != null)
          AppCard(child: Text(content.errorMessage!)),
        _WorkspaceGrid(
          children: [
            AdminMetricCard(
              label: 'Published content',
              value: '$published',
              note: 'Open learner-visible content',
              icon: Icons.public,
              onTap: () => onOpenContent(
                const AdminContentFilter(status: ContentStatus.published),
              ),
            ),
            AdminMetricCard(
              label: 'Draft content',
              value: '$drafts',
              note: 'Continue preparing content',
              icon: Icons.edit_note,
              onTap: () => onOpenContent(
                const AdminContentFilter(status: ContentStatus.draft),
              ),
            ),
            AdminMetricCard(
              label: 'Review due',
              value: '${due.length}',
              note: 'Scheduled for today or earlier',
              icon: Icons.event_available,
              onTap: () => onOpenContent(
                const AdminContentFilter(attention: ContentAttention.reviewDue),
              ),
            ),
            AdminMetricCard(
              label: 'Practice activities',
              value:
                  '${items.where((i) => i.type == ContentType.quiz || i.type == ContentType.activity).length}',
              note: 'Open quizzes and verification activities',
              icon: Icons.quiz_outlined,
              onTap: () => onOpenContent(
                const AdminContentFilter(attention: ContentAttention.practice),
              ),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final coverage = AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Learning coverage',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Published lessons by explicit topic. Tap a topic to inspect it.',
                  ),
                  const SizedBox(height: 16),
                  for (final topic in LearningTopic.values)
                    Builder(
                      builder: (context) {
                        final count = items
                            .where(
                              (i) =>
                                  i.type == ContentType.lesson &&
                                  i.status == ContentStatus.published &&
                                  i.adaptiveTopic == topic,
                            )
                            .length;
                        final total = items
                            .where(
                              (i) =>
                                  i.type == ContentType.lesson &&
                                  i.status == ContentStatus.published,
                            )
                            .length;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(topic.label),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(
                              value: total == 0 ? 0 : count / total,
                              minHeight: 5,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          trailing: Text('$count'),
                          onTap: () => onOpenContent(
                            AdminContentFilter(
                              type: ContentType.lesson,
                              status: ContentStatus.published,
                              topic: topic,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            );
            final priorities = AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Review priorities',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Based on published content with a scheduled review date.',
                  ),
                  const SizedBox(height: 16),
                  if (due.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No scheduled reviews are overdue. Content without a review date is not counted.',
                      ),
                    ),
                  for (final item in due.take(4))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: Text(
                        item.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Review ${adminDate(context, item.reviewDate)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => onOpenContent(
                        AdminContentFilter(query: item.id, itemId: item.id),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: () => onOpenContent(
                      const AdminContentFilter(
                        attention: ContentAttention.reviewDue,
                      ),
                    ),
                    child: const Text('Open review queue'),
                  ),
                  const Divider(height: 32),
                  const Text('Create and review AI drafts'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => onOpenStudio(2),
                        icon: const Icon(Icons.school_outlined),
                        label: const Text('Learning Studio'),
                      ),
                      TextButton.icon(
                        onPressed: () => onOpenStudio(3),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Verification Studio'),
                      ),
                    ],
                  ),
                ],
              ),
            );
            return constraints.maxWidth >= 850
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: coverage),
                      const SizedBox(width: 16),
                      Expanded(child: priorities),
                    ],
                  )
                : Column(
                    children: [
                      coverage,
                      const SizedBox(height: 16),
                      priorities,
                    ],
                  );
          },
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recently updated',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Latest recorded content changes; open an item to edit or view its version history.',
              ),
              if (recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No content available yet.'),
                ),
              for (final item in recent.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Icon(
                      item.status == ContentStatus.draft
                          ? Icons.edit_outlined
                          : Icons.article_outlined,
                    ),
                  ),
                  title: Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item.type.label} · ${item.status.label} · v${item.version} · ${adminDate(context, item.updatedAt ?? item.createdAt)}',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () => onOpenContent(
                    AdminContentFilter(query: item.id, itemId: item.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class AdminUsersPage extends StatefulWidget {
  final Future<List<AppProfile>> Function(bool force) loadProfiles;
  const AdminUsersPage({super.key, required this.loadProfiles});
  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  late Future<List<AppProfile>> _future;
  final _search = TextEditingController();
  String _query = '';
  AppRole? _role;
  String _sort = 'newest';
  @override
  void initState() {
    super.initState();
    _future = widget.loadProfiles(false);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = widget.loadProfiles(true);
    });
  }

  void _details(AppProfile profile) {
    final feedback = ValueNotifier<String>('');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          profile.fullName.isEmpty ? 'Unnamed user' : profile.fullName,
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(label: Text(profile.role.label)),
                const SizedBox(height: 16),
                SelectableText(profile.email),
                TextButton.icon(
                  onPressed: () async {
                    final message = await _copy(profile.email, 'Email');
                    if (dialogContext.mounted) feedback.value = message;
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy email'),
                ),
                const Divider(),
                const Text('Account ID'),
                SelectableText(profile.id),
                TextButton.icon(
                  onPressed: () async {
                    final message = await _copy(profile.id, 'Account ID');
                    if (dialogContext.mounted) feedback.value = message;
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy account ID'),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: feedback,
                  builder: (_, message, _) =>
                      Text(message, semanticsLabel: message),
                ),
                Text('Created ${adminDate(context, profile.createdAt)}'),
                Text(
                  'Profile updated ${adminDate(context, profile.updatedAt)}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Dates refer to the profile record, not sign-in activity.',
                ),
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
    ).whenComplete(feedback.dispose);
  }

  Future<String> _copy(String text, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return '$label copied.';
    } catch (_) {
      return 'Copy unavailable. Select the text to copy it manually.';
    }
  }

  @override
  Widget build(BuildContext context) => _WorkspacePage(
    title: 'Users',
    description:
        'Search the latest 500 loaded profiles, inspect account details, and copy identifiers for support.',
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh users'),
        ),
      ),
      FutureBuilder<List<AppProfile>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppCard(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return AppCard(
              child: Column(
                children: [
                  const Text('Users could not be loaded. Try again.'),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Retry users'),
                  ),
                ],
              ),
            );
          }
          final all = snapshot.data ?? [];
          final query = _query.trim().toLowerCase();
          final filtered = all
              .where(
                (p) =>
                    (_role == null || p.role == _role) &&
                    (query.isEmpty ||
                        '${p.fullName} ${p.email} ${p.id}'
                            .toLowerCase()
                            .contains(query)),
              )
              .toList();
          filtered.sort((a, b) {
            final result = _sort == 'name'
                ? a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase())
                : (b.createdAt ?? DateTime(1970)).compareTo(
                    a.createdAt ?? DateTime(1970),
                  );
            return result != 0 ? result : a.id.compareTo(b.id);
          });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WorkspaceGrid(
                children: [
                  AdminMetricCard(
                    label: 'Loaded accounts',
                    value: '${all.length}',
                    note: 'Browse every loaded profile',
                    icon: Icons.people_outline,
                    onTap: () => setState(() => _role = null),
                  ),
                  AdminMetricCard(
                    label: 'Learners',
                    value:
                        '${all.where((p) => p.role == AppRole.learner).length}',
                    note: 'Filter learner profiles',
                    icon: Icons.school_outlined,
                    onTap: () => setState(() => _role = AppRole.learner),
                  ),
                  AdminMetricCard(
                    label: 'Administrators',
                    value:
                        '${all.where((p) => p.role == AppRole.administrator).length}',
                    note: 'Filter administrator profiles',
                    icon: Icons.admin_panel_settings_outlined,
                    onTap: () => setState(() => _role = AppRole.administrator),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        labelText: 'Search users',
                        hintText: 'Name, email, or account ID',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear user search',
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text('All roles'),
                          selected: _role == null,
                          onSelected: (_) => setState(() => _role = null),
                        ),
                        for (final role in AppRole.values)
                          ChoiceChip(
                            label: Text(role.label),
                            selected: _role == role,
                            onSelected: (_) => setState(() => _role = role),
                          ),
                        DropdownButton<String>(
                          value: _sort,
                          items: const [
                            DropdownMenuItem(
                              value: 'newest',
                              child: Text('Newest profiles'),
                            ),
                            DropdownMenuItem(
                              value: 'name',
                              child: Text('Name A–Z'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _sort = v!),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                AppCard(
                  child: Column(
                    children: [
                      Text(
                        all.isEmpty
                            ? 'No user accounts found.'
                            : 'No users match your filters.',
                      ),
                      if (all.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            _search.clear();
                            setState(() {
                              _query = '';
                              _role = null;
                            });
                          },
                          child: const Text('Reset user filters'),
                        ),
                    ],
                  ),
                )
              else
                AdminRecordBrowser<AppProfile>(
                  key: ValueKey('$_query:$_role:$_sort'),
                  items: filtered,
                  noun: 'accounts',
                  builder: (page) => AppCard(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 700) {
                          return Column(
                            children: [
                              for (final profile in page)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    child: Text(_initial(profile)),
                                  ),
                                  title: Text(
                                    profile.fullName.isEmpty
                                        ? 'Unnamed user'
                                        : profile.fullName,
                                  ),
                                  subtitle: Text(
                                    '${profile.email}\n${profile.role.label}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _details(profile),
                                ),
                            ],
                          );
                        }
                        return SizedBox(
                          width: double.infinity,
                          child: DataTable(
                            columnSpacing: 24,
                            horizontalMargin: 12,
                            dataRowMinHeight: 68,
                            dataRowMaxHeight: 76,
                            columns: const [
                              DataColumn(label: Text('Account')),
                              DataColumn(label: Text('Role')),
                              DataColumn(label: Text('Created')),
                              DataColumn(label: Text('Details')),
                            ],
                            rows: page
                                .map(
                                  (profile) => DataRow(
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          width: (constraints.maxWidth - 420)
                                              .clamp(140.0, 420.0),
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 17,
                                                child: Text(_initial(profile)),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      profile.fullName.isEmpty
                                                          ? 'Unnamed user'
                                                          : profile.fullName,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      profile.email,
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodySmall,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        onTap: () => _details(profile),
                                      ),
                                      DataCell(Text(profile.role.label)),
                                      DataCell(
                                        Text(
                                          adminDate(context, profile.createdAt),
                                        ),
                                      ),
                                      DataCell(
                                        IconButton(
                                          tooltip:
                                              'View account ${profile.email}',
                                          onPressed: () => _details(profile),
                                          icon: const Icon(
                                            Icons.open_in_new,
                                            size: 19,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        );
                      },
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

String _initial(AppProfile profile) => profile.fullName.trim().isEmpty
    ? '?'
    : profile.fullName.trim().substring(0, 1).toUpperCase();

String adminDate(BuildContext context, DateTime? date) => date == null
    ? 'Date unavailable'
    : MaterialLocalizations.of(context).formatShortDate(date.toLocal());

class AdminMetricCard extends StatelessWidget {
  final String label, value, note;
  final IconData icon;
  final VoidCallback onTap;
  const AdminMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => AppCard(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Icon(icon),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_outward,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(note, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class _WorkspaceGrid extends StatelessWidget {
  final List<Widget> children;
  const _WorkspaceGrid({required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          (constraints.maxWidth >= 1000
                  ? 4
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1)
              .clamp(1, children.length);
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: children
            .map(
              (child) => SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 16) / columns,
                child: child,
              ),
            )
            .toList(),
      );
    },
  );
}

class _WorkspacePage extends StatelessWidget {
  final String title, description;
  final List<Widget> children;
  const _WorkspacePage({
    required this.title,
    required this.description,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => AdaptiveBody(
    useSafeArea: false,
    maxWidth: 1440,
    child: ListView(
      padding: AdaptiveLayout.pageInsets(context),
      children: [
        PageIntro(title: title, description: description),
        const SizedBox(height: 24),
        for (final child in children) ...[child, const SizedBox(height: 20)],
      ],
    ),
  );
}

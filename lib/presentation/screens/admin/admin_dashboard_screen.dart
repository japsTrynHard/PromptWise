import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/content_controller.dart';
import '../../../data/models/app_profile.dart';
import '../../../data/models/content_item.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/page_intro.dart';
import './admin_content_management_screen.dart';
import './admin_learning_studio_screen.dart';
import './admin_verification_studio_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _index = 0;

  Widget get _currentPage => switch (_index) {
    0 => _OverviewPage(onOpenContent: () => _select(1)),
    1 => const AdminContentManagementScreen(),
    2 => const AdminLearningStudioScreen(),
    3 => const AdminVerificationStudioScreen(),
    _ => const _UsersPage(),
  };

  void _select(int value) {
    if (_index == value) return;
    setState(() => _index = value);
  }

  Future<void> _signOut() async {
    final auth = context.read<AuthController>();
    final success = await auth.signOut();
    if (!mounted || !success) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.root, (_) => false);
  }

  Widget _animatedPage() {
    // Admin pages contain large scrollable editors. Rendering two of those
    // simultaneously during AnimatedSwitcher transitions can produce stale
    // sliver/render-object assertions on Flutter web. Switch the page
    // directly; individual controls can still animate safely.
    return KeyedSubtree(
      key: ValueKey(_index),
      child: _currentPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('PromptWise Admin')),
        body: const AdaptiveBody(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.page),
              child: AppCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language_rounded, size: 48),
                    SizedBox(height: AppSpacing.lg),
                    Text(
                      'Administrator access is available on the web app.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width >= AppBreakpoints.desktop) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _AdminSidebar(
                    selectedIndex: _index,
                    onSelected: _select,
                    onSignOut: _signOut,
                  ),
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(child: _animatedPage()),
                ],
              ),
            ),
          );
        }

        if (width >= AppBreakpoints.tablet) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _AdminRail(
                    selectedIndex: _index,
                    onSelected: _select,
                    onSignOut: _signOut,
                  ),
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(child: _animatedPage()),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Admin · ${_AdminItems.items[_index].label}'),
            actions: [
              IconButton(
                tooltip: 'Sign out',
                onPressed: _signOut,
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
          drawer: Drawer(
            child: SafeArea(
              child: _AdminDrawer(
                selectedIndex: _index,
                onSelected: (value) {
                  Navigator.pop(context);
                  _select(value);
                },
              ),
            ),
          ),
          body: SafeArea(top: false, child: _animatedPage()),
        );
      },
    );
  }
}

class _AdminItems {
  static const items = <_AdminDestination>[
    _AdminDestination('Overview', Icons.dashboard_outlined),
    _AdminDestination('Content', Icons.library_books_outlined),
    _AdminDestination('Learning Studio', Icons.school_outlined),
    _AdminDestination('Verification Studio', Icons.fact_check_outlined),
    _AdminDestination('Users', Icons.people_outline_rounded),
  ];
}

class _AdminDestination {
  final String label;
  final IconData icon;

  const _AdminDestination(this.label, this.icon);
}

class _AdminSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSignOut;

  const _AdminSidebar({
    required this.selectedIndex,
    required this.onSelected,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: 260,
      margin: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: isDark ? 0.90 : 0.94),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.055),
            blurRadius: 26,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.lg,
              ),
              child: AppLogo(
                size: 42,
                showTagline: false,
                alignment: MainAxisAlignment.start,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                'Admin Web',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (var index = 0; index < _AdminItems.items.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _AdminNavButton(
                  item: _AdminItems.items[index],
                  selected: selectedIndex == index,
                  onTap: () => onSelected(index),
                ),
              ),
            const Spacer(),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.admin_panel_settings_outlined),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          auth.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSignOut;

  const _AdminRail({
    required this.selectedIndex,
    required this.onSelected,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      labelType: NavigationRailLabelType.all,
      leading: const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: AppLogo(size: 40, showWordmark: false),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: IconButton(
              tooltip: 'Sign out',
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded),
            ),
          ),
        ),
      ),
      destinations: _AdminItems.items
          .map(
            (item) => NavigationRailDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.icon),
              label: Text(item.label),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _AdminDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _AdminDrawer({required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xxl,
          ),
          child: AppLogo(
            size: 44,
            showTagline: false,
            alignment: MainAxisAlignment.start,
          ),
        ),
        Text(
          'Admin Web',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var index = 0; index < _AdminItems.items.length; index++)
          ListTile(
            selected: selectedIndex == index,
            leading: Icon(_AdminItems.items[index].icon),
            title: Text(_AdminItems.items[index].label),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            onTap: () => onSelected(index),
          ),
      ],
    );
  }
}

class _AdminNavButton extends StatelessWidget {
  final _AdminDestination item;
  final bool selected;
  final VoidCallback onTap;

  const _AdminNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                item.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewPage extends StatelessWidget {
  final VoidCallback onOpenContent;

  const _OverviewPage({required this.onOpenContent});

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentController>();
    final publishedCount = content.items
        .where((item) => item.status == ContentStatus.published)
        .length;
    final draftCount = content.items
        .where((item) => item.status == ContentStatus.draft)
        .length;

    return _AdminPage(
      intro: const PageIntro(
        title: 'Overview',
        description:
            'Review the learning content that is currently available in PromptWise.',
      ),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onOpenContent,
            icon: const Icon(Icons.library_books_outlined),
            label: const Text('Manage content'),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _MetricGrid(
          metrics: [
            _Metric(
              'Published content',
              '$publishedCount',
              'Visible to learners',
              Icons.visibility_outlined,
            ),
            _Metric(
              'Draft content',
              '$draftCount',
              'Still being prepared',
              Icons.edit_note_rounded,
            ),
            _Metric(
              'Learning modules',
              '${content.modules.length}',
              'Available in Learn',
              Icons.menu_book_outlined,
            ),
            _Metric(
              'Practice activities',
              '${content.quizzes.length + content.activities.length}',
              '${content.quizzes.length} quizzes · ${content.activities.length} Real or AI rounds',
              Icons.school_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _QuickActionsCard(onOpenContent: onOpenContent),
      ],
    );
  }
}

class _UsersPage extends StatefulWidget {
  const _UsersPage();

  @override
  State<_UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<_UsersPage> {
  late Future<List<AppProfile>> _profilesFuture;

  @override
  void initState() {
    super.initState();
    _profilesFuture = context.read<AuthController>().loadAllProfiles();
  }

  void _refresh() {
    setState(() {
      _profilesFuture = context.read<AuthController>().loadAllProfiles(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _AdminPage(
      intro: const PageIntro(
        title: 'Users',
        description:
            'View the learner and administrator accounts in PromptWise.',
      ),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FutureBuilder<List<AppProfile>>(
          future: _profilesFuture,
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
                    const Icon(Icons.wifi_off_rounded, size: 40),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Users could not be loaded. Check your connection and try again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              );
            }
            final profiles = snapshot.data ?? const <AppProfile>[];
            if (profiles.isEmpty) {
              return const AppCard(child: Text('No user accounts were found.'));
            }
            return _UsersTable(profiles: profiles);
          },
        ),
      ],
    );
  }
}

class _UsersTable extends StatelessWidget {
  final List<AppProfile> profiles;

  const _UsersTable({required this.profiles});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Email')),
            DataColumn(label: Text('Account type')),
            DataColumn(label: Text('Created')),
          ],
          rows: profiles
              .map((profile) {
                final created = profile.createdAt?.toLocal();
                final date = created == null
                    ? '—'
                    : '${created.year}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}';
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        profile.fullName.isEmpty
                            ? 'Unnamed user'
                            : profile.fullName,
                      ),
                    ),
                    DataCell(Text(profile.email)),
                    DataCell(Text(profile.role.label)),
                    DataCell(Text(date)),
                  ],
                );
              })
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _AdminPage extends StatelessWidget {
  final PageIntro intro;
  final List<Widget> children;

  const _AdminPage({required this.intro, required this.children});

  @override
  Widget build(BuildContext context) {
    return AdaptiveBody(
      useSafeArea: false,
      maxWidth: 1440,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: AdaptiveLayout.pageInsets(context),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                intro,
                const SizedBox(height: AppSpacing.xxl),
                ...children,
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<_Metric> metrics;

  const _MetricGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = AdaptiveLayout.gridColumns(
          constraints.maxWidth,
          minimumTileWidth: 240,
          maximumColumns: 4,
        );
        final width =
            (constraints.maxWidth - (AppSpacing.lg * (columns - 1))) / columns;
        return Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          metric.icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          metric.value,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          metric.label,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          metric.note,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _Metric {
  final String label;
  final String value;
  final String note;
  final IconData icon;

  const _Metric(this.label, this.value, this.note, this.icon);
}

class _QuickActionsCard extends StatelessWidget {
  final VoidCallback onOpenContent;

  const _QuickActionsCard({required this.onOpenContent});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Content management',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          _QuickAction(
            icon: Icons.note_add_outlined,
            label: 'Create or edit lessons',
            onPressed: onOpenContent,
          ),
          _QuickAction(
            icon: Icons.quiz_outlined,
            label: 'Manage quizzes and Real or AI activities',
            onPressed: onOpenContent,
          ),
          _QuickAction(
            icon: Icons.campaign_outlined,
            label: 'Manage AI awareness guidance',
            onPressed: onOpenContent,
          ),
          _QuickAction(
            icon: Icons.history_rounded,
            label: 'Review previous content versions',
            onPressed: onOpenContent,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Align(alignment: Alignment.centerLeft, child: Text(label)),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/admin_appearance_menu.dart';
import './admin_content_management_screen.dart';
import 'admin_workspace_pages.dart';
import 'admin_content_insights.dart';
import './admin_learning_studio_screen.dart';
import './admin_verification_studio_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _index = 0;
  AdminContentFilter _contentFilter = const AdminContentFilter();

  void _openContent(AdminContentFilter filter) {
    setState(() {
      _contentFilter = filter;
      _index = 1;
    });
  }

  Widget get _currentPage => switch (_index) {
    0 => AdminOverviewPage(onOpenContent: _openContent, onOpenStudio: _select),
    1 => AdminContentManagementScreen(initialFilter: _contentFilter),
    2 => const AdminLearningStudioScreen(),
    3 => const AdminVerificationStudioScreen(),
    _ => AdminUsersPage(
      loadProfiles: (force) =>
          context.read<AuthController>().loadAllProfiles(force: force),
    ),
  };

  void _select(int value) {
    if (_index == value) return;
    setState(() {
      _index = value;
      if (value == 1) _contentFilter = const AdminContentFilter();
    });
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
    return KeyedSubtree(key: ValueKey(_index), child: _currentPage);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('PromptWise Admin'),
          actions: const [AdminAppearanceMenu(compact: true)],
        ),
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
            title: Text(
              'Admin · ${_AdminItems.items[_index].label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              const AdminAppearanceMenu(compact: true),
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
        color: theme.colorScheme.surface.withValues(
          alpha: isDark ? 0.90 : 0.94,
        ),
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
            const AdminAppearanceMenu(),
            const SizedBox(height: AppSpacing.sm),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AdminAppearanceMenu(compact: true),
                const SizedBox(height: AppSpacing.sm),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
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
        const Divider(),
        const AdminAppearanceMenu(),
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

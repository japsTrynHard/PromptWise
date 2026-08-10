import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../routes/app_routes.dart';
import '../../utils/constants.dart';
import '../widgets/app_logo.dart';
import 'home_screen.dart';
import 'learn_screen.dart';
import 'practice_screen.dart';
import 'profile_screen.dart';
import 'verify_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  static const _destinations = <_Destination>[
    _Destination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _Destination(
      label: 'Learn',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
    ),
    _Destination(
      label: 'Practice',
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note_rounded,
    ),
    _Destination(
      label: 'Verify',
      icon: Icons.image_search_outlined,
      selectedIcon: Icons.image_search_rounded,
    ),
    _Destination(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  static const _pages = <Widget>[
    HomeScreen(),
    LearnScreen(),
    PracticeScreen(),
    VerifyScreen(),
    ProfileScreen(),
  ];

  void _select(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  Future<void> _signOut() async {
    final auth = context.read<AuthController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your saved progress will remain connected to this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final success = await auth.signOut();
    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage ?? 'Sign out failed.')),
      );
      return;
    }

    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.root, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= AppBreakpoints.tablet;
        final extendedRail = constraints.maxWidth >= AppBreakpoints.desktop;
        final veryCompact = constraints.maxWidth < 360;

        // A direct page switch is intentionally used here instead of an
        // AnimatedSwitcher. This prevents the first learner screen from being
        // left transparent while authentication and progress synchronization
        // finish on Flutter Web.
        final page = KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: _pages[_currentIndex],
        );

        if (useRail) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: _select,
                    extended: extendedRail,
                    minExtendedWidth: 220,
                    groupAlignment: -1,
                    leading: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.xl,
                        AppSpacing.md,
                        AppSpacing.section,
                      ),
                      child: AppLogo(
                        size: 42,
                        showWordmark: extendedRail,
                        alignment: MainAxisAlignment.start,
                      ),
                    ),
                    trailing: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        AppSpacing.section,
                        AppSpacing.sm,
                        AppSpacing.md,
                      ),
                      child: extendedRail
                          ? OutlinedButton.icon(
                              onPressed: auth.isLoading ? null : _signOut,
                              icon: const Icon(Icons.logout_rounded),
                              label: const Text('Sign out'),
                            )
                          : IconButton.filledTonal(
                              tooltip: 'Sign out',
                              onPressed: auth.isLoading ? null : _signOut,
                              icon: const Icon(Icons.logout_rounded),
                            ),
                    ),
                    destinations: _destinations
                        .map(
                          (item) => NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: Text(item.label),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(child: page),
              ],
            ),
          );
        }

        return Scaffold(
          body: page,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            labelBehavior: veryCompact
                ? NavigationDestinationLabelBehavior.onlyShowSelected
                : NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: _select,
            destinations: _destinations
                .map(
                  (item) => NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }
}

class _Destination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

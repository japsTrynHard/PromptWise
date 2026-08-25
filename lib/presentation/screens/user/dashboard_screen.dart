import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/floating_glass_navigation.dart';
import './home_screen.dart';
import './learn_screen.dart';
import './practice_screen.dart';
import './profile_screen.dart';
import './verify_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  int _tabDirection = 1;
  bool _navMinimized = false;
  late final AnimationController _tabController;
  late final Animation<double> _tabCurve;

  static const _destinations = <GlassNavDestination>[
    GlassNavDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    GlassNavDestination(
      label: 'Learn',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
    ),
    GlassNavDestination(
      label: 'Practice',
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note_rounded,
    ),
    GlassNavDestination(
      label: 'Verify',
      icon: Icons.image_search_outlined,
      selectedIcon: Icons.image_search_rounded,
    ),
    GlassNavDestination(
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

  @override
  void initState() {
    super.initState();
    _tabController = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
      value: 1,
    );
    _tabCurve = CurvedAnimation(
      parent: _tabController,
      curve: AppMotion.standardCurve,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (_currentIndex == index) {
      if (_navMinimized) setState(() => _navMinimized = false);
      return;
    }

    setState(() {
      _tabDirection = index > _currentIndex ? 1 : -1;
      _currentIndex = index;
      _navMinimized = false;
    });
    _tabController.forward(from: 0);
  }

  void _setNavMinimized(bool value) {
    if (_navMinimized == value || !mounted) return;
    setState(() => _navMinimized = value);
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification.metrics.pixels <= 6) {
      _setNavMinimized(false);
      return false;
    }

    if (notification.direction == ScrollDirection.reverse) {
      _setNavMinimized(true);
    } else if (notification.direction == ScrollDirection.forward) {
      _setNavMinimized(false);
    }
    return false;
  }

  Widget _persistentPageStack(BuildContext context) {
    final animationsEnabled = AppMotion.animationsEnabled(context);
    final stack = IndexedStack(index: _currentIndex, children: _pages);

    if (!animationsEnabled) return stack;

    return AnimatedBuilder(
      animation: _tabCurve,
      child: stack,
      builder: (context, child) {
        final value = _tabCurve.value;
        final dx = (1 - value) * 5 * _tabDirection;
        final opacity = 0.94 + (0.06 * value);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    final auth = context.read<AuthController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your saved progress will stay connected to this account.',
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
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final success = await auth.signOut();
    if (!mounted) return;

    if (!success) {
      messenger.showSnackBar(
        SnackBar(content: Text(auth.errorMessage ?? 'Sign out failed.')),
      );
      return;
    }

    navigator.pushNamedAndRemoveUntil(AppRoutes.root, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = AdaptiveLayout.isPhone(context);
        final useRail = !phone && constraints.maxWidth >= AppBreakpoints.compact;
        final extendedRail = constraints.maxWidth >= AppBreakpoints.desktop;
        final page = _persistentPageStack(context);

        if (useRail) {
          return Scaffold(
            body: _LearnerAmbientBackground(
              child: SafeArea(
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: _FloatingLearnerRail(
                        selectedIndex: _currentIndex,
                        extended: extendedRail,
                        auth: auth,
                        onSelected: _select,
                        onSignOut: _signOut,
                      ),
                    ),
                    Expanded(child: page),
                  ],
                ),
              ),
            ),
          );
        }

        final topInset = MediaQuery.viewPaddingOf(context).top;
        final pageTopPadding = topInset + 58;

        return Scaffold(
          extendBody: true,
          body: _LearnerAmbientBackground(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _handleUserScroll,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(top: pageTopPadding),
                      child: page,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _LearnerMobileTopBar(
                      displayName: auth.displayName,
                      onProfile: () => _select(4),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: FloatingGlassNavigation(
                      selectedIndex: _currentIndex,
                      destinations: _destinations,
                      onSelected: _select,
                      minimized: _navMinimized,
                      showSelectedLabel: constraints.maxWidth >= 420,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LearnerAmbientBackground extends StatelessWidget {
  final Widget child;

  const _LearnerAmbientBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.tablet;

    final background = DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF080D18) : const Color(0xFFFAFAFC),
        gradient: compact
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0xFF080D18), Color(0xFF0B1220)]
                    : const [Color(0xFFFCFCFF), Color(0xFFF7F8FC)],
              ),
      ),
    );

    if (compact) {
      return Stack(
        children: [
          Positioned.fill(child: background),
          Positioned.fill(child: child),
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: background),
        Positioned(
          top: -120,
          right: -90,
          child: _AmbientOrb(
            size: 310,
            color: AppColors.violet.withValues(alpha: isDark ? 0.08 : 0.05),
          ),
        ),
        Positioned(
          bottom: -170,
          left: -100,
          child: _AmbientOrb(
            size: 350,
            color: AppColors.teal.withValues(alpha: isDark ? 0.05 : 0.035),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _LearnerMobileTopBar extends StatelessWidget {
  final String displayName;
  final VoidCallback onProfile;

  const _LearnerMobileTopBar({
    required this.displayName,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final isDark = theme.brightness == Brightness.dark;
    final firstName = displayName.trim().isEmpty
        ? 'Learner'
        : displayName.trim().split(' ').first;

    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              topInset + 7,
              AppSpacing.lg,
              7,
            ),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor.withValues(
                alpha: isDark ? 0.82 : 0.86,
              ),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.38),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const AppLogo(size: 30, showWordmark: false),
                      const SizedBox(width: 9),
                      RichText(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 21,
                            letterSpacing: -0.85,
                            color: theme.colorScheme.onSurface,
                          ),
                          children: const [
                            TextSpan(text: 'Prompt'),
                            TextSpan(
                              text: 'Wise',
                              style: TextStyle(color: AppColors.teal),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Profile · $firstName',
                  child: Material(
                    color: theme.colorScheme.surface.withValues(alpha: 0.62),
                    shape: CircleBorder(
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.62),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onProfile,
                      child: const SizedBox.square(
                        dimension: 38,
                        child: Icon(Icons.person_outline_rounded, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingLearnerRail extends StatelessWidget {
  final int selectedIndex;
  final bool extended;
  final AuthController auth;
  final ValueChanged<int> onSelected;
  final VoidCallback onSignOut;

  const _FloatingLearnerRail({
    required this.selectedIndex,
    required this.extended,
    required this.auth,
    required this.onSelected,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: extended ? 232 : 84,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: isDark ? 0.88 : 0.91),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.06),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        extended: extended,
        minExtendedWidth: 232,
        groupAlignment: -1,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.section,
          ),
          child: AppLogo(
            size: 40,
            showWordmark: extended,
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
          child: extended
              ? OutlinedButton.icon(
                  onPressed: auth.isLoading ? null : onSignOut,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                )
              : IconButton.filledTonal(
                  tooltip: 'Sign out',
                  onPressed: auth.isLoading ? null : onSignOut,
                  icon: const Icon(Icons.logout_rounded),
                ),
        ),
        destinations: _DashboardScreenState._destinations
            .map(
              (item) => NavigationRailDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: Text(item.label),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

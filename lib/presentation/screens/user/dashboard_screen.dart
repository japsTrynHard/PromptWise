import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
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

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  int _tabDirection = 1;

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

  void _select(int index) {
    if (_currentIndex == index) {
      return;
    }

    setState(() {
      _tabDirection = index > _currentIndex ? 1 : -1;
      _currentIndex = index;
    });
  }

  Widget _animatedPage(BuildContext context) {
    final animationEnabled = AppMotion.animationsEnabled(context);
    final page = KeyedSubtree(
      key: ValueKey(_currentIndex),
      child: _pages[_currentIndex],
    );

    if (!animationEnabled) {
      return page;
    }

    return AnimatedSwitcher(
      duration: AppMotion.normal,
      reverseDuration: AppMotion.fast,
      switchInCurve: AppMotion.standardCurve,
      switchOutCurve: AppMotion.reverseCurve,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == ValueKey(_currentIndex);
        final direction = isIncoming ? _tabDirection : -_tabDirection;
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.standardCurve,
          reverseCurve: AppMotion.reverseCurve,
        );
        final slide = Tween<Offset>(
          begin: Offset(0.016 * direction, 0.004),
          end: Offset.zero,
        ).animate(curved);
        final fade = Tween<double>(begin: 0.9, end: 1).animate(curved);

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: RepaintBoundary(child: child),
          ),
        );
      },
      child: page,
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
        final useRail = constraints.maxWidth >= AppBreakpoints.tablet;
        final extendedRail = constraints.maxWidth >= AppBreakpoints.desktop;
        final page = _animatedPage(context);

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

        final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
        const floatingNavHeight = 74.0;
        const topHeaderHeight = 76.0;
        final pageBottomPadding = floatingNavHeight + bottomInset + 18;
        final pageTopPadding = topHeaderHeight + 8;

        return Scaffold(
          extendBody: true,
          body: _LearnerAmbientBackground(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: pageTopPadding,
                      bottom: pageBottomPadding,
                    ),
                    child: page,
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _LearnerMobileTopBar(
                    displayName: auth.displayName,
                    isLoading: auth.isLoading,
                    onSignOut: _signOut,
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
                    showSelectedLabel: constraints.maxWidth >= 410,
                  ),
                ),
              ],
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

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0xFF080D18), Color(0xFF0B1220)]
                    : const [Color(0xFFFCFCFF), Color(0xFFF7F8FC)],
              ),
            ),
          ),
        ),
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
  final bool isLoading;
  final VoidCallback onSignOut;

  const _LearnerMobileTopBar({
    required this.displayName,
    required this.isLoading,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final isDark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              topInset + AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.scaffoldBackgroundColor.withValues(alpha: isDark ? 0.82 : 0.88),
                  theme.scaffoldBackgroundColor.withValues(alpha: isDark ? 0.62 : 0.68),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary,
                        AppColors.violet,
                        AppColors.teal,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(5),
                  child: const FittedBox(
                    child: AppLogo(size: 28, showWordmark: false),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
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
                      Text(
                        'Hi, ${displayName.split(' ').first}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _TopBarIconButton(
                  tooltip: 'Sign out',
                  icon: Icons.logout_rounded,
                  loading: isLoading,
                  onPressed: isLoading ? null : onSignOut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  const _TopBarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.62),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.68),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, size: 20),
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

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';
import './adaptive_layout.dart';
import './app_logo.dart';

class AuthShell extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;
  final Widget? footer;

  const AuthShell({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0xFF070C16), Color(0xFF10152A)]
                      : const [Color(0xFFF9FAFF), Color(0xFFF0F3FF)],
                ),
              ),
            ),
          ),
          Positioned(
            top: -110,
            right: -80,
            child: _AuthOrb(
              size: 300,
              color: AppColors.violet.withValues(alpha: isDark ? 0.13 : 0.08),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -100,
            child: _AuthOrb(
              size: 330,
              color: AppColors.teal.withValues(alpha: isDark ? 0.09 : 0.06),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    AdaptiveLayout.horizontalPaddingFor(constraints.maxWidth),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1060),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Expanded(child: _AuthPurpose()),
                                  const SizedBox(width: 52),
                                  Expanded(
                                    child: _AuthGlassCard(
                                      title: title,
                                      description: description,
                                      footer: footer,
                                      child: child,
                                    ),
                                  ),
                                ],
                              )
                            : _AuthGlassCard(
                                title: title,
                                description: description,
                                footer: footer,
                                child: child,
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthGlassCard extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;
  final Widget? footer;

  const _AuthGlassCard({
    required this.title,
    required this.description,
    required this.child,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(
              alpha: isDark ? 0.84 : 0.80,
            ),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.08),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppLogo(
                size: 48,
                showTagline: false,
                alignment: MainAxisAlignment.start,
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              child,
              if (footer != null) ...[
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthPurpose extends StatelessWidget {
  const _AuthPurpose();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  AppColors.violet,
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Icon(
              Icons.school_outlined,
              size: 30,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Learn on any device without losing your place.',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Your lessons, progress, practice results, and achievements stay connected to your PromptWise account.',
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _AuthBenefit(
            icon: Icons.bolt_rounded,
            text: 'Return to your dashboard quickly on devices you have used before',
          ),
          const _AuthBenefit(
            icon: Icons.sync_rounded,
            text: 'Saved progress can recover smoothly after connection problems',
          ),
          const _AuthBenefit(
            icon: Icons.lock_outline_rounded,
            text: 'Your learning information stays private to your account',
          ),
        ],
      ),
    );
  }
}

class _AuthBenefit extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AuthBenefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 19,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(text),
          )),
        ],
      ),
    );
  }
}

class _AuthOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _AuthOrb({required this.size, required this.color});

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

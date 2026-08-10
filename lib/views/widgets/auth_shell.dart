import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import 'adaptive_layout.dart';
import 'app_card.dart';
import 'app_logo.dart';

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
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return SingleChildScrollView(
              padding: EdgeInsets.all(
                AdaptiveLayout.horizontalPaddingFor(constraints.maxWidth),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Expanded(child: _AuthPurpose()),
                              const SizedBox(width: 48),
                              Expanded(
                                child: _AuthCard(
                                  title: title,
                                  description: description,
                                  footer: footer,
                                  child: child,
                                ),
                              ),
                            ],
                          )
                        : _AuthCard(
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
    );
  }
}

class _AuthCard extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;
  final Widget? footer;

  const _AuthCard({
    required this.title,
    required this.description,
    required this.child,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppLogo(
            size: 48,
            showTagline: false,
            alignment: MainAxisAlignment.start,
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    );
  }
}

class _AuthPurpose extends StatelessWidget {
  const _AuthPurpose();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'One account across every supported device.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Your completed lessons, best quiz results, badges, and learning level can stay connected across Android, iOS, tablet, and web.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _AuthBenefit(
            icon: Icons.sync_rounded,
            text: 'Progress stays saved even during connection problems',
          ),
          const _AuthBenefit(
            icon: Icons.lock_outline_rounded,
            text: 'Your learning information stays private to your account',
          ),
          const _AuthBenefit(
            icon: Icons.admin_panel_settings_outlined,
            text: 'Administrators use a separate web workspace',
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
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

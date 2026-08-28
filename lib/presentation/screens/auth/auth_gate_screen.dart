import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../../data/models/auth_otp_request.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import '../../widgets/app_logo.dart';
import '../admin/admin_dashboard_screen.dart';
import '../user/dashboard_screen.dart';
import '../shared/welcome_screen.dart';

class AuthGateScreen extends StatelessWidget {
  const AuthGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (!auth.isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLogo(size: 64, showTagline: true),
              SizedBox(height: AppSpacing.xxl),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }

    if (!auth.isAuthenticated) return const WelcomeScreen();

    if (!auth.isEmailVerified) {
      return _GateMessage(
        icon: Icons.mark_email_unread_outlined,
        title: 'Confirm your email',
        message:
            'Open the confirmation link sent to ${auth.email}. After confirmation, return to PromptWise.',
        primaryLabel: 'Enter confirmation code',
        onPrimary: auth.isLoading
            ? null
            : () => Navigator.pushNamed(
                context,
                AppRoutes.verifyEmail,
                arguments: AuthOtpRequest(
                  email: auth.email,
                  purpose: AuthOtpPurpose.signup,
                ),
              ),
        secondaryLabel: 'Sign out',
        onSecondary: auth.isLoading ? null : () => auth.signOut(),
      );
    }

    if (!auth.isReadyForRouting) {
      return const _GateLoading(
        message: 'Preparing your PromptWise workspace...',
      );
    }

    if (auth.isAdministrator) {
      if (kIsWeb) return const AdminDashboardScreen();
      return _GateMessage(
        icon: Icons.language_rounded,
        title: 'Administrator access is web-only',
        message:
            'Open PromptWise in a web browser to use this administrator account.',
        primaryLabel: 'Sign out',
        onPrimary: auth.isLoading ? null : () => auth.signOut(),
      );
    }

    return const DashboardScreen();
  }
}

class AuthenticatedRoute extends StatelessWidget {
  final Widget child;

  const AuthenticatedRoute({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!auth.isAuthenticated || !auth.isEmailVerified) {
      return _GateMessage(
        icon: Icons.lock_outline_rounded,
        title: 'Sign in required',
        message: 'Sign in with a verified PromptWise account to continue.',
        primaryLabel: 'Sign in',
        onPrimary: () =>
            Navigator.pushReplacementNamed(context, AppRoutes.login),
        secondaryLabel: 'Back',
        onSecondary: () =>
            Navigator.pushReplacementNamed(context, AppRoutes.welcome),
      );
    }
    if (!auth.isReadyForRouting) {
      return const _GateLoading(
        message: 'Preparing your PromptWise workspace...',
      );
    }
    if (auth.isAdministrator) {
      return _GateMessage(
        icon: Icons.admin_panel_settings_outlined,
        title: kIsWeb
            ? 'Open the administrator workspace'
            : 'Administrator access is web-only',
        message: kIsWeb
            ? 'This administrator account uses the web management workspace.'
            : 'Open PromptWise in a web browser to use administrator tools.',
        primaryLabel: kIsWeb ? 'Open admin' : 'Sign out',
        onPrimary: kIsWeb
            ? () => Navigator.pushReplacementNamed(context, AppRoutes.admin)
            : () => auth.signOut(),
      );
    }
    return child;
  }
}

class AdministratorRoute extends StatelessWidget {
  final Widget child;

  const AdministratorRoute({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!kIsWeb) {
      return _GateMessage(
        icon: Icons.language_rounded,
        title: 'Admin is web-only',
        message:
            'Open the PromptWise web app on a browser to use administrator tools.',
        primaryLabel: 'Sign out',
        onPrimary: auth.isLoading ? null : () => auth.signOut(),
      );
    }
    if (auth.isAuthenticated && !auth.isReadyForRouting) {
      return const _GateLoading(message: 'Checking administrator access...');
    }
    if (!auth.isAuthenticated || !auth.isAdministrator) {
      return _GateMessage(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Administrator access required',
        message:
            'This account does not have permission to open the administrator workspace.',
        primaryLabel: 'Return to app',
        onPrimary: () =>
            Navigator.pushReplacementNamed(context, AppRoutes.root),
      );
    }
    return child;
  }
}

class _GateLoading extends StatelessWidget {
  final String message;

  const _GateLoading({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 64, showTagline: true),
              const SizedBox(height: AppSpacing.xxl),
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.lg),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _GateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _GateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Text(message, textAlign: TextAlign.center),
                if (primaryLabel != null) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton(
                    onPressed: onPrimary,
                    child: Text(primaryLabel!),
                  ),
                ],
                if (secondaryLabel != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_routes.dart';
import '../../controllers/auth_controller.dart';
import '../../widgets/auth_shell.dart';

class SignupConfirmationScreen extends StatefulWidget {
  final String email;

  const SignupConfirmationScreen({super.key, required this.email});

  @override
  State<SignupConfirmationScreen> createState() =>
      _SignupConfirmationScreenState();
}

class _SignupConfirmationScreenState extends State<SignupConfirmationScreen> {
  Timer? _timer;
  int _cooldown = 60;
  bool _resent = false;
  bool _verifiedRouteScheduled = false;

  @override
  void initState() {
    super.initState();
    _startCooldown(notify: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _email(AuthController auth) {
    final supplied = widget.email.trim();
    return supplied.isNotEmpty ? supplied : (auth.pendingEmail ?? auth.email);
  }

  void _startCooldown({bool notify = true}) {
    _timer?.cancel();
    if (notify) {
      setState(() => _cooldown = 60);
    } else {
      _cooldown = 60;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  void _routeVerifiedUser(AuthController auth) {
    if (!auth.isAuthenticated ||
        !auth.isEmailVerified ||
        _verifiedRouteScheduled) {
      return;
    }
    _verifiedRouteScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.root, (_) => false);
    });
  }

  Future<void> _resend() async {
    final auth = context.read<AuthController>();
    final success = await auth.resendSignupConfirmation(email: _email(auth));
    if (!mounted || !success) return;
    setState(() => _resent = true);
    _startCooldown();
  }

  Future<void> _backToLogin() async {
    final auth = context.read<AuthController>();
    if (auth.isAuthenticated && !auth.isEmailVerified) {
      final signedOut = await auth.signOut();
      if (!mounted || !signedOut) return;
    } else {
      await auth.clearPendingSignupConfirmation();
      if (!mounted) return;
    }
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final email = _email(auth);
    _routeVerifiedUser(auth);

    return AuthShell(
      title: 'Check your email',
      description: 'We sent a confirmation link to your email address.',
      footer: TextButton(
        onPressed: auth.isLoading ? null : _backToLogin,
        child: const Text('Back to login'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.mark_email_unread_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            email.isEmpty
                ? 'Check your inbox for the PromptWise confirmation email.'
                : 'Confirmation email sent to $email',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Open the email and tap the confirmation link to verify your PromptWise account.',
            textAlign: TextAlign.center,
          ),
          if (_resent) ...[
            const SizedBox(height: 16),
            const _StatusNotice(
              message:
                  'A new confirmation email was sent. Use the latest email you receive.',
              isError: false,
            ),
          ],
          if (auth.errorMessage != null) ...[
            const SizedBox(height: 16),
            _StatusNotice(message: auth.errorMessage!, isError: true),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: auth.isLoading || _cooldown > 0 ? null : _resend,
            icon: auth.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              auth.isLoading
                  ? 'Sending confirmation email...'
                  : _cooldown > 0
                  ? 'Resend available in ${_cooldown}s'
                  : 'Resend confirmation email',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Check Inbox, Spam, and Promotions if the email does not appear.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  final String message;
  final bool isError;

  const _StatusNotice({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isError ? scheme.onErrorContainer : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

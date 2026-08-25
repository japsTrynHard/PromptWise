import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../../data/models/auth_otp_request.dart';
import '../../../core/routes/app_routes.dart';
import '../../widgets/auth_shell.dart';

class VerifyEmailScreen extends StatefulWidget {
  final AuthOtpRequest? request;

  const VerifyEmailScreen({super.key, this.request});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  Timer? _timer;
  int _cooldown = 60;
  bool _resent = false;

  @override
  void initState() {
    super.initState();
    _startCooldown(notify: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  AuthOtpRequest _request(AuthController auth) {
    return widget.request ??
        AuthOtpRequest(
          email: auth.pendingEmail ?? auth.email,
          purpose: auth.pendingOtpPurpose ?? AuthOtpPurpose.signup,
        );
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

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    final request = _request(auth);
    final success = await auth.verifyOtp(
      email: request.email,
      token: _codeController.text,
      purpose: request.purpose,
    );
    if (!mounted || !success) return;

    final route = request.purpose == AuthOtpPurpose.recovery
        ? AppRoutes.resetPassword
        : AppRoutes.root;
    Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
  }

  Future<void> _resend() async {
    final auth = context.read<AuthController>();
    final request = _request(auth);
    final success = await auth.resendOtp(
      email: request.email,
      purpose: request.purpose,
    );
    if (!mounted || !success) return;
    _codeController.clear();
    setState(() => _resent = true);
    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final request = _request(auth);

    return AuthShell(
      title: request.purpose.title,
      description: request.purpose.description,
      footer: TextButton(
        onPressed: auth.isLoading
            ? null
            : () => Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.login,
                (_) => false,
              ),
        child: const Text('Use a different email'),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.mark_email_read_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              request.email.isEmpty
                  ? 'Check your inbox for the latest PromptWise code.'
                  : 'Code sent to ${request.email}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (_resent) ...[
              const SizedBox(height: 12),
              _StatusNotice(
                message:
                    'A new code was requested. Use only the latest email you receive.',
                isError: false,
              ),
            ],
            if (auth.errorMessage != null) ...[
              const SizedBox(height: 12),
              _StatusNotice(message: auth.errorMessage!, isError: true),
            ],
            const SizedBox(height: 24),
            TextFormField(
              controller: _codeController,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(letterSpacing: 10),
              decoration: const InputDecoration(
                labelText: '6-digit code',
                hintText: '000000',
                counterText: '',
                prefixIcon: Icon(Icons.password_rounded),
              ),
              validator: (value) {
                final code = value?.trim() ?? '';
                return code.length == 6
                    ? null
                    : 'Enter the complete 6-digit code.';
              },
              onFieldSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: auth.isLoading ? null : _verify,
              icon: auth.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(
                auth.isLoading ? 'Verifying...' : request.purpose.actionLabel,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: auth.isLoading || _cooldown > 0 ? null : _resend,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                _cooldown > 0
                    ? 'Resend available in ${_cooldown}s'
                    : 'Resend code',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Check Inbox, Spam, and Promotions. If no code arrives, wait before requesting another one.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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

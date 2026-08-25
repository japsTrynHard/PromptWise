import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../../data/models/auth_otp_request.dart';
import '../../../core/routes/app_routes.dart';
import '../../widgets/auth_shell.dart';

enum _SignInMethod { password, emailCode }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  _SignInMethod _method = _SignInMethod.password;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    final email = _emailController.text.trim();

    if (_method == _SignInMethod.emailCode) {
      final success = await auth.sendSignInOtp(email);
      if (!mounted || !success) return;
      Navigator.pushNamed(
        context,
        AppRoutes.verifyEmail,
        arguments: AuthOtpRequest(email: email, purpose: AuthOtpPurpose.signIn),
      );
      return;
    }

    final success = await auth.signIn(
      email: email,
      password: _passwordController.text,
    );
    if (!mounted || !success) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.root, (_) => false);
    });
  }

  Future<void> _openSignupOtp() async {
    final email = _emailController.text.trim();
    final error = _validateEmail(email);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final auth = context.read<AuthController>();
    final success = await auth.resendOtp(
      email: email,
      purpose: AuthOtpPurpose.signup,
    );
    if (!mounted || !success) return;
    Navigator.pushNamed(
      context,
      AppRoutes.verifyEmail,
      arguments: AuthOtpRequest(email: email, purpose: AuthOtpPurpose.signup),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final requiresConfirmation =
        auth.errorMessage?.toLowerCase().contains('confirm your email') ??
        false;

    return AuthShell(
      title: 'Sign in to PromptWise',
      description:
          'Use the same sign-in for learning or admin access. PromptWise opens the right workspace automatically.',
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('No account yet?'),
          TextButton(
            onPressed: auth.isLoading
                ? null
                : () => Navigator.pushReplacementNamed(
                    context,
                    AppRoutes.register,
                  ),
            child: const Text('Create account'),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!auth.isBackendConfigured) const _ConfigurationNotice(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Password'),
                  avatar: const Icon(Icons.lock_outline_rounded, size: 18),
                  selected: _method == _SignInMethod.password,
                  onSelected: auth.isLoading
                      ? null
                      : (_) => setState(() => _method = _SignInMethod.password),
                ),
                ChoiceChip(
                  label: const Text('Email code'),
                  avatar: const Icon(Icons.password_rounded, size: 18),
                  selected: _method == _SignInMethod.emailCode,
                  onSelected: auth.isLoading
                      ? null
                      : (_) =>
                            setState(() => _method = _SignInMethod.emailCode),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _method == _SignInMethod.password
                  ? 'Password sign-in does not send an email.'
                  : 'Email code sends a 6-digit sign-in code to your email.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (auth.errorMessage != null) ...[
              _ErrorNotice(message: auth.errorMessage!),
              if (requiresConfirmation) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: auth.isLoading ? null : _openSignupOtp,
                  icon: const Icon(Icons.mark_email_unread_outlined),
                  label: const Text('Send confirmation code'),
                ),
              ],
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: _method == _SignInMethod.password
                  ? TextInputAction.next
                  : TextInputAction.done,
              onFieldSubmitted: _method == _SignInMethod.emailCode
                  ? (_) => _submit()
                  : null,
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: _validateEmail,
            ),
            if (_method == _SignInMethod.password) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password.'
                    : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: auth.isLoading
                      ? null
                      : () => Navigator.pushNamed(
                          context,
                          AppRoutes.forgotPassword,
                        ),
                  child: const Text('Forgot password?'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: auth.isLoading ? null : _submit,
              icon: auth.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _method == _SignInMethod.password
                          ? Icons.login_rounded
                          : Icons.mark_email_read_outlined,
                    ),
              label: Text(
                auth.isLoading
                    ? 'Please wait...'
                    : _method == _SignInMethod.password
                    ? 'Sign in'
                    : 'Send sign-in code',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: auth.isLoading
                  ? null
                  : () => Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.welcome,
                    ),
              child: const Text('Back to welcome'),
            ),
          ],
        ),
      ),
    );
  }
}

String? _validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Enter your email address.';
  final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  return valid ? null : 'Enter a valid email address.';
}

class _ErrorNotice extends StatelessWidget {
  final String message;

  const _ErrorNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _ConfigurationNotice extends StatelessWidget {
  const _ConfigurationNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text('Sign in is temporarily unavailable in this build.'),
    );
  }
}

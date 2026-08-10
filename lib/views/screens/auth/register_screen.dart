import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/auth_controller.dart';
import '../../../models/auth_otp_request.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/auth_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    final success = await auth.register(
      fullName: _nameController.text,
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (!mounted || !success) return;

    if (auth.isAuthenticated && auth.isEmailVerified) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.dashboard,
        (_) => false,
      );
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRoutes.verifyEmail,
      arguments: AuthOtpRequest(
        email: _emailController.text.trim(),
        purpose: AuthOtpPurpose.signup,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return AuthShell(
      title: 'Create learner account',
      description:
          'Registration creates a learner account. Administrator access is assigned separately and cannot be selected here.',
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Already registered?'),
          TextButton(
            onPressed: auth.isLoading
                ? null
                : () =>
                      Navigator.pushReplacementNamed(context, AppRoutes.login),
            child: const Text('Sign in'),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (auth.errorMessage != null) ...[
              _Notice(message: auth.errorMessage!, isError: true),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.length < 2) return 'Enter your full name.';
                if (name.length > 80) return 'Use 80 characters or fewer.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Enter your email address.';
                return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                    ? null
                    : 'Enter a valid email address.';
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: 'Use at least 8 characters.',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                final password = value ?? '';
                if (password.length < 8) {
                  return 'Use at least 8 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_reset_rounded),
              ),
              validator: (value) => value != _passwordController.text
                  ? 'Passwords do not match.'
                  : null,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: auth.isLoading ? null : _submit,
              icon: auth.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: Text(
                auth.isLoading ? 'Creating account...' : 'Create account',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String message;
  final bool isError;
  const _Notice({required this.message, required this.isError});

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
        style: TextStyle(
          color: isError ? scheme.onErrorContainer : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

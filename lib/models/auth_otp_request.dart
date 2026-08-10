enum AuthOtpPurpose { signup, signIn, recovery }

extension AuthOtpPurposeX on AuthOtpPurpose {
  String get title => switch (this) {
    AuthOtpPurpose.signup => 'Verify your email',
    AuthOtpPurpose.signIn => 'Enter your sign-in code',
    AuthOtpPurpose.recovery => 'Verify password recovery',
  };

  String get description => switch (this) {
    AuthOtpPurpose.signup =>
      'Enter the 6-digit code sent to your email to activate your PromptWise account.',
    AuthOtpPurpose.signIn =>
      'Enter the 6-digit code sent to your email to sign in.',
    AuthOtpPurpose.recovery =>
      'Enter the 6-digit code sent to your email before choosing a new password.',
  };

  String get actionLabel => switch (this) {
    AuthOtpPurpose.signup => 'Verify account',
    AuthOtpPurpose.signIn => 'Sign in',
    AuthOtpPurpose.recovery => 'Verify recovery code',
  };
}

class AuthOtpRequest {
  final String email;
  final AuthOtpPurpose purpose;

  const AuthOtpRequest({required this.email, required this.purpose});
}

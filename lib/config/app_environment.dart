import 'package:flutter/foundation.dart';

class AppEnvironment {
  AppEnvironment._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static const mobileAuthScheme = 'io.promptwise.app';
  static const mobileAuthHost = 'auth-callback';

  static bool get isSupabaseConfigured {
    final uri = Uri.tryParse(supabaseUrl);
    return uri != null &&
        uri.hasScheme &&
        uri.host.isNotEmpty &&
        supabasePublishableKey.trim().isNotEmpty;
  }

  static String? get emailConfirmationRedirectUrl {
    if (kIsWeb) return Uri.base.origin;
    return '$mobileAuthScheme://$mobileAuthHost/';
  }

  static String? get passwordRecoveryRedirectUrl {
    if (kIsWeb) return Uri.base.origin;
    return '$mobileAuthScheme://$mobileAuthHost/';
  }
}

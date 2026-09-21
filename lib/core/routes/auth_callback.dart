import 'package:supabase_flutter/supabase_flutter.dart';

/// Recognizes Supabase callbacks before Flutter treats their hash as a route.
/// These parameters identify navigation only; the SDK must verify the session.
class AuthCallback {
  const AuthCallback._(this.path, this._parameters);

  static const expiredLinkMessage =
      'This email link is invalid, has expired, or was already used. '
      'Request a new reset link and open only the latest email.';
  static const failedLinkMessage =
      'We could not open this email link. Request a new reset link and open '
      'it in the same browser where you requested it.';
  static const sameBrowserMessage =
      'Open the reset link in the same browser where you requested it. '
      'If that browser is unavailable, request a new reset link here.';

  final String path;
  final Map<String, String> _parameters;

  factory AuthCallback.parse(String location) {
    try {
      final uri = Uri.parse(location);
      var path = uri.path.isEmpty ? '/' : uri.path;
      final parameters = <String, String>{...uri.queryParameters};

      // Flutter's hash strategy can deliver /error=... or /access_token=...
      // as the route name, without the original # character.
      if (_isParameterPath(path)) {
        parameters.addAll(
          Uri.splitQueryString(path.replaceFirst(RegExp(r'^/'), '')),
        );
        path = '/';
      }

      final fragment = uri.fragment;
      if (fragment.startsWith('/') && !_isParameterPath(fragment)) {
        final route = Uri.parse(fragment);
        path = route.path;
        parameters.addAll(route.queryParameters);
      } else if (fragment.isNotEmpty) {
        parameters.addAll(
          Uri.splitQueryString(fragment.replaceFirst(RegExp(r'^/'), '')),
        );
      }
      return AuthCallback._(path, parameters);
    } on FormatException {
      return AuthCallback._(location, const {});
    }
  }

  static bool _isParameterPath(String path) => RegExp(
    r'^/?(?:error|error_code|error_description|access_token|refresh_token|expires_in|expires_at|token_type|type|code)=',
  ).hasMatch(path);

  bool get hasError => [
    'error',
    'error_code',
    'error_description',
  ].any((key) => _parameters[key]?.isNotEmpty ?? false);

  bool get isAuthCallback =>
      hasError ||
      _parameters.containsKey('code') ||
      _parameters.containsKey('access_token') ||
      _parameters['type'] == 'recovery';

  String? get errorMessage {
    if (!hasError) return null;
    return messageForException(
          AuthException(
            _parameters['error_description'] ?? '',
            code: _parameters['error_code'] ?? _parameters['error'],
          ),
        ) ??
        failedLinkMessage;
  }

  static String? messageForException(Object error) {
    if (error is! AuthException) return null;
    final code = error.code?.toLowerCase();
    // getSessionFromUrl puts the callback's error_code in statusCode.
    final status = error.statusCode?.toLowerCase();
    final message = error.message.toLowerCase();
    if (code == 'otp_expired' ||
        status == 'otp_expired' ||
        code == 'flow_state_expired' ||
        status == 'flow_state_expired' ||
        message.contains('link is invalid or has expired')) {
      return expiredLinkMessage;
    }
    if (error is AuthPKCEGrantCodeExchangeError ||
        code == 'flow_state_not_found' ||
        code == 'bad_code_verifier' ||
        message.contains('code verifier') ||
        message.contains('code_verifier')) {
      return sameBrowserMessage;
    }
    if (code == 'access_denied' || status == 'access_denied') {
      return failedLinkMessage;
    }
    return null;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/core/routes/app_routes.dart';
import 'package:promptwise/core/routes/auth_callback.dart';
import 'package:promptwise/core/routes/auth_callback_url.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const errorParameters =
      'error=access_denied&error_code=otp_expired'
      '&error_description=Email+link+is+invalid+or+has+expired';

  for (final location in [
    'http://localhost:3000/?$errorParameters#$errorParameters&sb=',
    'http://localhost:3000/#$errorParameters',
    '/?$errorParameters',
    '/$errorParameters',
    '/reset-password?$errorParameters',
  ]) {
    test('recognizes expired email callback: $location', () {
      final callback = AuthCallback.parse(location);

      expect(callback.isAuthCallback, isTrue);
      expect(callback.hasError, isTrue);
      expect(callback.errorMessage, AuthCallback.expiredLinkMessage);
    });
  }

  for (final location in [
    '/?code=test-auth-code',
    'http://localhost:3000/?code=test-auth-code',
    '/access_token=test-token&refresh_token=test-refresh&type=recovery',
  ]) {
    test('recognizes successful callback parameters: $location', () {
      final callback = AuthCallback.parse(location);

      expect(callback.isAuthCallback, isTrue);
      expect(callback.hasError, isFalse);
      expect(callback.errorMessage, isNull);
    });
  }

  test('ordinary routes retain their path without becoming auth callbacks', () {
    final callback = AuthCallback.parse('/forgot-password?source=email');

    expect(callback.path, AppRoutes.forgotPassword);
    expect(callback.isAuthCallback, isFalse);
    expect(callback.hasError, isFalse);
  });

  test(
    'startup preserves error parameters for rendering the callback failure',
    () {
      final uri = Uri.parse(
        'http://localhost:3000/?$errorParameters#$errorParameters',
      );

      expect(AppRoutes.initialRouteForUri(uri), uri.toString());
      expect(
        AppRoutes.initialRouteForUri(Uri.parse('http://localhost:3000/')),
        AppRoutes.root,
      );
    },
  );

  test(
    'maps SDK URL error_code from statusCode to the expired-link message',
    () {
      expect(
        AuthCallback.messageForException(
          const AuthException(
            'Email link is invalid or has expired',
            code: 'access_denied',
            statusCode: 'otp_expired',
          ),
        ),
        AuthCallback.expiredLinkMessage,
      );
    },
  );

  test('PKCE callback failures explain that the same browser is needed', () {
    final message = AuthCallback.messageForException(
      const AuthException('Code verifier could not be found in local storage.'),
    );

    expect(message, isNotNull);
    expect(message!.toLowerCase(), contains('same browser'));
  });

  test('ordinary sign-in failures are not classified as callback failures', () {
    expect(
      AuthCallback.messageForException(
        const AuthException('Invalid login credentials'),
      ),
      isNull,
    );
  });

  test(
    'failed callback cleanup removes both query and fragment auth fields',
    () {
      final uri = Uri.parse(
        'http://localhost:3000/?$errorParameters#$errorParameters',
      );
      final initialRoute = AppRoutes.initialRouteForUri(uri);
      final cleaned = removeFailedAuthCallbackParameters(uri);

      expect(AuthCallback.parse(initialRoute).hasError, isTrue);
      expect(cleaned.toString(), 'http://localhost:3000/');
      expect(cleaned.hasQuery, isFalse);
      expect(cleaned.hasFragment, isFalse);
      expect(AppRoutes.initialRouteForUri(cleaned), AppRoutes.root);
    },
  );

  test(
    'failed callback cleanup preserves unrelated and repeated parameters',
    () {
      final cleaned = removeFailedAuthCallbackParameters(
        Uri.parse(
          'https://example.com/promptwise/?source=email&tag=one&tag=two'
          '&$errorParameters#$errorParameters&campaign=recovery',
        ),
      );

      expect(cleaned.path, '/promptwise/');
      expect(cleaned.queryParametersAll, {
        'source': ['email'],
        'tag': ['one', 'two'],
      });
      expect(cleaned.fragment, 'campaign=recovery');
      expect(AuthCallback.parse(cleaned.toString()).hasError, isFalse);
      expect(removeFailedAuthCallbackParameters(cleaned), cleaned);
    },
  );

  test('failed callback cleanup preserves an existing hash route', () {
    final cleaned = removeFailedAuthCallbackParameters(
      Uri.parse(
        'http://localhost:3000/?$errorParameters'
        '#/forgot-password?source=email&error_code=otp_expired',
      ),
    );

    expect(cleaned.hasQuery, isFalse);
    expect(cleaned.fragment, '/forgot-password?source=email');
  });

  for (final location in [
    'http://localhost:3000/?code=still-needs-verification',
    'http://localhost:3000/#access_token=test-token&type=recovery',
    'http://localhost:3000/?source=email#/login',
  ]) {
    test(
      'cleanup leaves successful callbacks and ordinary URLs alone: $location',
      () {
        final uri = Uri.parse(location);

        expect(removeFailedAuthCallbackParameters(uri), same(uri));
      },
    );
  }
}

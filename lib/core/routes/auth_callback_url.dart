import 'auth_callback.dart';
import 'auth_callback_url_stub.dart'
    if (dart.library.js_interop) 'auth_callback_url_web.dart'
    as platform;

const _authParameters = {
  'error',
  'error_code',
  'error_description',
  'code',
  'access_token',
  'refresh_token',
  'expires_in',
  'expires_at',
  'token_type',
  'provider_token',
  'provider_refresh_token',
  'type',
};

/// Clears a failed callback after its navigation and message have been captured.
/// Successful callbacks stay intact until Supabase verifies their credentials.
void clearFailedAuthCallbackUrl(Uri uri) {
  final cleaned = removeFailedAuthCallbackParameters(uri);
  if (cleaned != uri) platform.replaceBrowserUrl(cleaned.toString());
}

/// Prevents old errors from surviving Flutter's hash-route navigation/reloads.
Uri removeFailedAuthCallbackParameters(Uri uri) {
  if (!AuthCallback.parse(uri.toString()).hasError) return uri;

  final query = _withoutAuthParameters(uri.queryParametersAll);
  final fragment = _cleanFragment(uri.fragment);
  return _withParameters(uri, query, fragment);
}

Map<String, List<String>> _withoutAuthParameters(
  Map<String, List<String>> parameters,
) => {
  for (final entry in parameters.entries)
    if (!_authParameters.contains(entry.key)) entry.key: entry.value,
};

Uri _withParameters(
  Uri uri,
  Map<String, List<String>> query,
  String fragment,
) => Uri(
  scheme: uri.scheme,
  userInfo: uri.userInfo,
  host: uri.hasAuthority ? uri.host : null,
  port: uri.hasPort ? uri.port : null,
  path: uri.path,
  queryParameters: query.isEmpty ? null : query,
  fragment: fragment.isEmpty ? null : fragment,
);

String _cleanFragment(String fragment) {
  if (fragment.isEmpty) return fragment;

  // Keep hash routes such as #/login?source=email, removing only auth fields.
  final route = Uri.parse(fragment);
  if (fragment.startsWith('/') && route.hasQuery) {
    return _withParameters(
      route,
      _withoutAuthParameters(route.queryParametersAll),
      route.fragment,
    ).toString();
  }

  final raw = fragment.startsWith('/') ? fragment.substring(1) : fragment;
  final parameters = Uri(query: raw).queryParametersAll;
  final cleaned = _withoutAuthParameters(parameters);
  if (cleaned.length == parameters.length) return fragment;
  return cleaned.isEmpty ? '' : Uri(queryParameters: cleaned).query;
}

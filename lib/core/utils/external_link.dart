import 'external_link/external_link_stub.dart'
    if (dart.library.html) 'external_link/external_link_web.dart' as implementation;

Future<bool> openExternalLink(String url) => implementation.openExternalLink(url);

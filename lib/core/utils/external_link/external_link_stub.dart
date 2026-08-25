import 'package:flutter/services.dart';

Future<bool> openExternalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return false;
  }
  await Clipboard.setData(ClipboardData(text: uri.toString()));
  return false;
}

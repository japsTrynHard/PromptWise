import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalLink(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    return false;
  }

  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return true;
    }
  } on PlatformException {
    // Fall through to the recoverable clipboard behavior below.
  }

  try {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
  } on PlatformException {
    // The caller still receives false and can show its normal fallback message.
  }
  return false;
}

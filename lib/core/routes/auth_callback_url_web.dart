import 'dart:ui_web' as ui_web;

void replaceBrowserUrl(String url) {
  const location = ui_web.BrowserPlatformLocation();
  location.replaceState(location.state, '', url);
}

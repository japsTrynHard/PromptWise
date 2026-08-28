import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web bootstrap declares one device-width viewport', () {
    final source = File('web/index.html').readAsStringSync();
    final viewportTags = RegExp(
      r'<meta\s+[^>]*name=["\u0027]viewport["\u0027][^>]*>',
      caseSensitive: false,
      multiLine: true,
    ).allMatches(source).toList(growable: false);

    expect(viewportTags, hasLength(1));
    final viewport = viewportTags.single.group(0)!;
    expect(viewport, contains('width=device-width'));
    expect(viewport, contains('initial-scale=1.0'));
  });
}

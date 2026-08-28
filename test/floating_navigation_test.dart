import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/presentation/widgets/floating_glass_navigation.dart';

void main() {
  test('scroll behavior ignores jitter and uses asymmetric thresholds', () {
    final behavior = FloatingNavigationScrollBehavior();

    for (var index = 0; index < 12; index++) {
      expect(
        behavior.update(pixels: 100, delta: index.isEven ? 0.5 : -0.5),
        isFalse,
      );
    }
    expect(behavior.minimized, isFalse);

    expect(behavior.update(pixels: 100, delta: 12), isFalse);
    expect(behavior.update(pixels: 112, delta: 12), isFalse);
    expect(behavior.update(pixels: 124, delta: 8), isTrue);
    expect(behavior.minimized, isTrue);

    expect(behavior.update(pixels: 116, delta: -8), isFalse);
    expect(behavior.update(pixels: 108, delta: -8), isTrue);
    expect(behavior.minimized, isFalse);
  });

  test('scroll behavior always restores near the top', () {
    final behavior = FloatingNavigationScrollBehavior();
    behavior.update(pixels: 100, delta: 32);
    expect(behavior.minimized, isTrue);

    expect(behavior.update(pixels: 18, delta: 0), isTrue);
    expect(behavior.minimized, isFalse);
  });

  testWidgets('minimized navigation remains visible, safe, and interactive', (
    tester,
  ) async {
    var selected = -1;
    const destinations = [
      GlassNavDestination(
        label: 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
      ),
      GlassNavDestination(
        label: 'Learn',
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book_rounded,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47, bottom: 34),
            viewPadding: EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: FloatingGlassNavigation(
                selectedIndex: 0,
                destinations: destinations,
                minimized: true,
                onSelected: (index) => selected = index,
              ),
            ),
          ),
        ),
      ),
    );

    final padding = tester.widget<AnimatedPadding>(
      find.byKey(const Key('floating-navigation-safe-padding')),
    );
    expect((padding.padding as EdgeInsets).bottom, 39);

    final opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity).first,
    );
    expect(opacity.opacity, 0.86);

    await tester.tap(find.byTooltip('Learn'));
    expect(selected, 1);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:promptwise/presentation/controllers/theme_controller.dart';
import 'package:promptwise/presentation/screens/admin/admin_dashboard_screen.dart';
import 'package:promptwise/presentation/widgets/admin_appearance_menu.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final compact in [false, true]) {
    testWidgets(
      'admin appearance switches modes and persists (compact: $compact)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = ThemeController();
        addTearDown(controller.dispose);
        await controller.init();
        await _mount(tester, controller, compact: compact);
        await _choose(tester, 'Dark');
        expect(controller.themeMode, ThemeMode.dark);
        expect(
          Theme.of(
            tester.element(find.byKey(const ValueKey('appearance-probe'))),
          ).brightness,
          Brightness.dark,
        );
        final restored = ThemeController();
        addTearDown(restored.dispose);
        await restored.init();
        expect(restored.themeMode, ThemeMode.dark);
        await _choose(tester, 'Light');
        expect(controller.themeMode, ThemeMode.light);
        expect(
          Theme.of(
            tester.element(find.byKey(const ValueKey('appearance-probe'))),
          ).brightness,
          Brightness.light,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'System follows device brightness while explicit Light overrides it',
    (tester) async {
      final controller = ThemeController();
      addTearDown(controller.dispose);
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await controller.init();
      await _mount(tester, controller);
      await _choose(tester, 'System');
      expect(controller.themeMode, ThemeMode.system);
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('appearance-probe'))),
        ).brightness,
        Brightness.dark,
      );
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('appearance-probe'))),
        ).brightness,
        Brightness.light,
      );
      final restored = ThemeController();
      addTearDown(restored.dispose);
      await restored.init();
      expect(restored.themeMode, ThemeMode.system);
      await _choose(tester, 'Light');
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('appearance-probe'))),
        ).brightness,
        Brightness.light,
      );
    },
  );

  testWidgets('admin shell exposes appearance without a learner profile', (
    tester,
  ) async {
    final controller = ThemeController();
    addTearDown(controller.dispose);
    await controller.init();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: AdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await _choose(tester, 'Dark');
    expect(controller.themeMode, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(
  WidgetTester tester,
  ThemeController controller, {
  bool compact = true,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: theme.themeMode,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AdminAppearanceMenu(compact: compact),
                    const Text(
                      'Theme preview',
                      key: ValueKey('appearance-probe'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Appearance'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(PopupMenuItem<ThemeMode>),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

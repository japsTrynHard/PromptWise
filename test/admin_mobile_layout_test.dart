import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/presentation/controllers/content_automation_controller.dart';
import 'package:promptwise/presentation/controllers/content_controller.dart';
import 'package:promptwise/presentation/controllers/verification_controller.dart';
import 'package:promptwise/presentation/screens/admin/admin_content_management_screen.dart';
import 'package:promptwise/presentation/screens/admin/admin_learning_studio_screen.dart';
import 'package:promptwise/presentation/screens/admin/admin_verification_studio_screen.dart';
import 'package:provider/provider.dart';

void main() {
  for (final width in [320.0, 360.0, 400.0]) {
    testWidgets('Learning Studio fits a ${width.toInt()}px viewport', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 858);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ContentAutomationController();
      addTearDown(controller.dispose);
      await controller.bindAdministrator(true, userId: 'admin-test');

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const MaterialApp(home: AdminLearningStudioScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Continuous content automation'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final headingRect = tester.getRect(
        find.text('Continuous content automation'),
      );
      expect(headingRect.left, greaterThanOrEqualTo(0));
      expect(headingRect.right, lessThanOrEqualTo(width));

      await tester.scrollUntilVisible(
        find.text('Trusted sources'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Content Management fits a ${width.toInt()}px viewport', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 858);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ContentController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const MaterialApp(
            home: Scaffold(body: AdminContentManagementScreen()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Content management'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('No matching content'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Verification Studio fits a ${width.toInt()}px viewport', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 858);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final studio = VerificationStudioController();
      final automation = ContentAutomationController();
      addTearDown(studio.dispose);
      addTearDown(automation.dispose);
      await studio.bindAdministrator(true);
      await automation.bindAdministrator(true, userId: 'admin-test');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: studio),
            ChangeNotifierProvider.value(value: automation),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AdminVerificationStudioScreen()),
          ),
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Published verification case bank'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}

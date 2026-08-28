import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/presentation/controllers/adaptive_learning_controller.dart';
import 'package:promptwise/presentation/controllers/content_controller.dart';
import 'package:promptwise/presentation/controllers/learning_progression_controller.dart';
import 'package:promptwise/presentation/controllers/progress_controller.dart';
import 'package:promptwise/presentation/controllers/verification_controller.dart';
import 'package:promptwise/presentation/screens/user/learn_screen.dart';
import 'package:promptwise/presentation/screens/user/verify_screen.dart';
import 'package:provider/provider.dart';

void main() {
  for (final width in [320.0, 360.0, 400.0]) {
    testWidgets('Learn screen fits a ${width.toInt()}px viewport', (
      tester,
    ) async {
      await _setViewport(tester, width);

      final content = ContentController();
      final progress = ProgressController(
        lessonIds: const [],
        quizIds: const [],
      );
      final adaptive = AdaptiveLearningController();
      addTearDown(content.dispose);
      addTearDown(progress.dispose);
      addTearDown(adaptive.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: content),
            ChangeNotifierProvider.value(value: progress),
            ChangeNotifierProvider.value(value: adaptive),
          ],
          child: const MaterialApp(home: Scaffold(body: LearnScreen())),
        ),
      );
      await tester.pump();

      final dropdownFinder = find.byType(DropdownButtonFormField<String?>);
      expect(dropdownFinder, findsOneWidget);
      expect(tester.getRect(dropdownFinder).right, lessThanOrEqualTo(width));
      await tester.scrollUntilVisible(
        find.text('Learning modules'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Verify screen fits a ${width.toInt()}px viewport', (
      tester,
    ) async {
      await _setViewport(tester, width);

      final content = ContentController();
      final adaptive = AdaptiveLearningController();
      final verification = VerificationController();
      final progression = LearningProgressionController();
      addTearDown(content.dispose);
      addTearDown(adaptive.dispose);
      addTearDown(verification.dispose);
      addTearDown(progression.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: content),
            ChangeNotifierProvider.value(value: adaptive),
            ChangeNotifierProvider.value(value: verification),
            ChangeNotifierProvider.value(value: progression),
          ],
          child: const MaterialApp(home: Scaffold(body: VerifyScreen())),
        ),
      );
      await tester.pump();

      expect(find.text('Fresh online images'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Quick tips'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _setViewport(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

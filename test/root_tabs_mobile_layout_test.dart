import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/presentation/controllers/adaptive_learning_controller.dart';
import 'package:promptwise/presentation/controllers/auth_controller.dart';
import 'package:promptwise/presentation/controllers/awareness_feed_controller.dart';
import 'package:promptwise/presentation/controllers/content_controller.dart';
import 'package:promptwise/presentation/controllers/learning_progression_controller.dart';
import 'package:promptwise/presentation/controllers/progress_controller.dart';
import 'package:promptwise/presentation/controllers/theme_controller.dart';
import 'package:promptwise/presentation/screens/user/home_screen.dart';
import 'package:promptwise/presentation/screens/user/news_screen.dart';
import 'package:promptwise/presentation/screens/user/practice_screen.dart';
import 'package:promptwise/presentation/screens/user/profile_screen.dart';
import 'package:provider/provider.dart';

void main() {
  for (final width in [320.0, 400.0]) {
    testWidgets('Home tab fits and scrolls at ${width.toInt()}px', (
      tester,
    ) async {
      await _pumpRootTab(tester, width, const HomeScreen());
      await _scrollTo(
        tester,
        find.text(
          'Fresh trusted AI awareness updates will appear here when available.',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Practice tab fits and scrolls at ${width.toInt()}px', (
      tester,
    ) async {
      await _pumpRootTab(tester, width, const PracticeScreen());
      await _scrollTo(
        tester,
        find.text(
          'PromptWise prefers questions you have not seen recently, then brings older ones back later for review.',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Profile tab fits and scrolls at ${width.toInt()}px', (
      tester,
    ) async {
      await _pumpRootTab(tester, width, const ProfileScreen());
      await _scrollTo(tester, find.text('Help and support'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Awareness screen fits at ${width.toInt()}px', (tester) async {
      await _pumpRootTab(tester, width, const NewsScreen(), scaffold: false);
      expect(find.text('No matching updates yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpRootTab(
  WidgetTester tester,
  double width,
  Widget screen, {
  bool scaffold = true,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = AuthController();
  final awareness = AwarenessFeedController();
  final content = ContentController();
  final progress = ProgressController(lessonIds: const [], quizIds: const []);
  final adaptive = AdaptiveLearningController();
  final progression = LearningProgressionController();
  final theme = ThemeController();
  addTearDown(auth.dispose);
  addTearDown(awareness.dispose);
  addTearDown(content.dispose);
  addTearDown(progress.dispose);
  addTearDown(adaptive.dispose);
  addTearDown(progression.dispose);
  addTearDown(theme.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: awareness),
        ChangeNotifierProvider.value(value: content),
        ChangeNotifierProvider.value(value: progress),
        ChangeNotifierProvider.value(value: adaptive),
        ChangeNotifierProvider.value(value: progression),
        ChangeNotifierProvider.value(value: theme),
      ],
      child: MaterialApp(home: scaffold ? Scaffold(body: screen) : screen),
    ),
  );
  await tester.pump();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

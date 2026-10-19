import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:promptwise/core/utils/constants.dart';
import 'package:promptwise/data/models/content_automation.dart';
import 'package:promptwise/data/models/learning_topic.dart';
import 'package:promptwise/data/models/verification.dart';
import 'package:promptwise/presentation/controllers/awareness_feed_controller.dart';
import 'package:promptwise/presentation/controllers/content_automation_controller.dart';
import 'package:promptwise/presentation/controllers/verification_controller.dart';
import 'package:promptwise/presentation/screens/admin/admin_learning_studio_screen.dart';
import 'package:promptwise/presentation/screens/admin/admin_verification_studio_screen.dart';
import 'package:promptwise/presentation/widgets/draft_queue_widgets.dart';

void main() {
  setUpAll(() async {
    final fontPath = Platform.environment['STUDIO_PREVIEW_FONT'];
    if (fontPath == null) return;
    final textFont = FontLoader('StudioPreview')
      ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
    await textFont.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final width in [320.0, 1280.0]) {
    for (final verify in [false, true]) {
      testWidgets(
        '${verify ? 'Verify' : 'Learning'} draft timestamps and paging at $width px',
        (tester) async {
          _viewport(tester, width);
          final automation = _Automation(draftCount: 6);
          final studio = _Verification(draftCount: 6);
          final awareness = _Awareness();
          addTearDown(automation.dispose);
          addTearDown(studio.dispose);
          addTearDown(awareness.dispose);
          await _mount(tester, automation, studio, awareness, verify: verify);
          expect(find.byType(DraftTimestamp), findsNWidgets(5));
          expect(find.text('Generated draft 0'), findsOneWidget);
          expect(find.text('Generated draft 5'), findsNothing);
          await tester.ensureVisible(find.text('Generated draft 0'));
          await tester.pumpAndSettle();
          await _preview(
            tester,
            '${verify ? 'verify' : 'learning'}-drafts-${width.toInt()}',
          );
          await tester.ensureVisible(find.byTooltip('Next page'));
          await tester.pumpAndSettle();
          await _preview(
            tester,
            '${verify ? 'verify' : 'learning'}-pagination-${width.toInt()}',
          );
          await tester.tap(find.byTooltip('Next page'));
          await tester.pumpAndSettle();
          expect(find.text('Generated draft 5'), findsOneWidget);
          expect(find.text('Generated draft 0'), findsNothing);
          expect(find.text('Showing 6-6 of 6 loaded drafts'), findsOneWidget);
          expect(find.byType(DraftTimestamp), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        '${verify ? 'Verify' : 'Learning'} focus selection at $width px',
        (tester) async {
          _viewport(tester, width);
          final automation = _Automation();
          final studio = _Verification();
          final awareness = _Awareness();
          addTearDown(automation.dispose);
          addTearDown(studio.dispose);
          addTearDown(awareness.dispose);
          await _mount(tester, automation, studio, awareness, verify: verify);
          await _preview(
            tester,
            '${verify ? 'verify' : 'learning'}-${width.toInt()}',
          );
          final generate = find.widgetWithText(
            FilledButton,
            verify ? 'Choose topics to generate' : 'Generate drafts',
          );
          await tester.ensureVisible(generate);
          await tester.pumpAndSettle();
          await tester.tap(generate);
          await tester.pumpAndSettle();
          if (verify) {
            expect(find.text('Choose verification topics'), findsOneWidget);
            expect(automation.skills, isNull);
          }
          final submit = find
              .widgetWithText(FilledButton, 'Generate drafts')
              .last;
          expect(tester.widget<FilledButton>(submit).onPressed, isNull);
          final label = verify ? 'Citation verification' : 'Context';
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.text('1 selected'), findsOneWidget);
          await _preview(
            tester,
            '${verify ? 'verify' : 'learning'}-picker-${width.toInt()}',
          );
          await tester.tap(submit);
          await tester.pumpAndSettle();
          if (verify) {
            expect(automation.skills, [
              VerificationSubskill.citationVerification,
            ]);
          } else {
            expect(automation.topics, [LearningTopic.context]);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'cooldown is shown as generation status, not a data-load failure',
    (tester) async {
      _viewport(tester, 1280);
      final automation = _Automation(cooldown: true);
      final studio = _Verification();
      final awareness = _Awareness();
      addTearDown(automation.dispose);
      addTearDown(studio.dispose);
      addTearDown(awareness.dispose);
      await _mount(tester, automation, studio, awareness);
      expect(
        find.textContaining('This wait applies to all learning topics.'),
        findsOneWidget,
      );
      expect(
        find.text('Some Learning Studio data could not load'),
        findsNothing,
      );
      expect(find.text('Generation could not complete'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Ready in 30 min'),
            )
            .onPressed,
        isNull,
      );
      expect(automation.topics, isNull);
      await _preview(tester, 'learning-cooldown');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'picker cancellation makes no request and select-all can be cleared',
    (tester) async {
      _viewport(tester, 1280);
      final automation = _Automation();
      final studio = _Verification();
      final awareness = _Awareness();
      addTearDown(automation.dispose);
      addTearDown(studio.dispose);
      addTearDown(awareness.dispose);
      await _mount(tester, automation, studio, awareness);
      await tester.tap(find.widgetWithText(FilledButton, 'Generate drafts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('5 selected'), findsOneWidget);
      await tester.tap(find.text('Clear selection'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(automation.topics, isNull);
      expect(automation.skills, isNull);
    },
  );
}

void _viewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _mount(
  WidgetTester tester,
  _Automation automation,
  _Verification studio,
  _Awareness awareness, {
  bool verify = false,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ContentAutomationController>.value(
          value: automation,
        ),
        ChangeNotifierProvider<VerificationStudioController>.value(
          value: studio,
        ),
        ChangeNotifierProvider<AwarenessFeedController>.value(value: awareness),
      ],
      child: RepaintBoundary(
        key: const ValueKey('studio-preview'),
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: Platform.environment['STUDIO_PREVIEW_FONT'] == null
                ? null
                : 'StudioPreview',
            cardTheme: const CardThemeData(color: Colors.white, elevation: 0),
            colorScheme:
                ColorScheme.fromSeed(
                  seedColor: AppColors.primary,
                  surface: Colors.white,
                ).copyWith(
                  primary: AppColors.primary,
                  secondary: AppColors.teal,
                  error: AppColors.danger,
                ),
            scaffoldBackgroundColor: const Color(0xFFFAFAFC),
          ),
          home: Scaffold(
            body: verify
                ? const AdminVerificationStudioScreen()
                : const AdminLearningStudioScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Optional local screenshots for visual review; no golden baselines or network.
Future<void> _preview(WidgetTester tester, String name) async {
  final directory = Platform.environment['STUDIO_PREVIEW_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('studio-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
  });
}

class _Automation extends ContentAutomationController {
  final bool cooldown;
  final int draftCount;
  _Automation({this.cooldown = false, this.draftCount = 0});
  List<LearningTopic>? topics;
  List<VerificationSubskill>? skills;
  @override
  List<GeneratedContentDraft> get drafts => [
    for (var i = 0; i < draftCount; i++)
      GeneratedContentDraft.fromMap({
        'id': 'lesson-draft-$i',
        'title': 'Generated draft $i',
        'summary':
            'Help learners add clear context and audience details to an AI prompt.',
        'topic_id': 'context',
        'source_name': 'Trusted learning source',
        'created_at': DateTime.now()
            .subtract(Duration(days: i))
            .toIso8601String(),
      }),
  ];
  @override
  bool get isAdministrator => true;
  @override
  bool get hasLoaded => true;
  @override
  AutomationSettings get settings => AutomationSettings.fromMap({
    'enabled': true,
    'focus_topics': <String>[],
    if (cooldown) 'last_manual_run_at': DateTime.now().toIso8601String(),
  });
  @override
  String? get actionErrorMessage => cooldown
      ? 'Manual content checks have a cooldown. Try again in about 30 minutes.'
      : null;
  @override
  Future<bool> runNow(List<LearningTopic> focusTopics) async {
    topics = focusTopics;
    return true;
  }

  @override
  Future<bool> runVerificationDraftsNow({
    List<VerificationSubskill> focusSkills = const [],
  }) async {
    skills = focusSkills;
    return true;
  }
}

class _Verification extends VerificationStudioController {
  final int draftCount;
  _Verification({this.draftCount = 0});
  @override
  List<VerificationCaseDraft> get drafts => [
    for (var i = 0; i < draftCount; i++)
      VerificationCaseDraft.fromMap({
        'id': 'verify-draft-$i',
        'title': 'Generated draft $i',
        'summary':
            'Review the original source before accepting a claim about AI.',
        'subskill': 'source_verification',
        'source_name': 'Trusted awareness source',
        'created_at': DateTime.now()
            .subtract(Duration(days: i))
            .toIso8601String(),
      }),
  ];
  @override
  bool get isAdministrator => true;
  @override
  bool get hasLoaded => true;
  @override
  Future<void> refresh() async {}
}

class _Awareness extends AwarenessFeedController {
  @override
  Future<bool> ensureCurrentSources() async => true;
}

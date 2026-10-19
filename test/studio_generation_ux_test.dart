import 'dart:async';
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
import 'package:promptwise/presentation/widgets/studio_generation_widgets.dart';

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
        '${verify ? 'Published cases' : 'Approved questions'} approval dates and paging at $width px',
        (tester) async {
          _viewport(tester, width);
          final automation = _Automation(bankCount: 7);
          final studio = _Verification(bankCount: 7);
          final awareness = _Awareness();
          addTearDown(automation.dispose);
          addTearDown(studio.dispose);
          addTearDown(awareness.dispose);
          await _mount(tester, automation, studio, awareness, verify: verify);
          final kind = verify ? 'cases' : 'questions';
          expect(find.text('Showing 1-5 of 7 loaded $kind'), findsOneWidget);
          expect(find.text('Bank item 0'), findsOneWidget);
          expect(find.text('Bank item 5'), findsNothing);
          expect(find.text('Approval time unavailable'), findsOneWidget);
          expect(find.textContaining('Approved today at'), findsWidgets);
          await tester.ensureVisible(find.text('Bank item 0'));
          await tester.pumpAndSettle();
          await _preview(
            tester,
            '${verify ? 'cases' : 'questions'}-approval-${width.toInt()}',
          );
          await tester.ensureVisible(find.byTooltip('Next page'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Next page'));
          await tester.pumpAndSettle();
          expect(find.text('Showing 6-7 of 7 loaded $kind'), findsOneWidget);
          expect(find.text('Bank item 6'), findsOneWidget);
          final search = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                (verify
                    ? widget.decoration?.hintText == 'Search cases'
                    : widget.decoration?.labelText ==
                          'Search approved questions'),
          );
          await tester.ensureVisible(search);
          await tester.pumpAndSettle();
          await tester.enterText(search, 'Bank item 6');
          await tester.pumpAndSettle();
          expect(find.text('Showing 1-1 of 1 loaded $kind'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (widget) => widget is Text && widget.data == 'Bank item 6',
            ),
            findsOneWidget,
          );
          expect(find.text('Bank item 5'), findsNothing);
          await tester.enterText(search, 'no_such_bank_item');
          await tester.pumpAndSettle();
          expect(find.byTooltip('Next page'), findsNothing);
          await tester.enterText(search, '');
          await tester.pumpAndSettle();
          expect(find.text('Showing 1-5 of 7 loaded $kind'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

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
            'Choose topics to generate',
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

  for (final verify in [false, true]) {
    testWidgets('generation animation persists until completion in $verify', (
      tester,
    ) async {
      _viewport(tester, 1280);
      final pending = Completer<void>();
      final automation = _Automation(pending: pending);
      final studio = _Verification();
      final awareness = _Awareness();
      addTearDown(automation.dispose);
      addTearDown(studio.dispose);
      addTearDown(awareness.dispose);
      await _mount(tester, automation, studio, awareness, verify: verify);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Choose topics to generate'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(verify ? 'Citation verification' : 'Context'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Generate drafts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(StudioGenerationSpinner), findsOneWidget);
      expect(find.byType(StudioGenerationProgress), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Generating...'),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.binding.hasScheduledFrame, isTrue);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(StudioGenerationProgress), findsNothing);
      expect(find.byType(StudioGenerationSpinner), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 1280.0]) {
    for (final verify in [false, true]) {
      testWidgets(
        'tipid defaults and unlimited settings work at $width, verify=$verify',
        (tester) async {
          _viewport(tester, width);
          final automation = _Automation();
          final studio = _Verification();
          final awareness = _Awareness();
          addTearDown(automation.dispose);
          addTearDown(studio.dispose);
          addTearDown(awareness.dispose);
          await _mount(tester, automation, studio, awareness, verify: verify);
          final settingsButton = find.text('Automation settings');
          await tester.ensureVisible(settingsButton);
          await tester.tap(settingsButton);
          await tester.pumpAndSettle();
          if (verify) {
            final monthly = find.widgetWithText(
              TextFormField,
              'Monthly Verify draft cap',
            );
            await tester.ensureVisible(monthly);
            await tester.enterText(monthly, '');
            final unlimited = find.widgetWithText(
              SwitchListTile,
              'Unlimited generation',
            );
            await tester.ensureVisible(unlimited);
            await tester.tap(unlimited);
            await tester.pumpAndSettle();
            expect(tester.widget<TextFormField>(monthly).enabled, isFalse);
            await tester.tap(find.text('Save settings'));
            await tester.pumpAndSettle();
            expect(studio.unlimitedSaved, isTrue);
            expect(find.text('Unlimited'), findsNWidgets(2));
            await tester.ensureVisible(settingsButton);
            await tester.tap(settingsButton);
            await tester.pumpAndSettle();
          } else {
            final cooldown = find.widgetWithText(
              TextFormField,
              'Manual generation cooldown',
            );
            await tester.ensureVisible(cooldown);
            await tester.enterText(cooldown, '0');
          }
          await tester.tap(find.text('Restore tipid defaults'));
          await tester.pumpAndSettle();
          final cooldown = find.widgetWithText(
            TextFormField,
            verify
                ? 'Manual successful-run cooldown'
                : 'Manual generation cooldown',
          );
          expect(
            tester.widget<TextFormField>(cooldown).controller!.text,
            verify ? '15' : '30',
          );
          if (verify) {
            expect(
              tester
                  .widget<SwitchListTile>(
                    find.widgetWithText(SwitchListTile, 'Unlimited generation'),
                  )
                  .value,
              isFalse,
            );
            expect(
              studio.unlimitedSaved,
              isTrue,
            ); // Not saved until explicitly submitted.
          } else {
            expect(automation.savedCooldown, isNull);
            final topic = find.widgetWithText(CheckboxListTile, 'Context');
            await tester.ensureVisible(topic);
            await tester.tap(topic);
          }
          await tester.tap(find.text('Save settings'));
          await tester.pumpAndSettle();
          expect(
            verify ? studio.unlimitedSaved : automation.savedCooldown == 0,
            isFalse,
          );
          if (!verify) expect(automation.savedCooldown, 30);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('zero cooldown can be saved during an existing wait', (
    tester,
  ) async {
    _viewport(tester, 1280);
    final automation = _Automation(cooldown: true);
    final studio = _Verification();
    final awareness = _Awareness();
    addTearDown(automation.dispose);
    addTearDown(studio.dispose);
    addTearDown(awareness.dispose);
    await _mount(tester, automation, studio, awareness);
    await tester.tap(find.text('Automation settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Context'));
    final field = find.widgetWithText(
      TextFormField,
      'Manual generation cooldown',
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    for (final invalid in ['-1', '1441']) {
      await tester.enterText(field, invalid);
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a whole number from 0 to 1440.'), findsOneWidget);
      expect(automation.savedCooldown, isNull);
    }
    await tester.enterText(field, '0');
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(automation.savedCooldown, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Choose topics to generate'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

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
      await tester.tap(
        find.widgetWithText(FilledButton, 'Choose topics to generate'),
      );
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

  testWidgets(
    'Verify partial success stays in Verify and is not a total-failure banner',
    (tester) async {
      _viewport(tester, 1280);
      final automation = _Automation(partialVerifyWarning: true);
      final studio = _Verification();
      final awareness = _Awareness();
      addTearDown(automation.dispose);
      addTearDown(studio.dispose);
      addTearDown(awareness.dispose);
      await _mount(tester, automation, studio, awareness, verify: true);
      expect(
        find.text('Drafts saved; some requests need retry'),
        findsOneWidget,
      );
      expect(find.text('Generation could not complete'), findsNothing);
      await _mount(tester, automation, studio, awareness);
      expect(find.text('Drafts saved; some requests need retry'), findsNothing);
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
  final Completer<void>? pending;
  String? activeScope;
  bool running = false;
  int? savedCooldown;
  @override
  bool get isMutating => running;
  Future<void> hold(String scope) async {
    if (pending == null) return;
    activeScope = scope;
    running = true;
    notifyListeners();
    await pending!.future;
    running = false;
    notifyListeners();
  }

  @override
  Future<bool> saveSettings({
    int? manualCooldownMinutes,
    required bool enabled,
    required int maxArticlesPerRun,
    required int maxDraftsPerDay,
    required int monthlyDraftCap,
    required int maxPendingDrafts,
    required int maxPendingQuestions,
    required int draftArchiveDays,
    required List<LearningTopic> focusTopics,
  }) async {
    savedCooldown = manualCooldownMinutes;
    notifyListeners();
    return true;
  }

  final bool partialVerifyWarning;
  final bool cooldown;
  final int draftCount;
  final int bankCount;
  _Automation({
    this.pending,
    this.cooldown = false,
    this.draftCount = 0,
    this.bankCount = 0,
    this.partialVerifyWarning = false,
  });
  @override
  String? get warningMessage => partialVerifyWarning
      ? '4 drafts saved for review. Retry remaining topics later.'
      : null;
  @override
  String? get generationScope =>
      activeScope ?? (partialVerifyWarning ? 'verification' : null);
  @override
  List<QuestionBankReviewItem> get approvedQuestions => [
    for (var i = 0; i < bankCount; i++)
      QuestionBankReviewItem.fromMap({
        'id': 'approved-question-$i',
        'stem': 'Bank item $i',
        'topic_id': 'context',
        'status': 'published',
        'validation_status': 'verified',
        'options': ['One', 'Two', 'Three', 'Four'],
        'correct_index': 1,
        if (i > 0) 'approved_at': DateTime.now().toIso8601String(),
      }),
  ];
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
    if (savedCooldown != null) 'manual_cooldown_minutes': savedCooldown,
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
    await hold('learning');
    return true;
  }

  @override
  Future<bool> runVerificationDraftsNow({
    List<VerificationSubskill> focusSkills = const [],
  }) async {
    skills = focusSkills;
    await hold('verification');
    return true;
  }
}

class _Verification extends VerificationStudioController {
  VerificationAutomationOverview? savedOverview;
  bool get unlimitedSaved => savedOverview?.unlimitedGeneration ?? false;
  @override
  VerificationAutomationOverview get automationOverview =>
      savedOverview ?? super.automationOverview;
  @override
  Future<bool> saveAutomationSettings({
    bool unlimitedGeneration = false,
    required bool enabled,
    required int maxArticlesPerRun,
    required int maxDraftsPerRun,
    required int maxDraftsPerDay,
    required int monthlyDraftCap,
    required int monthlyGroqRequestCap,
    required int maxPendingDrafts,
    required int manualCooldownMinutes,
  }) async {
    savedOverview = VerificationAutomationOverview.fromMap({
      'settings': {
        'enabled': enabled,
        'unlimited_generation': unlimitedGeneration,
        'max_articles_per_run': maxArticlesPerRun,
        'max_drafts_per_run': maxDraftsPerRun,
        'max_drafts_per_day': maxDraftsPerDay,
        'monthly_draft_cap': monthlyDraftCap,
        'monthly_groq_request_cap': monthlyGroqRequestCap,
        'max_pending_drafts': maxPendingDrafts,
        'manual_cooldown_minutes': manualCooldownMinutes,
      },
    });
    notifyListeners();
    return true;
  }

  final int draftCount;
  final int bankCount;
  _Verification({this.draftCount = 0, this.bankCount = 0});
  @override
  List<VerificationCase> get cases => [
    for (var i = 0; i < bankCount; i++)
      VerificationCase.fromMap({
        'id': 'published-case-$i',
        'title': 'Bank item $i',
        'scenario': 'Check the source behind this AI claim.',
        'subskill': 'claim_verification',
        'correct_decision': 'supported',
        'explanation': 'The documented evidence supports the claim.',
        if (i > 0) 'approved_at': DateTime.now().toIso8601String(),
      }),
  ];
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

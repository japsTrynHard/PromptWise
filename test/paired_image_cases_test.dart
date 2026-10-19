import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:promptwise/data/models/image_comparison.dart';
import 'package:promptwise/presentation/controllers/adaptive_learning_controller.dart';
import 'package:promptwise/presentation/controllers/image_comparison_controller.dart';
import 'package:promptwise/presentation/controllers/image_round_readiness.dart';
import 'package:promptwise/presentation/controllers/learning_progression_controller.dart';
import 'package:promptwise/presentation/controllers/progress_controller.dart';
import 'package:promptwise/presentation/controllers/verification_controller.dart';
import 'package:promptwise/presentation/screens/user/image_compare_screen.dart';

void main() {
  testWidgets(
    'broken images recover on retry without scoring or changing rounds',
    (tester) async {
      final images = await _mountScreen(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('An image could not load'), findsOneWidget);

      await tester.tap(find.text('Retry images'));
      // Eviction finishes before rebuilding the retried images. Supply decoded
      // frames for the same URLs, simulating restored image availability.
      await _primeImagesForSets(tester, const [0]);
      await tester.pumpAndSettle();
      expect(find.text('This online image could not load.'), findsNothing);
      expect(find.text('Round 1 of 5'), findsOneWidget);
      expect(find.text('0 / 5'), findsOneWidget);
      expect(images.calls, 0);
      for (final button in tester.widgetList<FilledButton>(
        find.widgetWithText(FilledButton, 'Pick this'),
      )) {
        expect(button.onPressed, isNotNull);
      }
      await tester.tap(find.text('Pick this').first);
      expect(images.calls, 1);
      images.finish();
      await tester.pumpAndSettle();
      expect(find.text('1 / 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable image source supports retry and return to Verify', (
    tester,
  ) async {
    final images = _UnavailableImages();
    await _mountScreen(tester, images: images, useEntryRoute: true);
    expect(find.text('Fresh images could not load'), findsOneWidget);
    expect(find.text('Pick this'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(images.retries, 1);
    expect(find.text('Fresh images could not load'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Verify'));
    await tester.pumpAndSettle();
    expect(find.text('Open comparison'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'TC_IMAGE_POS_001-005: five valid rounds score once, show sources, and reset',
    (tester) async {
      // The old test used broken network images and still expected submission.
      // Prime the image cache with genuinely decoded frames instead.
      await _primeImagesForSets(tester, const [0, 1]);
      final images = await _mountScreen(tester);

      expect(find.text('Round 1 of 5'), findsOneWidget);
      expect(find.text('0 / 5'), findsOneWidget);
      expect(find.text('This online image could not load.'), findsNothing);

      for (var i = 0; i < 5; i++) {
        // One deliberately incorrect answer followed by four correct answers.
        final pick = find.text('Pick this').at(i == 0 ? 1 : 0);
        final button = tester.widget<FilledButton>(
          find.ancestor(of: pick, matching: find.byType(FilledButton)).first,
        );
        expect(button.onPressed, isNotNull);

        await tester.tap(pick);
        await tester.tap(pick); // Rapid duplicate tap must not submit twice.
        await tester.pump();
        expect(images.calls, i + 1);

        images.finish();
        await tester.pumpAndSettle();
        expect(find.text('Source for round $i'), findsOneWidget);
        expect(find.text('${i == 0 ? 0 : i} / 5'), findsOneWidget);

        final next = find.text(i == 4 ? 'See results' : 'Next image');
        await tester.ensureVisible(next);
        await tester.tap(next);
        if (i < 4) await tester.tap(next); // Navigation must not skip a round.
        await tester.pumpAndSettle();
        if (i < 4) {
          expect(find.text('Round ${i + 2} of 5'), findsOneWidget);
        }
      }

      expect(find.text('Image set complete'), findsOneWidget);
      expect(find.textContaining('4 of 5 correct'), findsOneWidget);

      await tester.tap(find.text('Try another set'));
      await tester.pumpAndSettle();
      expect(images.setNumber, 1);
      expect(find.text('Round 1 of 5'), findsOneWidget);
      expect(find.text('0 / 5'), findsOneWidget);
      expect(find.text('Pick this'), findsNWidgets(2));
      expect(images.calls, 5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TC_IMAGE_NEG_004: broken images block answers and offer recovery',
    (tester) async {
      // Only B is available: the PDF's exact one-broken-image scenario must
      // disable both choices, even though one image rendered successfully.
      await _primeImagesForSets(tester, const [0], sides: const ['b']);
      final images = await _mountScreen(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.text('This online image could not load.'), findsOneWidget);
      expect(find.text('An image could not load'), findsOneWidget);
      expect(find.text('Round 1 of 5'), findsOneWidget);
      expect(find.text('0 / 5'), findsOneWidget);
      expect(images.calls, 0);

      // The button can remain visible, but MUST be disabled when images fail.
      final pickButtons = tester.widgetList<FilledButton>(
        find.widgetWithText(FilledButton, 'Pick this'),
      );
      expect(pickButtons.length, 2);
      for (final button in pickButtons) {
        expect(button.onPressed, isNull);
      }

      expect(find.text('Retry images'), findsOneWidget);
      await tester.tap(find.text('Try another set'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(images.setNumber, 1);
      expect(find.text('Round 1 of 5'), findsOneWidget);
      expect(find.text('0 / 5'), findsOneWidget);
      expect(images.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_Images> _mountScreen(
  WidgetTester tester, {
  _Images? images,
  bool useEntryRoute = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  images ??= _Images();
  final progress = ProgressController(lessonIds: [], quizIds: []);
  final adaptive = AdaptiveLearningController();
  final progression = LearningProgressionController();
  final verification = VerificationController();

  for (final controller in [
    images,
    progress,
    adaptive,
    progression,
    verification,
  ]) {
    addTearDown(controller.dispose);
  }
  await progress.init();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ImageComparisonController>.value(value: images),
        ChangeNotifierProvider.value(value: progress),
        ChangeNotifierProvider.value(value: adaptive),
        ChangeNotifierProvider.value(value: progression),
        ChangeNotifierProvider.value(value: verification),
      ],
      child: MaterialApp(
        home: useEntryRoute
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ImageCompareScreen(),
                      ),
                    ),
                    child: const Text('Open comparison'),
                  ),
                ),
              )
            : const ImageCompareScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (useEntryRoute) {
    await tester.tap(find.text('Open comparison'));
    await tester.pumpAndSettle();
  }
  return images;
}

class _UnavailableImages extends _Images {
  int retries = 0;

  @override
  List<ImageComparisonRound> get rounds => const [];

  @override
  String? get errorMessage => 'The image source is unavailable. Please retry.';

  @override
  Future<bool> ensureRounds({int count = 5}) async => false;

  @override
  Future<bool> loadFreshRounds({int count = 5}) async {
    retries++;
    notifyListeners();
    return false;
  }
}

Future<void> _primeImagesForSets(
  WidgetTester tester,
  List<int> sets, {
  List<String> sides = const ['a', 'b'],
}) async {
  // NetworkImage is unchanged in production. Provide decoded test images in
  // Flutter's image cache so the test exercises the valid-image path offline.
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() => picture.toImage(2, 2));
  picture.dispose();
  if (image == null) {
    throw StateError('Could not create image fixture.');
  }

  addTearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    image.dispose();
  });

  for (final set in sets) {
    for (var i = 0; i < 5; i++) {
      for (final side in sides) {
        final url = 'https://example.test/$set/$side$i.jpg';
        PaintingBinding.instance.imageCache.putIfAbsent(
          NetworkImage(url),
          () => OneFrameImageStreamCompleter(
            Future<ImageInfo>.value(ImageInfo(image: image.clone())),
          ),
        );
      }
    }
  }
}

class _Images extends ImageComparisonController {
  int setNumber = 0;
  int calls = 0;
  Completer<ImageComparisonAttemptResult>? pending;
  String? roundId;
  String? side;

  @override
  List<ImageComparisonRound> get rounds => [
    for (var i = 0; i < 5; i++)
      ImageComparisonRound(
        id: 'set-$setNumber-round-$i',
        topic: 'AI images',
        question: 'Choose the source-labeled AI image.',
        hint: 'Inspect the source.',
        imageA: ImageComparisonSource(
          id: 'a$i',
          imageUrl: 'https://example.test/$setNumber/a$i.jpg',
        ),
        imageB: ImageComparisonSource(
          id: 'b$i',
          imageUrl: 'https://example.test/$setNumber/b$i.jpg',
        ),
      ),
  ];

  @override
  Future<bool> ensureRounds({int count = 5}) async => true;

  @override
  Future<bool> loadFreshRounds({int count = 5}) async {
    setNumber++;
    notifyListeners();
    return true;
  }

  @override
  Future<ImageComparisonAttemptResult?> submitAttempt({
    required String roundId,
    required String selectedSide,
    required ImageRoundReadiness readiness,
  }) {
    // Match the updated controller signature and enforce its safety condition.
    if (!readiness.canSubmit || readiness.roundId != roundId) {
      return Future<ImageComparisonAttemptResult?>.value(null);
    }
    calls++;
    this.roundId = roundId;
    side = selectedSide;
    pending = Completer<ImageComparisonAttemptResult>();
    return pending!.future;
  }

  void finish() => pending!.complete(
    ImageComparisonAttemptResult.fromMap({
      'round_id': roundId,
      'selected_side': side,
      'correct_side': 'A',
      'is_correct': side == 'A',
      'explanation': 'The source identifies image A as AI-made.',
      'correct_source': {
        'title': 'Source for round ${calls - 1}',
        'source_page_url': 'https://example.test/source',
        'creator': 'Test creator',
        'license': 'CC BY',
      },
    }),
  );
}

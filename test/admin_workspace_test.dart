import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:promptwise/core/utils/constants.dart';
import 'package:promptwise/data/models/app_profile.dart';
import 'package:promptwise/data/models/content_item.dart';
import 'package:promptwise/data/models/learning_topic.dart';
import 'package:promptwise/presentation/controllers/content_controller.dart';
import 'package:promptwise/presentation/screens/admin/admin_content_insights.dart';
import 'package:promptwise/presentation/screens/admin/admin_content_management_screen.dart';
import 'package:promptwise/presentation/screens/admin/admin_workspace_pages.dart';
import 'package:promptwise/presentation/widgets/admin_record_browser.dart';

class _Content extends ContentController {
  final List<ContentItem> records;
  int refreshes = 0;
  _Content(this.records);
  @override
  List<ContentItem> get items => records;
  @override
  Future<void> refresh({bool force = true}) async {
    refreshes++;
  }
}

List<ContentItem> _items() => List.generate(
  16,
  (i) => ContentItem(
    id: 'content-$i',
    type: i == 15 ? ContentType.activity : ContentType.lesson,
    title: 'Lesson ${i.toString().padLeft(2, '0')}',
    body: 'A complete editable lesson.',
    description: 'Description $i',
    adaptiveTopic: i == 14 ? null : LearningTopic.context,
    status: i == 13 ? ContentStatus.draft : ContentStatus.published,
    updatedAt: DateTime(2026, 10, 19, 12, i),
    reviewDate: i == 0 ? DateTime(2020) : null,
  ),
);
List<AppProfile> _profiles() => List.generate(
  16,
  (i) => AppProfile(
    id: 'account-$i',
    email: 'person$i@example.com',
    fullName: 'Person ${i.toString().padLeft(2, '0')}',
    role: i == 15 ? AppRole.administrator : AppRole.learner,
    createdAt: DateTime(2026, 9, 1 + i),
  ),
);

Future<void> _mount(
  WidgetTester tester,
  Widget page,
  double width, {
  bool dark = false,
  _Content? content,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = content ?? _Content(_items());
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ContentController>.value(
      value: controller,
      child: MaterialApp(
        theme: ThemeData(
          fontFamily: Platform.environment['ADMIN_PREVIEW_FONT'] == null
              ? null
              : 'AdminPreview',
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('admin-preview'),
            child: ColoredBox(
              color: dark ? const Color(0xff080d18) : const Color(0xfffafafc),
              child: page,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 10000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _preview(WidgetTester tester, String name) async {
  final directory = Platform.environment['ADMIN_PREVIEW_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('admin-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });
  setUpAll(() async {
    final path = Platform.environment['ADMIN_PREVIEW_FONT'];
    if (path == null) return;
    await (FontLoader(
      'AdminPreview',
    )..addFont(File(path).readAsBytes().then(ByteData.sublistView))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test(
    'review priorities use calendar dates and exclude drafts and undated content',
    () {
      final now = DateTime(2026, 10, 19, 8);
      final item = _items().first;
      expect(
        contentReviewDue(
          item.copyWith(reviewDate: DateTime(2026, 10, 19, 23)),
          now,
        ),
        true,
      );
      expect(
        contentReviewDue(
          item.copyWith(reviewDate: DateTime(2026, 10, 20)),
          now,
        ),
        false,
      );
      expect(
        contentReviewDue(item.copyWith(status: ContentStatus.draft), now),
        false,
      );
      expect(
        contentReviewDue(item.copyWith(clearReviewDate: true), now),
        false,
      );
      expect(
        matchesContentAttention(
          _items()[14],
          ContentAttention.topicUnassigned,
          now,
        ),
        true,
      );
      expect(
        matchesContentAttention(_items()[15], ContentAttention.practice, now),
        true,
      );
    },
  );

  for (final width in [320.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('overview actions and layout $width dark=$dark', (
        tester,
      ) async {
        AdminContentFilter? selected;
        int? studio;
        final content = _Content(_items());
        await _mount(
          tester,
          AdminOverviewPage(
            onOpenContent: (filter) => selected = filter,
            onOpenStudio: (index) => studio = index,
          ),
          width,
          dark: dark,
          content: content,
        );
        await _preview(tester, 'overview-${width.toInt()}-$dark');
        await _tap(tester, find.text('Draft content'));
        expect(selected?.status, ContentStatus.draft);
        await _tap(tester, find.text('Practice activities'));
        expect(selected?.attention, ContentAttention.practice);
        await _tap(tester, find.text('Context'));
        expect(selected?.topic, LearningTopic.context);
        expect(selected?.type, ContentType.lesson);
        await _tap(tester, find.text('Open review queue'));
        expect(selected?.attention, ContentAttention.reviewDue);
        await _tap(tester, find.text('Learning Studio'));
        expect(studio, 2);
        await _tap(tester, find.text('Verification Studio'));
        expect(studio, 3);
        await _tap(tester, find.text('Refresh overview'));
        expect(content.refreshes, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'user directory paging search details and roles $width dark=$dark',
        (tester) async {
          int forced = 0;
          await _mount(
            tester,
            AdminUsersPage(
              loadProfiles: (force) async {
                if (force) forced++;
                return _profiles();
              },
            ),
            width,
            dark: dark,
          );
          await _preview(tester, 'users-${width.toInt()}-$dark');
          expect(find.text('Showing 1–10 of 16 accounts'), findsOneWidget);
          await _tap(tester, find.byTooltip('Next page'));
          expect(find.text('Showing 11–16 of 16 accounts'), findsOneWidget);
          await _tap(tester, find.text('Learner').first);
          expect(find.text('Showing 1–10 of 15 accounts'), findsOneWidget);
          final search = find.widgetWithText(TextField, 'Search users');
          await tester.ensureVisible(search);
          await tester.enterText(search, 'person4@example.com');
          await tester.pumpAndSettle();
          expect(find.text('Showing 1–1 of 1 accounts'), findsOneWidget);
          await _tap(tester, find.text('Person 04'));
          expect(find.text('Copy account ID'), findsOneWidget);
          expect(find.text('account-4'), findsOneWidget);
          await _tap(tester, find.text('Copy email'));
          expect(find.text('Email copied.'), findsOneWidget);
          await _tap(tester, find.text('Close'));
          await _tap(tester, find.byTooltip('Clear user search'));
          await _tap(tester, find.text('Refresh users'));
          expect(forced, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('content pagination filters reset and editor $width', (
      tester,
    ) async {
      await _mount(tester, const AdminContentManagementScreen(), width);
      await tester.scrollUntilVisible(
        find.text('Showing 1–10 of 16 content items'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _preview(tester, 'content-${width.toInt()}');
      await _tap(tester, find.byTooltip('Next page'));
      expect(find.text('Showing 11–16 of 16 content items'), findsOneWidget);
      await _tap(tester, find.text('Review due'));
      await _tap(tester, find.text('Showing 1–1 of 1 content items'));
      expect(find.text('Showing 1–1 of 1 content items'), findsOneWidget);
      expect(find.text('Lesson 00'), findsOneWidget);
      await _tap(tester, find.text('Topic unassigned'));
      await _tap(tester, find.text('Lesson 14'));
      expect(find.text('Lesson 14'), findsOneWidget);
      await _tap(tester, find.text('Reset filters'));
      await _tap(tester, find.text('Showing 1–10 of 16 content items'));
      expect(find.text('Showing 1–10 of 16 content items'), findsOneWidget);
      await _tap(tester, find.text('Drafts'));
      await _tap(tester, find.text('Showing 1–1 of 1 content items'));
      expect(find.text('Showing 1–1 of 1 content items'), findsOneWidget);
      expect(find.text('Lesson 13'), findsOneWidget);
      if (width > 900) {
        // The desktop table keeps less frequent actions in its horizontal area.
        await _tap(tester, find.byTooltip('Edit Lesson 13'));
      } else {
        await _tap(tester, find.byTooltip('Content actions'));
        await _tap(tester, find.text('Edit').last);
      }
      expect(find.text('Edit content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('overview filter arrives in the content browser', (tester) async {
    await _mount(
      tester,
      const AdminContentManagementScreen(
        initialFilter: AdminContentFilter(
          type: ContentType.lesson,
          topic: LearningTopic.context,
          status: ContentStatus.published,
        ),
      ),
      1280,
    );
    expect(find.text('Showing 1–10 of 13 content items'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('users error retry and zero matches recover', (tester) async {
    var calls = 0;
    await _mount(
      tester,
      AdminUsersPage(
        loadProfiles: (_) async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return _profiles();
        },
      ),
      1280,
    );
    await _tap(tester, find.text('Retry users'));
    final search = find.widgetWithText(TextField, 'Search users');
    await tester.enterText(search, 'not_a_real_account');
    await tester.pumpAndSettle();
    expect(find.text('No users match your filters.'), findsOneWidget);
    await _tap(tester, find.text('Reset user filters'));
    expect(find.text('Showing 1–10 of 16 accounts'), findsOneWidget);
  });

  testWidgets(
    'exact overview item targeting resets without trapping the filter',
    (tester) async {
      await _mount(
        tester,
        const AdminContentManagementScreen(
          initialFilter: AdminContentFilter(
            query: 'content-1',
            itemId: 'content-1',
          ),
        ),
        1280,
      );
      expect(find.text('Showing 1–1 of 1 content items'), findsOneWidget);
      expect(find.text('Lesson 01'), findsOneWidget);
      expect(find.text('Lesson 10'), findsNothing);
      await _tap(tester, find.text('Reset filters'));
      expect(find.text('Showing 1–10 of 16 content items'), findsOneWidget);
    },
  );

  testWidgets('user sort and page-size controls change the displayed records', (
    tester,
  ) async {
    await _mount(
      tester,
      AdminUsersPage(loadProfiles: (_) async => _profiles()),
      1280,
    );
    await _tap(tester, find.text('Newest profiles'));
    await _tap(tester, find.text('Name A–Z').last);
    expect(find.text('Person 00'), findsOneWidget);
    expect(find.text('Person 15'), findsNothing);
    await _tap(tester, find.byType(DropdownButton<int>));
    await _tap(tester, find.text('25').last);
    expect(find.text('Showing 1–16 of 16 accounts'), findsOneWidget);
    expect(find.text('Person 15'), findsOneWidget);
  });

  testWidgets('content sort and topic dropdown use the selected values', (
    tester,
  ) async {
    await _mount(tester, const AdminContentManagementScreen(), 1280);
    await _tap(tester, find.byType(DropdownButtonFormField<String>));
    await _tap(tester, find.text('Title A–Z').last);
    expect(find.text('Lesson 00'), findsOneWidget);
    expect(find.text('Lesson 15'), findsNothing);
    await _tap(tester, find.byType(DropdownButtonFormField<LearningTopic?>));
    await _tap(tester, find.text('Specificity').last);
    expect(find.text('No matching content'), findsOneWidget);
    await _tap(tester, find.text('Reset filters'));
    expect(find.text('Showing 1–10 of 16 content items'), findsOneWidget);
  });

  testWidgets('pagination clamps after removals and changes page size', (
    tester,
  ) async {
    var records = List.generate(26, (i) => i);
    late StateSetter update;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return ListView(
            children: [
              AdminRecordBrowser<int>(
                items: records,
                noun: 'records',
                builder: (page) => Text(page.join(',')),
              ),
            ],
          );
        },
      ),
      320,
    );
    await _tap(tester, find.byTooltip('Last page'));
    expect(find.text('Page 3 of 3'), findsOneWidget);
    update(() => records = [1]);
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 1'), findsOneWidget);
  });
}

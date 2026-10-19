import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/presentation/widgets/draft_queue_widgets.dart';

void main() {
  test(
    'approval labels use the approval event and leave unknown dates unavailable',
    () {
      final now = DateTime(2026, 10, 19, 22);
      expect(
        draftTimestampLabel(
          DateTime(2026, 10, 19, 21, 5),
          now: now,
          eventLabel: 'Approved',
        ),
        'Approved today at 9:05 PM',
      );
      expect(
        draftTimestampLabel(null, now: now, eventLabel: 'Approved'),
        'Approval time unavailable',
      );
    },
  );
  test(
    'generation dates distinguish today, yesterday, old, missing and future dates',
    () {
      final now = DateTime(2026, 10, 19, 22);
      expect(
        draftTimestampLabel(DateTime(2026, 10, 19, 21, 5), now: now),
        'Generated today at 9:05 PM',
      );
      expect(
        draftTimestampLabel(DateTime(2026, 10, 18, 0, 7), now: now),
        'Generated yesterday at 12:07 AM',
      );
      expect(
        draftTimestampLabel(DateTime(2026, 9, 2, 12), now: now),
        'Generated Sep 2, 2026 at 12:00 PM',
      );
      expect(
        draftTimestampLabel(DateTime(2026, 10, 20, 9), now: now),
        'Generated Oct 20, 2026 at 9:00 AM',
      );
      expect(
        draftTimestampLabel(null, now: now),
        'Generation time unavailable',
      );
      expect(
        draftTimestampLabel(
          DateTime(2026, 9, 30, 8),
          now: DateTime(2026, 10, 1),
        ),
        'Generated yesterday at 8:00 AM',
      );
    },
  );

  testWidgets(
    'pagination shows five drafts, navigation boundaries and page size',
    (tester) async {
      _viewport(tester, 800);
      await _mount(tester, List.generate(12, (i) => i));
      expect(find.text('Showing 1-5 of 12 loaded drafts'), findsOneWidget);
      expect(find.text('Draft 0'), findsOneWidget);
      expect(find.text('Draft 5'), findsNothing);
      expect(
        tester.widget<IconButton>(_pageButton('Previous page')).onPressed,
        isNull,
      );
      await tester.tap(_pageButton('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Showing 6-10 of 12 loaded drafts'), findsOneWidget);
      expect(find.text('Draft 5'), findsOneWidget);
      expect(find.text('Draft 0'), findsNothing);
      await tester.tap(_pageButton('Last page'));
      await tester.pumpAndSettle();
      expect(find.text('Showing 11-12 of 12 loaded drafts'), findsOneWidget);
      expect(
        tester.widget<IconButton>(_pageButton('Next page')).onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').last);
      await tester.pumpAndSettle();
      expect(find.text('Showing 1-10 of 12 loaded drafts'), findsOneWidget);
      expect(find.text('Draft 9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removal clamps the page and a newly generated draft resets to page one',
    (tester) async {
      _viewport(tester, 800);
      await _mount(tester, List.generate(11, (i) => i));
      await tester.tap(_pageButton('Last page'));
      await tester.pumpAndSettle();
      expect(find.text('Draft 10'), findsOneWidget);
      await _mount(tester, List.generate(10, (i) => i));
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(find.text('Draft 5'), findsOneWidget);
      await _mount(tester, [99, ...List.generate(10, (i) => i)]);
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.text('Draft 99'), findsOneWidget);
      await _mount(tester, []);
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact pager fits 320px and disables actions during mutation', (
    tester,
  ) async {
    _viewport(tester, 320);
    await _mount(tester, List.generate(6, (i) => i));
    await tester.tap(_pageButton('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.text('Draft 5'), findsOneWidget);
    await _mount(tester, List.generate(6, (i) => i), busy: true);
    expect(
      tester.widget<IconButton>(_pageButton('Previous page')).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .onChanged,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}

void _viewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _mount(
  WidgetTester tester,
  List<int> items, {
  bool busy = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: DraftQueue<int>(
            items: items,
            busy: busy,
            itemId: (item) => '$item',
            itemBuilder: (item) =>
                SizedBox(height: 48, child: Text('Draft $item')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _pageButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String verifyScreen;
  late String migration;

  setUpAll(() {
    verifyScreen = File(
      'lib/presentation/screens/user/verify_screen.dart',
    ).readAsStringSync();
    migration = File(
      'supabase/migrations/20260901120000_quick_check_rotation.sql',
    ).readAsStringSync();
  });

  test('Quick Check uses the Verification topic rank', () {
    expect(
      verifyScreen,
      contains('rankFor(LearningTopic.verification)'),
    );
    expect(
      verifyScreen,
      isNot(contains('rankLevel: progression.overallRank.level')),
    );
  });

  test('adaptive ranges include a controlled neighboring difficulty', () {
    for (final range in const [
      'v_rank = 1 and c.difficulty between 1 and 2',
      'v_rank = 2 and c.difficulty between 1 and 3',
      'v_rank = 3 and c.difficulty between 2 and 4',
      'v_rank = 4 and c.difficulty between 3 and 5',
      'v_rank = 5 and c.difficulty between 4 and 5',
    ]) {
      expect(migration, contains(range));
    }
  });

  test('served cases are exposed before the session payload is returned', () {
    final assignment = migration.indexOf(
      'insert into public.verification_session_cases',
    );
    final exposure = migration.indexOf(
      'insert into public.verification_case_exposure',
    );
    final response = migration.indexOf('select jsonb_build_object(');

    expect(assignment, greaterThanOrEqualTo(0));
    expect(exposure, greaterThan(assignment));
    expect(response, greaterThan(exposure));
    expect(
      migration,
      contains(
        'times_seen = public.verification_case_exposure.times_seen + 1',
      ),
    );
  });

  test('selection remains unique, least-recent first, and session-varied', () {
    expect(
      migration,
      contains('case when e.case_id is null then 0 else 1 end'),
    );
    expect(
      migration,
      contains("coalesce(e.last_seen_at, '1900-01-01'::timestamptz)"),
    );
    expect(migration, contains('md5(id::text || v_session::text)'));
    expect(
      migration,
      contains('select v_session, id, seq from chosen'),
    );
  });
}

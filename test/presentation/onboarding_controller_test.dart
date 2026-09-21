import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/data/repositories/onboarding_repository.dart';
import 'package:promptwise/presentation/controllers/onboarding_controller.dart';

class _FakeGateway implements OnboardingGateway {
  final Map<String, OrientationRecord> rows = {};
  Completer<OrientationRecord?>? pendingFetch;
  bool failFetch = false;
  bool failSave = false;
  String? lastCompletedUser;
  bool? lastWatched;

  @override
  Future<OrientationRecord?> fetch(String userId) async {
    final pending = pendingFetch;
    if (pending != null) return pending.future;
    if (failFetch) throw StateError('Offline');
    return rows[userId];
  }

  @override
  Future<OrientationRecord> complete(
    String userId, {
    required bool watched,
  }) async {
    if (failSave) throw StateError('Offline');
    lastCompletedUser = userId;
    lastWatched = watched;
    final previous = rows[userId];
    final row = OrientationRecord(
      completedAt: previous?.completedAt ?? DateTime.utc(2026, 9, 22),
      surveyCompletedAt: previous?.surveyCompletedAt,
      surveyExempt: previous?.surveyExempt ?? false,
      videoWatchedAt: watched
          ? previous?.videoWatchedAt ?? DateTime.utc(2026, 9, 22)
          : previous?.videoWatchedAt,
    );
    rows[userId] = row;
    return row;
  }
}

void main() {
  test('existing learner skips orientation without changing saved progress', () async {
    final gateway = _FakeGateway();
    gateway.rows['existing'] = OrientationRecord(
      completedAt: DateTime.utc(2026, 9, 22),
    );
    final controller = OnboardingController(repository: gateway);
    await controller.bindUser('existing');
    expect(controller.isReadyFor('existing'), true);
    expect(controller.orientationComplete, true);
    controller.dispose();
  });

  test('new account sees orientation then can continue without video', () async {
    final gateway = _FakeGateway();
    final controller = OnboardingController(repository: gateway);
    await controller.bindUser('new');
    expect(controller.isReadyFor('new'), true);
    expect(controller.orientationComplete, false);
    expect(await controller.completeOrientation(watched: false), true);
    expect(gateway.lastCompletedUser, 'new');
    expect(gateway.lastWatched, false);
    expect(controller.orientationComplete, true);
    expect(controller.videoWatched, false);
    controller.dispose();
  });

  test('replay preserves a previous watched timestamp', () async {
    final gateway = _FakeGateway();
    gateway.rows['user'] = OrientationRecord(
      completedAt: DateTime.utc(2026, 9, 22),
      videoWatchedAt: DateTime.utc(2026, 9, 22),
    );
    final controller = OnboardingController(repository: gateway);
    await controller.bindUser('user');
    expect(await controller.completeOrientation(watched: false), true);
    expect(controller.videoWatched, true);
    controller.dispose();
  });

  test('legacy exemption is preserved on video replay', () async {
    final gateway = _FakeGateway();
    gateway.rows['existing'] = OrientationRecord(
      completedAt: DateTime.utc(2026, 9, 22),
      surveyExempt: true,
    );
    final controller = OnboardingController(repository: gateway);
    await controller.bindUser('existing');
    expect(controller.surveyReady, true);
    expect(await controller.completeOrientation(watched: true), true);
    expect(controller.surveyReady, true);
    controller.dispose();
  });

  test('new learner still requires survey after orientation', () async {
    final controller = OnboardingController(repository: _FakeGateway());
    await controller.bindUser('new');
    expect(await controller.completeOrientation(watched: false), true);
    expect(controller.surveyReady, false);
    controller.dispose();
  });

  test('fetch failure blocks entry until retry succeeds', () async {
    final gateway = _FakeGateway()..failFetch = true;
    final controller = OnboardingController(repository: gateway);
    await controller.bindUser('user');
    expect(controller.isReadyFor('user'), false);
    expect(controller.errorMessage, isNotNull);
    gateway.failFetch = false;
    await controller.retry();
    expect(controller.isReadyFor('user'), true);
    controller.dispose();
  });

  test('save failure cannot mark orientation complete', () async {
    final gateway = _FakeGateway()..failSave = true;
    final controller = OnboardingController(repository: gateway);
    await controller.bindUser('user');
    expect(await controller.completeOrientation(watched: true), false);
    expect(controller.orientationComplete, false);
    expect(controller.isReadyFor('user'), true);
    expect(controller.errorMessage, isNotNull);
    controller.dispose();
  });

  test('account switch ignores late response from previous account', () async {
    final gateway = _FakeGateway();
    final stale = Completer<OrientationRecord?>();
    gateway.pendingFetch = stale;
    final controller = OnboardingController(repository: gateway);
    final oldLoad = controller.bindUser('old');
    gateway.pendingFetch = null;
    await controller.bindUser('new');
    stale.complete(OrientationRecord(completedAt: DateTime.utc(2026, 9, 22)));
    await oldLoad;
    expect(controller.activeUserId, 'new');
    expect(controller.orientationComplete, false);
    controller.dispose();
  });
}

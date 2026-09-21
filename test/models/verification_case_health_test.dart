import 'package:flutter_test/flutter_test.dart';

import 'package:promptwise/data/models/verification.dart';

VerificationCase _case({
  required String id,
  required String subskill,
  required int difficulty,
}) => VerificationCase.fromMap({
  'id': id,
  'case_code': 'CASE-$id',
  'title': 'Test case',
  'scenario': 'A claim needs verifying.',
  'subskill': subskill,
  'difficulty': difficulty,
  'correct_decision': 'supported',
  'explanation': 'Evidence supports this claim.',
});

void main() {
  test('published-case health counts by subskill and difficulty', () {
    final cases = [
      _case(id: '1', subskill: 'source_verification', difficulty: 1),
      _case(id: '2', subskill: 'source_verification', difficulty: 5),
      _case(id: '3', subskill: 'claim_verification', difficulty: 3),
    ];

    final result = VerificationCaseHealth.fromPublishedCases(cases);
    expect(result, hasLength(2));
    final sources = result.firstWhere(
      (health) => health.subskill == VerificationSubskill.sourceVerification,
    );
    final claims = result.firstWhere(
      (health) => health.subskill == VerificationSubskill.claimVerification,
    );
    expect(sources.publishedCases, 2);
    expect(sources.byLevel, {1: 1, 2: 0, 3: 0, 4: 0, 5: 1});
    expect(claims.publishedCases, 1);
    expect(claims.byLevel, {1: 0, 2: 0, 3: 1, 4: 0, 5: 0});
  });

  test('empty case bank yields an empty summary', () {
    expect(VerificationCaseHealth.fromPublishedCases([]), isEmpty);
  });
}

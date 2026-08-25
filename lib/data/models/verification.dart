import './learning_progression.dart';

enum VerificationSubskill {
  sourceVerification,
  claimVerification,
  mediaProvenance,
  manipulationDetection,
  citationVerification,
  uncertaintyJudgment,
}

extension VerificationSubskillX on VerificationSubskill {
  String get id => switch (this) {
        VerificationSubskill.sourceVerification => 'source_verification',
        VerificationSubskill.claimVerification => 'claim_verification',
        VerificationSubskill.mediaProvenance => 'media_provenance',
        VerificationSubskill.manipulationDetection => 'manipulation_detection',
        VerificationSubskill.citationVerification => 'citation_verification',
        VerificationSubskill.uncertaintyJudgment => 'uncertainty_judgment',
      };

  String get label => switch (this) {
        VerificationSubskill.sourceVerification => 'Source verification',
        VerificationSubskill.claimVerification => 'Claim verification',
        VerificationSubskill.mediaProvenance => 'Media provenance',
        VerificationSubskill.manipulationDetection => 'Manipulation detection',
        VerificationSubskill.citationVerification => 'Citation verification',
        VerificationSubskill.uncertaintyJudgment => 'Uncertainty judgment',
      };


  String get learnerLabel => switch (this) {
        VerificationSubskill.sourceVerification => 'Check the source',
        VerificationSubskill.claimVerification => 'Check the claim',
        VerificationSubskill.mediaProvenance => 'Where did it come from?',
        VerificationSubskill.manipulationDetection => 'Spot edits & AI',
        VerificationSubskill.citationVerification => 'Check references',
        VerificationSubskill.uncertaintyJudgment => 'Know when to say “not sure”',
      };

  String get learnerDescription => switch (this) {
        VerificationSubskill.sourceVerification =>
          'See who posted it and whether that source makes sense.',
        VerificationSubskill.claimVerification =>
          'Check if the evidence really supports what is being said.',
        VerificationSubskill.mediaProvenance =>
          'Look at where a photo, video, or audio clip came from.',
        VerificationSubskill.manipulationDetection =>
          'Notice signs that media may be edited or AI-made.',
        VerificationSubskill.citationVerification =>
          'Make sure references are real and actually support the claim.',
        VerificationSubskill.uncertaintyJudgment =>
          'Recognize when there is not enough information to be sure.',
      };
  String get shortDescription => switch (this) {
        VerificationSubskill.sourceVerification =>
          'Judge who published information and whether the source is appropriate.',
        VerificationSubskill.claimVerification =>
          'Check whether evidence actually supports a claim.',
        VerificationSubskill.mediaProvenance =>
          'Inspect origin, edit history, date, and context of media.',
        VerificationSubskill.manipulationDetection =>
          'Recognize edited, synthetic, or misleading media without relying on one clue.',
        VerificationSubskill.citationVerification =>
          'Confirm that cited sources exist and support what is being claimed.',
        VerificationSubskill.uncertaintyJudgment =>
          'Know when the available evidence is not strong enough for a confident conclusion.',
      };

  static VerificationSubskill? fromId(String? value) {
    final normalized = value?.trim().toLowerCase();
    for (final item in VerificationSubskill.values) {
      if (item.id == normalized) return item;
    }
    return null;
  }
}

enum VerificationCaseType { image, video, audio, claim, citation, scam }

extension VerificationCaseTypeX on VerificationCaseType {
  String get id => name;
  String get label => switch (this) {
        VerificationCaseType.image => 'Image',
        VerificationCaseType.video => 'Video',
        VerificationCaseType.audio => 'Audio',
        VerificationCaseType.claim => 'Claim',
        VerificationCaseType.citation => 'Citation',
        VerificationCaseType.scam => 'Scam',
      };

  static VerificationCaseType fromId(String? value) {
    return VerificationCaseType.values.firstWhere(
      (item) => item.id == value?.trim().toLowerCase(),
      orElse: () => VerificationCaseType.claim,
    );
  }
}

enum VerificationDecision {
  supported,
  aiGenerated,
  manipulated,
  misleadingContext,
  unsupportedClaim,
  unverified,
  insufficientEvidence,
}

extension VerificationDecisionX on VerificationDecision {
  String get id => switch (this) {
        VerificationDecision.supported => 'supported',
        VerificationDecision.aiGenerated => 'ai_generated',
        VerificationDecision.manipulated => 'manipulated',
        VerificationDecision.misleadingContext => 'misleading_context',
        VerificationDecision.unsupportedClaim => 'unsupported_claim',
        VerificationDecision.unverified => 'unverified',
        VerificationDecision.insufficientEvidence => 'insufficient_evidence',
      };

  String get label => switch (this) {
        VerificationDecision.supported => 'Looks genuine / supported',
        VerificationDecision.aiGenerated => 'AI-made',
        VerificationDecision.manipulated => 'Edited or altered',
        VerificationDecision.misleadingContext => 'Real, but misleading',
        VerificationDecision.unsupportedClaim => 'Claim is not supported',
        VerificationDecision.unverified => 'Cannot verify yet',
        VerificationDecision.insufficientEvidence => 'Not enough information',
      };

  static VerificationDecision? tryFromId(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final item in VerificationDecision.values) {
      if (item.id == normalized) return item;
    }
    return null;
  }

  static VerificationDecision fromId(String? value) =>
      tryFromId(value) ?? VerificationDecision.unverified;
}

enum VerificationConfidence { low, medium, high }

extension VerificationConfidenceX on VerificationConfidence {
  String get id => name;
  String get label => switch (this) {
        VerificationConfidence.low => 'Low',
        VerificationConfidence.medium => 'Medium',
        VerificationConfidence.high => 'High',
      };

  static VerificationConfidence fromId(String? value) {
    return VerificationConfidence.values.firstWhere(
      (item) => item.id == value?.trim().toLowerCase(),
      orElse: () => VerificationConfidence.medium,
    );
  }
}

class VerificationEvidence {
  final String code;
  final String label;
  final String detail;
  final String evidenceType;
  final bool isKey;
  final int sequence;

  const VerificationEvidence({
    required this.code,
    required this.label,
    required this.detail,
    required this.evidenceType,
    required this.isKey,
    required this.sequence,
  });

  factory VerificationEvidence.fromMap(Map<String, dynamic> map) =>
      VerificationEvidence(
        code: map['evidence_code']?.toString() ?? map['code']?.toString() ?? '',
        label: map['label']?.toString() ?? '',
        detail: map['detail']?.toString() ?? '',
        evidenceType: map['evidence_type']?.toString() ?? 'context',
        isKey: map['is_key'] == true,
        sequence: _asInt(map['sequence'], fallback: _asInt(map['sort_order'])),
      );
}

class VerificationAction {
  final String code;
  final String label;
  final String description;
  final bool useful;
  final List<String> revealsEvidenceCodes;
  final int sequence;

  const VerificationAction({
    required this.code,
    required this.label,
    required this.description,
    required this.useful,
    required this.revealsEvidenceCodes,
    required this.sequence,
  });

  factory VerificationAction.fromMap(Map<String, dynamic> map) =>
      VerificationAction(
        code: map['action_code']?.toString() ?? map['code']?.toString() ?? '',
        label: map['label']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        useful: map['useful'] == true,
        revealsEvidenceCodes: _stringList(map['reveals_evidence_codes']),
        sequence: _asInt(map['sequence'], fallback: _asInt(map['sort_order'])),
      );
}

class VerificationCase {
  final String id;
  final String code;
  final String title;
  final String scenario;
  final String claim;
  final VerificationCaseType caseType;
  final VerificationSubskill subskill;
  final QuestionDifficulty difficulty;
  final String mediaType;
  final String? mediaUrl;
  final String mediaDescription;
  final List<VerificationEvidence> evidence;
  final List<VerificationAction> actions;
  final List<String> sourceOptions;
  final VerificationDecision correctDecision;
  final VerificationConfidence expectedConfidence;
  final String explanation;
  final String learningPoint;
  final String sourceName;
  final String sourceUrl;
  final DateTime? sourcePublishedAt;
  final bool generated;
  final int sequence;

  const VerificationCase({
    required this.id,
    required this.code,
    required this.title,
    required this.scenario,
    required this.claim,
    required this.caseType,
    required this.subskill,
    required this.difficulty,
    required this.mediaType,
    required this.mediaUrl,
    required this.mediaDescription,
    required this.evidence,
    required this.actions,
    required this.sourceOptions,
    required this.correctDecision,
    required this.expectedConfidence,
    required this.explanation,
    required this.learningPoint,
    required this.sourceName,
    required this.sourceUrl,
    required this.sourcePublishedAt,
    required this.generated,
    required this.sequence,
  });

  factory VerificationCase.fromMap(Map<String, dynamic> map) {
    final rawEvidence = map['evidence'];
    final rawActions = map['actions'];
    final evidence = <VerificationEvidence>[];
    final actions = <VerificationAction>[];
    if (rawEvidence is List) {
      for (final item in rawEvidence) {
        if (item is Map) {
          evidence.add(
            VerificationEvidence.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    if (rawActions is List) {
      for (final item in rawActions) {
        if (item is Map) {
          actions.add(
            VerificationAction.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final subskill = VerificationSubskillX.fromId(map['subskill']?.toString());
    if (subskill == null) {
      throw const FormatException('Verification case has an unknown subskill.');
    }

    final correctDecision = VerificationDecisionX.tryFromId(
      map['correct_decision']?.toString(),
    );
    if (correctDecision == null) {
      throw const FormatException(
        'Verification case has an unknown correct decision.',
      );
    }

    return VerificationCase(
      id: map['case_id']?.toString() ?? map['id']?.toString() ?? '',
      code: map['case_code']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      scenario: map['scenario']?.toString() ?? '',
      claim: map['claim_text']?.toString() ?? map['claim']?.toString() ?? '',
      caseType: VerificationCaseTypeX.fromId(map['case_type']?.toString()),
      subskill: subskill,
      difficulty: QuestionDifficultyX.fromLevel(
        _asInt(map['difficulty'], fallback: 1),
      ),
      mediaType: map['media_type']?.toString() ?? 'text',
      mediaUrl: _nullableString(map['media_url']),
      mediaDescription: map['media_description']?.toString() ?? '',
      evidence: List.unmodifiable(evidence),
      actions: List.unmodifiable(actions),
      sourceOptions: _stringList(map['source_options']),
      correctDecision: correctDecision,
      expectedConfidence: VerificationConfidenceX.fromId(
        map['expected_confidence']?.toString(),
      ),
      explanation: map['explanation']?.toString() ?? '',
      learningPoint: map['learning_point']?.toString() ?? '',
      sourceName: map['source_name']?.toString() ?? '',
      sourceUrl: map['source_url']?.toString() ?? '',
      sourcePublishedAt: _asDate(map['source_published_at']),
      generated: map['generated_by']?.toString() == 'content_automation',
      sequence: _asInt(map['sequence'], fallback: 1),
    );
  }

  bool get isValid =>
      id.trim().isNotEmpty &&
      title.trim().isNotEmpty &&
      scenario.trim().isNotEmpty &&
      explanation.trim().isNotEmpty;
}

class VerificationSession {
  final String id;
  final int rankLevel;
  final List<VerificationCase> cases;
  final DateTime startedAt;

  const VerificationSession({
    required this.id,
    required this.rankLevel,
    required this.cases,
    required this.startedAt,
  });

  factory VerificationSession.fromMap(Map<String, dynamic> map) {
    final cases = <VerificationCase>[];
    final rawCases = map['cases'];
    if (rawCases is List) {
      for (final item in rawCases) {
        if (item is! Map) continue;
        try {
          final value = VerificationCase.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (value.isValid) cases.add(value);
        } catch (_) {
          // A malformed case should not break the rest of a session.
        }
      }
    }
    cases.sort((a, b) => a.sequence.compareTo(b.sequence));
    return VerificationSession(
      id: map['session_id']?.toString() ?? '',
      rankLevel: _asInt(map['rank_level'], fallback: 1).clamp(1, 5),
      cases: List.unmodifiable(cases),
      startedAt: _asDate(map['started_at']) ?? DateTime.now(),
    );
  }
}

class VerificationCaseFeedback {
  final String caseId;
  final VerificationSubskill subskill;
  final int evidenceScore;
  final int methodScore;
  final int decisionScore;
  final int sourceScore;
  final int confidenceScore;
  final int totalScore;
  final bool decisionCorrect;
  final bool countedForMastery;
  final VerificationDecision correctDecision;
  final String explanation;
  final String learningPoint;
  final int? subskillMasteryAfter;

  const VerificationCaseFeedback({
    required this.caseId,
    required this.subskill,
    required this.evidenceScore,
    required this.methodScore,
    required this.decisionScore,
    required this.sourceScore,
    required this.confidenceScore,
    required this.totalScore,
    required this.decisionCorrect,
    required this.countedForMastery,
    required this.correctDecision,
    required this.explanation,
    required this.learningPoint,
    this.subskillMasteryAfter,
  });

  factory VerificationCaseFeedback.fromMap(Map<String, dynamic> map) {
    final subskill = VerificationSubskillX.fromId(map['subskill']?.toString());
    if (subskill == null) throw const FormatException('Unknown subskill.');
    final correctDecision = VerificationDecisionX.tryFromId(
      map['correct_decision']?.toString(),
    );
    if (correctDecision == null) {
      throw const FormatException('Unknown correct verification decision.');
    }
    return VerificationCaseFeedback(
      caseId: map['case_id']?.toString() ?? '',
      subskill: subskill,
      evidenceScore: _asInt(map['evidence_score']).clamp(0, 30),
      methodScore: _asInt(map['method_score']).clamp(0, 25),
      decisionScore: _asInt(map['decision_score']).clamp(0, 25),
      sourceScore: _asInt(map['source_score']).clamp(0, 10),
      confidenceScore: _asInt(map['confidence_score']).clamp(0, 10),
      totalScore: _asInt(map['total_score']).clamp(0, 100),
      decisionCorrect: map['decision_correct'] == true,
      countedForMastery: map['counted_for_mastery'] == true,
      correctDecision: correctDecision,
      explanation: map['explanation']?.toString() ?? '',
      learningPoint: map['learning_point']?.toString() ?? '',
      subskillMasteryAfter: map['subskill_mastery_after'] == null
          ? null
          : _asInt(map['subskill_mastery_after']).clamp(0, 100),
    );
  }
}

class VerificationSubskillMastery {
  final VerificationSubskill subskill;
  final int mastery;
  final int attempts;
  final int successfulAttempts;
  final DateTime? lastPracticedAt;
  final DateTime? nextReviewAt;

  const VerificationSubskillMastery({
    required this.subskill,
    required this.mastery,
    required this.attempts,
    required this.successfulAttempts,
    this.lastPracticedAt,
    this.nextReviewAt,
  });

  factory VerificationSubskillMastery.initial(VerificationSubskill subskill) =>
      VerificationSubskillMastery(
        subskill: subskill,
        mastery: 0,
        attempts: 0,
        successfulAttempts: 0,
      );

  factory VerificationSubskillMastery.fromMap(Map<String, dynamic> map) {
    final subskill = VerificationSubskillX.fromId(map['subskill']?.toString());
    if (subskill == null) throw const FormatException('Unknown subskill.');
    return VerificationSubskillMastery(
      subskill: subskill,
      mastery: _asInt(map['mastery']).clamp(0, 100),
      attempts: _asInt(map['attempts']).clamp(0, 99999),
      successfulAttempts: _asInt(map['successful_attempts']).clamp(0, 99999),
      lastPracticedAt: _asDate(map['last_practiced_at']),
      nextReviewAt: _asDate(map['next_review_at']),
    );
  }
}

class VerificationSessionSummary {
  final String sessionId;
  final int averageScore;
  final int completedCases;
  final Map<VerificationSubskill, int> subskillScores;

  const VerificationSessionSummary({
    required this.sessionId,
    required this.averageScore,
    required this.completedCases,
    required this.subskillScores,
  });

  factory VerificationSessionSummary.fromMap(Map<String, dynamic> map) {
    final scores = <VerificationSubskill, int>{};
    final raw = map['subskill_scores'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final subskill = VerificationSubskillX.fromId(entry.key.toString());
        if (subskill != null) scores[subskill] = _asInt(entry.value).clamp(0, 100);
      }
    }
    return VerificationSessionSummary(
      sessionId: map['session_id']?.toString() ?? '',
      averageScore: _asInt(map['average_score']).clamp(0, 100),
      completedCases: _asInt(map['completed_cases']).clamp(0, 999),
      subskillScores: Map.unmodifiable(scores),
    );
  }
}

class VerificationCaseDraft {
  final String id;
  final String title;
  final String summary;
  final VerificationSubskill subskill;
  final VerificationCaseType caseType;
  final int difficulty;
  final String sourceName;
  final String sourceUrl;
  final DateTime? sourcePublishedAt;
  final DateTime? createdAt;

  const VerificationCaseDraft({
    required this.id,
    required this.title,
    required this.summary,
    required this.subskill,
    required this.caseType,
    required this.difficulty,
    required this.sourceName,
    required this.sourceUrl,
    this.sourcePublishedAt,
    this.createdAt,
  });

  factory VerificationCaseDraft.fromMap(Map<String, dynamic> map) {
    final payload = map['draft_payload'];
    final draft = payload is Map
        ? Map<String, dynamic>.from(payload)
        : const <String, dynamic>{};
    final subskill = VerificationSubskillX.fromId(
      draft['subskill']?.toString() ?? map['subskill']?.toString(),
    );
    if (subskill == null) throw const FormatException('Unknown draft subskill.');
    return VerificationCaseDraft(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? draft['title']?.toString() ?? '',
      summary: map['summary']?.toString() ?? draft['summary']?.toString() ?? '',
      subskill: subskill,
      caseType: VerificationCaseTypeX.fromId(
        draft['case_type']?.toString() ?? map['case_type']?.toString(),
      ),
      difficulty: _asInt(
        draft['difficulty'] ?? map['difficulty'],
        fallback: 3,
      ).clamp(1, 5),
      sourceName: map['source_name']?.toString() ?? '',
      sourceUrl: map['source_url']?.toString() ?? '',
      sourcePublishedAt: _asDate(map['source_published_at']),
      createdAt: _asDate(map['created_at']),
    );
  }
}

class VerificationAutomationOverview {
  final bool enabled;
  final int maxArticlesPerRun;
  final int maxDraftsPerRun;
  final int maxDraftsPerDay;
  final int monthlyDraftCap;
  final int monthlyGroqRequestCap;
  final int maxPendingDrafts;
  final int manualCooldownMinutes;
  final int pendingDrafts;
  final int draftsToday;
  final int draftsThisMonth;
  final int groqRequestsThisMonth;
  final int groqRequestsRemaining;
  final int cooldownRemainingMinutes;
  final int remainingToday;
  final int remainingThisMonth;

  const VerificationAutomationOverview({
    required this.enabled,
    required this.maxArticlesPerRun,
    required this.maxDraftsPerRun,
    required this.maxDraftsPerDay,
    required this.monthlyDraftCap,
    required this.monthlyGroqRequestCap,
    required this.maxPendingDrafts,
    required this.manualCooldownMinutes,
    required this.pendingDrafts,
    required this.draftsToday,
    required this.draftsThisMonth,
    required this.groqRequestsThisMonth,
    required this.groqRequestsRemaining,
    required this.cooldownRemainingMinutes,
    required this.remainingToday,
    required this.remainingThisMonth,
  });

  factory VerificationAutomationOverview.defaults() =>
      const VerificationAutomationOverview(
        enabled: true,
        maxArticlesPerRun: 6,
        maxDraftsPerRun: 2,
        maxDraftsPerDay: 4,
        monthlyDraftCap: 40,
        monthlyGroqRequestCap: 80,
        maxPendingDrafts: 40,
        manualCooldownMinutes: 15,
        pendingDrafts: 0,
        draftsToday: 0,
        draftsThisMonth: 0,
        groqRequestsThisMonth: 0,
        groqRequestsRemaining: 80,
        cooldownRemainingMinutes: 0,
        remainingToday: 4,
        remainingThisMonth: 40,
      );

  factory VerificationAutomationOverview.fromMap(Map<String, dynamic> map) {
    final rawSettings = map['settings'];
    final settings = rawSettings is Map
        ? Map<String, dynamic>.from(rawSettings)
        : const <String, dynamic>{};

    final maxDraftsPerDay = _asInt(
      settings['max_drafts_per_day'],
      fallback: 4,
    ).clamp(1, 50).toInt();
    final monthlyDraftCap = _asInt(
      settings['monthly_draft_cap'],
      fallback: 40,
    ).clamp(1, 1000).toInt();
    final monthlyGroqRequestCap = _asInt(
      settings['monthly_groq_request_cap'],
      fallback: 80,
    ).clamp(1, 5000).toInt();
    final draftsToday = _asInt(map['drafts_today']).clamp(0, 99999).toInt();
    final draftsThisMonth =
        _asInt(map['drafts_this_month']).clamp(0, 99999).toInt();

    return VerificationAutomationOverview(
      enabled: settings['enabled'] != false,
      maxArticlesPerRun: _asInt(
        settings['max_articles_per_run'],
        fallback: 6,
      ).clamp(1, 20).toInt(),
      maxDraftsPerRun: _asInt(
        settings['max_drafts_per_run'],
        fallback: 2,
      ).clamp(1, 10).toInt(),
      maxDraftsPerDay: maxDraftsPerDay,
      monthlyDraftCap: monthlyDraftCap,
      monthlyGroqRequestCap: monthlyGroqRequestCap,
      maxPendingDrafts: _asInt(
        settings['max_pending_drafts'],
        fallback: 40,
      ).clamp(5, 200).toInt(),
      manualCooldownMinutes: _asInt(
        settings['manual_cooldown_minutes'],
        fallback: 15,
      ).clamp(1, 120).toInt(),
      pendingDrafts: _asInt(map['pending_drafts']).clamp(0, 99999).toInt(),
      draftsToday: draftsToday,
      draftsThisMonth: draftsThisMonth,
      groqRequestsThisMonth:
          _asInt(map['groq_requests_this_month']).clamp(0, 999999).toInt(),
      groqRequestsRemaining: _asInt(
        map['groq_requests_remaining'],
        fallback: monthlyGroqRequestCap,
      ).clamp(0, monthlyGroqRequestCap).toInt(),
      cooldownRemainingMinutes: _asInt(
        map['cooldown_remaining_minutes'],
      ).clamp(0, 1440).toInt(),
      remainingToday: _asInt(
        map['remaining_today'],
        fallback: (maxDraftsPerDay - draftsToday).clamp(0, maxDraftsPerDay).toInt(),
      ).clamp(0, maxDraftsPerDay).toInt(),
      remainingThisMonth: _asInt(
        map['remaining_this_month'],
        fallback:
            (monthlyDraftCap - draftsThisMonth).clamp(0, monthlyDraftCap).toInt(),
      ).clamp(0, monthlyDraftCap).toInt(),
    );
  }
}

class VerificationCaseHealth {
  final VerificationSubskill subskill;
  final int publishedCases;
  final Map<int, int> byLevel;

  const VerificationCaseHealth({
    required this.subskill,
    required this.publishedCases,
    required this.byLevel,
  });

  factory VerificationCaseHealth.fromMap(Map<String, dynamic> map) {
    final subskill = VerificationSubskillX.fromId(map['subskill']?.toString());
    if (subskill == null) throw const FormatException('Unknown health subskill.');
    return VerificationCaseHealth(
      subskill: subskill,
      publishedCases: _asInt(map['published_cases']),
      byLevel: {
        1: _asInt(map['foundation']),
        2: _asInt(map['developing']),
        3: _asInt(map['proficient']),
        4: _asInt(map['advanced']),
        5: _asInt(map['expert']),
      },
    );
  }
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).where((item) => item.trim().isNotEmpty).toList(growable: false);
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

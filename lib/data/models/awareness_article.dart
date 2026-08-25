enum AwarenessScope { forYou, philippines, latest }

enum AwarenessCategory {
  scams,
  deepfakes,
  fakeNews,
  privacy,
  onlineSafety,
  aiMisuse,
  factChecking,
  cybersecurity,
}

extension AwarenessScopeX on AwarenessScope {
  String get label => switch (this) {
    AwarenessScope.forYou => 'For you',
    AwarenessScope.philippines => 'Philippines',
    AwarenessScope.latest => 'Latest',
  };
}

extension AwarenessCategoryX on AwarenessCategory {
  String get databaseValue => switch (this) {
    AwarenessCategory.scams => 'scams',
    AwarenessCategory.deepfakes => 'deepfakes',
    AwarenessCategory.fakeNews => 'fake_news',
    AwarenessCategory.privacy => 'privacy',
    AwarenessCategory.onlineSafety => 'online_safety',
    AwarenessCategory.aiMisuse => 'ai_misuse',
    AwarenessCategory.factChecking => 'fact_checking',
    AwarenessCategory.cybersecurity => 'cybersecurity',
  };

  String get label => switch (this) {
    AwarenessCategory.scams => 'AI scams',
    AwarenessCategory.deepfakes => 'AI & deepfakes',
    AwarenessCategory.fakeNews => 'AI misinformation',
    AwarenessCategory.privacy => 'AI & privacy',
    AwarenessCategory.onlineSafety => 'AI safety',
    AwarenessCategory.aiMisuse => 'AI misuse',
    AwarenessCategory.factChecking => 'AI fact checking',
    AwarenessCategory.cybersecurity => 'AI cybersecurity',
  };

  static AwarenessCategory fromDatabase(String? value) {
    return AwarenessCategory.values.firstWhere(
      (item) => item.databaseValue == value,
      orElse: () => AwarenessCategory.onlineSafety,
    );
  }
}

class AwarenessArticle {
  final String id;
  final String title;
  final String summary;
  final String whyItMatters;
  final String sourceName;
  final String sourceDomain;
  final String sourceUrl;
  final String? imageUrl;
  final DateTime? publishedAt;
  final DateTime? discoveredAt;
  final AwarenessCategory category;
  final String region;
  final int relevanceScore;
  final int trustLevel;
  final bool saved;
  final bool read;

  const AwarenessArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.whyItMatters,
    required this.sourceName,
    required this.sourceDomain,
    required this.sourceUrl,
    required this.category,
    required this.region,
    required this.relevanceScore,
    required this.trustLevel,
    this.imageUrl,
    this.publishedAt,
    this.discoveredAt,
    this.saved = false,
    this.read = false,
  });

  bool get isPhilippines => region.toLowerCase() == 'philippines';

  factory AwarenessArticle.fromMap(Map<String, dynamic> map) {
    return AwarenessArticle(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString().trim() ?? '',
      summary: map['summary']?.toString().trim() ?? '',
      whyItMatters: map['why_it_matters']?.toString().trim() ?? '',
      sourceName: map['source_name']?.toString().trim() ?? 'Source',
      sourceDomain: map['source_domain']?.toString().trim() ?? '',
      sourceUrl: map['source_url']?.toString().trim() ?? '',
      imageUrl: _nullableString(map['image_url']),
      publishedAt: _asDate(map['published_at']),
      discoveredAt: _asDate(map['discovered_at']),
      category: AwarenessCategoryX.fromDatabase(map['category']?.toString()),
      region: map['region']?.toString().trim() ?? 'Global',
      relevanceScore: _asInt(map['relevance_score']),
      trustLevel: _asInt(map['trust_level'], fallback: 70),
      saved: map['saved'] == true,
      read: map['read'] == true,
    );
  }

  AwarenessArticle copyWith({bool? saved, bool? read}) {
    return AwarenessArticle(
      id: id,
      title: title,
      summary: summary,
      whyItMatters: whyItMatters,
      sourceName: sourceName,
      sourceDomain: sourceDomain,
      sourceUrl: sourceUrl,
      imageUrl: imageUrl,
      publishedAt: publishedAt,
      discoveredAt: discoveredAt,
      category: category,
      region: region,
      relevanceScore: relevanceScore,
      trustLevel: trustLevel,
      saved: saved ?? this.saved,
      read: read ?? this.read,
    );
  }
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

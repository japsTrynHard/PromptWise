class DictionaryDefinition {
  final String partOfSpeech;
  final String definition;
  final String example;

  const DictionaryDefinition({
    required this.partOfSpeech,
    required this.definition,
    required this.example,
  });

  factory DictionaryDefinition.fromMap(Map<String, dynamic> map) {
    return DictionaryDefinition(
      partOfSpeech: map['partOfSpeech']?.toString().trim() ?? '',
      definition: map['definition']?.toString().trim() ?? '',
      example: map['example']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'partOfSpeech': partOfSpeech,
    'definition': definition,
    'example': example,
  };
}

class DictionaryEntry {
  final String word;
  final String phonetic;
  final List<DictionaryDefinition> definitions;
  final List<String> sourceUrls;

  const DictionaryEntry({
    required this.word,
    required this.phonetic,
    required this.definitions,
    required this.sourceUrls,
  });

  factory DictionaryEntry.fromApiMap(Map<String, dynamic> map) {
    final definitions = <DictionaryDefinition>[];
    final meanings = map['meanings'];
    if (meanings is List) {
      for (final rawMeaning in meanings) {
        if (rawMeaning is! Map) continue;
        final meaning = Map<String, dynamic>.from(rawMeaning);
        final partOfSpeech = meaning['partOfSpeech']?.toString().trim() ?? '';
        final rawDefinitions = meaning['definitions'];
        if (rawDefinitions is! List) continue;
        for (final rawDefinition in rawDefinitions.take(3)) {
          if (rawDefinition is! Map) continue;
          final definitionMap = Map<String, dynamic>.from(rawDefinition);
          final definition =
              definitionMap['definition']?.toString().trim() ?? '';
          if (definition.isEmpty) continue;
          definitions.add(
            DictionaryDefinition(
              partOfSpeech: partOfSpeech,
              definition: definition,
              example: definitionMap['example']?.toString().trim() ?? '',
            ),
          );
          if (definitions.length >= 5) break;
        }
        if (definitions.length >= 5) break;
      }
    }

    final sources = <String>[];
    final rawSources = map['sourceUrls'];
    if (rawSources is List) {
      for (final value in rawSources) {
        final source = value?.toString().trim() ?? '';
        if (source.isNotEmpty) sources.add(source);
      }
    }

    return DictionaryEntry(
      word: map['word']?.toString().trim() ?? '',
      phonetic: map['phonetic']?.toString().trim() ?? '',
      definitions: definitions,
      sourceUrls: sources,
    );
  }

  factory DictionaryEntry.fromMap(Map<String, dynamic> map) {
    final rawDefinitions = map['definitions'];
    final rawSources = map['sourceUrls'];
    return DictionaryEntry(
      word: map['word']?.toString().trim() ?? '',
      phonetic: map['phonetic']?.toString().trim() ?? '',
      definitions: rawDefinitions is List
          ? rawDefinitions
                .whereType<Map>()
                .map(
                  (value) => DictionaryDefinition.fromMap(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList(growable: false)
          : const [],
      sourceUrls: rawSources is List
          ? rawSources
                .map((value) => value?.toString().trim() ?? '')
                .where((value) => value.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toMap() => {
    'word': word,
    'phonetic': phonetic,
    'definitions': definitions.map((value) => value.toMap()).toList(),
    'sourceUrls': sourceUrls,
  };
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/data/models/dictionary_entry.dart';
import 'package:promptwise/data/services/dictionary_service.dart';
import 'package:promptwise/presentation/controllers/dictionary_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'lookup exposes loading immediately and coalesces duplicate requests',
    () async {
      final service = _FakeDictionaryService();
      final controller = DictionaryController(service: service);

      final first = controller.lookup('bias', forceOnline: true);
      final duplicate = controller.lookup('bias', forceOnline: true);

      expect(controller.isLoading, isTrue);
      expect(service.calls, ['bias']);

      service.complete('bias', _entry('bias'));
      await Future.wait([first, duplicate]);

      expect(controller.isLoading, isFalse);
      expect(controller.entry?.word, 'bias');
      controller.dispose();
    },
  );

  test('an older result cannot replace a newer word', () async {
    final service = _FakeDictionaryService();
    final controller = DictionaryController(service: service);

    final oldRequest = controller.lookup('bias', forceOnline: true);
    final newRequest = controller.lookup('context', forceOnline: true);
    service.complete('bias', _entry('bias'));
    await oldRequest;
    expect(controller.entry?.word, isNot('bias'));

    service.complete('context', _entry('context'));
    await newRequest;
    expect(controller.entry?.word, 'context');
    controller.dispose();
  });

  test('a disposed controller ignores a late dictionary result', () async {
    final service = _FakeDictionaryService();
    final controller = DictionaryController(service: service);

    final request = controller.lookup('bias', forceOnline: true);
    controller.dispose();
    service.complete('bias', _entry('bias'));

    await request;
    expect(controller.entry, isNull);
  });

  test(
    'typed not-found failures remain distinct from connectivity failures',
    () async {
      final service = _FakeDictionaryService();
      final controller = DictionaryController(service: service);

      final request = controller.lookup('zzzz', forceOnline: true);
      service.fail('zzzz', const DictionaryNotFoundException());
      await request;

      expect(controller.entry, isNull);
      expect(controller.message, contains('No definition was found'));
      expect(controller.message, isNot(contains('offline')));
      controller.dispose();
    },
  );

  test('retry starts a clean request after a failed lookup', () async {
    final service = _RetryDictionaryService();
    final controller = DictionaryController(service: service);

    await controller.lookup('prompt', forceOnline: true);
    expect(controller.isLoading, isFalse);
    expect(controller.entry, isNull);
    expect(service.calls, 1);

    final retry = controller.retry();
    expect(controller.isLoading, isTrue);
    expect(service.calls, 2);
    await retry;

    expect(controller.isLoading, isFalse);
    expect(controller.entry?.word, 'prompt');
    controller.dispose();
  });

  test('successful-definition cache keeps the newest 75 LRU entries', () async {
    final controller = DictionaryController(
      service: _ImmediateDictionaryService(),
    );

    for (var index = 0; index < 76; index++) {
      await controller.lookup('word$index', forceOnline: true);
    }

    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString('lessonDictionaryCacheV2');
    expect(encoded, isNotNull);
    final cache = Map<String, dynamic>.from(jsonDecode(encoded!) as Map);
    expect(cache, hasLength(75));
    expect(cache.containsKey('word0'), isFalse);
    expect(cache.containsKey('word1'), isTrue);
    expect(cache.containsKey('word75'), isTrue);
    controller.dispose();
  });
}

DictionaryEntry _entry(String word) => DictionaryEntry(
  word: word,
  phonetic: '',
  definitions: const [
    DictionaryDefinition(
      partOfSpeech: 'noun',
      definition: 'A test definition.',
      example: '',
    ),
  ],
  sourceUrls: const [],
);

class _FakeDictionaryService implements DictionaryLookupService {
  final calls = <String>[];
  final _pending = <String, Completer<DictionaryEntry>>{};

  @override
  Future<DictionaryEntry> lookup(String word) {
    calls.add(word);
    return (_pending[word] ??= Completer<DictionaryEntry>()).future;
  }

  void complete(String word, DictionaryEntry entry) {
    _pending[word]!.complete(entry);
  }

  void fail(String word, Object error) {
    _pending[word]!.completeError(error);
  }
}

class _RetryDictionaryService implements DictionaryLookupService {
  int calls = 0;

  @override
  Future<DictionaryEntry> lookup(String word) {
    calls++;
    if (calls == 1) {
      return Future<DictionaryEntry>.error(
        const DictionaryServiceException(
          'The dictionary providers are temporarily unavailable.',
          kind: DictionaryFailureKind.upstream,
        ),
      );
    }
    return Future<DictionaryEntry>.value(_entry(word));
  }
}

class _ImmediateDictionaryService implements DictionaryLookupService {
  @override
  Future<DictionaryEntry> lookup(String word) async => _entry(word);
}

import 'dart:async';

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

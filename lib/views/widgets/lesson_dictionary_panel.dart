import 'package:flutter/material.dart';

import '../../controllers/dictionary_controller.dart';
import '../../models/dictionary_entry.dart';
import '../../utils/constants.dart';
import 'app_card.dart';

class LessonDictionaryPanel extends StatefulWidget {
  final String lessonTitle;
  final String lessonContent;

  const LessonDictionaryPanel({
    super.key,
    required this.lessonTitle,
    required this.lessonContent,
  });

  @override
  State<LessonDictionaryPanel> createState() => _LessonDictionaryPanelState();
}

class _LessonDictionaryPanelState extends State<LessonDictionaryPanel> {
  final TextEditingController _wordController = TextEditingController();
  final FocusNode _wordFocus = FocusNode();
  late final DictionaryController _controller;

  static const _knownTerms = <String>[
    'prompt',
    'context',
    'bias',
    'hallucination',
    'privacy',
    'ethics',
    'verification',
    'source',
    'model',
    'algorithm',
    'data',
    'misinformation',
    'deepfake',
    'accuracy',
    'fairness',
    'automation',
  ];

  @override
  void initState() {
    super.initState();
    _controller = DictionaryController()..addListener(_refresh);
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    _wordController.dispose();
    _wordFocus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<String> get _suggestedTerms {
    final source = '${widget.lessonTitle} ${widget.lessonContent}'
        .toLowerCase();
    final matches = _knownTerms
        .where(
          (term) => RegExp('\\b${RegExp.escape(term)}\\b').hasMatch(source),
        )
        .take(6)
        .toList(growable: false);
    return matches;
  }

  Future<void> _lookup([String? suggested]) async {
    if (suggested != null) {
      _wordController.text = suggested;
      _wordController.selection = TextSelection.collapsed(
        offset: suggested.length,
      );
    }
    FocusScope.of(context).unfocus();
    await _controller.lookup(_wordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestedTerms;
    final entry = _controller.entry;
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.menu_book_outlined, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need help with a term?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Look up a word without leaving the lesson.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Terms in this lesson',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: suggestions
                  .map(
                    (term) => ActionChip(
                      label: Text(term),
                      onPressed: _controller.isLoading
                          ? null
                          : () => _lookup(term),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final field = TextField(
                controller: _wordController,
                focusNode: _wordFocus,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _lookup(),
                decoration: const InputDecoration(
                  labelText: 'Word from the lesson',
                  hintText: 'Example: bias',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              );
              final button = FilledButton.icon(
                onPressed: _controller.isLoading ? null : _lookup,
                icon: _controller.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
                label: Text(
                  _controller.isLoading ? 'Looking up...' : 'Find meaning',
                ),
              );

              if (constraints.maxWidth >= 620) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: field),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(width: 170, child: button),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field,
                  const SizedBox(height: AppSpacing.md),
                  button,
                ],
              );
            },
          ),
          if (_controller.message != null) ...[
            const SizedBox(height: AppSpacing.md),
            _DictionaryMessage(
              message: _controller.message!,
              saved: _controller.showingSavedDefinition,
              onRetry: _controller.lastWord.isEmpty || _controller.isLoading
                  ? null
                  : _controller.retry,
            ),
          ],
          if (entry != null) ...[
            const SizedBox(height: AppSpacing.xl),
            _DefinitionResult(entry: entry),
          ] else if (_controller.hasSearched &&
              !_controller.isLoading &&
              _controller.message == null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No meaning was found for that word.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _DictionaryMessage extends StatelessWidget {
  final String message;
  final bool saved;
  final VoidCallback? onRetry;

  const _DictionaryMessage({
    required this.message,
    required this.saved,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: saved
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(saved ? Icons.offline_pin_outlined : Icons.info_outline_rounded),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _DefinitionResult extends StatelessWidget {
  final DictionaryEntry entry;

  const _DefinitionResult({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text(entry.word, style: Theme.of(context).textTheme.headlineSmall),
            if (entry.phonetic.isNotEmpty)
              Text(
                entry.phonetic,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ...entry.definitions
            .take(3)
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.partOfSpeech.isNotEmpty)
                      Text(
                        item.partOfSpeech,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: scheme.primary),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.definition,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                    if (item.example.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Example: ${item.example}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        Text(
          'Source: Free Dictionary',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

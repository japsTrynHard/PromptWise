import 'package:flutter/foundation.dart';

class SandboxController extends ChangeNotifier {
  String _lastPrompt = '';
  String _feedbackSummary = '';
  bool _evaluated = false;
  double _clarity = 0;
  double _context = 0;
  double _specificity = 0;
  double _responsibility = 0;
  double _overall = 0;
  int _attemptCount = 0;
  List<String> _strengths = const [];
  List<String> _suggestions = const [];

  String get lastPrompt => _lastPrompt;
  String get feedbackSummary => _feedbackSummary;
  bool get evaluated => _evaluated;
  double get clarity => _clarity;
  double get context => _context;
  double get specificity => _specificity;
  double get responsibility => _responsibility;
  double get overall => _overall;
  int get attemptCount => _attemptCount;
  List<String> get strengths => List.unmodifiable(_strengths);
  List<String> get suggestions => List.unmodifiable(_suggestions);

  void reviewPrompt(String prompt) {
    final cleanedPrompt = prompt.trim();
    if (cleanedPrompt.isEmpty) return;

    _lastPrompt = cleanedPrompt;
    _attemptCount++;

    final lowerPrompt = cleanedPrompt.toLowerCase();
    final wordCount = cleanedPrompt
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;

    final hasClearTask = _containsAny(lowerPrompt, const [
      'create',
      'write',
      'explain',
      'compare',
      'summarize',
      'identify',
      'design',
      'list',
      'make',
      'gumawa',
      'ipaliwanag',
      'ihambing',
      'ibuod',
    ]);

    final hasContext = _containsAny(lowerPrompt, const [
      'for',
      'because',
      'background',
      'context',
      'audience',
      'student',
      'beginner',
      'para sa',
      'dahil',
      'konteksto',
      'estudyante',
    ]);

    final hasOutputDetails = RegExp(r'\d').hasMatch(lowerPrompt) ||
        _containsAny(lowerPrompt, const [
          'paragraph',
          'sentence',
          'bullet',
          'table',
          'steps',
          'example',
          'format',
          'tone',
          'words',
          'talata',
          'pangungusap',
          'hakbang',
          'halimbawa',
        ]);

    final asksForVerification = _containsAny(lowerPrompt, const [
      'verify',
      'source',
      'citation',
      'fact-check',
      'limitations',
      'check accuracy',
      'beripikahin',
      'sanggunian',
      'pinagmulan',
    ]);

    _clarity = hasClearTask
        ? (wordCount >= 8 ? 0.95 : 0.78)
        : (wordCount >= 8 ? 0.62 : 0.38);
    _context = hasContext ? 0.9 : 0.42;
    _specificity = hasOutputDetails ? 0.9 : 0.4;
    _responsibility = asksForVerification ? 0.95 : 0.7;
    _overall =
        (_clarity + _context + _specificity + _responsibility) / 4;

    final strengths = <String>[];
    final suggestions = <String>[];

    if (hasClearTask) {
      strengths.add('Your prompt states an action or task for the AI.');
    } else {
      suggestions.add(
        'Start with a clear action such as explain, compare, create, or summarize.',
      );
    }

    if (hasContext) {
      strengths.add('You included useful context or identified the audience.');
    } else {
      suggestions.add(
        'Add background information and identify who the output is for.',
      );
    }

    if (hasOutputDetails) {
      strengths.add('You specified at least one output detail or format.');
    } else {
      suggestions.add(
        'Specify the expected format, length, tone, steps, or number of examples.',
      );
    }

    if (asksForVerification) {
      strengths.add('You reminded the AI to verify information or use sources.');
    } else {
      suggestions.add(
        'Ask for sources, limitations, or facts that you can verify independently.',
      );
    }

    if (wordCount < 5) {
      suggestions.add(
        'Your prompt is very short. Add enough detail to remove possible ambiguity.',
      );
    }

    _strengths = strengths;
    _suggestions = suggestions;
    _feedbackSummary = _overall >= 0.8
        ? 'Strong foundation. Review the suggestions, then improve the prompt using your own wording.'
        : 'The prompt can be improved. Use the suggestions as clues, revise it yourself, and review it again.';
    _evaluated = true;
    notifyListeners();
  }

  bool _containsAny(String value, List<String> terms) {
    return terms.any(value.contains);
  }

  void reset() {
    _lastPrompt = '';
    _feedbackSummary = '';
    _evaluated = false;
    _clarity = 0;
    _context = 0;
    _specificity = 0;
    _responsibility = 0;
    _overall = 0;
    _attemptCount = 0;
    _strengths = const [];
    _suggestions = const [];
    notifyListeners();
  }
}

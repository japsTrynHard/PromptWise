import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/prompt_coach_feedback.dart';
import '../services/integration_service.dart';

class SandboxController extends ChangeNotifier {
  SandboxController({required IntegrationService? service})
    : _service = service;

  static const int minimumPromptLength = 10;
  static const int maximumPromptLength = 1500;

  final IntegrationService? _service;

  String _lastPrompt = '';
  String _feedbackSummary = '';
  String _safetyReminder =
      'Remove private or sensitive information before sharing a prompt with any online AI service.';
  String? _validationMessage;
  String? _serviceMessage;
  bool _evaluated = false;
  bool _isLoading = false;
  bool _coachAvailable = false;
  bool _coachChecked = false;
  bool _usedBasicFeedback = false;
  double _clarity = 0;
  double _context = 0;
  double _specificity = 0;
  double _responsibility = 0;
  double _overall = 0;
  int _attemptCount = 0;
  List<String> _strengths = const [];
  List<String> _suggestions = const [];
  List<String> _guidingQuestions = const [];

  String get lastPrompt => _lastPrompt;
  String get feedbackSummary => _feedbackSummary;
  String get safetyReminder => _safetyReminder;
  String? get validationMessage => _validationMessage;
  String? get serviceMessage => _serviceMessage;
  bool get evaluated => _evaluated;
  bool get isLoading => _isLoading;
  bool get coachAvailable => _coachAvailable;
  bool get coachChecked => _coachChecked;
  bool get usedBasicFeedback => _usedBasicFeedback;
  double get clarity => _clarity;
  double get context => _context;
  double get specificity => _specificity;
  double get responsibility => _responsibility;
  double get overall => _overall;
  int get attemptCount => _attemptCount;
  List<String> get strengths => List.unmodifiable(_strengths);
  List<String> get suggestions => List.unmodifiable(_suggestions);
  List<String> get guidingQuestions => List.unmodifiable(_guidingQuestions);

  Future<void> init() async {
    if (_coachChecked || _isLoading) return;
    await checkCoachAvailability();
  }

  Future<void> checkCoachAvailability() async {
    final service = _service;
    if (service == null) {
      _coachChecked = true;
      _coachAvailable = false;
      _serviceMessage =
          'AI Coach is unavailable right now. Basic feedback is still available.';
      notifyListeners();
      return;
    }

    try {
      _coachAvailable = await service.isCoachAvailable();
      _serviceMessage = _coachAvailable
          ? null
          : 'AI Coach is unavailable right now. Basic feedback is still available.';
    } on TimeoutException {
      _coachAvailable = false;
      _serviceMessage =
          'This is taking longer than expected. Basic feedback is still available.';
    } on http.ClientException {
      _coachAvailable = false;
      _serviceMessage =
          'You appear to be offline. Basic feedback will still work on this device.';
    } on IntegrationException catch (error) {
      _coachAvailable = false;
      _serviceMessage = _friendlyServiceMessage(error.message);
    } catch (_) {
      _coachAvailable = false;
      _serviceMessage =
          'AI Coach is unavailable right now. Basic feedback is still available.';
    } finally {
      _coachChecked = true;
      notifyListeners();
    }
  }

  Future<bool> reviewPrompt(String prompt) async {
    final cleanedPrompt = prompt.trim();
    final validationError = validatePrompt(cleanedPrompt);

    if (validationError != null) {
      _validationMessage = validationError;
      _evaluated = false;
      notifyListeners();
      return false;
    }

    _validationMessage = null;
    _lastPrompt = cleanedPrompt;
    _attemptCount++;
    _isLoading = true;
    _serviceMessage = null;
    notifyListeners();

    final localFeedback = _buildBasicFeedback(cleanedPrompt);
    final containsSensitiveData = _mayContainSensitiveData(cleanedPrompt);

    if (containsSensitiveData) {
      _applyFeedback(localFeedback, usedBasicFeedback: true);
      _serviceMessage =
          'Remove private information first. This prompt was not sent to the AI Coach.';
      _isLoading = false;
      _coachChecked = true;
      notifyListeners();
      return true;
    }

    final service = _service;
    if (service == null) {
      _applyFeedback(localFeedback, usedBasicFeedback: true);
      _serviceMessage =
          'AI Coach is unavailable right now. Showing basic feedback from this device.';
      _isLoading = false;
      notifyListeners();
      return true;
    }

    try {
      final feedback = await service.getPromptFeedback(cleanedPrompt);
      _applyFeedback(feedback, usedBasicFeedback: false);
      _coachAvailable = true;
      _coachChecked = true;
      _serviceMessage = null;
    } on TimeoutException {
      _applyFeedback(localFeedback, usedBasicFeedback: true);
      _coachAvailable = false;
      _coachChecked = true;
      _serviceMessage =
          'This is taking longer than expected. Showing basic feedback from this device.';
    } on http.ClientException {
      _applyFeedback(localFeedback, usedBasicFeedback: true);
      _coachAvailable = false;
      _coachChecked = true;
      _serviceMessage =
          'You appear to be offline. Showing basic feedback from this device.';
    } on IntegrationException catch (error) {
      _applyFeedback(localFeedback, usedBasicFeedback: true);
      _coachAvailable = false;
      _coachChecked = true;
      _serviceMessage = _friendlyServiceMessage(error.message);
    } catch (_) {
      _applyFeedback(localFeedback, usedBasicFeedback: true);
      _coachAvailable = false;
      _coachChecked = true;
      _serviceMessage =
          'AI Coach is unavailable right now. Showing basic feedback from this device.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return true;
  }

  String? validatePrompt(String prompt) {
    if (prompt.isEmpty) {
      return 'Enter a prompt before requesting feedback.';
    }
    if (prompt.length < minimumPromptLength) {
      return 'Add more detail. The prompt must contain at least $minimumPromptLength characters.';
    }
    if (prompt.length > maximumPromptLength) {
      return 'The prompt is too long. Keep it within $maximumPromptLength characters.';
    }
    return null;
  }

  void clearValidationMessage() {
    if (_validationMessage == null) return;
    _validationMessage = null;
    notifyListeners();
  }

  void reset() {
    _lastPrompt = '';
    _feedbackSummary = '';
    _safetyReminder =
        'Remove private or sensitive information before sharing a prompt with any online AI service.';
    _validationMessage = null;
    _serviceMessage = null;
    _evaluated = false;
    _isLoading = false;
    _usedBasicFeedback = false;
    _clarity = 0;
    _context = 0;
    _specificity = 0;
    _responsibility = 0;
    _overall = 0;
    _attemptCount = 0;
    _strengths = const [];
    _suggestions = const [];
    _guidingQuestions = const [];
    notifyListeners();
  }

  void _applyFeedback(
    PromptCoachFeedback feedback, {
    required bool usedBasicFeedback,
  }) {
    _clarity = feedback.clarity;
    _context = feedback.context;
    _specificity = feedback.specificity;
    _responsibility = feedback.responsibility;
    _overall = feedback.overall;
    _strengths = feedback.strengths;
    _suggestions = feedback.suggestions;
    _guidingQuestions = feedback.guidingQuestions;
    _safetyReminder = feedback.safetyReminder.isEmpty
        ? 'Remove private or sensitive information before sharing a prompt with any online AI service.'
        : feedback.safetyReminder;
    _feedbackSummary = feedback.summary.isEmpty
        ? 'Use the feedback as guidance, then revise the prompt using your own words.'
        : feedback.summary;
    _usedBasicFeedback = usedBasicFeedback;
    _evaluated = true;
  }

  PromptCoachFeedback _buildBasicFeedback(String cleanedPrompt) {
    final lowerPrompt = cleanedPrompt.toLowerCase();
    final words = cleanedPrompt
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final wordCount = words.length;

    final hasClearTask = _containsAny(lowerPrompt, const [
      'analyze',
      'create',
      'define',
      'describe',
      'design',
      'evaluate',
      'explain',
      'identify',
      'list',
      'make',
      'outline',
      'review',
      'summarize',
      'compare',
      'write',
      'gumawa',
      'ipaliwanag',
      'ihambing',
      'ibuod',
      'suriin',
      'ilarawan',
    ]);

    final hasAudience = _containsAny(lowerPrompt, const [
      'audience',
      'beginner',
      'student',
      'teacher',
      'reader',
      'customer',
      'for children',
      'for adults',
      'para sa',
      'estudyante',
      'guro',
      'mambabasa',
    ]);

    final hasBackground = _containsAny(lowerPrompt, const [
      'background',
      'context',
      'because',
      'given that',
      'based on',
      'purpose',
      'goal',
      'konteksto',
      'dahil',
      'layunin',
      'batay sa',
    ]);

    final hasOutputDetails =
        RegExp(r'\b\d+\b').hasMatch(lowerPrompt) ||
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
          'concise',
          'detailed',
          'talata',
          'pangungusap',
          'hakbang',
          'halimbawa',
          'pormat',
        ]);

    final asksForVerification = _containsAny(lowerPrompt, const [
      'verify',
      'source',
      'citation',
      'limitations',
      'check accuracy',
      'uncertainty',
      'beripikahin',
      'sanggunian',
      'pinagmulan',
      'katumpakan',
    ]);

    final clarity = hasClearTask
        ? (wordCount >= 8 ? 0.95 : 0.78)
        : (wordCount >= 8 ? 0.58 : 0.38);
    final contextSignals = [hasAudience, hasBackground].where((v) => v).length;
    final context = switch (contextSignals) {
      2 => 0.95,
      1 => 0.72,
      _ => wordCount >= 20 ? 0.52 : 0.38,
    };
    final specificity = hasOutputDetails
        ? (wordCount >= 12 ? 0.92 : 0.78)
        : (wordCount >= 20 ? 0.58 : 0.4);
    final responsibility = asksForVerification ? 0.95 : 0.68;
    final overall = (clarity + context + specificity + responsibility) / 4;

    final strengths = <String>[];
    final suggestions = <String>[];
    final questions = <String>[];

    if (hasClearTask) {
      strengths.add('Your prompt states a recognizable task.');
    } else {
      suggestions.add('State the main task clearly.');
      questions.add('What exactly should the AI help you do?');
    }
    if (hasAudience) {
      strengths.add('You identified who the output is for.');
    } else {
      suggestions.add(
        'Consider identifying the target audience or skill level.',
      );
      questions.add('Who will read or use the output?');
    }
    if (hasBackground) {
      strengths.add('You included useful background or purpose.');
    } else {
      suggestions.add('Add only the background needed to understand the task.');
      questions.add(
        'What context would prevent the task from being misunderstood?',
      );
    }
    if (hasOutputDetails) {
      strengths.add('You specified at least one output detail.');
    } else {
      suggestions.add(
        'Consider the format, length, tone, or number of examples.',
      );
      questions.add('What should the final response look like?');
    }
    if (asksForVerification) {
      strengths.add('You included a reminder to verify important information.');
    } else {
      suggestions.add(
        'For factual tasks, ask for uncertainty or sources you can check.',
      );
    }

    return PromptCoachFeedback(
      clarity: clarity,
      context: context,
      specificity: specificity,
      responsibility: responsibility,
      overall: overall,
      strengths: strengths,
      suggestions: suggestions,
      guidingQuestions: questions.take(3).toList(growable: false),
      safetyReminder:
          'Do not include passwords, account details, private contact information, or confidential school or company data.',
      summary: overall >= 0.8
          ? 'Strong foundation. Choose the useful feedback and revise the prompt in your own words.'
          : 'There are a few areas to strengthen. Use the guidance, make your own decisions, and revise the prompt yourself.',
    );
  }

  bool _mayContainSensitiveData(String value) {
    final lower = value.toLowerCase();
    return _containsAny(lower, const [
          'password:',
          'api key:',
          'secret key:',
          'credit card:',
          'account number:',
        ]) ||
        RegExp(r'\b\d{11,16}\b').hasMatch(value) ||
        RegExp(r'[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}').hasMatch(value);
  }

  bool _containsAny(String value, List<String> terms) {
    return terms.any(value.contains);
  }

  String _friendlyServiceMessage(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('rate') || lower.contains('too many')) {
      return 'The AI Coach is busy right now. Showing basic feedback from this device.';
    }
    if (lower.contains('key') || lower.contains('configured')) {
      return 'AI Coach is unavailable right now. Showing basic feedback from this device.';
    }
    if (lower.contains('timeout') || lower.contains('connection')) {
      return 'You appear to be offline. Showing basic feedback from this device.';
    }
    return 'AI Coach is unavailable right now. Showing basic feedback from this device.';
  }
}

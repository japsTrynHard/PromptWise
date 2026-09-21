import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_routes.dart';
import '../../../data/models/learning_survey.dart';
import '../../../data/models/learning_topic.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/learning_survey_controller.dart';
import '../../controllers/onboarding_controller.dart';

/// Required only for newly onboarded learners. Existing users can edit later.
class LearningSurveyScreen extends StatefulWidget {
  final bool replay;
  const LearningSurveyScreen({super.key, this.replay = false});

  @override
  State<LearningSurveyScreen> createState() => _LearningSurveyScreenState();
}

class _LearningSurveyScreenState extends State<LearningSurveyScreen> {
  final Set<LearningTopic> _interests = {};
  String? _experience;
  String? _goal;
  bool _initialized = false;

  Future<void> _save() async {
    if (_interests.isEmpty || _experience == null || _goal == null) return;
    final preferences = LearningSurvey(
      interests: Set.unmodifiable(_interests),
      experienceLevel: _experience!,
      learningGoal: _goal!,
    );
    final saved = await context.read<LearningSurveyController>().submit(
      preferences,
    );
    if (!mounted || !saved) return;
    if (widget.replay) {
      await context.read<OnboardingController>().retry();
      if (mounted) Navigator.of(context).pop();
    } else {
      // Refresh the server-owned completion marker, never assume success from
      // a local selection. The auth gate will then unlock the dashboard.
      await context.read<OnboardingController>().retry();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.root,
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final survey = context.watch<LearningSurveyController>();
    final theme = Theme.of(context);
    if (!survey.isReadyFor(context.watch<AuthController>().userId)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Learning preferences')),
        body: Center(
          child: survey.errorMessage == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(survey.errorMessage!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () => survey.retry(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
        ),
      );
    }
    if (!_initialized) {
      final saved = survey.survey;
      if (saved != null) {
        _interests.addAll(saved.interests);
        _experience = saved.experienceLevel;
        _goal = saved.learningGoal;
      }
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.replay,
        title: Text(
          widget.replay ? 'Edit learning preferences' : 'Make learning yours',
        ),
        actions: [
          if (!widget.replay)
            TextButton(
              onPressed: () => context.read<AuthController>().signOut(),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Text(
                  'What would you like to learn?',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose one to three interests. These are your preferences, not a test of ability.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final topic in LearningTopic.values)
                      FilterChip(
                        label: Text(topic.label),
                        selected: _interests.contains(topic),
                        onSelected: survey.isSaving
                            ? null
                            : (selected) {
                                setState(() {
                                  if (selected && _interests.length < 3) {
                                    _interests.add(topic);
                                  } else if (!selected) {
                                    _interests.remove(topic);
                                  }
                                });
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_interests.length} / 3 selected',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 26),
                Text(
                  'How familiar are you with AI?',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _experience,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Experience level',
                  ),
                  items: [
                    for (final entry in LearningSurvey.experienceLevels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: survey.isSaving
                      ? null
                      : (value) => setState(() => _experience = value),
                ),
                const SizedBox(height: 26),
                Text(
                  'What is your main goal?',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _goal,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Learning goal',
                  ),
                  items: [
                    for (final entry in LearningSurvey.learningGoals.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: survey.isSaving
                      ? null
                      : (value) => setState(() => _goal = value),
                ),
                if (survey.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    survey.errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed:
                      survey.isSaving ||
                          _interests.isEmpty ||
                          _experience == null ||
                          _goal == null
                      ? null
                      : _save,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      survey.isSaving
                          ? 'Saving...'
                          : widget.replay
                          ? 'Save preferences'
                          : 'Continue to learning',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your interests influence recommendations. Your knowledge '
                  'check and subsequent practice measure progress separately.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

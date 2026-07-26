import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/progress_controller.dart';
import '../../controllers/sandbox_controller.dart';
import '../widgets/prompt_score_widget.dart';

class SandboxScreen extends StatefulWidget {
  const SandboxScreen({super.key});

  @override
  State<SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends State<SandboxScreen> {
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();

  @override
  void dispose() {
    _promptController.dispose();
    _promptFocusNode.dispose();
    super.dispose();
  }

  void _reviewPrompt() {
    final sandboxController = context.read<SandboxController>();
    sandboxController.reviewPrompt(_promptController.text);

    if (sandboxController.overall >= 0.8) {
      context.read<ProgressController>().addSandboxBadge();
    }
  }

  void _reset() {
    context.read<SandboxController>().reset();
    _promptController.clear();
    _promptFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompt Coach'),
        actions: [
          IconButton(
            tooltip: 'Start over',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reset,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Consumer<SandboxController>(
          builder: (context, state, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.school_rounded),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'PromptWise will analyze your prompt and give learning suggestions. It will not rewrite the prompt or complete the task for you.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Write your own AI prompt',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'After reviewing the feedback, revise the prompt using your own words.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _promptController,
                  focusNode: _promptFocusNode,
                  minLines: 4,
                  maxLines: 7,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText:
                        'Example: Explain cybersecurity for senior high school students...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _reviewPrompt,
                    icon: const Icon(Icons.rate_review_rounded),
                    label: Text(
                      state.evaluated ? 'Review Revised Prompt' : 'Review My Prompt',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                if (state.evaluated) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Attempt ${state.attemptCount}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  PromptScoreWidget(
                    clarity: state.clarity,
                    context: state.context,
                    specificity: state.specificity,
                    responsibility: state.responsibility,
                    overall: state.overall,
                  ),
                  const SizedBox(height: 20),
                  _FeedbackCard(
                    title: 'What you did well',
                    icon: Icons.check_circle_outline_rounded,
                    items: state.strengths.isEmpty
                        ? const [
                            'No strength detected yet. Use the suggestions below as your guide.',
                          ]
                        : state.strengths,
                  ),
                  const SizedBox(height: 16),
                  _FeedbackCard(
                    title: 'Suggestions for your revision',
                    icon: Icons.lightbulb_outline_rounded,
                    items: state.suggestions.isEmpty
                        ? const [
                            'Try making the prompt more precise without making it unnecessarily long.',
                          ]
                        : state.suggestions,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.feedbackSummary,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _promptFocusNode.requestFocus(),
                          icon: const Icon(Icons.edit_rounded),
                          label: const Text('Revise It Myself'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> items;

  const _FeedbackCard({
    required this.title,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(Icons.circle, size: 6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

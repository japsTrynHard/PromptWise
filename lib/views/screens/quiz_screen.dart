import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/quiz.dart';
import '../../controllers/progress_controller.dart';

class QuizScreen extends StatefulWidget {
  final Quiz quiz;
  const QuizScreen({super.key, required this.quiz});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int? _selectedIndex;
  bool _answered = false;

  void _submitAnswer() {
    if (_selectedIndex == null) return;
    setState(() => _answered = true);
    if (_selectedIndex == widget.quiz.correctIndex) {
      context.read<ProgressController>().addQuizScore(100);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.quiz.question,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 24),
            ...List.generate(widget.quiz.options.length, (index) {
              final isCorrect = index == widget.quiz.correctIndex;
              final isSelected = _selectedIndex == index;
              Color? bgColor;
              if (_answered) {
                if (isCorrect) {
                  bgColor = Colors.green.shade50;
                } else if (isSelected && !isCorrect) {
                  bgColor = Colors.red.shade50;
                }
              } else if (isSelected) {
                bgColor = Theme.of(context).colorScheme.primaryContainer;
              }

              return Card(
                color: bgColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _answered
                        ? (isCorrect
                            ? Colors.green
                            : isSelected
                                ? Colors.red
                                : Colors.grey.shade300)
                        : Colors.grey.shade200,
                  ),
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(widget.quiz.options[index]),
                  leading: _answered
                      ? Icon(
                          isCorrect ? Icons.check_circle : Icons.cancel,
                          color: isCorrect ? Colors.green : Colors.red,
                        )
                      : Radio<int>(
                          value: index,
                          groupValue: _selectedIndex,
                          onChanged: (value) =>
                              setState(() => _selectedIndex = value),
                        ),
                  onTap: _answered
                      ? null
                      : () => setState(() => _selectedIndex = index),
                ),
              );
            }),
            if (_answered)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.quiz.explanation,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            const Spacer(),
            if (!_answered)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedIndex != null ? _submitAnswer : null,
                  child: const Text('Submit Answer'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Lessons'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

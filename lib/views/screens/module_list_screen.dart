import 'package:flutter/material.dart';
import '../../models/lesson.dart';
import 'lesson_detail_screen.dart';

class ModuleListScreen extends StatelessWidget {
  final Module module;
  const ModuleListScreen({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(module.title)),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: module.lessons.length,
        itemBuilder: (context, index) {
          final lesson = module.lessons[index];
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                lesson.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text('${lesson.estimatedMinutes} min read'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LessonDetailScreen(lesson: lesson),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

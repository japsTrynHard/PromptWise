import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'controllers/progress_controller.dart';
import 'controllers/sandbox_controller.dart';
import 'data/modules_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final progressController = ProgressController(
    totalLessons: totalLessonCount,
  );
  await progressController.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: progressController),
        ChangeNotifierProvider(create: (_) => SandboxController()),
      ],
      child: const PromptWiseApp(),
    ),
  );
}

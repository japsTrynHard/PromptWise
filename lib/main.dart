import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/app_environment.dart';
import 'controllers/adaptive_learning_controller.dart';
import 'controllers/auth_controller.dart';
import 'controllers/content_controller.dart';
import 'controllers/content_automation_controller.dart';
import 'controllers/learning_progression_controller.dart';
import 'controllers/progress_controller.dart';
import 'controllers/sandbox_controller.dart';
import 'controllers/theme_controller.dart';
import 'repositories/adaptive_learning_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/content_repository.dart';
import 'repositories/content_automation_repository.dart';
import 'repositories/learning_progression_repository.dart';
import 'repositories/progress_repository.dart';
import 'services/integration_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AuthRepository? authRepository;
  AdaptiveLearningRepository? adaptiveLearningRepository;
  ProgressRepository? progressRepository;
  ContentRepository? contentRepository;
  ContentAutomationRepository? contentAutomationRepository;
  LearningProgressionRepository? learningProgressionRepository;
  IntegrationService? integrationService;

  if (AppEnvironment.isSupabaseConfigured) {
    await Supabase.initialize(
      url: AppEnvironment.supabaseUrl,
      publishableKey: AppEnvironment.supabasePublishableKey,
    );
    final client = Supabase.instance.client;
    authRepository = AuthRepository(client);
    adaptiveLearningRepository = AdaptiveLearningRepository(client);
    progressRepository = ProgressRepository(client);
    contentRepository = ContentRepository(client);
    contentAutomationRepository = ContentAutomationRepository(client);
    learningProgressionRepository = LearningProgressionRepository(client);
    integrationService = IntegrationService(client: client);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthController(repository: authRepository)..init(),
        ),
        ChangeNotifierProxyProvider<AuthController, ContentController>(
          create: (_) => ContentController(repository: contentRepository),
          update: (_, auth, controller) {
            final content =
                controller ?? ContentController(repository: contentRepository);
            unawaited(
              content.bindAuthenticatedUser(
                auth.userId,
                isAdministrator: auth.isAdministrator,
              ),
            );
            return content;
          },
        ),
        ChangeNotifierProxyProvider2<
          AuthController,
          ContentController,
          ProgressController
        >(
          create: (_) => ProgressController(
            lessonIds: const [],
            quizIds: const [],
            remoteRepository: progressRepository,
          )..init(),
          update: (_, auth, content, controller) {
            final progressController =
                controller ??
                ProgressController(
                  lessonIds: content.lessonIds,
                  quizIds: content.quizIds,
                  remoteRepository: progressRepository,
                );
            progressController.updateContentIds(
              lessonIds: content.lessonIds,
              quizIds: content.quizIds,
            );
            unawaited(progressController.bindAuthenticatedUser(auth.userId));
            if (content.isLive &&
                progressController.syncState == ProgressSyncState.error) {
              unawaited(progressController.retryInit());
            }
            return progressController;
          },
        ),
        ChangeNotifierProxyProvider3<
          AuthController,
          ContentController,
          ProgressController,
          AdaptiveLearningController
        >(
          create: (_) => AdaptiveLearningController(
            repository: adaptiveLearningRepository,
          ),
          update: (_, auth, content, progress, controller) {
            final adaptive =
                controller ??
                AdaptiveLearningController(
                  repository: adaptiveLearningRepository,
                );
            final userId = auth.userId;
            unawaited(
              adaptive.bindAuthenticatedUser(userId).then((_) async {
                if (userId == null || auth.userId != userId) return;
                if (!content.hasLoaded ||
                    progress.activeUserId != userId ||
                    progress.isLoading) {
                  return;
                }
                await adaptive.synchronizeExistingProgress(
                  quizzes: content.quizzes,
                  bestScores: progress.progress.quizBestScores,
                );
              }),
            );
            return adaptive;
          },
        ),
        ChangeNotifierProxyProvider<AuthController, LearningProgressionController>(
          create: (_) => LearningProgressionController(
            repository: learningProgressionRepository,
          ),
          update: (_, auth, controller) {
            final progression = controller ??
                LearningProgressionController(
                  repository: learningProgressionRepository,
                );
            unawaited(progression.bindAuthenticatedUser(auth.userId));
            return progression;
          },
        ),
        ChangeNotifierProxyProvider<AuthController, ContentAutomationController>(
          create: (_) => ContentAutomationController(
            repository: contentAutomationRepository,
          ),
          update: (_, auth, controller) {
            final automation = controller ??
                ContentAutomationController(
                  repository: contentAutomationRepository,
                );
            unawaited(automation.bindAdministrator(auth.isAdministrator));
            return automation;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => SandboxController(service: integrationService),
        ),
        ChangeNotifierProvider(create: (_) => ThemeController()..init()),
      ],
      child: const PromptWiseApp(),
    ),
  );
}

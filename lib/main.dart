import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './app.dart';
import './core/config/app_environment.dart';
import './presentation/controllers/adaptive_learning_controller.dart';
import './presentation/controllers/auth_controller.dart';
import './presentation/controllers/awareness_feed_controller.dart';
import './presentation/controllers/content_controller.dart';
import './presentation/controllers/content_automation_controller.dart';
import './presentation/controllers/learning_progression_controller.dart';
import './presentation/controllers/image_comparison_controller.dart';
import './presentation/controllers/progress_controller.dart';
import './presentation/controllers/sandbox_controller.dart';
import './presentation/controllers/theme_controller.dart';
import './presentation/controllers/verification_controller.dart';
import './data/repositories/adaptive_learning_repository.dart';
import './data/repositories/auth_repository.dart';
import './data/repositories/content_repository.dart';
import './data/repositories/content_automation_repository.dart';
import './data/repositories/learning_progression_repository.dart';
import './data/repositories/progress_repository.dart';
import './data/repositories/prompt_coach_repository.dart';
import './data/repositories/verification_repository.dart';
import './data/services/integration_service.dart';
import './data/services/awareness_feed_service.dart';
import './data/services/verification_media_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AuthRepository? authRepository;
  AdaptiveLearningRepository? adaptiveLearningRepository;
  ProgressRepository? progressRepository;
  ContentRepository? contentRepository;
  ContentAutomationRepository? contentAutomationRepository;
  LearningProgressionRepository? learningProgressionRepository;
  IntegrationService? integrationService;
  PromptCoachRepository? promptCoachRepository;
  VerificationRepository? verificationRepository;
  VerificationMediaService? verificationMediaService;
  AwarenessFeedService? awarenessFeedService;

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
    promptCoachRepository = PromptCoachRepository(client);
    verificationRepository = VerificationRepository(client);
    verificationMediaService = VerificationMediaService(client: client);
    awarenessFeedService = AwarenessFeedService(client: client);
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
              unawaited(progressController.retryInit(automatic: true));
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
        ChangeNotifierProxyProvider<AuthController, VerificationController>(
          create: (_) => VerificationController(repository: verificationRepository),
          update: (_, auth, controller) {
            final verification = controller ??
                VerificationController(repository: verificationRepository);
            unawaited(verification.bindAuthenticatedUser(auth.userId));
            return verification;
          },
        ),
        ChangeNotifierProxyProvider<AuthController, ImageComparisonController>(
          create: (_) => ImageComparisonController(service: verificationMediaService),
          update: (_, auth, controller) {
            final comparison = controller ??
                ImageComparisonController(service: verificationMediaService);
            unawaited(comparison.bindAuthenticatedUser(auth.userId));
            return comparison;
          },
        ),
        ChangeNotifierProxyProvider<AuthController, AwarenessFeedController>(
          create: (_) => AwarenessFeedController(service: awarenessFeedService),
          update: (_, auth, controller) {
            final awareness = controller ??
                AwarenessFeedController(service: awarenessFeedService);
            unawaited(awareness.bindAuthenticatedUser(auth.userId));
            return awareness;
          },
        ),
        ChangeNotifierProxyProvider<AuthController, VerificationStudioController>(
          create: (_) => VerificationStudioController(
            repository: verificationRepository,
          ),
          update: (_, auth, controller) {
            final studio = controller ??
                VerificationStudioController(repository: verificationRepository);
            unawaited(studio.bindAdministrator(auth.isAdministrator));
            return studio;
          },
        ),
        ChangeNotifierProxyProvider<AuthController, SandboxController>(
          create: (_) => SandboxController(
            service: integrationService,
            repository: promptCoachRepository,
          ),
          update: (_, auth, controller) {
            final coach = controller ??
                SandboxController(
                  service: integrationService,
                  repository: promptCoachRepository,
                );
            unawaited(coach.bindAuthenticatedUser(auth.userId));
            return coach;
          },
        ),
        ChangeNotifierProvider(create: (_) => ThemeController()..init()),
      ],
      child: const PromptWiseApp(),
    ),
  );
}

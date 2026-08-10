import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/app_environment.dart';
import 'controllers/auth_controller.dart';
import 'controllers/content_controller.dart';
import 'controllers/progress_controller.dart';
import 'controllers/sandbox_controller.dart';
import 'controllers/theme_controller.dart';
import 'repositories/auth_repository.dart';
import 'repositories/content_repository.dart';
import 'repositories/progress_repository.dart';
import 'services/integration_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AuthRepository? authRepository;
  ProgressRepository? progressRepository;
  ContentRepository? contentRepository;
  IntegrationService? integrationService;

  if (AppEnvironment.isSupabaseConfigured) {
    await Supabase.initialize(
      url: AppEnvironment.supabaseUrl,
      publishableKey: AppEnvironment.supabasePublishableKey,
    );
    final client = Supabase.instance.client;
    authRepository = AuthRepository(client);
    progressRepository = ProgressRepository(client);
    contentRepository = ContentRepository(client);
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
        ChangeNotifierProvider(
          create: (_) => SandboxController(service: integrationService),
        ),
        ChangeNotifierProvider(create: (_) => ThemeController()..init()),
      ],
      child: const PromptWiseApp(),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import './presentation/controllers/auth_controller.dart';
import './presentation/controllers/theme_controller.dart';
import './core/routes/app_routes.dart';
import './core/theme/app_theme.dart';
import './core/utils/constants.dart';
import './presentation/screens/auth/reset_password_screen.dart';

class PromptWiseApp extends StatelessWidget {
  const PromptWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeController>().themeMode;
    final passwordRecovery = context.watch<AuthController>().isPasswordRecovery;

    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      themeAnimationDuration: AppMotion.normal,
      themeAnimationCurve: AppMotion.standardCurve,
      initialRoute: AppRoutes.root,
      onGenerateRoute: AppRoutes.generateRoute,
      builder: (context, child) {
        if (passwordRecovery) {
          return const ResetPasswordScreen();
        }

        final content = child ?? const SizedBox.shrink();
        final disableAnimations =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;

        if (disableAnimations) {
          return content;
        }

        // Repaint isolation keeps theme and route animations from forcing
        // expensive repaints outside the active app surface.
        return RepaintBoundary(child: content);
      },
    );
  }
}

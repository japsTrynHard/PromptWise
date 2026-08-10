import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/auth_controller.dart';
import 'controllers/theme_controller.dart';
import 'routes/app_routes.dart';
import 'theme/app_theme.dart';
import 'utils/constants.dart';
import 'views/screens/auth/reset_password_screen.dart';

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
      initialRoute: AppRoutes.root,
      onGenerateRoute: AppRoutes.generateRoute,
      builder: (context, child) {
        if (passwordRecovery) return const ResetPasswordScreen();
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

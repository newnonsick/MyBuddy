import 'package:flutter/material.dart';

import '../features/chat/presentation/pages/buddy_home_page.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyBuddy',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const BuddyHomePage(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      colorScheme: AppColors.colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

abstract final class AppColors {
  static const Color primary = Color(0xFF0A84FF);
  static const Color secondary = Color(0xFFC7B17B);

  static const Color surface = Color(0xFF111217);
  static const Color surfaceLight = Color(0xFF1A1A1D);

  static const Color error = Color(0xFFFF5E5E);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);

  static const Color statusOnline = Color(0xFF34C759);
  static const Color statusOffline = Color(0xFFFF3B30);

  static const ColorScheme colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: primary,
    onPrimary: Colors.white,
    secondary: secondary,
    onSecondary: surface,
    surface: surface,
    onSurface: Colors.white,
    error: error,
    onError: Colors.white,
  );
}

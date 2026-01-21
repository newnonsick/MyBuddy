import 'package:flutter/material.dart';

import 'package:mybuddy/features/chat/presentation/pages/buddy_home_page.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyBuddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF0A84FF),
          onPrimary: Colors.white,
          secondary: Color(0xFFC7B17B),
          onSecondary: Color(0xFF111217),
          surface: Color(0xFF111217),
          onSurface: Colors.white,
          error: Color(0xFFFF5E5E),
          onError: Colors.white,
        ),
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
      ),
      home: const BuddyHomePage(),
    );
  }
}

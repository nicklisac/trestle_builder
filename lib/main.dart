import 'package:flutter/material.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(const TrestleBuilderApp());
}

class TrestleBuilderApp extends StatelessWidget {
  const TrestleBuilderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trestle Track Builder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFe94560),
          secondary: Color(0xFF533483),
          surface: Color(0xFF1a1a2e),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

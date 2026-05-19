import 'package:flutter/material.dart';
import 'screens/gallery_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShutRApp());
}

class ShutRApp extends StatelessWidget {
  const ShutRApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shutr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      home: const GalleryScreen(),
    );
  }
}

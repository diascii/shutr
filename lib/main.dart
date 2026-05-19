import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/gallery_screen.dart';
import 'services/peer_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set edge-to-edge globally; viewer switches to immersiveSticky
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PeerService()),
      ],
      child: const ShutRApp(),
    ),
  );
}

class ShutRApp extends StatelessWidget {
  const ShutRApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData.dark(useMaterial3: true);

    return MaterialApp(
      title: 'Shutr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B8AFF),
          brightness: Brightness.dark,
          primary: const Color(0xFF6B8AFF),
          surface: const Color(0xFF0A0A0A),
          surfaceContainer: const Color(0xFF141414),
          surfaceContainerHigh: const Color(0xFF1C1C1C),
          surfaceContainerHighest: const Color(0xFF2A2A2A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme).copyWith(
          displayLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w300, letterSpacing: -1.5),
          titleLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w400, letterSpacing: -0.5),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1C1C1C),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6B8AFF),
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(56),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            elevation: 0,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF141414),
          selectedItemColor: Colors.white,
          unselectedItemColor: Color(0xFF555555),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        extensions: const [
          ShutrThemeExtension(
            surfaceVariant: Color(0xFF141414),
            glassyBackground: Color(0xCC0A0A0A),
          ),
        ],
      ),
      home: const PermissionGate(),
    );
  }
}

@immutable
class ShutrThemeExtension extends ThemeExtension<ShutrThemeExtension> {
  const ShutrThemeExtension({
    required this.surfaceVariant,
    required this.glassyBackground,
  });

  final Color surfaceVariant;
  final Color glassyBackground;

  @override
  ShutrThemeExtension copyWith({
    Color? surfaceVariant,
    Color? glassyBackground,
  }) {
    return ShutrThemeExtension(
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      glassyBackground: glassyBackground ?? this.glassyBackground,
    );
  }

  @override
  ShutrThemeExtension lerp(
      ThemeExtension<ShutrThemeExtension>? other, double t) {
    if (other is! ShutrThemeExtension) return this;
    return ShutrThemeExtension(
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      glassyBackground:
          Color.lerp(glassyBackground, other.glassyBackground, t)!,
    );
  }
}

class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool _checked = false;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth || ps.hasAccess) {
      setState(() {
        _granted = true;
        _checked = true;
      });
    } else {
      setState(() => _checked = true);
    }
  }

  Future<void> _request() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();

    // Also request notifications for the live feature
    await Permission.notification.request();

    if (ps.isAuth || ps.hasAccess) {
      setState(() => _granted = true);
    } else {
      // If still not granted, user might need to go to settings
      final status = await Permission.photos.status;
      if (status.isPermanentlyDenied) {
        openAppSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    if (_granted) return const GalleryScreen();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 32),
            Text(
              'Access your Gallery',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'Shutr needs permission to show your photos and save the ones shared by your friends.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white54,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _request,
              child: const Text('Grant Access'),
            ),
          ],
        ),
      ),
    );
  }
}

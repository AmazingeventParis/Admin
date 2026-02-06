import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/screens/splash_screen.dart';
// import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force l'orientation portrait pour un jeu mobile
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Mode plein écran immersif - masque la barre de navigation
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );

  // Barre de statut transparente pour un look immersif
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Supabase désactivé temporairement pour debug iOS
  // try {
  //   await SupabaseService.initialize();
  // } catch (e) {
  //   print('Erreur Supabase init: $e');
  // }

  runApp(const BlockPuzzleApp());
}

class BlockPuzzleApp extends StatelessWidget {
  const BlockPuzzleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Candy Puzzle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00BCD4),
          secondary: Color(0xFF4CAF50),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

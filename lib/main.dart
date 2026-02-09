import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/menu_screen.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';

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

  // Initialiser Supabase
  try {
    await SupabaseService.initialize();
  } catch (e) {
    print('Erreur Supabase init: $e');
  }

  // Initialiser OneSignal pour les notifications push
  try {
    await NotificationService.initialize();
  } catch (e) {
    print('Erreur OneSignal init: $e');
  }

  // Vérifier si l'utilisateur est déjà connecté
  bool hasSession = false;
  try {
    await supabaseService.checkSession();
    hasSession = supabaseService.isLoggedIn;
  } catch (e) {
    print('Erreur checkSession: $e');
  }

  // Vérifier aussi si un joueur anonyme a déjà mis son prénom
  if (!hasSession) {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('userName');
      if (savedName != null && savedName.isNotEmpty) {
        hasSession = true;
      }
    } catch (e) {
      print('Erreur SharedPreferences: $e');
    }
  }

  runApp(BlockPuzzleApp(isLoggedIn: hasSession));
}

class BlockPuzzleApp extends StatelessWidget {
  final bool isLoggedIn;

  const BlockPuzzleApp({super.key, required this.isLoggedIn});

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
      home: isLoggedIn ? const MenuScreen() : const AuthScreen(),
    );
  }
}

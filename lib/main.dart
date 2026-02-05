import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_preview/device_preview.dart';
import 'package:device_frame/device_frame.dart';
import 'ui/screens/splash_screen.dart';
import 'services/supabase_service.dart';

// Mettre à true pour activer Device Preview (mode test)
// Mettre à false pour la version production (APK final)
const bool kEnableDevicePreview = false;

// ============================================
// APPAREILS PERSONNALISÉS - TOP VENTES MONDE
// ============================================
final customDevices = <DeviceInfo>[
  // --- SAMSUNG GALAXY A SERIES (très populaire) ---
  DeviceInfo.genericPhone(
    id: 'samsung-a54',
    name: 'Samsung Galaxy A54',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2340),
    pixelRatio: 2.625,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'samsung-a34',
    name: 'Samsung Galaxy A34',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2340),
    pixelRatio: 2.625,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'samsung-a14',
    name: 'Samsung Galaxy A14',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2408),
    pixelRatio: 2.625,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),

  // --- SAMSUNG GALAXY S SERIES ---
  DeviceInfo.genericPhone(
    id: 'samsung-s23',
    name: 'Samsung Galaxy S23',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2340),
    pixelRatio: 2.625,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'samsung-s23-ultra',
    name: 'Samsung Galaxy S23 Ultra',
    platform: TargetPlatform.android,
    screenSize: const Size(1440, 3088),
    pixelRatio: 3.0,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'samsung-s24',
    name: 'Samsung Galaxy S24',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2340),
    pixelRatio: 2.625,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'samsung-s24-ultra',
    name: 'Samsung Galaxy S24 Ultra',
    platform: TargetPlatform.android,
    screenSize: const Size(1440, 3120),
    pixelRatio: 3.0,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),

  // --- XIAOMI / REDMI (très populaire budget) ---
  DeviceInfo.genericPhone(
    id: 'xiaomi-redmi-note-13',
    name: 'Xiaomi Redmi Note 13',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'xiaomi-redmi-note-12',
    name: 'Xiaomi Redmi Note 12',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'xiaomi-redmi-13c',
    name: 'Xiaomi Redmi 13C',
    platform: TargetPlatform.android,
    screenSize: const Size(720, 1600),
    pixelRatio: 2.0,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'xiaomi-14',
    name: 'Xiaomi 14',
    platform: TargetPlatform.android,
    screenSize: const Size(1200, 2670),
    pixelRatio: 2.875,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),

  // --- HUAWEI ---
  DeviceInfo.genericPhone(
    id: 'huawei-nova-12',
    name: 'Huawei Nova 12',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2412),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'huawei-p60',
    name: 'Huawei P60',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'huawei-mate-60',
    name: 'Huawei Mate 60',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),

  // --- HONOR ---
  DeviceInfo.genericPhone(
    id: 'honor-90',
    name: 'Honor 90',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'honor-magic-6',
    name: 'Honor Magic 6',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2376),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'honor-x8',
    name: 'Honor X8',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2388),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),

  // --- OPPO ---
  DeviceInfo.genericPhone(
    id: 'oppo-reno-11',
    name: 'Oppo Reno 11',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'oppo-a79',
    name: 'Oppo A79',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),

  // --- VIVO ---
  DeviceInfo.genericPhone(
    id: 'vivo-v30',
    name: 'Vivo V30',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'vivo-y100',
    name: 'Vivo Y100',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),

  // --- ONEPLUS ---
  DeviceInfo.genericPhone(
    id: 'oneplus-12',
    name: 'OnePlus 12',
    platform: TargetPlatform.android,
    screenSize: const Size(1440, 3168),
    pixelRatio: 3.0,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'oneplus-nord',
    name: 'OnePlus Nord CE 3',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),

  // --- GOOGLE PIXEL ---
  DeviceInfo.genericPhone(
    id: 'pixel-7',
    name: 'Google Pixel 7',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'pixel-7-pro',
    name: 'Google Pixel 7 Pro',
    platform: TargetPlatform.android,
    screenSize: const Size(1440, 3120),
    pixelRatio: 3.0,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'pixel-8',
    name: 'Google Pixel 8',
    platform: TargetPlatform.android,
    screenSize: const Size(1080, 2400),
    pixelRatio: 2.75,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
  DeviceInfo.genericPhone(
    id: 'pixel-8-pro',
    name: 'Google Pixel 8 Pro',
    platform: TargetPlatform.android,
    screenSize: const Size(1344, 2992),
    pixelRatio: 3.0,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),

  // --- PETIT ÉCRAN (budget / ancien) ---
  DeviceInfo.genericPhone(
    id: 'samsung-a05',
    name: 'Samsung Galaxy A05 (petit)',
    platform: TargetPlatform.android,
    screenSize: const Size(720, 1600),
    pixelRatio: 2.0,
    safeAreas: const EdgeInsets.only(top: 24, bottom: 16),
  ),
];

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
  await SupabaseService.initialize();

  runApp(
    kEnableDevicePreview
        ? DevicePreview(
            enabled: true,
            devices: [
              // Appareils personnalisés (top ventes)
              ...customDevices,
              // Garder quelques iPhone populaires
              Devices.ios.iPhone13,
              Devices.ios.iPhone13ProMax,
              Devices.ios.iPhone12,
              Devices.ios.iPhone12ProMax,
              Devices.ios.iPhoneSE,
            ],
            builder: (context) => const BlockPuzzleApp(),
          )
        : const BlockPuzzleApp(),
  );
}

class BlockPuzzleApp extends StatelessWidget {
  const BlockPuzzleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Candy Puzzle',
      debugShowCheckedModeBanner: false,
      // Device Preview settings
      useInheritedMediaQuery: kEnableDevicePreview,
      locale: kEnableDevicePreview ? DevicePreview.locale(context) : null,
      builder: kEnableDevicePreview ? DevicePreview.appBuilder : null,
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

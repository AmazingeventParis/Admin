import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/audio_service.dart';
import 'auth_screen.dart';
import 'menu_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _bounceAnimation;

  // Animation rotation du cercle
  late AnimationController _circleController;

  // Animation bulle du texte PLAY
  late AnimationController _playController;
  late Animation<double> _playScaleAnimation;

  // Animation du logo
  late AnimationController _logoController;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoBounceAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _bounceAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Rotation continue du cercle
    _circleController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    // Animation bulle pour PLAY
    _playController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _playScaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _playController, curve: Curves.easeInOut),
    );

    // Animation du logo - balancement gauche/droite
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);

    // Rotation de balancement (-5° à +5°)
    _logoScaleAnimation = Tween<double>(begin: -0.08, end: 0.08).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    // Léger mouvement horizontal
    _logoBounceAnimation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    // Lancer la musique d'intro via le service global
    try {
      audioService.playIntroMusic();
    } catch (e) {
      print('Erreur audio: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _circleController.dispose();
    _playController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  void _navigateToGame() async {
    // Vérifier si l'utilisateur est déjà connecté avec Google
    try {
      await supabaseService.checkSession();
    } catch (e) {
      print('Erreur checkSession: $e');
    }

    if (!mounted) return;

    // Si connecté, aller directement au menu, sinon à l'écran de connexion
    final destination = supabaseService.isLoggedIn
        ? const MenuScreen()
        : const AuthScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFFFB6C1),
      body: GestureDetector(
        onTap: _navigateToGame,
        child: Container(
          width: screenWidth,
          height: screenHeight,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/ui/Fond.png'),
              fit: BoxFit.fill,
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: screenHeight * 0.08),

              // Logo titre en haut - animé balancement
              AnimatedBuilder(
                animation: _logoController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_logoBounceAnimation.value, 0),
                    child: Transform.rotate(
                      angle: _logoScaleAnimation.value,
                      child: child,
                    ),
                  );
                },
                child: Image.asset(
                  'assets/ui/Logo titre.png',
                  width: screenWidth * 0.9,
                ),
              ),

              SizedBox(height: screenHeight * 0.05),

              // Zone centrale - dans le cadre du fond (remonté de 15%)
              Expanded(
                child: Container(
                  alignment: Alignment.topCenter,
                  padding: EdgeInsets.only(top: screenHeight * 0.02),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, -_bounceAnimation.value),
                        child: Transform.scale(
                          scale: _scaleAnimation.value,
                          child: child,
                        ),
                      );
                    },
                    child: SizedBox(
                      width: screenWidth * 0.7,
                      height: screenWidth * 0.7,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Play logo (triangle) - centré (pas agrandi)
                          Center(
                            child: Image.asset(
                              'assets/ui/play logo.png',
                              width: screenWidth * 0.5,
                              height: screenWidth * 0.5,
                            ),
                          ),
                          // Cercle (lollipop) - descendu à la même hauteur que l'ours
                          Positioned(
                            right: screenWidth * 0.02,
                            bottom: screenWidth * 0.08,
                            child: AnimatedBuilder(
                              animation: _circleController,
                              builder: (context, child) {
                                return Transform.rotate(
                                  angle: _circleController.value * 2 * 3.14159,
                                  child: child,
                                );
                              },
                              child: Image.asset(
                                'assets/ui/cercle.png',
                                width: screenWidth * 0.42,
                                height: screenWidth * 0.42,
                              ),
                            ),
                          ),
                          // Ourse (bear) - agrandi de 20%
                          Positioned(
                            left: screenWidth * 0.0,
                            bottom: screenWidth * 0.10,
                            child: Image.asset(
                              'assets/ui/ourse.png',
                              width: screenWidth * 0.31,
                              height: screenWidth * 0.43,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Texte PLAY - descendu de 10%
              Transform.translate(
                offset: Offset(0, -screenHeight * 0.10),
                child: AnimatedBuilder(
                  animation: _playController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _playScaleAnimation.value,
                      child: child,
                    );
                  },
                  child: Image.asset(
                    'assets/ui/play.png',
                    width: screenWidth * 0.55,
                  ),
                ),
              ),

              SizedBox(height: screenHeight * 0.02),
            ],
          ),
        ),
      ),
    );
  }
}

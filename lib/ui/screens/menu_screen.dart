import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../widgets/candy_ui.dart';
import 'game_screen.dart';
import 'profile_screen.dart';
import 'auth_screen.dart';
import 'leaderboard_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with TickerProviderStateMixin {
  String _userName = 'Joueur';
  String? _googlePhotoUrl;

  // Animation pour le bouton JOUER
  late AnimationController _buttonController;
  late Animation<double> _buttonScaleAnimation;

  // Animation pour les boutons du menu en bas
  late AnimationController _menuButtonController;
  late Animation<double> _menuButtonAnimation;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _setupAnimations();
  }

  void _setupAnimations() {
    _buttonController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );

    // Animation douce pour les boutons du menu
    _menuButtonController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _menuButtonAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _menuButtonController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadUserData() async {
    await supabaseService.checkSession();
    if (supabaseService.isLoggedIn && supabaseService.userName != null) {
      setState(() {
        _userName = supabaseService.userName!;
        _googlePhotoUrl = supabaseService.userAvatar;
      });
    }
  }

  @override
  void dispose() {
    _buttonController.dispose();
    _menuButtonController.dispose();
    super.dispose();
  }

  void _startGame() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GameScreen()),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    );
  }

  void _openSettings() {
    // TODO: Implémenter la page paramètres
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Paramètres - Bientôt disponible'),
        backgroundColor: Colors.purple,
      ),
    );
  }

  void _openLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
    );
  }

  void _openMessages() {
    // TODO: Implémenter les messages
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Messages - Bientôt disponible'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _logout() async {
    await supabaseService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Container(
        width: screenWidth,
        height: screenHeight,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/ui/fondpageaccueil.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header avec profil
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Avatar et nom
                    GestureDetector(
                      onTap: _openProfile,
                      child: Row(
                        children: [
                          CandyAvatarButton(
                            letter: _userName.isNotEmpty ? _userName[0] : '?',
                            backgroundImage: 'assets/ui/cerclevidephoto.png',
                            onTap: _openProfile,
                            size: 60,
                            profilePhotoUrl: _googlePhotoUrl,
                          ),
                          const SizedBox(width: 10),
                          CandyText(
                            text: _userName,
                            fontSize: 18,
                            textColor: Colors.white,
                            strokeColor: const Color(0xFFE91E63),
                            strokeWidth: 2,
                          ),
                        ],
                      ),
                    ),
                    // Bouton paramètres
                    CandyCircleButton(
                      icon: Icons.settings,
                      backgroundImage: 'assets/ui/cercleparametres.png',
                      onTap: _openSettings,
                      size: 55,
                    ),
                  ],
                ),
              ),

              // Logo et bouton JOUER
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(height: screenHeight * 0.08),
                    // Logo du jeu
                    Image.asset(
                      'assets/ui/Logo titre.png',
                      width: screenWidth * 0.8,
                    ),
                    const SizedBox(height: 40),

                    // Bouton JOUER
                    AnimatedBuilder(
                      animation: _buttonController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _buttonScaleAnimation.value,
                          child: child,
                        );
                      },
                      child: GestureDetector(
                        onTap: _startGame,
                        child: Container(
                          width: screenWidth * 0.6,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                            ),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE91E63).withOpacity(0.5),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: CandyText(
                              text: 'JOUER',
                              fontSize: 32,
                              textColor: Colors.white,
                              strokeColor: Color(0xFFAD1457),
                              strokeWidth: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Menu en bas avec les boutons candy
              _buildBottomMenu(screenWidth),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomMenu(double screenWidth) {
    final menuHeight = screenWidth * 0.22;
    final buttonSize = screenWidth * 0.25;

    return Container(
      width: screenWidth,
      height: menuHeight + 20,
      padding: const EdgeInsets.only(bottom: 10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Fond du menu (Menu.png)
          Image.asset(
            'assets/ui/Menu.png',
            width: screenWidth * 0.95,
            fit: BoxFit.contain,
          ),
          // Boutons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Bouton Accueil (pas animé - on est sur cette page)
              _buildStaticMenuButton(
                'assets/ui/Boutonaccueil.png',
                buttonSize,
              ),
              // Bouton Leader (animé)
              _buildAnimatedMenuButton(
                'assets/ui/boutonleader.png',
                buttonSize,
                _openLeaderboard,
                0.33,
              ),
              // Bouton Messages (animé)
              _buildAnimatedMenuButton(
                'assets/ui/boutonmessages.png',
                buttonSize,
                _openMessages,
                0.66,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedMenuButton(String asset, double size, VoidCallback onTap, double delay) {
    return AnimatedBuilder(
      animation: _menuButtonController,
      builder: (context, child) {
        // Animation avec décalage pour effet vague
        final animValue = (_menuButtonAnimation.value + delay) % 1.0;
        final scale = 1.0 + 0.08 * (0.5 - (animValue - 0.5).abs()) * 2;
        final translateY = -5.0 * (0.5 - (animValue - 0.5).abs()) * 2;

        return Transform.translate(
          offset: Offset(0, translateY),
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Image.asset(
          asset,
          width: size,
          height: size,
        ),
      ),
    );
  }

  // Bouton statique (page courante - pas d'animation)
  Widget _buildStaticMenuButton(String asset, double size) {
    return Opacity(
      opacity: 0.6,
      child: Image.asset(
        asset,
        width: size,
        height: size,
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/supabase_service.dart';
import '../../services/duel_service.dart';
import '../../services/friend_service.dart';
import '../../services/message_service.dart';
import '../widgets/candy_ui.dart';
import 'game_screen.dart';
import 'profile_screen.dart';
import 'auth_screen.dart';
import 'leaderboard_screen.dart';
import 'duel_screen.dart';
import 'messages_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  String _userName = 'Joueur';
  String? _googlePhotoUrl;
  int _pendingDuelCount = 0;
  int _unreadMessageCount = 0;

  // Animation pour le bouton JOUER
  late AnimationController _buttonController;
  late Animation<double> _buttonScaleAnimation;

  // Animation pour les boutons du menu en bas
  late AnimationController _menuButtonController;
  late Animation<double> _menuButtonAnimation;

  // Timer pour mise à jour du statut en ligne
  Timer? _onlineStatusTimer;
  // Timer pour rotation des bots en ligne
  Timer? _botRotationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
    _setupAnimations();
    _startOnlineStatusUpdater();
    _startBotOnlineSimulation();
    _checkPendingBotCompletion();
  }

  /// Détecte quand l'app passe en arrière-plan ou revient
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // App en arrière-plan ou fermée → mettre hors ligne immédiatement
      friendService.setOffline(playerId);
    } else if (state == AppLifecycleState.resumed) {
      // App revenue au premier plan → mettre en ligne
      _updateOnlineStatus();
    }
  }

  /// Démarre le timer pour mettre à jour le statut "en ligne" toutes les minutes
  void _startOnlineStatusUpdater() {
    _updateOnlineStatus(); // Mise à jour immédiate
    _onlineStatusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateOnlineStatus();
    });
  }

  /// Met à jour le statut "en ligne" dans la base de données
  Future<void> _updateOnlineStatus() async {
    final playerId = supabaseService.playerId;
    if (playerId != null) {
      await friendService.updateOnlineStatus(playerId);
    }
  }

  /// Vérifie si un bot doit finir sa partie (soumission différée)
  Future<void> _checkPendingBotCompletion() async {
    final prefs = await SharedPreferences.getInstance();
    final duelId = prefs.getString('pending_bot_duel_id');
    if (duelId == null) return;

    final finishAt = prefs.getInt('pending_bot_finish_at') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now >= finishAt) {
      // Le bot a fini, soumettre son score
      final opponentId = prefs.getString('pending_bot_opponent_id') ?? '';
      final botScore = prefs.getInt('pending_bot_score') ?? 0;
      final botTime = prefs.getInt('pending_bot_time') ?? 60;

      try {
        await duelService.submitScore(
          duelId: duelId,
          playerId: opponentId,
          score: botScore,
          timeInSeconds: botTime,
        );
      } catch (e) {
        print('Erreur soumission bot différée: $e');
      }

      // Nettoyer
      await prefs.remove('pending_bot_duel_id');
      await prefs.remove('pending_bot_opponent_id');
      await prefs.remove('pending_bot_score');
      await prefs.remove('pending_bot_time');
      await prefs.remove('pending_bot_finish_at');
    } else {
      // Pas encore le moment, planifier pour plus tard
      final remaining = finishAt - now;
      Timer(Duration(milliseconds: remaining), () {
        if (mounted) _checkPendingBotCompletion();
      });
    }
  }

  /// Simule des bots en ligne de manière aléatoire
  void _startBotOnlineSimulation() {
    // Première rotation immédiate (choix aléatoire des bots en ligne)
    friendService.simulateBotOnlineStatus();

    // Rafraîchir le last_seen_at des bots en ligne toutes les 45 secondes
    _botRotationTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
      friendService.refreshBotOnlineStatus();
    });

    // Changer les bots en ligne toutes les 3-5 minutes (rotation)
    Future.delayed(Duration(minutes: 3 + DateTime.now().second % 3), () {
      if (mounted) {
        _rotateBots();
      }
    });
  }

  /// Rotation des bots en ligne (change le groupe de bots connectés)
  void _rotateBots() async {
    await friendService.simulateBotOnlineStatus();
    // Planifier la prochaine rotation dans 3-5 minutes
    Future.delayed(Duration(minutes: 3 + DateTime.now().second % 3), () {
      if (mounted) {
        _rotateBots();
      }
    });
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
    } else {
      // Joueur anonyme : lire le prénom depuis SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('userName');
      if (savedName != null && savedName.isNotEmpty && mounted) {
        // Initialiser le joueur dans la base de données
        await supabaseService.getOrCreatePlayer(savedName);
        setState(() {
          _userName = savedName;
        });
      } else if (mounted) {
        // Pas de prénom sauvegardé → renvoyer vers l'écran de connexion
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthScreen()),
          (route) => false,
        );
        return;
      }
    }

    // Charger le nombre de duels en attente et messages non lus
    final playerId = supabaseService.playerId;
    if (playerId != null) {
      final duelCount = await duelService.getPendingDuelCount(playerId);
      final messageCount = await messageService.getTotalUnreadCount(playerId);
      if (mounted) {
        setState(() {
          _pendingDuelCount = duelCount;
          _unreadMessageCount = messageCount;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onlineStatusTimer?.cancel();
    _botRotationTimer?.cancel();
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MessagesScreen()),
    );
  }

  void _openDuel() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DuelScreen()),
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
    final buttonSize = screenWidth * 0.20; // Réduit pour 4 boutons

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
                0.25,
              ),
              // Bouton Messages (animé) avec badge
              _buildMessagesButtonWithBadge(buttonSize),
              // Bouton Duel (animé) avec badge
              _buildDuelButtonWithBadge(buttonSize),
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
  /// Bouton Messages avec badge de notification
  Widget _buildMessagesButtonWithBadge(double size) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildAnimatedMenuButton(
          'assets/ui/boutonmessages.png',
          size,
          _openMessages,
          0.50,
        ),
        if (_unreadMessageCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.5),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _unreadMessageCount > 9 ? '9+' : '$_unreadMessageCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Bouton Duel avec badge de notification
  Widget _buildDuelButtonWithBadge(double size) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildAnimatedMenuButton(
          'assets/ui/boutonduel.png',
          size,
          _openDuel,
          0.75,
        ),
        if (_pendingDuelCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.5),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _pendingDuelCount > 9 ? '9+' : '$_pendingDuelCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

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

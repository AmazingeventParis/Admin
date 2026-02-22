import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/supabase_service.dart';
import '../../services/stats_service.dart';
import '../../services/duel_service.dart';
import '../../services/friend_service.dart';
import '../../services/message_service.dart';
import '../widgets/candy_ui.dart';
import 'game_screen.dart';
import 'profile_screen.dart';
import 'auth_screen.dart';
import 'leaderboard_screen.dart';
import 'duel_screen.dart';
import 'duel_lobby_screen.dart';
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

    // Vérifier le bonus de connexion quotidienne
    await statsService.init();
    final dailyReward = await statsService.checkDailyLogin();
    if (dailyReward > 0 && mounted) {
      _showDailyRewardDialog(dailyReward);
    }
  }

  /// Affiche le popup de récompense de connexion quotidienne
  void _showDailyRewardDialog(int reward) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D1B69),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('🍬', style: TextStyle(fontSize: 28)),
            SizedBox(width: 8),
            Text(
              'Bonus quotidien !',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+$reward bonbons',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Jour ${statsService.loginStreak}',
              style: const TextStyle(
                color: Color(0xFFFF6B9D),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Reviens demain pour encore plus !',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B9D),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text(
                'Super !',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
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

  void _startGame() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GameScreen()),
    );
    // Rafraîchir le solde de bonbons au retour
    if (mounted) setState(() {});
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

  /// Affiche le popup des joueurs en ligne pour lancer un duel rapide
  Future<void> _playOnline() async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    // Afficher le popup avec un loader pendant le chargement
    showDialog(
      context: context,
      builder: (dialogContext) {
        return _OnlinePlayersDialog(
          playerId: playerId,
          onChallenge: (player) => _challengeFromPopup(player, dialogContext),
        );
      },
    );
  }

  /// Lance un duel depuis le popup joueurs en ligne
  Future<void> _challengeFromPopup(PlayerSummary player, BuildContext dialogContext) async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    // Vérifier le solde de bonbons
    if (!statsService.canAffordDuel) {
      Navigator.pop(dialogContext);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF2D1B69),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              'Pas assez de bonbons !',
              style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🍬', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  'Tu as ${statsService.candies} bonbons.\nIl en faut au moins 20 pour un duel.',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Joue en solo pour en gagner !',
                  style: TextStyle(color: Color(0xFFFF6B9D), fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B9D),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Fermer le popup joueurs en ligne
    Navigator.pop(dialogContext);

    // Afficher le popup de sélection de mise
    final betAmount = await _showBetSelectionDialog();
    if (betAmount == null || !mounted) return; // Annulé

    // Déduire la mise
    await statsService.removeCandies(betAmount);
    await statsService.syncToCloud();
    setState(() {}); // Rafraîchir l'affichage du solde

    // Créer le duel avec la mise
    final duel = await duelService.createDuel(
      challengerId: playerId,
      challengedId: player.id,
      betAmount: betAmount,
    );

    if (duel != null && mounted) {
      final isBot = await duelService.isBot(player.id);

      if (isBot) {
        // Bot : auto-accept et lancer la partie
        await duelService.acceptDuelLive(duel.id);
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GameScreen(
                duelSeed: duel.seed,
                duelId: duel.id,
                opponentId: player.id,
                opponentName: player.username,
                opponentPhotoUrl: player.photoUrl,
                isBotDuel: true,
                betAmount: betAmount,
              ),
            ),
          );
          // Rafraîchir les compteurs au retour
          _loadUserData();
        }
      } else {
        // Joueur réel : vérifier s'il est en ligne pour mode temps réel
        final isOnline = player.isOnline;
        if (isOnline && mounted) {
          await duelService.acceptDuelLive(duel.id);
          if (mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DuelLobbyScreen(
                  duel: duel,
                  myPlayerId: playerId,
                  opponentId: player.id,
                  opponentName: player.username,
                  opponentPhotoUrl: player.photoUrl,
                  myName: supabaseService.userName,
                  myPhotoUrl: supabaseService.userAvatar,
                ),
              ),
            );
            if (mounted) _loadUserData();
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Défi envoyé à ${player.username} !'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// Affiche le popup de sélection de mise pour un duel
  Future<int?> _showBetSelectionDialog() async {
    final currentCandies = statsService.candies;
    int selectedBet = 50.clamp(20, currentCandies);

    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Options de mise
            final betOptions = <int>[20, 50, 100];
            // Ajouter "Tout miser" si > 100
            if (currentCandies > 100) {
              betOptions.add(currentCandies);
            }
            // Filtrer les options que le joueur peut se permettre
            final affordableOptions = betOptions.where((b) => b <= currentCandies).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF2D1B69),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              title: const Text(
                'Choisis ta mise',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Solde actuel
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🍬', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 6),
                      Text(
                        '$currentCandies bonbons',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Boutons de mise
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: affordableOptions.map((bet) {
                      final isSelected = selectedBet == bet;
                      final label = bet == currentCandies && bet > 100 ? 'TOUT' : '$bet';
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedBet = bet),
                        child: Container(
                          width: 75,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isSelected
                                  ? [const Color(0xFFFFD700), const Color(0xFFFFA500)]
                                  : [const Color(0xFF4A148C), const Color(0xFF7C4DFF)],
                            ),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.white38,
                              width: isSelected ? 3 : 1.5,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.4), blurRadius: 10)]
                                : null,
                          ),
                          child: Column(
                            children: [
                              const Text('🍬', style: TextStyle(fontSize: 16)),
                              const SizedBox(height: 2),
                              Text(
                                label,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: isSelected ? 18 : 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, selectedBet),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B9D),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Text(
                          'MISER $selectedBet 🍬',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
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
                    // Bonbons + Paramètres
                    Row(
                      children: [
                        // Solde bonbons
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFFF6B9D).withOpacity(0.7),
                                const Color(0xFFE91E63).withOpacity(0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🍬', style: TextStyle(fontSize: 16)),
                              const SizedBox(width: 4),
                              Text(
                                '${statsService.candies}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  shadows: [
                                    Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Bouton paramètres
                        CandyCircleButton(
                          icon: Icons.settings,
                          backgroundImage: 'assets/ui/cercleparametres.png',
                          onTap: _openSettings,
                          size: 55,
                        ),
                      ],
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

                    const SizedBox(height: 16),

                    // Bouton JOUER EN LIGNE
                    GestureDetector(
                      onTap: _playOnline,
                      child: Container(
                        width: screenWidth * 0.5,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C4DFF), Color(0xFF651FFF)],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF651FFF).withOpacity(0.5),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.wifi, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            CandyText(
                              text: 'EN LIGNE',
                              fontSize: 20,
                              textColor: Colors.white,
                              strokeColor: Color(0xFF4A148C),
                              strokeWidth: 2,
                            ),
                          ],
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

/// Popup qui affiche les joueurs en ligne
class _OnlinePlayersDialog extends StatefulWidget {
  final String playerId;
  final Function(PlayerSummary) onChallenge;

  const _OnlinePlayersDialog({
    required this.playerId,
    required this.onChallenge,
  });

  @override
  State<_OnlinePlayersDialog> createState() => _OnlinePlayersDialogState();
}

class _OnlinePlayersDialogState extends State<_OnlinePlayersDialog> {
  List<PlayerSummary>? _players;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOnlinePlayers();
  }

  Future<void> _loadOnlinePlayers() async {
    final players = await friendService.getOnlinePlayers(widget.playerId);
    if (mounted) {
      setState(() {
        _players = players;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2A1B3D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 450, maxWidth: 340),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Titre
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.wifi, color: Color(0xFF7C4DFF), size: 24),
                SizedBox(width: 8),
                CandyText(
                  text: 'JOUEURS EN LIGNE',
                  fontSize: 20,
                  textColor: Colors.white,
                  strokeColor: Color(0xFF7C4DFF),
                  strokeWidth: 2,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Contenu
            Flexible(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF7C4DFF),
                      ),
                    )
                  : _players == null || _players!.isEmpty
                      ? _buildEmptyState()
                      : _buildPlayerList(),
            ),

            const SizedBox(height: 12),

            // Bouton fermer
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Fermer',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.wifi_off, color: Colors.white.withOpacity(0.3), size: 48),
        const SizedBox(height: 12),
        Text(
          'Aucun joueur en ligne',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          'Reviens plus tard ou défie un bot !',
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPlayerList() {
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _players!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final player = _players![index];
        return _buildPlayerTile(player);
      },
    );
  }

  Widget _buildPlayerTile(PlayerSummary player) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFD700),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: ClipOval(
              child: player.photoUrl != null
                  ? Image.network(
                      player.photoUrl!,
                      fit: BoxFit.cover,
                      width: 40,
                      height: 40,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          player.username.isNotEmpty ? player.username[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Color(0xFF5D3A1A),
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        player.username.isNotEmpty ? player.username[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Color(0xFF5D3A1A),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),

          // Nom + point vert
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    player.username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.6),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bouton DÉFIER
          GestureDetector(
            onTap: () => widget.onChallenge(player),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE91E63).withOpacity(0.5),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Text(
                'DÉFIER',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

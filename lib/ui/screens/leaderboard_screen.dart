import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/duel_service.dart';
import '../../services/message_service.dart';
import 'menu_screen.dart';
import 'duel_screen.dart';
import 'messages_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with TickerProviderStateMixin {
  List<Map<String, dynamic>> _leaderboard = [];
  bool _isLoading = true;
  int _pendingDuelCount = 0;
  int _unreadMessageCount = 0;

  // Animation pour les boutons du menu en bas
  late AnimationController _menuButtonController;
  late Animation<double> _menuButtonAnimation;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
    _loadPendingDuels();
    _setupAnimations();
  }

  Future<void> _loadPendingDuels() async {
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

  void _setupAnimations() {
    // Animation douce pour les boutons du menu
    _menuButtonController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _menuButtonAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _menuButtonController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _menuButtonController.dispose();
    super.dispose();
  }

  Future<void> _loadLeaderboard() async {
    try {
      final data = await supabaseService.getLeaderboard(limit: 100);
      setState(() {
        _leaderboard = data;
        _isLoading = false;
      });
    } catch (e) {
      print('Erreur chargement leaderboard: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String? _getPhotoUrl(Map<String, dynamic> player) {
    // D'abord vérifier photo_url (nouvelle colonne)
    final photoUrl = player['photo_url'] as String?;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return photoUrl;
    }
    // Fallback sur device_id pour les anciens faux profils
    final deviceId = player['device_id'] as String?;
    if (deviceId != null && deviceId.startsWith('http')) {
      return deviceId;
    }
    return null;
  }

  Widget _buildDefaultAvatar(String username, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Avatar par défaut (en dessous)
          Container(
            width: size * 0.75,
            height: size * 0.75,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFFF9EC4), Color(0xFFE85A8F)],
              ),
            ),
            child: Center(
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // Cadre candy par dessus
          Positioned.fill(
            child: Image.asset(
              'assets/ui/Cerclevidepourphoto.png',
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumPhoto(Map<String, dynamic>? player, double size) {
    if (player == null) {
      return _buildDefaultAvatar('?', size);
    }

    final photoUrl = _getPhotoUrl(player);
    final username = player['username'] as String? ?? 'Joueur';

    if (photoUrl != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Photo de profil (en dessous)
            Container(
              width: size * 0.75,
              height: size * 0.75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: NetworkImage(photoUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // Cadre candy par dessus
            Positioned.fill(
              child: Image.asset(
                'assets/ui/Cerclevidepourphoto.png',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      );
    }

    return _buildDefaultAvatar(username, size);
  }

  // Formater le score avec espaces (ex: 1 750 000)
  String _formatScore(int score) {
    String scoreStr = score.toString();
    String result = '';
    int count = 0;
    for (int i = scoreStr.length - 1; i >= 0; i--) {
      result = scoreStr[i] + result;
      count++;
      if (count % 3 == 0 && i != 0) {
        result = ' $result';
      }
    }
    return result;
  }

  // Texte avec contour (stroke effect)
  Widget _buildStrokedText(String text, double fontSize, Color fillColor, Color strokeColor, {double strokeWidth = 2.0}) {
    return Stack(
      children: [
        // Contour
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = strokeColor,
          ),
        ),
        // Remplissage
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
            color: fillColor,
          ),
        ),
      ],
    );
  }

  // Widget pour une ligne de classement (4ème position et après)
  Widget _buildLeaderboardRow(Map<String, dynamic> player, int rank, double screenWidth) {
    final photoUrl = _getPhotoUrl(player);
    final username = player['username'] as String? ?? 'Joueur';
    final highScore = player['high_score'] as int? ?? 0;
    final photoSize = screenWidth * 0.12;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.05,
        vertical: screenWidth * 0.02,
      ),
      child: Row(
        children: [
          // Numéro de position (blanc avec contour fuchsia)
          SizedBox(
            width: screenWidth * 0.09,
            child: _buildStrokedText(
              '$rank',
              screenWidth * 0.06,
              Colors.white,
              const Color(0xFFD4679A), // Fuchsia
              strokeWidth: 3.5,
            ),
          ),
          // Photo avec cadre
          photoUrl != null
              ? SizedBox(
                  width: photoSize,
                  height: photoSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: photoSize * 0.75,
                        height: photoSize * 0.75,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          image: DecorationImage(
                            image: NetworkImage(photoUrl),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Image.asset(
                          'assets/ui/Cerclevidepourphoto.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                )
              : _buildDefaultAvatar(username, photoSize),
          SizedBox(width: screenWidth * 0.03),
          // Nom du joueur (blanc avec contour fuchsia)
          Expanded(
            child: _buildStrokedText(
              username,
              screenWidth * 0.05,
              Colors.white,
              const Color(0xFFD4679A), // Fuchsia
              strokeWidth: 2.5,
            ),
          ),
          // Score (jaune/doré avec contour marron bien visible)
          _buildStrokedText(
            _formatScore(highScore),
            screenWidth * 0.045,
            const Color(0xFFFFD966), // Jaune doré
            const Color(0xFF8B4513), // Marron foncé
            strokeWidth: 3.0,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Tailles des photos
    final photoSize1 = screenWidth * 0.108; // 35px sur 324px
    final photoSize2 = screenWidth * 0.105; // 34px sur 324px
    final photoSize3 = screenWidth * 0.105; // 34px sur 324px

    // Récupérer les 3 premiers joueurs
    final player1 = _leaderboard.isNotEmpty ? _leaderboard[0] : null;
    final player2 = _leaderboard.length > 1 ? _leaderboard[1] : null;
    final player3 = _leaderboard.length > 2 ? _leaderboard[2] : null;

    return Scaffold(
      body: Container(
        width: screenWidth,
        height: screenHeight,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/ui/Fondleader.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            // Bouton retour - left=4.6%, top=4.9%
            Positioned(
              left: screenWidth * 0.046,
              top: screenHeight * 0.049,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9EC4), Color(0xFFE85A8F)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE85A8F).withOpacity(0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),

            // Titre - left=2.5%, top=12.5%, width=95%
            Positioned(
              left: screenWidth * 0.025,
              top: screenHeight * 0.125,
              child: Image.asset(
                'assets/ui/texteleaderboard.png',
                width: screenWidth * 0.95,
              ),
            ),

            // Photo 1ère place - left=50.0%, top=25.4% (SOUS Fondscrore)
            Positioned(
              left: screenWidth * 0.500 - (photoSize1 / 2),
              top: screenHeight * 0.254,
              child: _buildPodiumPhoto(player1, photoSize1),
            ),

            // Photo 2ème place - left=13.9%, top=26.9% (SOUS Fondscrore)
            Positioned(
              left: screenWidth * 0.139,
              top: screenHeight * 0.269,
              child: _buildPodiumPhoto(player2, photoSize2),
            ),

            // Photo 3ème place - left=75.9%, top=27.2% (SOUS Fondscrore)
            Positioned(
              left: screenWidth * 0.759,
              top: screenHeight * 0.272,
              child: _buildPodiumPhoto(player3, photoSize3),
            ),

            // Tableau des scores - left=-1.2%, top=20.1%, width=102% (AU-DESSUS des photos)
            Positioned(
              left: screenWidth * -0.012,
              top: screenHeight * 0.201,
              child: Image.asset(
                'assets/ui/Fondscrore.png',
                width: screenWidth * 1.02,
                fit: BoxFit.contain,
              ),
            ),

            // Nom et score 1ère place (centre)
            if (player1 != null)
              Positioned(
                left: 0,
                right: 0,
                top: screenHeight * 0.305,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStrokedText(
                      player1['username'] ?? 'Joueur',
                      screenWidth * 0.038,
                      Colors.white,
                      const Color(0xFFD4679A),
                      strokeWidth: 2.0,
                    ),
                    Transform.translate(
                      offset: Offset(0, -screenHeight * 0.005),
                      child: _buildStrokedText(
                        _formatScore(player1['high_score'] ?? 0),
                        screenWidth * 0.032,
                        const Color(0xFFFFD966),
                        const Color(0xFF8B4513),
                        strokeWidth: 2.0,
                      ),
                    ),
                  ],
                ),
              ),

            // Nom et score 2ème place (gauche) - Maya décalée
            if (player2 != null)
              Positioned(
                left: screenWidth * 0.065,
                top: screenHeight * 0.322,
                child: SizedBox(
                  width: screenWidth * 0.25,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStrokedText(
                        player2['username'] ?? 'Joueur',
                        screenWidth * 0.032,
                        Colors.white,
                        const Color(0xFFD4679A),
                        strokeWidth: 1.8,
                      ),
                      _buildStrokedText(
                        _formatScore(player2['high_score'] ?? 0),
                        screenWidth * 0.028,
                        const Color(0xFFFFD966),
                        const Color(0xFF8B4513),
                        strokeWidth: 1.8,
                      ),
                    ],
                  ),
                ),
              ),

            // Nom et score 3ème place (droite) - Héloïse décalée
            if (player3 != null)
              Positioned(
                right: screenWidth * 0.065,
                top: screenHeight * 0.322,
                child: SizedBox(
                  width: screenWidth * 0.25,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStrokedText(
                        player3['username'] ?? 'Joueur',
                        screenWidth * 0.032,
                        Colors.white,
                        const Color(0xFFD4679A),
                        strokeWidth: 1.8,
                      ),
                      _buildStrokedText(
                        _formatScore(player3['high_score'] ?? 0),
                        screenWidth * 0.028,
                        const Color(0xFFFFD966),
                        const Color(0xFF8B4513),
                        strokeWidth: 1.8,
                      ),
                    ],
                  ),
                ),
              ),

            // Liste des joueurs à partir de la 4ème position
            if (_leaderboard.length > 3)
              Positioned(
                left: screenWidth * 0.08,
                right: screenWidth * 0.08,
                top: screenHeight * 0.40,
                child: SizedBox(
                  height: screenHeight * 0.38,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _leaderboard.length - 3,
                    itemBuilder: (context, index) {
                      final player = _leaderboard[index + 3];
                      final rank = index + 4;
                      return _buildLeaderboardRow(player, rank, screenWidth);
                    },
                  ),
                ),
              ),

            // Menu de navigation en bas
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomMenu(screenWidth),
            ),

            // Indicateur de chargement
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFE85A8F),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Menu de navigation en bas (même style que menu_screen)
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
          // Fond du menu
          Image.asset(
            'assets/ui/Menu.png',
            width: screenWidth * 0.95,
            fit: BoxFit.contain,
          ),
          // Boutons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Bouton Accueil (animé)
              _buildAnimatedMenuButton(
                'assets/ui/Boutonaccueil.png',
                buttonSize,
                () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const MenuScreen()),
                  );
                },
                0.0,
              ),
              // Bouton Leader (pas animé - on est sur cette page)
              _buildStaticMenuButton(
                'assets/ui/boutonleader.png',
                buttonSize,
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

  // Bouton animé du menu
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
          () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const MessagesScreen()),
            );
          },
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
          () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DuelScreen()),
            );
          },
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

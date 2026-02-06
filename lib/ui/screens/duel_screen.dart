import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/duel_service.dart';
import '../../services/friend_service.dart';
import '../../models/duel.dart';
import '../widgets/candy_ui.dart';
import 'menu_screen.dart';
import 'leaderboard_screen.dart';
import 'game_screen.dart';

class DuelScreen extends StatefulWidget {
  const DuelScreen({super.key});

  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> with TickerProviderStateMixin {
  // Onglet actif: 0=Amis, 1=En Ligne, 2=Tous
  int _activeTab = 0;

  // Données
  List<PlayerSummary> _players = [];
  List<Duel> _pendingDuels = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // Controller pour la recherche
  final TextEditingController _searchController = TextEditingController();

  // Animation pour les boutons du menu en bas
  late AnimationController _menuButtonController;
  late Animation<double> _menuButtonAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadData();
  }

  void _setupAnimations() {
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final playerId = supabaseService.playerId;
    if (playerId == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Mettre à jour le statut en ligne
    await friendService.updateOnlineStatus(playerId);

    // Charger les duels en attente
    _pendingDuels = await duelService.getPendingDuels(playerId);

    // Charger les joueurs selon l'onglet
    await _loadPlayersForTab();

    setState(() => _isLoading = false);
  }

  Future<void> _loadPlayersForTab() async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    switch (_activeTab) {
      case 0: // Amis
        _players = await friendService.getFriends(playerId);
        break;
      case 1: // En Ligne
        _players = await friendService.getOnlinePlayers(playerId);
        break;
      case 2: // Tous
        _players = await friendService.getAllPlayers(
          playerId,
          search: _searchQuery.isNotEmpty ? _searchQuery : null,
        );
        break;
    }

    if (mounted) setState(() {});
  }

  void _onTabChanged(int index) {
    setState(() {
      _activeTab = index;
      _isLoading = true;
    });
    _loadPlayersForTab().then((_) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _onSearch(String query) {
    _searchQuery = query;
    if (_activeTab == 2) {
      _loadPlayersForTab();
    }
  }

  Future<void> _challengePlayer(PlayerSummary player) async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    // Afficher confirmation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1B3D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const CandyText(
          text: 'DÉFIER',
          fontSize: 24,
          textColor: Colors.white,
          strokeColor: Color(0xFFE91E63),
        ),
        content: Text(
          'Défier ${player.username} ?',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE91E63),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('DÉFIER !', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Créer le duel
    final duel = await duelService.createDuel(
      challengerId: playerId,
      challengedId: player.id,
    );

    if (duel != null && mounted) {
      // Lancer la partie avec le seed
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(
            duelSeed: duel.seed,
            duelId: duel.id,
          ),
        ),
      );
    }
  }

  Future<void> _acceptDuel(Duel duel) async {
    final accepted = await duelService.acceptDuel(duel.id);
    if (accepted && mounted) {
      // Lancer la partie avec le seed du duel
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(
            duelSeed: duel.seed,
            duelId: duel.id,
          ),
        ),
      );
    }
  }

  Future<void> _declineDuel(Duel duel) async {
    await duelService.declineDuel(duel.id);
    _loadData();
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
            image: AssetImage('assets/ui/fondduel.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header avec bouton retour et titre
              _buildHeader(screenWidth, screenHeight),

              // Barre de recherche
              _buildSearchBar(screenWidth),

              // Onglets
              _buildTabs(screenWidth),

              // Duels en attente (si on est sur l'onglet Amis)
              if (_activeTab == 0 && _pendingDuels.isNotEmpty)
                _buildPendingDuels(screenWidth),

              // Liste des joueurs
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFE91E63),
                        ),
                      )
                    : _players.isEmpty
                        ? _buildEmptyState()
                        : _buildPlayerList(screenWidth),
              ),

              // Menu en bas
              _buildBottomMenu(screenWidth),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double screenWidth, double screenHeight) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.05,
        vertical: screenHeight * 0.02,
      ),
      child: Row(
        children: [
          // Bouton retour
          GestureDetector(
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
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 16),
          // Titre
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CandyText(
                  text: 'CHOISIS TON',
                  fontSize: screenWidth * 0.055,
                  textColor: Colors.white,
                  strokeColor: const Color(0xFFE91E63),
                  strokeWidth: 2,
                ),
                CandyText(
                  text: 'ADVERSAIRE',
                  fontSize: screenWidth * 0.07,
                  textColor: const Color(0xFFFFD700),
                  strokeColor: const Color(0xFF8B4513),
                  strokeWidth: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(double screenWidth) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.05,
        vertical: 8,
      ),
      child: Container(
        height: 45,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearch,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Rechercher un joueur...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.6)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs(double screenWidth) {
    final tabs = ['Amis', 'En Ligne', 'Tous'];

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.05,
        vertical: 8,
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isActive = _activeTab == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => _onTabChanged(index),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                        )
                      : null,
                  color: isActive ? null : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    tabs[index],
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPendingDuels(double screenWidth) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.05, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CandyText(
            text: 'DÉFIS EN ATTENTE',
            fontSize: 14,
            textColor: Color(0xFFFFD700),
            strokeColor: Color(0xFF8B4513),
          ),
          const SizedBox(height: 8),
          ...(_pendingDuels.take(3).map((duel) => _buildPendingDuelCard(duel, screenWidth))),
        ],
      ),
    );
  }

  Widget _buildPendingDuelCard(Duel duel, double screenWidth) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Avatar du challenger
          CandyAvatarButton(
            letter: (duel.challengerName ?? 'J')[0],
            backgroundImage: 'assets/ui/cerclevidephoto.png',
            size: 40,
            profilePhotoUrl: duel.challengerPhotoUrl,
          ),
          const SizedBox(width: 12),
          // Nom
          Expanded(
            child: Text(
              duel.challengerName ?? 'Joueur',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Boutons accepter/refuser
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => _declineDuel(duel),
          ),
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: () => _acceptDuel(duel),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    String message;
    switch (_activeTab) {
      case 0:
        message = 'Tu n\'as pas encore d\'amis.\nVa dans "Tous" pour en ajouter !';
        break;
      case 1:
        message = 'Aucun joueur en ligne\npour le moment.';
        break;
      default:
        message = 'Aucun joueur trouvé.';
    }

    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withOpacity(0.7),
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildPlayerList(double screenWidth) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03),
      itemCount: _players.length,
      itemBuilder: (context, index) {
        return _buildPlayerCard(_players[index], screenWidth);
      },
    );
  }

  Widget _buildPlayerCard(PlayerSummary player, double screenWidth) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.02,
        vertical: 6,
      ),
      padding: EdgeInsets.all(screenWidth * 0.03),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.15),
            Colors.pink.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.4),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          CandyAvatarButton(
            letter: player.username.isNotEmpty ? player.username[0] : '?',
            backgroundImage: 'assets/ui/cerclevidephoto.png',
            size: 50,
            profilePhotoUrl: player.photoUrl,
          ),
          const SizedBox(width: 12),
          // Nom et statut
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: player.isOnline ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      player.isOnline ? 'En ligne' : 'Hors ligne',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                    if (player.isFriend) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Ami',
                          style: TextStyle(color: Colors.green, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Bouton défier
          GestureDetector(
            onTap: () => _challengePlayer(player),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE91E63).withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
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

  Widget _buildBottomMenu(double screenWidth) {
    final menuHeight = screenWidth * 0.22;
    final buttonSize = screenWidth * 0.20;

    return Container(
      width: screenWidth,
      height: menuHeight + 20,
      padding: const EdgeInsets.only(bottom: 10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/ui/Menu.png',
            width: screenWidth * 0.95,
            fit: BoxFit.contain,
          ),
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
              // Bouton Leader (animé)
              _buildAnimatedMenuButton(
                'assets/ui/boutonleader.png',
                buttonSize,
                () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
                  );
                },
                0.25,
              ),
              // Bouton Messages (animé)
              _buildAnimatedMenuButton(
                'assets/ui/boutonmessages.png',
                buttonSize,
                () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Messages - Bientôt disponible'),
                      backgroundColor: Colors.blue,
                    ),
                  );
                },
                0.50,
              ),
              // Bouton Duel (statique - on est sur cette page)
              _buildStaticMenuButton(
                'assets/ui/boutonduel.png',
                buttonSize,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedMenuButton(
      String asset, double size, VoidCallback onTap, double delay) {
    return AnimatedBuilder(
      animation: _menuButtonController,
      builder: (context, child) {
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

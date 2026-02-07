import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../services/duel_service.dart';
import '../../services/friend_service.dart';
import '../../services/notification_service.dart';
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
  // Onglet actif: 0=Duels, 1=Amis, 2=En Ligne, 3=Tous
  int _activeTab = 0;

  // Données
  List<PlayerSummary> _players = [];
  List<Duel> _pendingDuels = [];    // Duels en attente (défis reçus)
  List<Duel> _activeDuels = [];     // Duels actifs (en cours)
  List<Duel> _myPendingChallenges = []; // Défis que j'ai envoyés
  List<PlayerSummary> _pendingFriendRequests = []; // Demandes d'amis reçues
  bool _isLoading = true;
  String _searchQuery = '';

  // Controller pour la recherche
  final TextEditingController _searchController = TextEditingController();

  // Animation pour les boutons du menu en bas
  late AnimationController _menuButtonController;
  late Animation<double> _menuButtonAnimation;

  // Abonnements temps réel Supabase
  RealtimeChannel? _duelsChannel;
  RealtimeChannel? _friendsChannel;

  // Timer pour rafraîchissement automatique (backup si realtime ne fonctionne pas)
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadData();
    _setupRealtimeSubscriptions();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    // Rafraîchir toutes les 5 secondes
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _refreshDuelsData();
        _refreshFriendsData();
      }
    });
  }

  void _setupRealtimeSubscriptions() {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    // Écouter les changements sur la table duels (nouveaux défis reçus)
    _duelsChannel = Supabase.instance.client
        .channel('duels_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'duels',
          callback: (payload) {
            // Recharger les données quand un duel est créé/modifié
            if (mounted) {
              _refreshDuelsData();
            }
          },
        )
        .subscribe();

    // Écouter les changements sur la table friends (demandes d'amis)
    _friendsChannel = Supabase.instance.client
        .channel('friends_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friends',
          callback: (payload) {
            // Recharger les données quand une demande d'ami arrive
            if (mounted) {
              _refreshFriendsData();
            }
          },
        )
        .subscribe();
  }

  Future<void> _refreshDuelsData() async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    // Garder le compte actuel pour comparaison
    final previousPendingCount = _pendingDuels.length;

    // Recharger uniquement les duels sans toucher au reste
    final pendingDuels = await duelService.getPendingDuels(playerId);
    final activeDuels = await duelService.getActiveDuels(playerId);
    final myPendingChallenges = await duelService.getMySentChallenges(playerId);

    if (mounted) {
      // Vérifier s'il y a un nouveau défi
      if (pendingDuels.length > previousPendingCount) {
        // Trouver le nouveau défi
        final newDuel = pendingDuels.firstWhere(
          (d) => !_pendingDuels.any((old) => old.id == d.id),
          orElse: () => pendingDuels.first,
        );
        _showNewDuelNotification(newDuel);
      }

      setState(() {
        _pendingDuels = pendingDuels;
        _activeDuels = activeDuels;
        _myPendingChallenges = myPendingChallenges;
      });
    }
  }

  void _showNewDuelNotification(Duel duel) {
    // Ne pas afficher si déjà sur l'onglet Duels
    if (_activeTab == 0) return;

    // Notification élégante en haut
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        elevation: 6,
        leading: const Icon(Icons.sports_esports, color: Colors.white, size: 22),
        backgroundColor: const Color(0xFFE91E63),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        content: Text(
          '⚔️ ${duel.challengerName ?? "Quelqu\'un"} vous défie !',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              setState(() => _activeTab = 0);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text(
              'VOIR',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text(
              '✕',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ],
      ),
    );

    // Auto-fermer après 5 secondes
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });
  }

  Future<void> _refreshFriendsData() async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    // Garder le compte actuel pour comparaison
    final previousRequestsCount = _pendingFriendRequests.length;

    // Recharger les demandes d'amis
    final pendingRequests = await friendService.getPendingRequests(playerId);

    if (mounted) {
      // Vérifier s'il y a une nouvelle demande d'ami
      if (pendingRequests.length > previousRequestsCount) {
        final newRequest = pendingRequests.firstWhere(
          (r) => !_pendingFriendRequests.any((old) => old.id == r.id),
          orElse: () => pendingRequests.first,
        );
        _showNewFriendRequestNotification(newRequest);
      }

      setState(() {
        _pendingFriendRequests = pendingRequests;
      });

      // Si on est sur l'onglet Amis, recharger aussi la liste
      if (_activeTab == 1) {
        _loadPlayersForTab();
      }
    }
  }

  void _showNewFriendRequestNotification(PlayerSummary player) {
    // Ne pas afficher si déjà sur l'onglet Amis
    if (_activeTab == 1) return;

    // Notification élégante en haut
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        elevation: 6,
        leading: const Icon(Icons.person_add, color: Colors.white, size: 22),
        backgroundColor: Colors.orange,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        content: Text(
          '👋 ${player.username} veut être ton ami !',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              setState(() => _activeTab = 1);
              _loadPlayersForTab();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text(
              'VOIR',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text(
              '✕',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ],
      ),
    );

    // Auto-fermer après 5 secondes
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });
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
    // Annuler le timer de rafraîchissement
    _refreshTimer?.cancel();
    // Annuler les abonnements temps réel
    _duelsChannel?.unsubscribe();
    _friendsChannel?.unsubscribe();
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

    // Charger les duels en attente (défis reçus)
    _pendingDuels = await duelService.getPendingDuels(playerId);

    // Charger les duels actifs
    _activeDuels = await duelService.getActiveDuels(playerId);

    // Charger les défis que j'ai envoyés (en attente de réponse)
    _myPendingChallenges = await duelService.getMySentChallenges(playerId);

    // Charger les demandes d'amis reçues
    _pendingFriendRequests = await friendService.getPendingRequests(playerId);

    // Charger les joueurs selon l'onglet
    await _loadPlayersForTab();

    setState(() => _isLoading = false);
  }

  Future<void> _loadPlayersForTab() async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    switch (_activeTab) {
      case 0: // Duels - pas besoin de charger des joueurs
        break;
      case 1: // Amis
        _players = await friendService.getFriends(playerId);
        _pendingFriendRequests = await friendService.getPendingRequests(playerId);
        break;
      case 2: // En Ligne
        _players = await friendService.getOnlinePlayers(playerId);
        break;
      case 3: // Tous
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
    // Recherche instantanée pour l'onglet "Tous" (index 3)
    if (_activeTab == 3) {
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(
            duelSeed: duel.seed,
            duelId: duel.id,
            opponentId: player.id,
            opponentName: player.username,
            opponentPhotoUrl: player.photoUrl,
          ),
        ),
      );
      // Recharger les données au retour
      if (mounted) _loadData();
    }
  }

  Future<void> _acceptDuel(Duel duel) async {
    final accepted = await duelService.acceptDuel(duel.id);
    if (accepted && mounted) {
      // Lancer la partie avec le seed du duel
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(
            duelSeed: duel.seed,
            duelId: duel.id,
            opponentId: duel.challengerId,
            opponentName: duel.challengerName,
            opponentPhotoUrl: duel.challengerPhotoUrl,
          ),
        ),
      );
      // Recharger les données au retour
      if (mounted) _loadData();
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

              // Contenu selon l'onglet
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFE91E63),
                        ),
                      )
                    : _activeTab == 0
                        ? _buildDuelsTab(screenWidth)  // Onglet Duels
                        : _activeTab == 1
                            ? _buildFriendsTab(screenWidth)  // Onglet Amis
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
          // Titre centré
          Expanded(
            child: Column(
              children: [
                CandyText(
                  text: 'CHOISIS TON',
                  fontSize: screenWidth * 0.06,
                  textColor: Colors.white,
                  strokeColor: const Color(0xFFE91E63),
                  strokeWidth: 3,
                ),
                CandyText(
                  text: 'ADVERSAIRE',
                  fontSize: screenWidth * 0.08,
                  textColor: const Color(0xFFFFD700),
                  strokeColor: const Color(0xFF8B4513),
                  strokeWidth: 4,
                ),
              ],
            ),
          ),
          // Espace pour équilibrer
          const SizedBox(width: 40),
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
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.4),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Center(
          child: TextField(
            controller: _searchController,
            onChanged: _onSearch,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(color: Color(0xFF5D3A1A), fontWeight: FontWeight.w500, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Rechercher un joueur...',
              hintStyle: TextStyle(color: const Color(0xFF5D3A1A).withOpacity(0.6), fontSize: 15),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(Icons.search, color: const Color(0xFF5D3A1A).withOpacity(0.6), size: 22),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              isCollapsed: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs(double screenWidth) {
    final tabs = ['Duels', 'Amis', 'En Ligne', 'Tous'];

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.03,
        vertical: 8,
      ),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isActive = _activeTab == index;

          return Expanded(
            child: GestureDetector(
              onTap: () => _onTabChanged(index),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                        )
                      : null,
                  color: isActive ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: isActive ? Border.all(color: Colors.white, width: 2) : null,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: const Color(0xFFE91E63).withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    tabs[index],
                    style: TextStyle(
                      color: isActive ? Colors.white : const Color(0xFF5D3A1A),
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                      fontSize: 13,
                      shadows: isActive
                          ? [
                              Shadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 2,
                                offset: const Offset(1, 1),
                              ),
                            ]
                          : null,
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
          // Bouton Refuser
          GestureDetector(
            onTap: () => _declineDuel(duel),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B6B), Color(0xFFEE5A5A)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Text(
                'Refuser',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Bouton Accepter
          GestureDetector(
            onTap: () => _acceptDuel(duel),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF66BB6A), Color(0xFF43A047)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Text(
                'Accepter',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    String message;
    switch (_activeTab) {
      case 0: // Duels
        message = 'Aucun duel en cours.\nDéfie quelqu\'un !';
        break;
      case 1: // Amis
        message = 'Tu n\'as pas encore d\'amis.\nVa dans "Tous" pour en ajouter !';
        break;
      case 2: // En Ligne
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

  /// Onglet Duels - affiche tous les duels
  Widget _buildDuelsTab(double screenWidth) {
    final playerId = supabaseService.playerId;
    final hasAnyDuels = _pendingDuels.isNotEmpty || _activeDuels.isNotEmpty || _myPendingChallenges.isNotEmpty;

    if (!hasAnyDuels) {
      return _buildEmptyState();
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03, vertical: 8),
      children: [
        // Défis reçus (à accepter/refuser)
        if (_pendingDuels.isNotEmpty) ...[
          _buildSectionHeader('DÉFIS REÇUS', Colors.orange, Icons.notification_important, badgeCount: _pendingDuels.length),
          ..._pendingDuels.map((duel) => _buildDuelCard(
            duel: duel,
            screenWidth: screenWidth,
            type: 'received',
            playerId: playerId!,
          )),
          const SizedBox(height: 16),
        ],

        // Duels actifs (à jouer)
        if (_activeDuels.isNotEmpty) ...[
          _buildSectionHeader('DUELS EN COURS', Colors.green, Icons.sports_esports),
          ..._activeDuels.map((duel) => _buildDuelCard(
            duel: duel,
            screenWidth: screenWidth,
            type: 'active',
            playerId: playerId!,
          )),
          const SizedBox(height: 16),
        ],

        // Défis envoyés (en attente)
        if (_myPendingChallenges.isNotEmpty) ...[
          _buildSectionHeader('DÉFIS ENVOYÉS', Colors.blue, Icons.send),
          ..._myPendingChallenges.map((duel) => _buildDuelCard(
            duel: duel,
            screenWidth: screenWidth,
            type: 'sent',
            playerId: playerId!,
          )),
        ],
      ],
    );
  }

  /// Onglet Amis - affiche les demandes d'amis et la liste des amis
  Widget _buildFriendsTab(double screenWidth) {
    final hasFriends = _players.isNotEmpty;
    final hasPendingRequests = _pendingFriendRequests.isNotEmpty;

    if (!hasFriends && !hasPendingRequests) {
      return _buildEmptyState();
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03, vertical: 8),
      children: [
        // Demandes d'amis en attente
        if (hasPendingRequests) ...[
          _buildSectionHeader('DEMANDES D\'AMIS', Colors.orange, Icons.person_add),
          ..._pendingFriendRequests.map((player) => _buildFriendRequestCard(player, screenWidth)),
          const SizedBox(height: 16),
        ],

        // Liste des amis
        if (hasFriends) ...[
          _buildSectionHeader('MES AMIS', Colors.green, Icons.people),
          ..._players.map((player) => _buildPlayerCard(player, screenWidth)),
        ],
      ],
    );
  }

  Widget _buildFriendRequestCard(PlayerSummary player, double screenWidth) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 85,
      child: Stack(
        children: [
          // Fond beige opaque à l'intérieur
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.only(left: 8, right: 8, top: 18, bottom: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E7),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          // Cadre candy par dessus
          Positioned.fill(
            child: Image.asset(
              'assets/ui/Cadreonline.png',
              fit: BoxFit.fill,
            ),
          ),
          // Contenu par dessus
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 18, top: 22, bottom: 12),
            child: Row(
              children: [
                // Avatar avec fond doré (plus petit)
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFD700),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: player.photoUrl != null
                        ? Image.network(
                            player.photoUrl!,
                            fit: BoxFit.cover,
                            width: 46,
                            height: 46,
                            errorBuilder: (_, __, ___) => _buildDefaultAvatarLetter(player.username),
                          )
                        : _buildDefaultAvatarLetter(player.username),
                  ),
                ),
                const SizedBox(width: 12),
                // Nom
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.username,
                        style: TextStyle(
                          color: const Color(0xFF5D3A1A),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          shadows: [
                            Shadow(
                              color: Colors.white.withOpacity(0.5),
                              blurRadius: 1,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Veut être ton ami !',
                        style: TextStyle(
                          color: Colors.orange[800],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Bouton Refuser
                GestureDetector(
                  onTap: () => _declineFriendRequest(player),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B6B), Color(0xFFEE5A5A)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Refuser',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Bouton Accepter
                GestureDetector(
                  onTap: () => _acceptFriendRequest(player),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF66BB6A), Color(0xFF43A047)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Accepter',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptFriendRequest(PlayerSummary player) async {
    // Trouver l'ID de la demande
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    final success = await friendService.acceptFriendRequestByPlayerId(playerId, player.id);
    if (success) {
      // Envoyer notification
      await NotificationService.sendFriendRequestAccepted(
        targetPlayerId: player.id,
        accepterName: supabaseService.userName ?? 'Quelqu\'un',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${player.username} est maintenant ton ami !'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
    _loadData();
  }

  Future<void> _declineFriendRequest(PlayerSummary player) async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    final success = await friendService.declineFriendRequestByPlayerId(playerId, player.id);
    if (success) {
      // Envoyer notification
      await NotificationService.sendFriendRequestDeclined(
        targetPlayerId: player.id,
        declinerName: supabaseService.userName ?? 'Quelqu\'un',
      );
    }
    _loadData();
  }

  Widget _buildSectionHeader(String title, Color color, IconData icon, {int badgeCount = 0}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: 1.5,
              shadows: [
                Shadow(
                  color: color.withOpacity(0.8),
                  blurRadius: 4,
                  offset: const Offset(1, 1),
                ),
              ],
            ),
          ),
          // Badge notification à droite
          if (badgeCount > 0) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDuelCard({
    required Duel duel,
    required double screenWidth,
    required String type,
    required String playerId,
  }) {
    final isChallenger = duel.challengerId == playerId;
    final opponentName = isChallenger ? duel.challengedName : duel.challengerName;
    final opponentPhoto = isChallenger ? duel.challengedPhotoUrl : duel.challengerPhotoUrl;
    final myScore = isChallenger ? duel.challengerScore : duel.challengedScore;
    final opponentScore = isChallenger ? duel.challengedScore : duel.challengerScore;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 85,
      child: Stack(
        children: [
          // Fond beige opaque à l'intérieur
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.only(left: 8, right: 8, top: 18, bottom: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E7),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          // Cadre candy par dessus
          Positioned.fill(
            child: Image.asset(
              'assets/ui/Cadreonline.png',
              fit: BoxFit.fill,
            ),
          ),
          // Contenu par dessus
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 18, top: 22, bottom: 12),
            child: Row(
              children: [
                // Avatar adversaire avec fond jaune (plus petit)
                GestureDetector(
                  onTap: () => _showPlayerInfo(
                    isChallenger ? duel.challengedId : duel.challengerId,
                    opponentName ?? 'Joueur',
                    opponentPhoto,
                  ),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFD700),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withOpacity(0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: opponentPhoto != null
                          ? Image.network(
                              opponentPhoto,
                              fit: BoxFit.cover,
                              width: 46,
                              height: 46,
                              errorBuilder: (_, __, ___) => _buildDefaultAvatarLetter(opponentName ?? 'J'),
                            )
                          : _buildDefaultAvatarLetter(opponentName ?? 'J'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info duel
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opponentName ?? 'Joueur',
                        style: TextStyle(
                          color: const Color(0xFF5D3A1A),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          shadows: [
                            Shadow(
                              color: Colors.white.withOpacity(0.5),
                              blurRadius: 1,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      _buildDuelStatus(type, myScore, opponentScore),
                    ],
                  ),
                ),
                // Boutons d'action
                _buildDuelActions(duel, type, myScore),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatarLetter(String name) {
    return Container(
      color: const Color(0xFFFF6B9D),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildDuelStatus(String type, int? myScore, int? opponentScore) {
    switch (type) {
      case 'received':
        return Text(
          'Vous a défié !',
          style: TextStyle(
            color: Colors.orange[800],
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        );
      case 'active':
        if (myScore != null) {
          return Text(
            'Ton score: $myScore - En attente',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          );
        } else if (opponentScore != null) {
          return Text(
            'Score à battre: $opponentScore',
            style: TextStyle(
              color: Colors.green[700],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          );
        } else {
          return Text(
            'À toi de jouer !',
            style: TextStyle(
              color: Colors.green[700],
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          );
        }
      case 'sent':
        return Text(
          'En attente de réponse...',
          style: TextStyle(
            color: Colors.blue[700],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildDuelActions(Duel duel, String type, int? myScore) {
    switch (type) {
      case 'received':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bouton Refuser
            GestureDetector(
              onTap: () => _declineDuel(duel),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFEE5A5A)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Refuser',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Bouton Accepter
            GestureDetector(
              onTap: () => _acceptDuel(duel),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF66BB6A), Color(0xFF43A047)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Accepter',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      case 'active':
        if (myScore == null) {
          return ElevatedButton(
            onPressed: () => _playDuel(duel),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('JOUER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          );
        } else {
          return const Icon(Icons.hourglass_empty, color: Colors.white54);
        }
      case 'sent':
        return IconButton(
          icon: const Icon(Icons.cancel, color: Colors.red),
          onPressed: () => _cancelChallenge(duel),
          tooltip: 'Annuler',
        );
      default:
        return const SizedBox();
    }
  }

  Future<void> _playDuel(Duel duel) async {
    final playerId = supabaseService.playerId;
    final isChallenger = duel.challengerId == playerId;
    final opponentId = isChallenger ? duel.challengedId : duel.challengerId;
    final opponentName = isChallenger ? duel.challengedName : duel.challengerName;
    final opponentPhoto = isChallenger ? duel.challengedPhotoUrl : duel.challengerPhotoUrl;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameScreen(
          duelSeed: duel.seed,
          duelId: duel.id,
          opponentId: opponentId,
          opponentName: opponentName,
          opponentPhotoUrl: opponentPhoto,
        ),
      ),
    );
    if (mounted) _loadData();
  }

  Future<void> _cancelChallenge(Duel duel) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1B3D),
        title: const Text('Annuler le défi ?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oui', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await duelService.declineDuel(duel.id);
      _loadData();
    }
  }

  void _showPlayerInfo(String odataId, String name, String? photoUrl) {
    showDialog(
      context: context,
      builder: (context) => _PlayerInfoDialog(
        playerId: odataId,
        playerName: name,
        playerPhotoUrl: photoUrl,
        onAddFriend: () => _sendFriendRequest(odataId),
      ),
    );
  }

  Future<void> _sendFriendRequest(String odataId) async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    final success = await friendService.sendFriendRequest(playerId, odataId);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Demande d\'ami envoyée !' : 'Erreur lors de l\'envoi'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
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
      height: 85,
      child: Stack(
        children: [
          // Fond beige opaque à l'intérieur
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.only(left: 8, right: 8, top: 18, bottom: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E7),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          // Cadre candy par dessus
          Positioned.fill(
            child: Image.asset(
              'assets/ui/Cadreonline.png',
              fit: BoxFit.fill,
            ),
          ),
          // Contenu par dessus avec positions exactes
          Stack(
            children: [
              // Photo - left=20, top=22
              Positioned(
                left: 20,
                top: 22,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFD700),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: player.photoUrl != null
                        ? Image.network(
                            player.photoUrl!,
                            fit: BoxFit.cover,
                            width: 46,
                            height: 46,
                            errorBuilder: (_, __, ___) => _buildDefaultAvatarLetter(player.username),
                          )
                        : _buildDefaultAvatarLetter(player.username),
                  ),
                ),
              ),
              // Nom - left=70, top=33
              Positioned(
                left: 70,
                top: 33,
                child: Text(
                  player.username,
                  style: TextStyle(
                    color: const Color(0xFF5D3A1A),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    shadows: [
                      Shadow(
                        color: Colors.white.withOpacity(0.5),
                        blurRadius: 1,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              // Pastille en ligne - position adaptée selon ami ou pas
              Positioned(
                left: player.isFriend ? 160 : 208,
                top: 37,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: player.isOnline ? Colors.green : Colors.red,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: (player.isOnline ? Colors.green : Colors.red).withOpacity(0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              // Bouton Messages (seulement pour les amis) - vert
              if (player.isFriend)
                Positioned(
                  left: 182,
                  top: 29,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF66BB6A), Color(0xFF43A047)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.5),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Messages',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              // Bouton DÉFIER - position adaptée selon ami ou pas
              Positioned(
                left: player.isFriend ? 266 : 249,
                top: player.isFriend ? 29 : 26,
                child: GestureDetector(
                  onTap: () => _challengePlayer(player),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: player.isFriend ? 10 : 14,
                      vertical: player.isFriend ? 6 : 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                      ),
                      borderRadius: BorderRadius.circular(player.isFriend ? 14 : 18),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE91E63).withOpacity(0.5),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      'DÉFIER',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: player.isFriend ? 10 : 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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

/// Dialog pour afficher les infos d'un joueur
class _PlayerInfoDialog extends StatelessWidget {
  final String playerId;
  final String playerName;
  final String? playerPhotoUrl;
  final VoidCallback onAddFriend;

  const _PlayerInfoDialog({
    required this.playerId,
    required this.playerName,
    this.playerPhotoUrl,
    required this.onAddFriend,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1B3D), Color(0xFF1A0F2E)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE91E63), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Photo
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFD700), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: ClipOval(
                child: playerPhotoUrl != null
                    ? Image.network(
                        playerPhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
                      )
                    : _buildDefaultAvatar(),
              ),
            ),
            const SizedBox(height: 16),
            // Nom
            Text(
              playerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // Boutons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Bouton Fermer
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Fermer',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                // Bouton Ajouter ami
                ElevatedButton.icon(
                  onPressed: onAddFriend,
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Ajouter ami'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE91E63),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: const Color(0xFFFF6B9D),
      child: Center(
        child: Text(
          playerName.isNotEmpty ? playerName[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 40,
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'duel_lobby_screen.dart';
import 'chat_screen.dart';
import 'messages_screen.dart';
import '../../services/message_service.dart';

class DuelScreen extends StatefulWidget {
  const DuelScreen({super.key});

  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  // Onglet actif: 0=Duels, 1=Amis, 2=En Ligne, 3=Tous
  int _activeTab = 0;

  // Données
  List<PlayerSummary> _players = [];
  List<Duel> _pendingDuels = [];    // Duels en attente (défis reçus)
  List<Duel> _activeDuels = [];     // Duels actifs (en cours)
  List<Duel> _myPendingChallenges = []; // Défis que j'ai envoyés
  List<Duel> _completedDuels = [];  // Duels terminés (résultats)
  List<PlayerSummary> _pendingFriendRequests = []; // Demandes d'amis reçues
  bool _isLoading = true;
  String _searchQuery = '';
  int _unreadMessageCount = 0;

  // Controller pour la recherche
  final TextEditingController _searchController = TextEditingController();

  // Animation pour les boutons du menu en bas
  late AnimationController _menuButtonController;
  late Animation<double> _menuButtonAnimation;

  // Abonnements temps réel Supabase
  RealtimeChannel? _duelsChannel;
  RealtimeChannel? _friendsChannel;
  RealtimeChannel? _playersOnlineChannel;

  // Timer pour rafraîchissement automatique (backup si realtime ne fonctionne pas)
  Timer? _refreshTimer;

  // Timer pour mise à jour du statut online
  Timer? _onlineStatusTimer;

  // Timer pour mouvement des bots (connexion/déconnexion en live)
  Timer? _botMovementTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAnimations();
    _checkPendingBotCompletion();
    _loadData();
    _setupRealtimeSubscriptions();
    _startAutoRefresh();
    _startOnlineStatusUpdates();
    _startBotMovement();
  }

  /// Vérifie si un bot doit finir sa partie (soumission différée)
  Future<void> _checkPendingBotCompletion() async {
    final prefs = await SharedPreferences.getInstance();
    final duelId = prefs.getString('pending_bot_duel_id');
    if (duelId == null) return;

    final finishAt = prefs.getInt('pending_bot_finish_at') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now >= finishAt) {
      // Le temps est écoulé, soumettre le score du bot maintenant
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
        if (mounted) {
          _checkPendingBotCompletion();
          // Recharger les données pour voir le résultat
          _loadData();
        }
      });
    }
  }

  /// Démarre les mises à jour du statut online toutes les 30 secondes
  void _startOnlineStatusUpdates() {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    // Mettre à jour immédiatement
    friendService.updateOnlineStatus(playerId);

    // Puis toutes les 30 secondes
    _onlineStatusTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        friendService.updateOnlineStatus(playerId);
      }
    });
  }

  /// Fait bouger les bots en live : un bot se connecte ou se déconnecte toutes les 15-40s
  void _startBotMovement() {
    _scheduleBotMovement();
  }

  void _scheduleBotMovement() {
    if (!mounted) return;
    // Prochain mouvement dans 15-40 secondes (aléatoire)
    final delay = 15 + Random().nextInt(26);
    _botMovementTimer = Timer(Duration(seconds: delay), () {
      if (!mounted) return;
      friendService.randomBotToggle();
      // Planifier le prochain mouvement
      _scheduleBotMovement();
    });
  }

  /// Gère les changements d'état de l'application (avant-plan/arrière-plan)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App en arrière-plan ou inactive → mettre offline immédiatement
      friendService.setOffline(playerId);
    } else if (state == AppLifecycleState.resumed) {
      // App revenue au premier plan → mettre online
      friendService.updateOnlineStatus(playerId);
      // Recharger les données
      _loadData();
    }
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

    // Écouter les changements de statut online des joueurs (last_seen_at)
    _playersOnlineChannel = Supabase.instance.client
        .channel('players_online_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'players',
          callback: (payload) {
            // Recharger la liste des joueurs quand un statut change
            if (mounted && (_activeTab == 1 || _activeTab == 2 || _activeTab == 3)) {
              _loadPlayersForTab();
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
    final previousSentChallengesIds = _myPendingChallenges.map((d) => d.id).toList();

    // Recharger uniquement les duels sans toucher au reste
    final pendingDuels = await duelService.getPendingDuels(playerId);
    final activeDuels = await duelService.getActiveDuels(playerId);
    final myPendingChallenges = await duelService.getMySentChallenges(playerId);
    final completedDuels = await duelService.getDuelHistory(playerId, limit: 10);

    if (mounted) {
      // Vérifier s'il y a un nouveau défi reçu
      if (pendingDuels.length > previousPendingCount) {
        // Trouver le nouveau défi
        final newDuel = pendingDuels.firstWhere(
          (d) => !_pendingDuels.any((old) => old.id == d.id),
          orElse: () => pendingDuels.first,
        );
        _showNewDuelNotification(newDuel);
      }

      // Vérifier si un de mes défis envoyés a été accepté ou refusé
      for (final oldChallengeId in previousSentChallengesIds) {
        final stillPending = myPendingChallenges.any((d) => d.id == oldChallengeId);
        final nowActive = activeDuels.any((d) => d.id == oldChallengeId);

        if (!stillPending) {
          // Trouver le défi dans l'ancienne liste
          final oldDuel = _myPendingChallenges.firstWhere(
            (d) => d.id == oldChallengeId,
            orElse: () => _myPendingChallenges.first,
          );

          if (nowActive) {
            // Le défi a été accepté ! Vérifier si c'est un duel live
            final freshDuel = await duelService.getDuel(oldChallengeId);
            if (freshDuel != null && freshDuel.isLive) {
              // Duel live : naviguer directement vers le lobby
              _navigateToLobby(freshDuel);
            } else {
              _showDuelAcceptedNotification(oldDuel);
            }
          } else {
            // Le défi a été refusé
            _showDuelDeclinedNotification(oldDuel);
          }
        }
      }

      setState(() {
        _pendingDuels = pendingDuels;
        _activeDuels = activeDuels;
        _myPendingChallenges = myPendingChallenges;
        _completedDuels = completedDuels;
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

  void _showDuelDeclinedNotification(Duel duel) {
    // Notification élégante en haut
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        elevation: 6,
        leading: const Icon(Icons.cancel, color: Colors.white, size: 22),
        backgroundColor: Colors.red[600]!,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        content: Text(
          '${duel.challengedName ?? "L\'adversaire"} a refusé ton défi',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text(
              'OK',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
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

  void _showDuelAcceptedNotification(Duel duel) {
    // Notification élégante en haut - vert pour accepté
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        elevation: 6,
        leading: const Icon(Icons.check_circle, color: Colors.white, size: 22),
        backgroundColor: Colors.green[600]!,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        content: Text(
          '🎮 ${duel.challengedName ?? "L\'adversaire"} a accepté ton défi ! À toi de jouer !',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              // Aller sur l'onglet Duels pour jouer
              setState(() => _activeTab = 0);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text(
              'JOUER',
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

    // Auto-fermer après 8 secondes (plus long car important)
    Future.delayed(const Duration(seconds: 8), () {
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
    // Retirer l'observateur de lifecycle
    WidgetsBinding.instance.removeObserver(this);
    // Annuler le timer de rafraîchissement
    _refreshTimer?.cancel();
    // Annuler le timer de statut online
    _onlineStatusTimer?.cancel();
    // Annuler le timer de mouvement des bots
    _botMovementTimer?.cancel();
    // Mettre offline avant de quitter
    final playerId = supabaseService.playerId;
    if (playerId != null) {
      friendService.setOffline(playerId);
    }
    // Annuler les abonnements temps réel
    _duelsChannel?.unsubscribe();
    _friendsChannel?.unsubscribe();
    _playersOnlineChannel?.unsubscribe();
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

    // Charger les duels terminés (résultats)
    _completedDuels = await duelService.getDuelHistory(playerId, limit: 10);

    // Charger les demandes d'amis reçues
    _pendingFriendRequests = await friendService.getPendingRequests(playerId);

    // Charger les joueurs selon l'onglet
    await _loadPlayersForTab();

    // Charger le nombre de messages non lus
    _unreadMessageCount = await messageService.getTotalUnreadCount(playerId);

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
      // Vérifier si l'adversaire est un bot (faux profil)
      final isBot = await duelService.isBot(player.id);

      if (isBot) {
        // BOT : auto-accepter et lancer directement la partie
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
              ),
            ),
          );
          if (mounted) _loadData();
        }
      } else {
        // VRAI JOUEUR : attendre qu'il accepte
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Défi envoyé à ${player.username} ! Tu pourras jouer quand il aura accepté.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        _loadData();
      }
    }
  }

  Future<void> _acceptDuel(Duel duel) async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    // Vérifier si le challenger est en ligne
    final isOpponentOnline = await _checkPlayerOnline(duel.challengerId);

    if (isOpponentOnline) {
      // MODE TEMPS RÉEL : lobby → countdown → jeu simultané
      final accepted = await duelService.acceptDuelLive(duel.id);
      if (accepted && mounted) {
        await NotificationService.sendDuelAccepted(
          challengerId: duel.challengerId,
          accepterName: supabaseService.userName ?? 'Quelqu\'un',
        );

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DuelLobbyScreen(
              duel: duel,
              myPlayerId: playerId,
              opponentId: duel.challengerId,
              opponentName: duel.challengerName,
              opponentPhotoUrl: duel.challengerPhotoUrl,
              myName: supabaseService.userName,
              myPhotoUrl: supabaseService.userAvatar,
            ),
          ),
        );
        if (mounted) _loadData();
      }
    } else {
      // MODE ASYNC : comportement existant
      final accepted = await duelService.acceptDuel(duel.id);
      if (accepted && mounted) {
        await NotificationService.sendDuelAccepted(
          challengerId: duel.challengerId,
          accepterName: supabaseService.userName ?? 'Quelqu\'un',
        );

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
        if (mounted) _loadData();
      }
    }
  }

  /// Naviguer vers le lobby pour un duel live (appelé pour le challenger)
  void _navigateToLobby(Duel duel) {
    final playerId = supabaseService.playerId;
    if (playerId == null || !mounted) return;

    // Fermer toute notification en cours
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DuelLobbyScreen(
          duel: duel,
          myPlayerId: playerId,
          opponentId: duel.challengedId,
          opponentName: duel.challengedName,
          opponentPhotoUrl: duel.challengedPhotoUrl,
          myName: supabaseService.userName,
          myPhotoUrl: supabaseService.userAvatar,
        ),
      ),
    ).then((_) {
      if (mounted) _loadData();
    });
  }

  /// Vérifie si un joueur est en ligne (last_seen_at < 60s)
  Future<bool> _checkPlayerOnline(String playerId) async {
    try {
      final response = await Supabase.instance.client
          .from('players')
          .select('last_seen_at')
          .eq('id', playerId)
          .single();
      if (response['last_seen_at'] != null) {
        final lastSeen = DateTime.parse(response['last_seen_at']);
        return DateTime.now().toUtc().difference(lastSeen).inSeconds < 60;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _declineDuel(Duel duel) async {
    await duelService.declineDuel(duel.id);

    // Envoyer notification au challenger que son défi a été refusé
    await NotificationService.sendDuelDeclined(
      challengerId: duel.challengerId,
      declinerName: supabaseService.userName ?? 'Quelqu\'un',
    );

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
    final hasAnyDuels = _pendingDuels.isNotEmpty || _activeDuels.isNotEmpty || _myPendingChallenges.isNotEmpty || _completedDuels.isNotEmpty;

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
          const SizedBox(height: 16),
        ],

        // Résultats (duels terminés)
        if (_completedDuels.isNotEmpty) ...[
          _buildSectionHeader('RÉSULTATS', Colors.purple, Icons.emoji_events),
          ..._completedDuels.map((duel) => _buildDuelCard(
            duel: duel,
            screenWidth: screenWidth,
            type: 'completed',
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
      case 'completed':
        // Afficher le résultat du duel
        if (myScore != null && opponentScore != null) {
          final isWinner = myScore > opponentScore;
          final isDraw = myScore == opponentScore;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$myScore - $opponentScore',
                style: TextStyle(
                  color: isDraw ? Colors.blue[700] : (isWinner ? Colors.green[700] : Colors.red[700]),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isDraw ? '⚖️ Égalité' : (isWinner ? '🏆 Victoire !' : '❌ Défaite'),
                style: TextStyle(
                  color: isDraw ? Colors.blue[700] : (isWinner ? Colors.green[700] : Colors.red[700]),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );
        }
        return const SizedBox();
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
      case 'completed':
        // Bouton Revanche pour les duels terminés
        return GestureDetector(
          onTap: () => _revengePlayer(duel),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE91E63).withOpacity(0.4),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              'Revanche',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
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

  /// Lancer une revanche contre l'adversaire d'un duel terminé
  Future<void> _revengePlayer(Duel duel) async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    // Déterminer l'adversaire
    final isChallenger = duel.challengerId == playerId;
    final opponentId = isChallenger ? duel.challengedId : duel.challengerId;
    final opponentName = isChallenger ? duel.challengedName : duel.challengerName;
    final opponentPhoto = isChallenger ? duel.challengedPhotoUrl : duel.challengerPhotoUrl;

    // Créer un PlayerSummary pour réutiliser la méthode existante
    final opponent = PlayerSummary(
      id: opponentId,
      username: opponentName ?? 'Joueur',
      photoUrl: opponentPhoto,
      isOnline: false,
      isFriend: false,
    );

    await _challengePlayer(opponent);
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

  /// Ouvre le chat avec un ami
  void _openChat(PlayerSummary player) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          friendId: player.id,
          friendName: player.username,
          friendPhotoUrl: player.photoUrl,
        ),
      ),
    );
  }

  /// Affiche le profil d'un joueur avec ses stats et options
  void _showFriendProfile(PlayerSummary player) {
    showDialog(
      context: context,
      builder: (context) => _FriendProfileDialog(
        player: player,
        // Bouton supprimer seulement si c'est un ami
        onRemoveFriend: player.isFriend ? () async {
          final playerId = supabaseService.playerId;
          if (playerId == null) return;

          // Confirmer la suppression
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF2A1B3D),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'Supprimer cet ami ?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Text(
                'Tu ne seras plus ami avec ${player.username}.',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Supprimer', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (confirm == true) {
            final success = await friendService.removeFriend(playerId, player.id);
            if (mounted) {
              Navigator.pop(context); // Fermer le dialog du profil
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success
                    ? '${player.username} a été supprimé de tes amis'
                    : 'Erreur lors de la suppression'),
                  backgroundColor: success ? Colors.orange : Colors.red,
                ),
              );
              if (success) _loadData(); // Recharger la liste
            }
          }
        } : null,
        // Bouton ajouter seulement si ce n'est PAS un ami
        onAddFriend: !player.isFriend ? () async {
          final playerId = supabaseService.playerId;
          if (playerId == null) return;

          final success = await friendService.sendFriendRequest(playerId, player.id);
          if (mounted) {
            Navigator.pop(context); // Fermer le dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success
                  ? 'Demande d\'ami envoyée à ${player.username} !'
                  : 'Erreur lors de l\'envoi'),
                backgroundColor: success ? Colors.green : Colors.red,
              ),
            );
          }
        } : null,
        onChallenge: () {
          Navigator.pop(context); // Fermer le dialog
          _challengePlayer(player);
        },
        // Bouton chat seulement si c'est un ami
        onOpenChat: player.isFriend ? () {
          Navigator.pop(context); // Fermer le dialog
          _openChat(player);
        } : null,
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
              // Photo - left=20, top=22 - cliquable pour voir le profil
              Positioned(
                left: 20,
                top: 22,
                child: GestureDetector(
                  onTap: () => _showFriendProfile(player),
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
                  child: GestureDetector(
                    onTap: () => _openChat(player),
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
              // Bouton Messages (animé) avec badge
              _buildMessagesButtonWithBadge(buttonSize),
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

/// Dialog pour afficher le profil complet d'un joueur avec stats
class _FriendProfileDialog extends StatefulWidget {
  final PlayerSummary player;
  final VoidCallback? onRemoveFriend;  // Null si pas ami
  final VoidCallback onChallenge;
  final VoidCallback? onAddFriend;  // Pour ajouter en ami si pas ami
  final VoidCallback? onOpenChat;  // Pour ouvrir le chat (si ami)

  const _FriendProfileDialog({
    required this.player,
    this.onRemoveFriend,
    required this.onChallenge,
    this.onAddFriend,
    this.onOpenChat,
  });

  @override
  State<_FriendProfileDialog> createState() => _FriendProfileDialogState();
}

class _FriendProfileDialogState extends State<_FriendProfileDialog> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await friendService.getPlayerStats(widget.player.id);
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1B3D), Color(0xFF1A0F2E)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE91E63), width: 3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE91E63).withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header avec photo et statut
            Stack(
              alignment: Alignment.center,
              children: [
                // Photo
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFFD700), width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.4),
                        blurRadius: 15,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: widget.player.photoUrl != null
                        ? Image.network(
                            widget.player.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
                          )
                        : _buildDefaultAvatar(),
                  ),
                ),
                // Pastille online/offline
                Positioned(
                  bottom: 5,
                  right: 5,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.player.isOnline ? Colors.green : Colors.red,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: (widget.player.isOnline ? Colors.green : Colors.red).withOpacity(0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Nom
            Text(
              widget.player.username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            // Statut
            Text(
              widget.player.isOnline ? '🟢 En ligne' : '🔴 Hors ligne',
              style: TextStyle(
                color: widget.player.isOnline ? Colors.green[300] : Colors.red[300],
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 20),

            // Stats
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Color(0xFFE91E63)),
              )
            else
              _buildStatsGrid(),

            const SizedBox(height: 20),

            // Boutons d'action - rangée 1 (Supprimer/Ajouter + Message)
            if (widget.player.isFriend)
              Row(
                children: [
                  // Bouton Message (vert)
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onOpenChat,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF66BB6A), Color(0xFF43A047)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Message',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Bouton Supprimer (rouge)
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onRemoveFriend,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B6B), Color(0xFFEE5A5A)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_remove, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Supprimer',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else if (widget.onAddFriend != null)
              // Bouton Ajouter (pour non-amis)
              GestureDetector(
                onTap: widget.onAddFriend,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF66BB6A), Color(0xFF43A047)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_add, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Ajouter en ami',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Bouton Défier (toujours visible)
            GestureDetector(
              onTap: widget.onChallenge,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B9D), Color(0xFFE91E63)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE91E63).withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sports_esports, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Défier',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Bouton Fermer
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Fermer',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final gamesPlayed = _stats?['games_played'] ?? 0;
    final highScore = _stats?['high_score'] ?? 0;
    final totalScore = _stats?['total_score'] ?? 0;
    final bestCombo = _stats?['best_combo'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatItem(Icons.games, 'Parties', '$gamesPlayed', Colors.blue),
              const SizedBox(width: 16),
              _buildStatItem(Icons.emoji_events, 'Record', '$highScore', Colors.amber),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatItem(Icons.stars, 'Total', '$totalScore', Colors.purple),
              const SizedBox(width: 16),
              _buildStatItem(Icons.flash_on, 'Combo', 'x$bestCombo', Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: const Color(0xFFFF6B9D),
      child: Center(
        child: Text(
          widget.player.username.isNotEmpty ? widget.player.username[0].toUpperCase() : '?',
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

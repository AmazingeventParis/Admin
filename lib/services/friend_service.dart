import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modèle représentant un joueur pour l'affichage
class PlayerSummary {
  final String id;
  final String username;
  final String? photoUrl;
  final bool isOnline;
  final bool isFriend;
  final bool hasPendingRequest;

  PlayerSummary({
    required this.id,
    required this.username,
    this.photoUrl,
    this.isOnline = false,
    this.isFriend = false,
    this.hasPendingRequest = false,
  });

  factory PlayerSummary.fromJson(Map<String, dynamic> json, {
    bool isFriend = false,
    bool hasPendingRequest = false,
  }) {
    // Vérifier si le joueur est en ligne (actif dans la dernière minute)
    bool online = false;
    if (json['last_seen_at'] != null) {
      final lastSeen = DateTime.parse(json['last_seen_at']);
      online = DateTime.now().difference(lastSeen).inSeconds < 60;
    }

    return PlayerSummary(
      id: json['id'],
      username: json['username'] ?? 'Joueur',
      photoUrl: json['photo_url'],
      isOnline: online,
      isFriend: isFriend,
      hasPendingRequest: hasPendingRequest,
    );
  }
}

/// Service gérant les amis et la liste des joueurs
class FriendService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Envoie une demande d'ami
  Future<bool> sendFriendRequest(String playerId, String friendId) async {
    try {
      await _client.from('friends').insert({
        'player_id': playerId,
        'friend_id': friendId,
        'status': 'pending',
      });
      return true;
    } catch (e) {
      print('Erreur envoi demande ami: $e');
      return false;
    }
  }

  /// Accepte une demande d'ami
  Future<bool> acceptFriendRequest(String requestId) async {
    try {
      await _client.from('friends').update({
        'status': 'accepted',
      }).eq('id', requestId);
      return true;
    } catch (e) {
      print('Erreur acceptation ami: $e');
      return false;
    }
  }

  /// Refuse une demande d'ami
  Future<bool> declineFriendRequest(String requestId) async {
    try {
      await _client.from('friends').delete().eq('id', requestId);
      return true;
    } catch (e) {
      print('Erreur refus ami: $e');
      return false;
    }
  }

  /// Accepte une demande d'ami en utilisant les IDs des joueurs
  Future<bool> acceptFriendRequestByPlayerId(String myPlayerId, String senderPlayerId) async {
    try {
      await _client.from('friends').update({
        'status': 'accepted',
      }).eq('player_id', senderPlayerId).eq('friend_id', myPlayerId);
      return true;
    } catch (e) {
      print('Erreur acceptation ami par playerId: $e');
      return false;
    }
  }

  /// Refuse une demande d'ami en utilisant les IDs des joueurs
  Future<bool> declineFriendRequestByPlayerId(String myPlayerId, String senderPlayerId) async {
    try {
      await _client.from('friends').delete()
          .eq('player_id', senderPlayerId)
          .eq('friend_id', myPlayerId);
      return true;
    } catch (e) {
      print('Erreur refus ami par playerId: $e');
      return false;
    }
  }

  /// Supprime un ami
  Future<bool> removeFriend(String playerId, String friendId) async {
    try {
      // Supprimer dans les deux sens
      await _client
          .from('friends')
          .delete()
          .or('and(player_id.eq.$playerId,friend_id.eq.$friendId),and(player_id.eq.$friendId,friend_id.eq.$playerId)');
      return true;
    } catch (e) {
      print('Erreur suppression ami: $e');
      return false;
    }
  }

  /// Récupère la liste des amis d'un joueur
  Future<List<PlayerSummary>> getFriends(String playerId) async {
    try {
      // Amis où je suis player_id
      final response1 = await _client
          .from('friends')
          .select('''
            friend:players!friends_friend_id_fkey(id, username, photo_url, last_seen_at)
          ''')
          .eq('player_id', playerId)
          .eq('status', 'accepted');

      // Amis où je suis friend_id
      final response2 = await _client
          .from('friends')
          .select('''
            friend:players!friends_player_id_fkey(id, username, photo_url, last_seen_at)
          ''')
          .eq('friend_id', playerId)
          .eq('status', 'accepted');

      final List<PlayerSummary> friends = [];

      for (var row in response1) {
        if (row['friend'] != null) {
          friends.add(PlayerSummary.fromJson(row['friend'], isFriend: true));
        }
      }

      for (var row in response2) {
        if (row['friend'] != null) {
          friends.add(PlayerSummary.fromJson(row['friend'], isFriend: true));
        }
      }

      // Trier par statut en ligne puis par nom
      friends.sort((a, b) {
        if (a.isOnline && !b.isOnline) return -1;
        if (!a.isOnline && b.isOnline) return 1;
        return a.username.compareTo(b.username);
      });

      return friends;
    } catch (e) {
      print('Erreur récupération amis: $e');
      return [];
    }
  }

  /// Récupère les demandes d'ami en attente
  Future<List<PlayerSummary>> getPendingRequests(String playerId) async {
    try {
      final response = await _client
          .from('friends')
          .select('''
            id,
            player:players!friends_player_id_fkey(id, username, photo_url, last_seen_at)
          ''')
          .eq('friend_id', playerId)
          .eq('status', 'pending');

      return (response as List).map((row) {
        if (row['player'] != null) {
          return PlayerSummary.fromJson(
            row['player'],
            hasPendingRequest: true,
          );
        }
        return null;
      }).whereType<PlayerSummary>().toList();
    } catch (e) {
      print('Erreur récupération demandes: $e');
      return [];
    }
  }

  /// Récupère tous les joueurs (pour onglet "Tous") - sans les amis
  Future<List<PlayerSummary>> getAllPlayers(String currentPlayerId, {String? search}) async {
    try {
      var query = _client
          .from('players')
          .select('id, username, photo_url, last_seen_at')
          .neq('id', currentPlayerId);

      if (search != null && search.isNotEmpty) {
        query = query.ilike('username', '%$search%');
      }

      final response = await query.order('username').limit(100);

      // Récupérer les IDs des amis pour les exclure
      final friends = await getFriends(currentPlayerId);
      final friendIds = friends.map((f) => f.id).toSet();

      // Récupérer les demandes en attente envoyées
      final sentRequests = await _getSentPendingRequests(currentPlayerId);
      final sentRequestIds = sentRequests.toSet();

      // Filtrer pour exclure les amis
      return (response as List)
          .where((json) => !friendIds.contains(json['id']))
          .map((json) {
            return PlayerSummary.fromJson(
              json,
              isFriend: false,
              hasPendingRequest: sentRequestIds.contains(json['id']),
            );
          }).toList();
    } catch (e) {
      print('Erreur récupération tous les joueurs: $e');
      return [];
    }
  }

  /// Récupère les joueurs en ligne
  Future<List<PlayerSummary>> getOnlinePlayers(String currentPlayerId) async {
    try {
      final oneMinuteAgo = DateTime.now().subtract(const Duration(seconds: 60));

      final response = await _client
          .from('players')
          .select('id, username, photo_url, last_seen_at')
          .neq('id', currentPlayerId)
          .gte('last_seen_at', oneMinuteAgo.toIso8601String())
          .order('username')
          .limit(50);

      // Récupérer les IDs des amis
      final friends = await getFriends(currentPlayerId);
      final friendIds = friends.map((f) => f.id).toSet();

      return (response as List).map((json) {
        return PlayerSummary.fromJson(
          json,
          isFriend: friendIds.contains(json['id']),
        );
      }).toList();
    } catch (e) {
      print('Erreur récupération joueurs en ligne: $e');
      return [];
    }
  }

  /// Récupère les demandes d'ami envoyées en attente
  Future<List<String>> _getSentPendingRequests(String playerId) async {
    try {
      final response = await _client
          .from('friends')
          .select('friend_id')
          .eq('player_id', playerId)
          .eq('status', 'pending');

      return (response as List).map((row) => row['friend_id'] as String).toList();
    } catch (e) {
      return [];
    }
  }

  /// Met à jour le statut "en ligne" du joueur
  Future<void> updateOnlineStatus(String playerId) async {
    try {
      await _client.from('players').update({
        'last_seen_at': DateTime.now().toIso8601String(),
      }).eq('id', playerId);
    } catch (e) {
      print('Erreur mise à jour statut en ligne: $e');
    }
  }

  /// Met le joueur hors ligne immédiatement
  Future<void> setOffline(String playerId) async {
    try {
      // Mettre last_seen_at à 10 minutes dans le passé pour être immédiatement hors ligne
      final offlineTime = DateTime.now().subtract(const Duration(minutes: 10));
      await _client.from('players').update({
        'last_seen_at': offlineTime.toIso8601String(),
      }).eq('id', playerId);
    } catch (e) {
      print('Erreur mise hors ligne: $e');
    }
  }

  /// Simule la présence en ligne de quelques bots aléatoires
  /// Appelé au démarrage de l'app et toutes les 2-3 minutes
  List<String> _currentOnlineBotIds = [];

  Future<void> simulateBotOnlineStatus() async {
    try {
      final rng = Random();

      // 1. Récupérer tous les faux profils
      final response = await _client
          .from('players')
          .select('id, device_id')
          .like('device_id', 'fake_%');

      final allBots = (response as List);
      if (allBots.isEmpty) return;

      // 2. Mettre tous les anciens bots "en ligne" → hors ligne
      if (_currentOnlineBotIds.isNotEmpty) {
        final offlineTime = DateTime.now().subtract(const Duration(minutes: 10));
        for (final botId in _currentOnlineBotIds) {
          await _client.from('players').update({
            'last_seen_at': offlineTime.toIso8601String(),
          }).eq('id', botId);
        }
      }

      // 3. Choisir aléatoirement combien de bots seront en ligne
      // Entre 20% et 50% des bots, minimum 1, maximum 8
      final total = allBots.length;
      final ratio = 0.20 + rng.nextDouble() * 0.30;
      final nbOnline = (total * ratio).round().clamp(1, 8);

      // 4. Mélanger et prendre les N premiers
      allBots.shuffle(rng);
      final selectedBots = allBots.take(nbOnline).toList();
      _currentOnlineBotIds = selectedBots.map((b) => b['id'] as String).toList();

      // 5. Mettre ces bots "en ligne" avec des last_seen_at récents mais variés
      for (final bot in selectedBots) {
        // Chaque bot a un last_seen_at entre maintenant et il y a 30 secondes
        final secondsAgo = rng.nextInt(30);
        final lastSeen = DateTime.now().subtract(Duration(seconds: secondsAgo));
        await _client.from('players').update({
          'last_seen_at': lastSeen.toIso8601String(),
        }).eq('id', bot['id']);
      }
    } catch (e) {
      print('Erreur simulation bots en ligne: $e');
    }
  }

  /// Rafraîchit le last_seen_at des bots actuellement "en ligne"
  /// Pour qu'ils restent en ligne entre les rotations
  Future<void> refreshBotOnlineStatus() async {
    try {
      if (_currentOnlineBotIds.isEmpty) return;
      final rng = Random();

      for (final botId in _currentOnlineBotIds) {
        final secondsAgo = rng.nextInt(20);
        final lastSeen = DateTime.now().subtract(Duration(seconds: secondsAgo));
        await _client.from('players').update({
          'last_seen_at': lastSeen.toIso8601String(),
        }).eq('id', botId);
      }
    } catch (e) {
      print('Erreur refresh bots en ligne: $e');
    }
  }

  /// Connecte ou déconnecte UN bot aléatoire (micro-mouvement en live)
  Future<void> randomBotToggle() async {
    try {
      final rng = Random();

      // Récupérer tous les faux profils
      final response = await _client
          .from('players')
          .select('id, device_id, last_seen_at')
          .like('device_id', 'fake_%');

      final allBots = (response as List);
      if (allBots.isEmpty) return;

      // Séparer les bots en ligne et hors ligne
      final now = DateTime.now();
      final onlineBots = <Map<String, dynamic>>[];
      final offlineBots = <Map<String, dynamic>>[];

      for (final bot in allBots) {
        if (bot['last_seen_at'] != null) {
          final lastSeen = DateTime.parse(bot['last_seen_at']);
          if (now.difference(lastSeen).inSeconds < 60) {
            onlineBots.add(bot);
          } else {
            offlineBots.add(bot);
          }
        } else {
          offlineBots.add(bot);
        }
      }

      // Décider : connecter un offline ou déconnecter un online ?
      // Si trop de bots en ligne (>50%), plus de chances de déconnecter
      // Si peu en ligne (<20%), plus de chances de connecter
      final onlineRatio = allBots.isEmpty ? 0.0 : onlineBots.length / allBots.length;
      final connectChance = onlineRatio > 0.45 ? 0.3 : (onlineRatio < 0.15 ? 0.85 : 0.55);

      if (rng.nextDouble() < connectChance && offlineBots.isNotEmpty) {
        // Connecter un bot offline
        final bot = offlineBots[rng.nextInt(offlineBots.length)];
        final secondsAgo = rng.nextInt(15);
        final lastSeen = now.subtract(Duration(seconds: secondsAgo));
        await _client.from('players').update({
          'last_seen_at': lastSeen.toIso8601String(),
        }).eq('id', bot['id']);

        // L'ajouter à la liste des bots en ligne gérés
        if (!_currentOnlineBotIds.contains(bot['id'])) {
          _currentOnlineBotIds.add(bot['id']);
        }
      } else if (onlineBots.isNotEmpty) {
        // Déconnecter un bot online
        final bot = onlineBots[rng.nextInt(onlineBots.length)];
        final offlineTime = now.subtract(const Duration(minutes: 10));
        await _client.from('players').update({
          'last_seen_at': offlineTime.toIso8601String(),
        }).eq('id', bot['id']);

        _currentOnlineBotIds.remove(bot['id']);
      }
    } catch (e) {
      print('Erreur toggle bot: $e');
    }
  }

  /// Récupère les stats d'un joueur
  Future<Map<String, dynamic>?> getPlayerStats(String playerId) async {
    try {
      final response = await _client
          .from('player_stats')
          .select('*')
          .eq('player_id', playerId)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Erreur récupération stats: $e');
      return null;
    }
  }
}

// Instance globale
final friendService = FriendService();

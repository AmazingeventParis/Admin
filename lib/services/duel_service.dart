import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/duel.dart';
import 'notification_service.dart';
import 'supabase_service.dart';

/// Service gérant toutes les opérations liées aux duels
class DuelService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Crée un nouveau défi de duel
  Future<Duel?> createDuel({
    required String challengerId,
    required String challengedId,
  }) async {
    try {
      final seed = Random().nextInt(2147483647);

      final response = await _client
          .from('duels')
          .insert({
            'challenger_id': challengerId,
            'challenged_id': challengedId,
            'seed': seed,
            'status': 'pending',
          })
          .select()
          .single();

      // Envoyer une notification au joueur défié
      final challengerName = supabaseService.userName ?? 'Quelqu\'un';
      await NotificationService.sendDuelChallenge(
        challengedPlayerId: challengedId,
        challengerName: challengerName,
      );

      return Duel.fromJson(response);
    } catch (e) {
      print('Erreur création duel: $e');
      return null;
    }
  }

  /// Accepte un défi de duel
  Future<bool> acceptDuel(String duelId) async {
    try {
      await _client.from('duels').update({
        'status': 'active',
      }).eq('id', duelId);
      return true;
    } catch (e) {
      print('Erreur acceptation duel: $e');
      return false;
    }
  }

  /// Refuse un défi de duel
  Future<bool> declineDuel(String duelId) async {
    try {
      await _client.from('duels').update({
        'status': 'declined',
      }).eq('id', duelId);
      return true;
    } catch (e) {
      print('Erreur refus duel: $e');
      return false;
    }
  }

  /// Soumet le score d'un joueur pour un duel
  Future<Duel?> submitScore({
    required String duelId,
    required String playerId,
    required int score,
  }) async {
    try {
      // Récupérer le duel actuel
      final duel = await getDuel(duelId);
      if (duel == null) return null;

      Map<String, dynamic> updates = {};

      // Mettre à jour le bon score
      if (duel.challengerId == playerId) {
        updates['challenger_score'] = score;
      } else if (duel.challengedId == playerId) {
        updates['challenged_score'] = score;
      } else {
        return null; // Le joueur n'est pas dans ce duel
      }

      // Vérifier si l'autre joueur a déjà joué
      final otherScore = duel.challengerId == playerId
          ? duel.challengedScore
          : duel.challengerScore;

      if (otherScore != null) {
        // Les deux ont joué, déterminer le gagnant
        if (score > otherScore) {
          updates['winner_id'] = playerId;
        } else if (otherScore > score) {
          updates['winner_id'] = duel.challengerId == playerId
              ? duel.challengedId
              : duel.challengerId;
        }
        // Si égalité, winner_id reste null

        updates['status'] = 'completed';
      }

      await _client
          .from('duels')
          .update(updates)
          .eq('id', duelId);

      // Récupérer le duel mis à jour avec les infos joueurs
      final updatedDuel = await getDuel(duelId);

      // Envoyer les notifications de résultat si le duel est terminé
      if (otherScore != null && updatedDuel != null) {
        final isChallenger = playerId == duel.challengerId;
        final opponentId = isChallenger ? duel.challengedId : duel.challengerId;
        final opponentName = isChallenger ? duel.challengedName : duel.challengerName;
        final myName = isChallenger ? duel.challengerName : duel.challengedName;

        // Notification pour moi (le joueur qui vient de finir)
        await NotificationService.sendDuelResult(
          playerId: playerId,
          opponentName: opponentName ?? 'Adversaire',
          playerScore: score,
          opponentScore: otherScore,
          isWinner: score > otherScore,
        );

        // Notification pour l'adversaire
        await NotificationService.sendDuelResult(
          playerId: opponentId,
          opponentName: myName ?? 'Adversaire',
          playerScore: otherScore,
          opponentScore: score,
          isWinner: otherScore > score,
        );
      }

      return updatedDuel;
    } catch (e) {
      print('Erreur soumission score: $e');
      return null;
    }
  }

  /// Récupère un duel par son ID (avec infos joueurs)
  Future<Duel?> getDuel(String duelId) async {
    try {
      final response = await _client
          .from('duels')
          .select('''
            *,
            challenger:players!duels_challenger_id_fkey(id, username, photo_url),
            challenged:players!duels_challenged_id_fkey(id, username, photo_url)
          ''')
          .eq('id', duelId)
          .single();

      final duel = Duel.fromJson(response);

      // Ajouter les infos du challenger
      if (response['challenger'] != null) {
        duel.challengerName = response['challenger']['username'];
        duel.challengerPhotoUrl = response['challenger']['photo_url'];
      }

      // Ajouter les infos du challenged
      if (response['challenged'] != null) {
        duel.challengedName = response['challenged']['username'];
        duel.challengedPhotoUrl = response['challenged']['photo_url'];
      }

      return duel;
    } catch (e) {
      print('Erreur récupération duel: $e');
      return null;
    }
  }

  /// Récupère les duels en attente pour un joueur
  Future<List<Duel>> getPendingDuels(String playerId) async {
    try {
      final response = await _client
          .from('duels')
          .select('''
            *,
            challenger:players!duels_challenger_id_fkey(id, username, photo_url),
            challenged:players!duels_challenged_id_fkey(id, username, photo_url)
          ''')
          .eq('challenged_id', playerId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return _parseDuelsWithPlayers(response);
    } catch (e) {
      print('Erreur récupération duels en attente: $e');
      return [];
    }
  }

  /// Récupère le nombre de duels en attente (pour le badge)
  Future<int> getPendingDuelCount(String playerId) async {
    try {
      final response = await _client
          .from('duels')
          .select('id')
          .eq('challenged_id', playerId)
          .eq('status', 'pending');

      return (response as List).length;
    } catch (e) {
      print('Erreur comptage duels: $e');
      return 0;
    }
  }

  /// Récupère les duels actifs (en cours de jeu)
  Future<List<Duel>> getActiveDuels(String playerId) async {
    try {
      final response = await _client
          .from('duels')
          .select('''
            *,
            challenger:players!duels_challenger_id_fkey(id, username, photo_url),
            challenged:players!duels_challenged_id_fkey(id, username, photo_url)
          ''')
          .or('challenger_id.eq.$playerId,challenged_id.eq.$playerId')
          .eq('status', 'active')
          .order('created_at', ascending: false);

      return _parseDuelsWithPlayers(response);
    } catch (e) {
      print('Erreur récupération duels actifs: $e');
      return [];
    }
  }

  /// Récupère l'historique des duels d'un joueur
  Future<List<Duel>> getDuelHistory(String playerId, {int limit = 20}) async {
    try {
      final response = await _client
          .from('duels')
          .select('''
            *,
            challenger:players!duels_challenger_id_fkey(id, username, photo_url),
            challenged:players!duels_challenged_id_fkey(id, username, photo_url)
          ''')
          .or('challenger_id.eq.$playerId,challenged_id.eq.$playerId')
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(limit);

      return _parseDuelsWithPlayers(response);
    } catch (e) {
      print('Erreur récupération historique: $e');
      return [];
    }
  }

  /// Parse les duels avec les infos joueurs
  List<Duel> _parseDuelsWithPlayers(List<dynamic> response) {
    return response.map((json) {
      final duel = Duel.fromJson(json);

      // Ajouter les infos du challenger
      if (json['challenger'] != null) {
        duel.challengerName = json['challenger']['username'];
        duel.challengerPhotoUrl = json['challenger']['photo_url'];
      }

      // Ajouter les infos du challenged
      if (json['challenged'] != null) {
        duel.challengedName = json['challenged']['username'];
        duel.challengedPhotoUrl = json['challenged']['photo_url'];
      }

      return duel;
    }).toList();
  }
}

// Instance globale
final duelService = DuelService();

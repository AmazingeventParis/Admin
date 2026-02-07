import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Service de gestion des notifications push (désactivé temporairement)
class NotificationService {
  static String? _fcmToken;

  /// Initialise les notifications (stub - Firebase désactivé)
  static Future<void> initialize() async {
    print('Notifications désactivées (Firebase non configuré)');
    // Firebase temporairement désactivé pour iOS
  }

  /// Met à jour le token après connexion
  static Future<void> updateTokenAfterLogin() async {
    // Désactivé
  }

  /// Envoie une notification de défi à un joueur
  static Future<void> sendDuelChallenge({
    required String challengedPlayerId,
    required String challengerName,
  }) async {
    // Utiliser Supabase Edge Function si disponible
    try {
      await Supabase.instance.client.functions.invoke(
        'send-notification',
        body: {
          'type': 'duel_challenge',
          'target_player_id': challengedPlayerId,
          'title': 'Nouveau défi !',
          'body': '$challengerName vous a défié en duel !',
        },
      );
    } catch (e) {
      print('Notification non envoyée: $e');
    }
  }

  /// Envoie une notification de résultat de duel
  static Future<void> sendDuelResult({
    required String playerId,
    required String opponentName,
    required int playerScore,
    required int opponentScore,
    required bool isWinner,
  }) async {
    try {
      final String title;
      final String body;

      if (playerScore == opponentScore) {
        title = 'Égalité !';
        body = 'Match nul contre $opponentName ($playerScore - $opponentScore)';
      } else if (isWinner) {
        title = 'Victoire !';
        body = 'Vous avez battu $opponentName ($playerScore - $opponentScore)';
      } else {
        title = 'Défaite';
        body = '$opponentName vous a battu ($opponentScore - $playerScore)';
      }

      await Supabase.instance.client.functions.invoke(
        'send-notification',
        body: {
          'type': 'duel_result',
          'target_player_id': playerId,
          'title': title,
          'body': body,
        },
      );
    } catch (e) {
      print('Notification non envoyée: $e');
    }
  }

  /// Envoie une notification de demande d'ami
  static Future<void> sendFriendRequest({
    required String targetPlayerId,
    required String senderName,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-notification',
        body: {
          'type': 'friend_request',
          'target_player_id': targetPlayerId,
          'title': 'Demande d\'ami',
          'body': '$senderName veut être ton ami !',
        },
      );
    } catch (e) {
      print('Notification non envoyée: $e');
    }
  }

  /// Envoie une notification d'acceptation de demande d'ami
  static Future<void> sendFriendRequestAccepted({
    required String targetPlayerId,
    required String accepterName,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-notification',
        body: {
          'type': 'friend_accepted',
          'target_player_id': targetPlayerId,
          'title': 'Ami accepté !',
          'body': '$accepterName a accepté ta demande d\'ami !',
        },
      );
    } catch (e) {
      print('Notification non envoyée: $e');
    }
  }

  /// Envoie une notification de refus de demande d'ami
  static Future<void> sendFriendRequestDeclined({
    required String targetPlayerId,
    required String declinerName,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-notification',
        body: {
          'type': 'friend_declined',
          'target_player_id': targetPlayerId,
          'title': 'Demande refusée',
          'body': '$declinerName a refusé ta demande d\'ami.',
        },
      );
    } catch (e) {
      print('Notification non envoyée: $e');
    }
  }
}

// Instance globale
final notificationService = NotificationService();

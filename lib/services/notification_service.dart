import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Service de gestion des notifications push via OneSignal
class NotificationService {
  static const String _oneSignalAppId = '01e66a57-6563-4572-b396-ad338b648ddf';

  /// Initialise OneSignal
  static Future<void> initialize() async {
    try {
      // Initialiser OneSignal
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      OneSignal.initialize(_oneSignalAppId);

      // Demander la permission pour les notifications
      OneSignal.Notifications.requestPermission(true);

      // Écouter quand l'utilisateur clique sur une notification
      OneSignal.Notifications.addClickListener((event) {
        print('Notification cliquée: ${event.notification.body}');
        // Tu peux naviguer vers une page spécifique ici
      });

      print('OneSignal initialisé avec succès');
    } catch (e) {
      print('Erreur initialisation OneSignal: $e');
    }
  }

  /// Met à jour le tag du joueur après connexion (pour cibler les notifications)
  static Future<void> updateTokenAfterLogin() async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    try {
      // Définir l'external user id pour pouvoir cibler ce joueur
      await OneSignal.login(playerId);

      // Ajouter des tags pour identifier le joueur
      await OneSignal.User.addTags({
        'player_id': playerId,
      });

      print('OneSignal user id défini: $playerId');
    } catch (e) {
      print('Erreur mise à jour OneSignal user: $e');
    }
  }

  /// Déconnexion OneSignal
  static Future<void> logout() async {
    try {
      await OneSignal.logout();
    } catch (e) {
      print('Erreur logout OneSignal: $e');
    }
  }

  /// Envoie une notification via Supabase Edge Function (qui appellera OneSignal API)
  static Future<void> _sendNotification({
    required String targetPlayerId,
    required String title,
    required String body,
    String? imageUrl,
    Map<String, dynamic>? data,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-onesignal-notification',
        body: {
          'target_player_id': targetPlayerId,
          'title': title,
          'body': body,
          'image_url': imageUrl,
          'data': data,
        },
      );
    } catch (e) {
      print('Notification non envoyée: $e');
    }
  }

  /// Envoie une notification de défi à un joueur
  static Future<void> sendDuelChallenge({
    required String challengedPlayerId,
    required String challengerName,
  }) async {
    await _sendNotification(
      targetPlayerId: challengedPlayerId,
      title: 'Nouveau défi !',
      body: '$challengerName vous a défié en duel !',
      data: {'type': 'duel_challenge'},
    );
  }

  /// Envoie une notification de défi accepté
  static Future<void> sendDuelAccepted({
    required String challengerId,
    required String accepterName,
  }) async {
    await _sendNotification(
      targetPlayerId: challengerId,
      title: 'Défi accepté !',
      body: '$accepterName a accepté ton défi ! À toi de jouer !',
      data: {'type': 'duel_accepted'},
    );
  }

  /// Envoie une notification de défi refusé
  static Future<void> sendDuelDeclined({
    required String challengerId,
    required String declinerName,
  }) async {
    await _sendNotification(
      targetPlayerId: challengerId,
      title: 'Défi refusé',
      body: '$declinerName a refusé ton défi.',
      data: {'type': 'duel_declined'},
    );
  }

  /// Envoie une notification de résultat de duel
  static Future<void> sendDuelResult({
    required String playerId,
    required String opponentName,
    required int playerScore,
    required int opponentScore,
    required bool isWinner,
  }) async {
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

    await _sendNotification(
      targetPlayerId: playerId,
      title: title,
      body: body,
      data: {'type': 'duel_result'},
    );
  }

  /// Envoie une notification de demande d'ami
  static Future<void> sendFriendRequest({
    required String targetPlayerId,
    required String senderName,
  }) async {
    await _sendNotification(
      targetPlayerId: targetPlayerId,
      title: 'Demande d\'ami',
      body: '$senderName veut être ton ami !',
      data: {'type': 'friend_request'},
    );
  }

  /// Envoie une notification d'acceptation de demande d'ami
  static Future<void> sendFriendRequestAccepted({
    required String targetPlayerId,
    required String accepterName,
  }) async {
    await _sendNotification(
      targetPlayerId: targetPlayerId,
      title: 'Ami accepté !',
      body: '$accepterName a accepté ta demande d\'ami !',
      data: {'type': 'friend_accepted'},
    );
  }

  /// Envoie une notification de refus de demande d'ami
  static Future<void> sendFriendRequestDeclined({
    required String targetPlayerId,
    required String declinerName,
  }) async {
    await _sendNotification(
      targetPlayerId: targetPlayerId,
      title: 'Demande refusée',
      body: '$declinerName a refusé ta demande d\'ami.',
      data: {'type': 'friend_declined'},
    );
  }

  /// Envoie une notification de nouveau message
  static Future<void> sendNewMessage({
    required String targetPlayerId,
    required String senderName,
    required String? senderPhotoUrl,
    required String messagePreview,
  }) async {
    // Limiter le preview à 50 caractères
    final preview = messagePreview.length > 50
        ? '${messagePreview.substring(0, 50)}...'
        : messagePreview;

    await _sendNotification(
      targetPlayerId: targetPlayerId,
      title: senderName,
      body: preview,
      imageUrl: senderPhotoUrl,
      data: {
        'type': 'new_message',
        'sender_name': senderName,
        'sender_photo': senderPhotoUrl,
      },
    );
  }
}

// Instance globale
final notificationService = NotificationService();

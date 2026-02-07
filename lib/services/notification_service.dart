import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Service de gestion des notifications push
class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static String? _fcmToken;

  /// Initialise Firebase et les notifications
  static Future<void> initialize() async {
    try {
      // Initialiser Firebase
      await Firebase.initializeApp();

      // Demander les permissions de notification
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('Permission notifications: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Obtenir le token FCM
        _fcmToken = await _messaging.getToken();
        print('FCM Token: $_fcmToken');

        // Sauvegarder le token dans la base de données
        await _saveTokenToDatabase();

        // Ecouter les changements de token
        _messaging.onTokenRefresh.listen((newToken) {
          _fcmToken = newToken;
          _saveTokenToDatabase();
        });

        // Configurer les handlers de notifications
        _setupNotificationHandlers();
      }
    } catch (e) {
      print('Erreur initialisation notifications: $e');
    }
  }

  /// Sauvegarde le token FCM dans Supabase
  static Future<void> _saveTokenToDatabase() async {
    if (_fcmToken == null) return;

    final playerId = supabaseService.playerId;
    if (playerId == null) return;

    try {
      await Supabase.instance.client.from('players').update({
        'fcm_token': _fcmToken,
      }).eq('id', playerId);
      print('Token FCM sauvegardé');
    } catch (e) {
      print('Erreur sauvegarde token FCM: $e');
    }
  }

  /// Met à jour le token après connexion
  static Future<void> updateTokenAfterLogin() async {
    if (_fcmToken != null) {
      await _saveTokenToDatabase();
    }
  }

  /// Configure les handlers de notifications
  static void _setupNotificationHandlers() {
    // Notification reçue quand l'app est au premier plan
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Notification reçue (foreground): ${message.notification?.title}');
      // TODO: Afficher une notification locale ou un snackbar
    });

    // Notification cliquée quand l'app était en arrière-plan
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification cliquée: ${message.data}');
      // TODO: Naviguer vers la page appropriée (ex: page duel)
    });
  }

  /// Envoie une notification de défi à un joueur
  static Future<void> sendDuelChallenge({
    required String challengedPlayerId,
    required String challengerName,
  }) async {
    try {
      // Appeler une Edge Function Supabase pour envoyer la notification
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
      print('Erreur envoi notification défi: $e');
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
      print('Erreur envoi notification résultat: $e');
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
      print('Erreur envoi notification demande ami: $e');
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
      print('Erreur envoi notification ami accepté: $e');
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
      print('Erreur envoi notification ami refusé: $e');
    }
  }
}

// Instance globale
final notificationService = NotificationService();

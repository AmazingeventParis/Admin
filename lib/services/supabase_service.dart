import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'stats_service.dart';
import 'notification_service.dart';

class SupabaseService {
  static const String _supabaseUrl = 'https://icujwpwicsmyuyidubqf.supabase.co';
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImljdWp3cHdpY3NteXV5aWR1YnFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAxMTk5NjEsImV4cCI6MjA4NTY5NTk2MX0.PddUsHjUcHaJfeDciB8BYAVE50oNWG9AwkLLYjMFUl4';

  // Web Client ID from Google Cloud Console (pour Android)
  static const String _webClientId = '329868845376-hbh8plnscagl2smu97pphatm0kanmdg2.apps.googleusercontent.com';

  // iOS Client ID from Google Cloud Console
  static const String _iosClientId = '329868845376-mlj0g6jsgpqkglocvbc87h6vprosnb40.apps.googleusercontent.com';

  static SupabaseClient get client => Supabase.instance.client;

  String? _playerId;
  String? _deviceId;
  User? _currentUser;

  /// Initialise Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  }

  /// Vérifie si l'utilisateur est connecté avec Google
  bool get isLoggedIn => _currentUser != null;

  /// Récupère l'utilisateur actuel
  User? get currentUser => _currentUser;

  /// Récupère l'ID du joueur dans la base de données
  String? get playerId => _playerId;

  /// Récupère l'email de l'utilisateur connecté
  String? get userEmail => _currentUser?.email;

  /// Récupère le prénom de l'utilisateur connecté (seulement le premier mot)
  String? get userName {
    final fullName = _currentUser?.userMetadata?['full_name'] as String?;
    if (fullName == null || fullName.isEmpty) return null;
    // Ne garder que le prénom (premier mot)
    return fullName.split(' ').first;
  }

  /// Récupère l'avatar de l'utilisateur connecté
  String? get userAvatar {
    // Google peut utiliser 'avatar_url' ou 'picture'
    final metadata = _currentUser?.userMetadata;
    if (metadata == null) return null;
    return (metadata['avatar_url'] ?? metadata['picture']) as String?;
  }

  /// Connexion avec Google
  Future<bool> signInWithGoogle() async {
    try {
      // Utiliser le bon client ID selon la plateforme
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: !kIsWeb && Platform.isIOS ? _iosClientId : null,
        serverClientId: _webClientId,
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return false; // L'utilisateur a annulé
      }

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        return false;
      }

      final response = await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      _currentUser = response.user;

      if (_currentUser != null) {
        // Créer ou mettre à jour le joueur dans la base
        await _createOrUpdatePlayerFromAuth();
        // Sauvegarder le token FCM maintenant que playerId est défini
        await NotificationService.updateTokenAfterLogin();
        // Charger les stats du cloud pour ce compte (remplace les stats locales)
        await statsService.init();
        await statsService.loadFromCloudForNewUser();
        return true;
      }

      return false;
    } catch (e) {
      print('Erreur Google Sign-In: $e');
      return false;
    }
  }

  /// Déconnexion
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
      await client.auth.signOut();
      _currentUser = null;
      _playerId = null;
      // Réinitialiser les stats locales pour le prochain utilisateur
      await statsService.init();
      await statsService.resetAllStats();
    } catch (e) {
      print('Erreur déconnexion: $e');
    }
  }

  /// Vérifie la session au démarrage
  Future<void> checkSession() async {
    _currentUser = client.auth.currentUser;
    if (_currentUser != null) {
      await _createOrUpdatePlayerFromAuth();
      // Sauvegarder le token FCM maintenant que playerId est défini
      await NotificationService.updateTokenAfterLogin();
      // Charger les stats du cloud pour ce compte
      await statsService.init();
      await statsService.loadFromCloudForNewUser();
    }
  }

  /// Crée ou met à jour le joueur depuis l'auth Google
  Future<void> _createOrUpdatePlayerFromAuth() async {
    if (_currentUser == null) return;

    try {
      final email = _currentUser!.email ?? '';
      final fullName = _currentUser!.userMetadata?['full_name'] as String? ?? 'Joueur';
      // Ne garder que le prénom (premier mot) pour la vie privée
      final name = fullName.split(' ').first;

      // Chercher le joueur existant par email
      final existingPlayer = await client
          .from('players')
          .select('id')
          .eq('device_id', email)
          .maybeSingle();

      // Récupérer la photo Google
      final photoUrl = userAvatar;

      if (existingPlayer != null) {
        _playerId = existingPlayer['id'];
        // Mettre à jour le username et la photo
        await client
            .from('players')
            .update({
              'username': name,
              'photo_url': photoUrl,
              'updated_at': DateTime.now().toIso8601String()
            })
            .eq('id', _playerId!);
      } else {
        // Créer un nouveau joueur
        final newPlayer = await client
            .from('players')
            .insert({
              'device_id': email,
              'username': name,
              'photo_url': photoUrl,
            })
            .select('id')
            .single();

        _playerId = newPlayer['id'];

        // Créer les stats initiales
        await client.from('player_stats').insert({
          'player_id': _playerId,
        });
      }
    } catch (e) {
      print('Erreur _createOrUpdatePlayerFromAuth: $e');
    }
  }

  /// Récupère ou crée un ID unique pour cet appareil (mode anonyme)
  Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');

    if (_deviceId == null) {
      _deviceId = DateTime.now().millisecondsSinceEpoch.toString() +
          '_' +
          (DateTime.now().microsecond * 1000).toString();
      await prefs.setString('device_id', _deviceId!);
    }

    return _deviceId!;
  }

  /// Récupère ou crée le joueur dans la base de données (mode anonyme)
  Future<String?> getOrCreatePlayer(String username) async {
    // Si connecté avec Google, utiliser ce compte
    if (_currentUser != null) {
      await _createOrUpdatePlayerFromAuth();
      await NotificationService.updateTokenAfterLogin();
      return _playerId;
    }

    // Sinon, mode anonyme avec device_id
    try {
      final deviceId = await _getDeviceId();

      final existingPlayer = await client
          .from('players')
          .select('id')
          .eq('device_id', deviceId)
          .maybeSingle();

      if (existingPlayer != null) {
        _playerId = existingPlayer['id'];

        await client
            .from('players')
            .update({'username': username, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', _playerId!);

        // Sauvegarder le token FCM
        await NotificationService.updateTokenAfterLogin();
        return _playerId;
      }

      final newPlayer = await client
          .from('players')
          .insert({
            'device_id': deviceId,
            'username': username,
          })
          .select('id')
          .single();

      _playerId = newPlayer['id'];

      await client.from('player_stats').insert({
        'player_id': _playerId,
      });

      // Sauvegarder le token FCM
      await NotificationService.updateTokenAfterLogin();
      return _playerId;
    } catch (e) {
      print('Erreur getOrCreatePlayer: $e');
      return null;
    }
  }

  /// Met à jour le nom du joueur
  Future<void> updateUsername(String username) async {
    if (_playerId == null) return;

    try {
      await client
          .from('players')
          .update({'username': username, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', _playerId!);
    } catch (e) {
      print('Erreur updateUsername: $e');
    }
  }

  /// Synchronise les statistiques avec Supabase
  Future<void> syncStats({
    required int gamesPlayed,
    required int highScore,
    required int totalScore,
    required int totalLinesCleared,
    required int totalPlayTimeSeconds,
    required int bestCombo,
  }) async {
    if (_playerId == null) return;

    try {
      await client.from('player_stats').upsert({
        'player_id': _playerId,
        'games_played': gamesPlayed,
        'high_score': highScore,
        'total_score': totalScore,
        'total_lines_cleared': totalLinesCleared,
        'total_play_time_seconds': totalPlayTimeSeconds,
        'best_combo': bestCombo,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'player_id');
    } catch (e) {
      print('Erreur syncStats: $e');
    }
  }

  /// Récupère les stats depuis Supabase
  Future<Map<String, dynamic>?> fetchStats() async {
    if (_playerId == null) return null;

    try {
      final stats = await client
          .from('player_stats')
          .select()
          .eq('player_id', _playerId!)
          .maybeSingle();

      return stats;
    } catch (e) {
      print('Erreur fetchStats: $e');
      return null;
    }
  }

  /// Récupère le classement
  Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 50}) async {
    try {
      // Récupérer les stats triées par score décroissant
      final statsData = await client
          .from('player_stats')
          .select('''
            high_score,
            games_played,
            player_id,
            players (
              id,
              username,
              device_id,
              photo_url
            )
          ''')
          .order('high_score', ascending: false)
          .limit(limit);

      // Transformer les données
      final List<Map<String, dynamic>> result = [];
      for (var stat in statsData) {
        final player = stat['players'];
        if (player != null) {
          result.add({
            'id': player['id'],
            'username': player['username'],
            'device_id': player['device_id'],
            'photo_url': player['photo_url'],
            'high_score': stat['high_score'] ?? 0,
          });
        }
      }

      return result;
    } catch (e) {
      print('Erreur getLeaderboard: $e');
      return [];
    }
  }

  /// Récupère le rang du joueur
  Future<int?> getPlayerRank() async {
    if (_playerId == null) return null;

    try {
      final playerStats = await client
          .from('player_stats')
          .select('high_score')
          .eq('player_id', _playerId!)
          .maybeSingle();

      if (playerStats == null) return null;

      final highScore = playerStats['high_score'] as int;

      final result = await client
          .from('player_stats')
          .select('id')
          .gt('high_score', highScore);

      return (result as List).length + 1;
    } catch (e) {
      print('Erreur getPlayerRank: $e');
      return null;
    }
  }
}

// Instance globale
final supabaseService = SupabaseService();

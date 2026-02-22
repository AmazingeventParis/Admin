import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

/// Service pour gérer les statistiques du joueur
class StatsService {
  static const String _keyGamesPlayed = 'stats_games_played';
  static const String _keyHighScore = 'highScore';
  static const String _keyTotalLinesCleared = 'stats_total_lines_cleared';
  static const String _keyTotalPlayTimeSeconds = 'stats_total_play_time';
  static const String _keyTotalScore = 'stats_total_score';
  static const String _keyBestCombo = 'stats_best_combo';
  static const String _keyCandies = 'stats_candies';
  static const String _keyLastLoginDate = 'stats_last_login_date';
  static const String _keyLoginStreak = 'stats_login_streak';

  SharedPreferences? _prefs;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  // Parties jouées
  int get gamesPlayed => _prefs?.getInt(_keyGamesPlayed) ?? 0;

  Future<void> incrementGamesPlayed() async {
    await _prefs?.setInt(_keyGamesPlayed, gamesPlayed + 1);
    await _syncToCloud();
  }

  // Meilleur score
  int get highScore => _prefs?.getInt(_keyHighScore) ?? 0;

  Future<void> updateHighScore(int score) async {
    if (score > highScore) {
      await _prefs?.setInt(_keyHighScore, score);
      await _syncToCloud();
    }
  }

  // Lignes complétées (total)
  int get totalLinesCleared => _prefs?.getInt(_keyTotalLinesCleared) ?? 0;

  Future<void> addLinesCleared(int lines) async {
    await _prefs?.setInt(_keyTotalLinesCleared, totalLinesCleared + lines);
  }

  // Temps de jeu total (en secondes)
  int get totalPlayTimeSeconds => _prefs?.getInt(_keyTotalPlayTimeSeconds) ?? 0;

  Future<void> addPlayTime(int seconds) async {
    await _prefs?.setInt(_keyTotalPlayTimeSeconds, totalPlayTimeSeconds + seconds);
  }

  String get formattedPlayTime {
    final total = totalPlayTimeSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  // Score total cumulé
  int get totalScore => _prefs?.getInt(_keyTotalScore) ?? 0;

  Future<void> addScore(int score) async {
    await _prefs?.setInt(_keyTotalScore, totalScore + score);
  }

  // Meilleur combo
  int get bestCombo => _prefs?.getInt(_keyBestCombo) ?? 0;

  Future<void> updateBestCombo(int combo) async {
    if (combo > bestCombo) {
      await _prefs?.setInt(_keyBestCombo, combo);
    }
  }

  // Bonbons (monnaie du jeu)
  int get candies => _prefs?.getInt(_keyCandies) ?? 500;

  Future<void> addCandies(int amount) async {
    await _prefs?.setInt(_keyCandies, candies + amount);
  }

  Future<void> removeCandies(int amount) async {
    final newValue = (candies - amount).clamp(0, 999999);
    await _prefs?.setInt(_keyCandies, newValue);
  }

  bool get canAffordDuel => candies >= 20;

  // Login quotidien
  String? get lastLoginDate => _prefs?.getString(_keyLastLoginDate);
  int get loginStreak => _prefs?.getInt(_keyLoginStreak) ?? 0;

  /// Vérifie et attribue le bonus de connexion quotidienne
  /// Retourne le nombre de bonbons gagnés (0 si déjà réclamé aujourd'hui)
  Future<int> checkDailyLogin() async {
    final today = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
    final lastDate = lastLoginDate;

    if (lastDate == today) return 0; // Déjà réclamé aujourd'hui

    int newStreak;
    if (lastDate != null) {
      final lastDay = DateTime.parse(lastDate);
      final todayDay = DateTime.parse(today);
      final diff = todayDay.difference(lastDay).inDays;
      if (diff == 1) {
        // Jour consécutif
        newStreak = loginStreak + 1;
      } else {
        // Streak cassé
        newStreak = 1;
      }
    } else {
      newStreak = 1;
    }

    // Calculer la récompense : 30 + (streak-1) * 10, max 100
    final reward = (30 + (newStreak - 1) * 10).clamp(30, 100);

    await _prefs?.setString(_keyLastLoginDate, today);
    await _prefs?.setInt(_keyLoginStreak, newStreak);
    await addCandies(reward);
    await _syncToCloud();

    return reward;
  }

  // Score moyen par partie
  double get averageScore {
    if (gamesPlayed == 0) return 0;
    return totalScore / gamesPlayed;
  }

  /// Synchronise toutes les stats avec Supabase
  Future<void> _syncToCloud() async {
    await supabaseService.syncStats(
      gamesPlayed: gamesPlayed,
      highScore: highScore,
      totalScore: totalScore,
      totalLinesCleared: totalLinesCleared,
      totalPlayTimeSeconds: totalPlayTimeSeconds,
      bestCombo: bestCombo,
      candies: candies,
      lastLoginDate: lastLoginDate,
      loginStreak: loginStreak,
    );
  }

  /// Sync manuel (appelé à la fin d'une partie)
  Future<void> syncToCloud() async {
    await _syncToCloud();
  }

  /// Charge les stats depuis le cloud (au démarrage)
  Future<void> loadFromCloud() async {
    final cloudStats = await supabaseService.fetchStats();
    if (cloudStats == null) return;

    // Prendre le max entre local et cloud pour chaque stat
    final cloudGamesPlayed = cloudStats['games_played'] as int? ?? 0;
    final cloudHighScore = cloudStats['high_score'] as int? ?? 0;
    final cloudTotalScore = cloudStats['total_score'] as int? ?? 0;
    final cloudTotalLines = cloudStats['total_lines_cleared'] as int? ?? 0;
    final cloudPlayTime = cloudStats['total_play_time_seconds'] as int? ?? 0;
    final cloudBestCombo = cloudStats['best_combo'] as int? ?? 0;
    final cloudCandies = cloudStats['candies'] as int? ?? 500;
    final cloudLastLoginDate = cloudStats['last_login_date'] as String?;
    final cloudLoginStreak = cloudStats['login_streak'] as int? ?? 0;

    // Fusionner : prendre le max
    if (cloudGamesPlayed > gamesPlayed) {
      await _prefs?.setInt(_keyGamesPlayed, cloudGamesPlayed);
    }
    if (cloudHighScore > highScore) {
      await _prefs?.setInt(_keyHighScore, cloudHighScore);
    }
    if (cloudTotalScore > totalScore) {
      await _prefs?.setInt(_keyTotalScore, cloudTotalScore);
    }
    if (cloudTotalLines > totalLinesCleared) {
      await _prefs?.setInt(_keyTotalLinesCleared, cloudTotalLines);
    }
    if (cloudPlayTime > totalPlayTimeSeconds) {
      await _prefs?.setInt(_keyTotalPlayTimeSeconds, cloudPlayTime);
    }
    if (cloudBestCombo > bestCombo) {
      await _prefs?.setInt(_keyBestCombo, cloudBestCombo);
    }
    if (cloudCandies > candies) {
      await _prefs?.setInt(_keyCandies, cloudCandies);
    }
    if (cloudLastLoginDate != null) {
      await _prefs?.setString(_keyLastLoginDate, cloudLastLoginDate);
    }
    if (cloudLoginStreak > loginStreak) {
      await _prefs?.setInt(_keyLoginStreak, cloudLoginStreak);
    }
  }

  /// Charge les stats du cloud en remplaçant les stats locales (pour changement de compte)
  Future<void> loadFromCloudForNewUser() async {
    // D'abord réinitialiser les stats locales
    await resetAllStats();

    // Puis charger depuis le cloud
    final cloudStats = await supabaseService.fetchStats();
    if (cloudStats == null) return;

    final cloudGamesPlayed = cloudStats['games_played'] as int? ?? 0;
    final cloudHighScore = cloudStats['high_score'] as int? ?? 0;
    final cloudTotalScore = cloudStats['total_score'] as int? ?? 0;
    final cloudTotalLines = cloudStats['total_lines_cleared'] as int? ?? 0;
    final cloudPlayTime = cloudStats['total_play_time_seconds'] as int? ?? 0;
    final cloudBestCombo = cloudStats['best_combo'] as int? ?? 0;
    final cloudCandies = cloudStats['candies'] as int? ?? 500;
    final cloudLastLoginDate = cloudStats['last_login_date'] as String?;
    final cloudLoginStreak = cloudStats['login_streak'] as int? ?? 0;

    await _prefs?.setInt(_keyGamesPlayed, cloudGamesPlayed);
    await _prefs?.setInt(_keyHighScore, cloudHighScore);
    await _prefs?.setInt(_keyTotalScore, cloudTotalScore);
    await _prefs?.setInt(_keyTotalLinesCleared, cloudTotalLines);
    await _prefs?.setInt(_keyTotalPlayTimeSeconds, cloudPlayTime);
    await _prefs?.setInt(_keyBestCombo, cloudBestCombo);
    await _prefs?.setInt(_keyCandies, cloudCandies);
    if (cloudLastLoginDate != null) {
      await _prefs?.setString(_keyLastLoginDate, cloudLastLoginDate);
    }
    await _prefs?.setInt(_keyLoginStreak, cloudLoginStreak);
  }

  // Réinitialiser toutes les stats
  Future<void> resetAllStats() async {
    await _prefs?.setInt(_keyGamesPlayed, 0);
    await _prefs?.setInt(_keyHighScore, 0);
    await _prefs?.setInt(_keyTotalLinesCleared, 0);
    await _prefs?.setInt(_keyTotalPlayTimeSeconds, 0);
    await _prefs?.setInt(_keyTotalScore, 0);
    await _prefs?.setInt(_keyBestCombo, 0);
    await _prefs?.setInt(_keyCandies, 500);
    await _prefs?.remove(_keyLastLoginDate);
    await _prefs?.setInt(_keyLoginStreak, 0);
  }
}

// Instance globale
final statsService = StatsService();

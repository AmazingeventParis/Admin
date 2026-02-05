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

    await _prefs?.setInt(_keyGamesPlayed, cloudGamesPlayed);
    await _prefs?.setInt(_keyHighScore, cloudHighScore);
    await _prefs?.setInt(_keyTotalScore, cloudTotalScore);
    await _prefs?.setInt(_keyTotalLinesCleared, cloudTotalLines);
    await _prefs?.setInt(_keyTotalPlayTimeSeconds, cloudPlayTime);
    await _prefs?.setInt(_keyBestCombo, cloudBestCombo);
  }

  // Réinitialiser toutes les stats
  Future<void> resetAllStats() async {
    await _prefs?.setInt(_keyGamesPlayed, 0);
    await _prefs?.setInt(_keyHighScore, 0);
    await _prefs?.setInt(_keyTotalLinesCleared, 0);
    await _prefs?.setInt(_keyTotalPlayTimeSeconds, 0);
    await _prefs?.setInt(_keyTotalScore, 0);
    await _prefs?.setInt(_keyBestCombo, 0);
  }
}

// Instance globale
final statsService = StatsService();

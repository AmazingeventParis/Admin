import 'package:audioplayers/audioplayers.dart';

/// Service audio global pour gérer la musique de fond et les effets sonores
class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _introPlayer = AudioPlayer();
  final AudioPlayer _gamePlayer = AudioPlayer();

  // Players pour effets sonores (peuvent jouer en parallèle)
  final AudioPlayer _sfxPlayer1 = AudioPlayer();
  final AudioPlayer _sfxPlayer2 = AudioPlayer();
  int _currentSfxPlayer = 0;

  bool _isIntroPlaying = false;
  bool _isGamePlaying = false;
  bool _isInitialized = false;

  double _introVolume = 0.6;
  double _gameVolume = 0.5;
  double _sfxVolume = 0.8;

  /// Initialiser le service audio
  Future<void> init() async {
    if (_isInitialized) return;

    // Configurer les players en mode boucle
    await _introPlayer.setReleaseMode(ReleaseMode.loop);
    await _gamePlayer.setReleaseMode(ReleaseMode.loop);

    await _introPlayer.setVolume(_introVolume);
    await _gamePlayer.setVolume(_gameVolume);

    _isInitialized = true;
  }

  /// Jouer la musique d'intro (pour toutes les pages sauf le jeu)
  Future<void> playIntroMusic() async {
    try {
      await init();

      // Si la musique de jeu joue, l'arrêter
      if (_isGamePlaying) {
        await _gamePlayer.stop();
        _isGamePlaying = false;
      }

      // Si l'intro ne joue pas déjà, la démarrer
      if (!_isIntroPlaying) {
        await _introPlayer.play(AssetSource('sounds/intro.mp3'));
        _isIntroPlaying = true;
      }
    } catch (e) {
      print('Erreur playIntroMusic: $e');
    }
  }

  /// Jouer la musique de jeu
  Future<void> playGameMusic() async {
    await init();

    // Arrêter la musique d'intro
    if (_isIntroPlaying) {
      await _introPlayer.stop();
      _isIntroPlaying = false;
    }

    // Démarrer la musique de jeu si pas déjà en cours
    if (!_isGamePlaying) {
      await _gamePlayer.play(AssetSource('sounds/music.mp3'));
      _isGamePlaying = true;
    }
  }

  /// Arrêter la musique de jeu et reprendre l'intro
  Future<void> stopGameMusic() async {
    if (_isGamePlaying) {
      await _gamePlayer.stop();
      _isGamePlaying = false;
    }
    // Reprendre la musique d'intro
    await playIntroMusic();
  }

  /// Mettre en pause toute la musique
  Future<void> pauseAll() async {
    if (_isIntroPlaying) {
      await _introPlayer.pause();
    }
    if (_isGamePlaying) {
      await _gamePlayer.pause();
    }
  }

  /// Reprendre la musique
  Future<void> resumeAll() async {
    if (_isIntroPlaying) {
      await _introPlayer.resume();
    }
    if (_isGamePlaying) {
      await _gamePlayer.resume();
    }
  }

  /// Arrêter toute la musique
  Future<void> stopAll() async {
    await _introPlayer.stop();
    await _gamePlayer.stop();
    _isIntroPlaying = false;
    _isGamePlaying = false;
  }

  /// Définir le volume de l'intro
  Future<void> setIntroVolume(double volume) async {
    _introVolume = volume;
    await _introPlayer.setVolume(volume);
  }

  /// Définir le volume du jeu
  Future<void> setGameVolume(double volume) async {
    _gameVolume = volume;
    await _gamePlayer.setVolume(volume);
  }

  /// Définir le volume des effets sonores
  Future<void> setSfxVolume(double volume) async {
    _sfxVolume = volume;
    await _sfxPlayer1.setVolume(volume);
    await _sfxPlayer2.setVolume(volume);
  }

  /// Jouer un effet sonore
  /// Utilise des players alternés pour permettre plusieurs sons simultanés
  Future<void> playSound(String soundName) async {
    await init();

    // Alterner entre les players pour permettre overlapping
    final player = _currentSfxPlayer == 0 ? _sfxPlayer1 : _sfxPlayer2;
    _currentSfxPlayer = (_currentSfxPlayer + 1) % 2;

    await player.setVolume(_sfxVolume);

    // Mapper les noms de sons aux fichiers
    String soundFile;
    switch (soundName) {
      case 'splat':
      case 'boom':
      case 'explosion':
        // Utiliser combo.mp3 comme son d'explosion (en attendant un vrai son)
        soundFile = 'sounds/combo.mp3';
        break;
      case 'place':
        soundFile = 'sounds/place.mp4';
        break;
      case 'combo':
        soundFile = 'sounds/combo.mp3';
        break;
      default:
        soundFile = 'sounds/combo.mp3';
    }

    await player.play(AssetSource(soundFile));
  }

  /// Jouer le son d'explosion de Jelly Bomb
  Future<void> playJellyBombExplosion() async {
    await playSound('boom');
  }

  /// Libérer les ressources
  Future<void> dispose() async {
    await _introPlayer.dispose();
    await _gamePlayer.dispose();
    await _sfxPlayer1.dispose();
    await _sfxPlayer2.dispose();
    _isInitialized = false;
  }

  bool get isIntroPlaying => _isIntroPlaying;
  bool get isGamePlaying => _isGamePlaying;
}

/// Instance globale du service audio
final audioService = AudioService();

import 'dart:math' as Math;
import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/game_state.dart';
import '../../models/piece.dart';
import '../../models/pieces_catalog.dart';
import '../../services/stats_service.dart';
import '../../services/supabase_service.dart';
import '../../services/audio_service.dart';
import '../../services/screen_shake_service.dart';
import '../../services/duel_service.dart';
import '../../logic/seeded_piece_generator.dart';
import '../widgets/cell_widget.dart';
import '../widgets/piece_widget.dart';
import '../widgets/particle_effect.dart';
import '../widgets/block_widget.dart';
import '../widgets/jelly_bomb_widget.dart';
import '../widgets/candy_ui.dart';
import '../widgets/sugar_rush_widget.dart';
import 'profile_screen.dart';

class GameScreen extends StatefulWidget {
  final int? duelSeed;  // Si fourni, active le mode duel
  final String? duelId; // ID du duel pour soumettre le score

  const GameScreen({
    super.key,
    this.duelSeed,
    this.duelId,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late GameState _gameState;
  List<Piece?> _availablePieces = [];
  final GlobalKey _gridKey = GlobalKey();
  double _cellSize = 0;

  // Mode duel
  bool _isDuelMode = false;
  SeededPieceGenerator? _pieceGenerator;
  String? _duelId;

  // Résultat du duel (après soumission du score)
  int? _opponentScore;
  String? _opponentName;
  String? _opponentPhotoUrl;
  bool? _isDuelWinner; // true = gagné, false = perdu, null = égalité ou pas encore joué

  // Profil utilisateur
  String _userName = 'Joueur';
  String? _userAvatarPath;
  String? _googlePhotoUrl; // Photo de profil Google
  int _highScore = 0;

  // Audio - lecteurs séparés pour éviter les coupures (sons uniquement)
  final AudioPlayer _placePlayer = AudioPlayer();
  final AudioPlayer _comboPlayer = AudioPlayer();
  // La musique est gérée par audioService global

  // Pour l'aperçu (ghost)
  Piece? _draggingPiece;
  int _draggingIndex = -1;
  int? _previewX;
  int? _previewY;
  bool _canPlacePreview = false;

  // Aperçu des lignes qui seront complétées
  List<int> _previewCompletedRows = [];
  List<int> _previewCompletedColumns = [];

  // Position de la pièce flottante (au-dessus du doigt)
  Offset? _floatingPiecePosition;

  // Pour l'animation de placement
  Set<String> _animatingCells = {};
  AnimationController? _placeAnimController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _glowAnimation;

  // Pour les particules
  List<_ParticleData> _activeParticles = [];
  int _particleIdCounter = 0;

  // Pour l'animation de suppression de lignes
  Set<String> _clearingCells = {};
  AnimationController? _clearAnimController;
  Animation<double>? _clearScaleAnimation;
  Animation<double>? _clearFlashAnimation;
  List<Color> _clearingColors = [];
  List<int> _clearingRows = [];    // Lignes en cours d'effacement
  List<int> _clearingColumns = []; // Colonnes en cours d'effacement
  Color? _lastPlacedPieceColor;    // Couleur de la dernière pièce posée (pour l'animation)

  // Pour garder la couleur entre le placement et l'animation de suppression
  List<int> _pendingClearRows = [];
  List<int> _pendingClearColumns = [];

  // Blocs qui tombent (overlay)
  List<_FallingBlock> _fallingBlocks = [];

  // Pour le système de combo
  int _comboCount = 0;
  AnimationController? _comboAnimController;
  Animation<double>? _comboScaleAnimation;
  Animation<double>? _comboOpacityAnimation;

  // Game Over
  bool _isGameOver = false;

  // Temps de jeu
  DateTime? _sessionStartTime;
  int _sessionLinesCleared = 0;

  // Combo image animation
  bool _showComboImage = false;
  int _currentComboLevel = 1;
  AnimationController? _comboImageController;

  // Jelly Bomb system
  final Math.Random _jellyBombRandom = Math.Random();
  static const double _jellyBombSpawnChance = 0.25; // 25% de chance par pièce placée
  List<_JellyBombExplosion> _activeJellyBombExplosions = [];
  int _jellyBombExplosionIdCounter = 0;
  Set<String> _explodingJellyBombs = {}; // Positions des bombes en cours d'explosion
  bool _processingChainReaction = false;

  // Scores flottants
  List<_FloatingScore> _floatingScores = [];
  int _floatingScoreIdCounter = 0;

  // Sugar Rush system
  double _sugarRushProgress = 0.0; // 0.0 à 1.0
  bool _isSugarRushActive = false;
  double _sugarRushRemainingTime = 0.0;
  static const double _sugarRushDuration = 10.0; // 10 secondes
  static const int _sugarRushMultiplier = 5; // x5 pendant Sugar Rush
  DateTime? _lastActionTime; // Pour la décroissance
  bool _showSugarRushOverlay = false;
  int _sugarRushOverlayId = 0; // ID unique pour chaque overlay
  DateTime? _lastSugarRushEnd; // Cooldown entre Sugar Rush

  // Particules d'énergie vers la jauge
  List<_EnergyParticle> _energyParticles = [];
  int _energyParticleIdCounter = 0;
  final GlobalKey _sugarGaugeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialiser le mode duel si un seed est fourni
    if (widget.duelSeed != null) {
      _isDuelMode = true;
      _duelId = widget.duelId;
      _pieceGenerator = SeededPieceGenerator(widget.duelSeed!);
    }

    _gameState = GameState.initial();
    _generateNewPieces();
    _setupAnimations();
    _loadUserData();
    _initStats();
    _startBackgroundMusic();
    _lastActionTime = DateTime.now();
    // Démarrer le timer de décroissance Sugar Rush
    _handleSugarRushDecay();
  }

  Future<void> _initStats() async {
    await statsService.init();
    _sessionStartTime = DateTime.now();
    _sessionLinesCleared = 0;

    // Vérifier si l'utilisateur est connecté avec Google
    await supabaseService.checkSession();

    // Si connecté avec Google, utiliser le nom et la photo Google
    if (supabaseService.isLoggedIn && supabaseService.userName != null) {
      setState(() {
        _userName = supabaseService.userName!;
        _googlePhotoUrl = supabaseService.userAvatar;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', _userName);
    }

    // Enregistrer/récupérer le joueur dans Supabase
    await supabaseService.getOrCreatePlayer(_userName);
    // Charger les stats depuis le cloud
    await statsService.loadFromCloud();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App en arrière-plan - pause la musique
      audioService.pauseAll();
    } else if (state == AppLifecycleState.resumed) {
      // App revenue au premier plan - reprend la musique
      audioService.resumeAll();
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();

    // Si connecté avec Google, utiliser le nom du compte Google
    if (supabaseService.isLoggedIn && supabaseService.userName != null) {
      setState(() {
        _userName = supabaseService.userName!;
        _highScore = prefs.getInt('highScore') ?? 0;
      });
      // Sauvegarder le nom Google en local aussi
      await prefs.setString('userName', _userName);
    } else {
      setState(() {
        _userName = prefs.getString('userName') ?? 'Joueur';
        _highScore = prefs.getInt('highScore') ?? 0;
      });
    }
  }

  Future<void> _saveHighScore() async {
    if (_score > _highScore) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('highScore', _score);
      setState(() {
        _highScore = _score;
      });
    }
  }

  Future<void> _saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
    // Sync avec Supabase
    await supabaseService.updateUsername(name);
  }

  void _openProfilePage() async {
    // Sauvegarder le temps de jeu actuel avant d'ouvrir le profil
    if (_sessionStartTime != null) {
      final playTime = DateTime.now().difference(_sessionStartTime!).inSeconds;
      await statsService.addPlayTime(playTime);
      _sessionStartTime = DateTime.now(); // Reset pour la suite
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    );

    // Recharger le nom au retour
    _loadUserData();
  }

  void _playPlaceSound() {
    _placePlayer.play(AssetSource('sounds/place.mp4'));
  }

  void _playComboSound() {
    _comboPlayer.play(AssetSource('sounds/combo.mp3'));
  }

  void _startBackgroundMusic() {
    // Utiliser le service audio global pour passer à la musique de jeu
    audioService.playGameMusic();
  }

  void _setupAnimations() {
    // Animation de placement
    _placeAnimController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.15), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _placeAnimController!,
      curve: Curves.easeOut,
    ));

    _glowAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 70),
    ]).animate(CurvedAnimation(
      parent: _placeAnimController!,
      curve: Curves.easeOut,
    ));

    _placeAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _animatingCells.clear();
        });
        // Vérifier les lignes après l'animation de placement
        _checkAndClearLines();
        // Vérifier game over après un court délai si pas de lignes à effacer
        if (_clearingCells.isEmpty) {
          // Pas de lignes à effacer, nettoyer les pending
          setState(() {
            _pendingClearRows.clear();
            _pendingClearColumns.clear();
            _lastPlacedPieceColor = null;
          });
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && !_isGameOver) {
              _checkGameOver();
            }
          });
        }
      }
    });

    // Animation de suppression de lignes - cascade très visible
    _clearAnimController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Animation simple de 0 à 1 - le timing par cellule sera calculé dynamiquement
    _clearFlashAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _clearAnimController!, curve: Curves.easeInOut),
    );

    _clearScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _clearAnimController!, curve: Curves.easeInOut),
    );

    _clearAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finishClearingLines();
        // Vérifier game over après un court délai
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && !_isGameOver) {
            _checkGameOver();
          }
        });
      }
    });

    // Animation du texte combo
    _comboAnimController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _comboScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.5), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(
      parent: _comboAnimController!,
      curve: Curves.easeOut,
    ));

    _comboOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(
      parent: _comboAnimController!,
      curve: Curves.easeOut,
    ));

    // Animation de l'image combo
    _comboImageController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _comboImageController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _showComboImage = false;
        });
      }
    });
  }

  // Obtenir l'image combo selon le niveau
  String _getComboImage() {
    if (_currentComboLevel >= 3) return 'assets/ui/ComboX3.png';
    if (_currentComboLevel == 2) return 'assets/ui/ComboX2.png';
    return 'assets/ui/ComboX1.png';
  }

  // Durée de l'animation selon le niveau
  Duration _getComboDuration() {
    if (_currentComboLevel >= 3) return const Duration(milliseconds: 2000);
    if (_currentComboLevel == 2) return const Duration(milliseconds: 1700);
    return const Duration(milliseconds: 1400);
  }

  void _checkAndClearLines() {
    final linesToClear = <int>[];
    final columnsToClear = <int>[];

    // Vérifier les lignes horizontales
    for (int y = 0; y < GameState.gridSize; y++) {
      bool fullLine = true;
      for (int x = 0; x < GameState.gridSize; x++) {
        if (!_gameState.grid[y][x].occupied) {
          fullLine = false;
          break;
        }
      }
      if (fullLine) {
        linesToClear.add(y);
      }
    }

    // Vérifier les colonnes verticales
    for (int x = 0; x < GameState.gridSize; x++) {
      bool fullColumn = true;
      for (int y = 0; y < GameState.gridSize; y++) {
        if (!_gameState.grid[y][x].occupied) {
          fullColumn = false;
          break;
        }
      }
      if (fullColumn) {
        columnsToClear.add(x);
      }
    }

    if (linesToClear.isEmpty && columnsToClear.isEmpty) return;

    // Détecter les Jelly Bombs dans les lignes/colonnes à effacer
    final jellyBombsToExplode = <Point<int>>[];
    for (final y in linesToClear) {
      for (int x = 0; x < GameState.gridSize; x++) {
        if (_gameState.grid[y][x].isJellyBomb) {
          jellyBombsToExplode.add(Point(x, y));
        }
      }
    }
    for (final x in columnsToClear) {
      for (int y = 0; y < GameState.gridSize; y++) {
        final cell = _gameState.grid[y][x];
        if (cell.isJellyBomb && !jellyBombsToExplode.any((p) => p.x == x && p.y == y)) {
          jellyBombsToExplode.add(Point(x, y));
        }
      }
    }

    // Calculer le combo (nombre de lignes + colonnes)
    _comboCount = linesToClear.length + columnsToClear.length;

    // Marquer les cellules à effacer et créer les blocs qui tombent
    setState(() {
      _clearingCells.clear();
      _clearingColors.clear();
      _fallingBlocks.clear();
      _clearingRows = List.from(linesToClear);
      _clearingColumns = List.from(columnsToClear);

      for (final y in linesToClear) {
        for (int x = 0; x < GameState.gridSize; x++) {
          _clearingCells.add('$x,$y');
          final color = _gameState.grid[y][x].color;
          if (color != null) {
            if (!_clearingColors.contains(color)) {
              _clearingColors.add(color);
            }
            // Créer un bloc qui tombe avec délai cascade
            _fallingBlocks.add(_FallingBlock(
              x: x,
              y: y,
              color: color,
              delay: x / (GameState.gridSize * 2.0),
            ));
          }
        }
      }

      for (final x in columnsToClear) {
        for (int y = 0; y < GameState.gridSize; y++) {
          final cellKey = '$x,$y';
          if (!_clearingCells.contains(cellKey)) {
            _clearingCells.add(cellKey);
            final color = _gameState.grid[y][x].color;
            if (color != null) {
              if (!_clearingColors.contains(color)) {
                _clearingColors.add(color);
              }
              // Créer un bloc qui tombe avec délai cascade
              _fallingBlocks.add(_FallingBlock(
                x: x,
                y: y,
                color: color,
                delay: y / (GameState.gridSize * 2.0),
              ));
            }
          }
        }
      }

    });

    // Ajouter des particules pour chaque cellule (plus de particules si combo)
    _spawnClearParticles();

    // Jouer le son quand une ligne est complétée
    _playComboSound();

    // Afficher l'image combo avec animation (DÉSACTIVÉ TEMPORAIREMENT)
    setState(() {
      // _showComboImage = true;  // Désactivé
      _currentComboLevel = _comboCount.clamp(1, 3);
    });
    // _comboImageController!.duration = _getComboDuration();
    // _comboImageController!.forward(from: 0.0);

    // Nettoyer les pending (maintenant gérés par clearing)
    _pendingClearRows.clear();
    _pendingClearColumns.clear();

    // Lancer l'animation
    _clearAnimController!.forward(from: 0.0);

    // Déclencher les explosions de Jelly Bombs après un court délai
    if (jellyBombsToExplode.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _triggerJellyBombExplosions(jellyBombsToExplode);
        }
      });
    }
  }

  /// Déclenche les explosions de Jelly Bombs
  void _triggerJellyBombExplosions(List<Point<int>> bombs) async {
    if (bombs.isEmpty) return;

    // Jouer le son d'explosion
    audioService.playJellyBombExplosion();

    // Déclencher le screen shake traumatique
    screenShakeService.traumaticShake();

    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    Offset? gridGlobalPosition;
    if (gridBox != null) {
      gridGlobalPosition = gridBox.localToGlobal(Offset.zero);
    }

    // Collecter toutes les cellules dans le rayon 3x3 de chaque bombe
    final cellsToDestroy = <String>{};
    final newJellyBombs = <Point<int>>[];

    for (final bomb in bombs) {
      final bombKey = '${bomb.x},${bomb.y}';
      if (_explodingJellyBombs.contains(bombKey)) continue;
      _explodingJellyBombs.add(bombKey);

      // Ajouter l'explosion visuelle
      if (gridGlobalPosition != null && _cellSize > 0) {
        final explosionX = gridGlobalPosition.dx + (bomb.x + 0.5) * _cellSize;
        final explosionY = gridGlobalPosition.dy + (bomb.y + 0.5) * _cellSize;
        final bombColor = _gameState.grid[bomb.y][bomb.x].color ?? Colors.orange;

        setState(() {
          _activeJellyBombExplosions.add(_JellyBombExplosion(
            id: _jellyBombExplosionIdCounter++,
            position: Offset(explosionX, explosionY),
            color: bombColor,
          ));
        });
      }

      // Détruire les blocs dans un rayon 3x3
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final nx = bomb.x + dx;
          final ny = bomb.y + dy;

          if (nx >= 0 && nx < GameState.gridSize &&
              ny >= 0 && ny < GameState.gridSize) {
            final cell = _gameState.grid[ny][nx];
            if (cell.occupied) {
              cellsToDestroy.add('$nx,$ny');

              // Vérifier si c'est une autre Jelly Bomb (réaction en chaîne)
              if (cell.isJellyBomb && !_explodingJellyBombs.contains('$nx,$ny')) {
                newJellyBombs.add(Point(nx, ny));
              }
            }
          }
        }
      }
    }

    // Détruire les cellules et ajouter des particules
    setState(() {
      for (final cellKey in cellsToDestroy) {
        final parts = cellKey.split(',');
        final x = int.parse(parts[0]);
        final y = int.parse(parts[1]);

        final cell = _gameState.grid[y][x];
        if (cell.occupied && gridGlobalPosition != null && _cellSize > 0) {
          // Ajouter des particules
          final particleX = gridGlobalPosition.dx + (x + 0.5) * _cellSize;
          final particleY = gridGlobalPosition.dy + (y + 0.5) * _cellSize;
          _activeParticles.add(_ParticleData(
            id: _particleIdCounter++,
            position: Offset(particleX, particleY),
            color: cell.color ?? Colors.white,
          ));
        }

        // Effacer la cellule
        _gameState = _gameState.setCellAt(x, y, Cell.empty);
      }
    });

    // Bonus de score pour les explosions (avec multiplicateur Sugar Rush)
    final sugarRushMult = _isSugarRushActive ? _sugarRushMultiplier : 1;
    final explosionScore = cellsToDestroy.length * 15 * sugarRushMult;

    // Bonus Sugar Rush: +25% de la jauge par Jelly Bomb
    if (!_isSugarRushActive) {
      _addSugarRushProgress(0.25);
    }

    // Marquer le temps de la dernière action
    _lastActionTime = DateTime.now();

    setState(() {
      _score += explosionScore;
    });

    // Réaction en chaîne après un délai
    if (newJellyBombs.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          _triggerJellyBombExplosions(newJellyBombs);
        }
      });
    } else {
      // Fin des explosions, nettoyer
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _explodingJellyBombs.clear();
          });
          // Vérifier game over
          _checkGameOver();
        }
      });
    }
  }

  void _removeJellyBombExplosion(int id) {
    setState(() {
      _activeJellyBombExplosions.removeWhere((e) => e.id == id);
    });
  }

  // ============ SUGAR RUSH SYSTEM ============

  /// Ajoute de la progression à la jauge Sugar Rush (avec lerp automatique)
  void _addSugarRushProgress(double amount) {
    // Cooldown de 3 secondes après la fin d'un Sugar Rush
    if (_lastSugarRushEnd != null) {
      final cooldown = DateTime.now().difference(_lastSugarRushEnd!).inSeconds;
      if (cooldown < 3) return;
    }

    setState(() {
      _sugarRushProgress = (_sugarRushProgress + amount).clamp(0.0, 1.0);
    });

    // Vérifier si on atteint 100%
    if (_sugarRushProgress >= 1.0 && !_isSugarRushActive) {
      _activateSugarRush();
    }
  }

  /// Active le mode Sugar Rush
  void _activateSugarRush() {
    // Empêcher la double activation
    if (_showSugarRushOverlay || _isSugarRushActive) return;

    _sugarRushOverlayId++;
    setState(() {
      _isSugarRushActive = true;
      _sugarRushRemainingTime = _sugarRushDuration;
      _showSugarRushOverlay = true;
    });

    // Jouer la musique accélérée (si disponible)
    // audioService.playFeverMusic();

    // Lancer le timer de Sugar Rush
    _startSugarRushTimer();
  }

  /// Timer pour le compte à rebours et la décroissance
  void _startSugarRushTimer() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;

      if (_isSugarRushActive) {
        setState(() {
          _sugarRushRemainingTime -= 0.1;

          if (_sugarRushRemainingTime <= 0) {
            // Fin du Sugar Rush
            _isSugarRushActive = false;
            _sugarRushProgress = 0.0;
            _sugarRushRemainingTime = 0.0;
            _lastSugarRushEnd = DateTime.now();
            // Revenir à la musique normale
            // audioService.playGameMusic();
          } else {
            // Continuer le timer
            _startSugarRushTimer();
          }
        });
      } else {
        // Mode inactif: décroissance de la jauge si pas d'action récente
        _handleSugarRushDecay();
      }
    });
  }

  /// Gère la décroissance de la jauge quand inactif
  void _handleSugarRushDecay() {
    if (_isSugarRushActive || _sugarRushProgress <= 0) return;

    final now = DateTime.now();
    final lastAction = _lastActionTime ?? now;
    final inactiveSeconds = now.difference(lastAction).inSeconds;

    // Décroissance après 2 secondes d'inactivité
    if (inactiveSeconds >= 2 && _sugarRushProgress > 0) {
      setState(() {
        // Décroissance lente: 5% par seconde
        _sugarRushProgress = (_sugarRushProgress - 0.005).clamp(0.0, 1.0);
      });
    }

    // Continuer à vérifier
    if (_sugarRushProgress > 0) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _handleSugarRushDecay();
      });
    }
  }

  /// Appelé quand l'overlay Sugar Rush est terminé
  void _onSugarRushOverlayComplete() {
    setState(() {
      _showSugarRushOverlay = false;
    });
  }

  /// Crée des particules d'énergie qui volent vers la jauge Sugar Rush
  void _spawnEnergyParticlesToGauge(List<String> cellKeys, Color color) {
    if (_isSugarRushActive) return; // Pas besoin si déjà actif

    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    final gaugeBox = _sugarGaugeKey.currentContext?.findRenderObject() as RenderBox?;

    if (gridBox == null || gaugeBox == null) return;

    final gridGlobalPosition = gridBox.localToGlobal(Offset.zero);
    final gaugeGlobalPosition = gaugeBox.localToGlobal(Offset.zero);
    final gaugeSize = gaugeBox.size;

    // Position cible: centre-droite de la jauge (où l'étoile arrive)
    final targetX = gaugeGlobalPosition.dx + gaugeSize.width * 0.5;
    final targetY = gaugeGlobalPosition.dy + gaugeSize.height * 0.5;

    // Créer beaucoup de particules quasi continues depuis les cellules effacées
    int particleCount = 0;
    for (final cellKey in cellKeys) {
      if (particleCount >= 12) break; // Max 12 particules par clear

      final parts = cellKey.split(',');
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);

      final startX = gridGlobalPosition.dx + (x + 0.5) * _cellSize;
      final startY = gridGlobalPosition.dy + (y + 0.5) * _cellSize;

      // Délai très court entre particules (quasi continu)
      Future.delayed(Duration(milliseconds: particleCount * 25), () {
        if (!mounted) return;
        setState(() {
          _energyParticles.add(_EnergyParticle(
            id: _energyParticleIdCounter++,
            startPosition: Offset(startX, startY),
            endPosition: Offset(targetX, targetY),
            color: color,
          ));
        });
      });

      particleCount++;
    }
  }

  /// Supprime une particule d'énergie terminée
  void _removeEnergyParticle(int id) {
    setState(() {
      _energyParticles.removeWhere((p) => p.id == id);
    });
  }

  String _getComboText(int combo) {
    switch (combo) {
      case 2:
        return 'DOUBLE!';
      case 3:
        return 'TRIPLE!';
      case 4:
        return 'QUAD!';
      case 5:
        return 'PENTA!';
      default:
        if (combo > 5) return 'MEGA x$combo!';
        return '';
    }
  }

  void _spawnClearParticles() {
    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox == null) return;

    final gridGlobalPosition = gridBox.localToGlobal(Offset.zero);

    // 1 particule par cellule - simple et clean
    int cellIndex = 0;
    for (final cellKey in _clearingCells) {
      final parts = cellKey.split(',');
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);
      final color = _gameState.grid[y][x].color ?? Colors.white;

      final particleX = gridGlobalPosition.dx + (x + 0.5) * _cellSize;
      final particleY = gridGlobalPosition.dy + (y + 0.5) * _cellSize;

      _activeParticles.add(_ParticleData(
        id: _particleIdCounter++,
        position: Offset(particleX, particleY),
        color: _comboCount >= 3 ? _getRainbowColor(cellIndex) : color,
      ));

      cellIndex++;
    }
    setState(() {});
  }

  Color _getRainbowColor(int index) {
    final colors = [
      const Color(0xFFFF0000), // Rouge
      const Color(0xFFFF8C00), // Orange
      const Color(0xFFFFD700), // Jaune
      const Color(0xFF32CD32), // Vert
      const Color(0xFF00CED1), // Cyan
      const Color(0xFF4169E1), // Bleu
      const Color(0xFF9932CC), // Violet
      const Color(0xFFFF69B4), // Rose
    ];
    return colors[index % colors.length];
  }

  void _finishClearingLines() {
    // Calculer le score avec bonus combo
    final baseScore = _clearingCells.length * 10;
    final comboMultiplier = _comboCount >= 2 ? (_comboCount * 0.5 + 0.5) : 1.0;
    // Appliquer le multiplicateur Sugar Rush si actif
    final sugarRushMult = _isSugarRushActive ? _sugarRushMultiplier : 1;
    final earnedScore = (baseScore * comboMultiplier * sugarRushMult).round();

    // Créer le score flottant au centre des cellules effacées
    _createFloatingScore(earnedScore);

    // Tracker les stats
    final linesCleared = _clearingRows.length + _clearingColumns.length;
    _sessionLinesCleared += linesCleared;
    statsService.addLinesCleared(linesCleared);
    statsService.updateBestCombo(_comboCount);

    // Remplir la jauge Sugar Rush (si pas déjà actif)
    if (!_isSugarRushActive) {
      // Chaque ligne = 8% de la jauge
      final progressGain = linesCleared * 0.08;
      _addSugarRushProgress(progressGain);

      // Lancer des particules d'énergie vers la jauge
      final particleColor = _lastPlacedPieceColor ?? Colors.orange;
      _spawnEnergyParticlesToGauge(_clearingCells.toList(), particleColor);
    }

    // Marquer le temps de la dernière action
    _lastActionTime = DateTime.now();

    setState(() {
      _score += earnedScore;

      // Effacer les cellules de la grille
      for (final cellKey in _clearingCells) {
        final parts = cellKey.split(',');
        final x = int.parse(parts[0]);
        final y = int.parse(parts[1]);
        _gameState = _gameState.setCellAt(x, y, Cell.empty);
      }
      _clearingCells.clear();
      _clearingColors.clear();
      _clearingRows.clear();
      _clearingColumns.clear();
      _fallingBlocks.clear();
      _comboCount = 0;
      _lastPlacedPieceColor = null;
    });
  }

  void _createFloatingScore(int score) {
    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox == null || _clearingCells.isEmpty) return;

    final gridGlobalPosition = gridBox.localToGlobal(Offset.zero);

    // Calculer le centre des cellules effacées
    double sumX = 0, sumY = 0;
    for (final cellKey in _clearingCells) {
      final parts = cellKey.split(',');
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);
      sumX += x;
      sumY += y;
    }
    final centerX = gridGlobalPosition.dx + (sumX / _clearingCells.length + 0.5) * _cellSize;
    final centerY = gridGlobalPosition.dy + (sumY / _clearingCells.length + 0.5) * _cellSize;

    _floatingScores.add(_FloatingScore(
      id: _floatingScoreIdCounter++,
      score: score,
      startPosition: Offset(centerX, centerY),
      color: _comboCount >= 2 ? const Color(0xFFFFD700) : Colors.white,
      isCombo: _comboCount >= 2,
    ));
  }

  void _removeFloatingScore(int id) {
    setState(() {
      _floatingScores.removeWhere((s) => s.id == id);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _placeAnimController?.dispose();
    _clearAnimController?.dispose();
    _comboAnimController?.dispose();
    _comboImageController?.dispose();
    _placePlayer.dispose();
    _comboPlayer.dispose();
    // Arrêter la musique de jeu et reprendre la musique d'intro
    audioService.stopGameMusic();
    super.dispose();
  }

  void _generateNewPieces() {
    // Utilise la même logique pour normal et duel
    // La différence: en mode duel, on utilise un Random seedé
    _generateNewPiecesRandom();
  }

  /// Génère les pièces (avec ou sans seed selon le mode)
  void _generateNewPiecesRandom() {
    final allPieces = List<Piece>.from(PiecesCatalog.main);

    // En mode duel, utiliser le random seedé pour garantir les mêmes pièces
    if (_isDuelMode && _pieceGenerator != null) {
      _pieceGenerator!.shuffleList(allPieces);
    } else {
      allPieces.shuffle();
    }

    // Compter les cellules vides
    int emptyCells = 0;
    for (int y = 0; y < GameState.gridSize; y++) {
      for (int x = 0; x < GameState.gridSize; x++) {
        if (!_gameState.grid[y][x].occupied) {
          emptyCells++;
        }
      }
    }

    // Si le plateau est presque vide, donner des pièces variées
    if (emptyCells > 50) {
      _availablePieces = [allPieces[0], allPieces[1], allPieces[2]];
      return;
    }

    // Filtrer les pièces jouables
    final playablePieces = <Piece>[];
    for (final piece in allPieces) {
      if (_canPlacePieceAnywhere(piece)) {
        playablePieces.add(piece);
      }
    }

    // S'il n'y a pas assez de pièces jouables, utiliser les pièces random
    if (playablePieces.length < 3) {
      // Ajouter des petites pièces en priorité
      final smallPieces = allPieces.where((p) => p.blocks.length <= 2).toList();
      if (_isDuelMode && _pieceGenerator != null) {
        _pieceGenerator!.shuffleList(smallPieces);
      } else {
        smallPieces.shuffle();
      }
      for (final piece in smallPieces) {
        if (!playablePieces.contains(piece)) {
          playablePieces.add(piece);
          if (playablePieces.length >= 3) break;
        }
      }
    }

    // Mélanger et sélectionner 3 pièces
    if (_isDuelMode && _pieceGenerator != null) {
      _pieceGenerator!.shuffleList(playablePieces);
    } else {
      playablePieces.shuffle();
    }

    _availablePieces = [
      playablePieces.isNotEmpty ? playablePieces[0] : allPieces[0],
      playablePieces.length > 1 ? playablePieces[1] : allPieces[1],
      playablePieces.length > 2 ? playablePieces[2] : allPieces[2],
    ];
  }

  /// Vérifie si une pièce peut être placée quelque part sur le plateau
  bool _canPlacePieceAnywhere(Piece piece) {
    for (int y = 0; y < GameState.gridSize; y++) {
      for (int x = 0; x < GameState.gridSize; x++) {
        if (_canPlacePiece(piece, x, y)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _canPlacePiece(Piece piece, int startX, int startY) {
    for (final block in piece.blocks) {
      final x = startX + block.x;
      final y = startY + block.y;
      if (x < 0 || x >= GameState.gridSize || y < 0 || y >= GameState.gridSize) {
        return false;
      }
      if (_gameState.grid[y][x].occupied) {
        return false;
      }
    }
    return true;
  }

  /// Calcule quelles lignes et colonnes seraient complétées si la pièce est placée
  void _calculatePreviewCompletedLines(Piece piece, int startX, int startY) {
    _previewCompletedRows.clear();
    _previewCompletedColumns.clear();

    if (!_canPlacePiece(piece, startX, startY)) return;

    // Créer une copie virtuelle de la grille avec la pièce placée
    final virtualGrid = List.generate(
      GameState.gridSize,
      (y) => List.generate(GameState.gridSize, (x) => _gameState.grid[y][x].occupied),
    );

    // Placer la pièce virtuellement
    for (final block in piece.blocks) {
      final x = startX + block.x;
      final y = startY + block.y;
      virtualGrid[y][x] = true;
    }

    // Vérifier les lignes horizontales
    for (int y = 0; y < GameState.gridSize; y++) {
      bool fullLine = true;
      for (int x = 0; x < GameState.gridSize; x++) {
        if (!virtualGrid[y][x]) {
          fullLine = false;
          break;
        }
      }
      if (fullLine) {
        _previewCompletedRows.add(y);
      }
    }

    // Vérifier les colonnes verticales
    for (int x = 0; x < GameState.gridSize; x++) {
      bool fullColumn = true;
      for (int y = 0; y < GameState.gridSize; y++) {
        if (!virtualGrid[y][x]) {
          fullColumn = false;
          break;
        }
      }
      if (fullColumn) {
        _previewCompletedColumns.add(x);
      }
    }
  }

  void _placePiece(Piece piece, int startX, int startY, int pieceIndex) {
    if (!_canPlacePiece(piece, startX, startY)) return;

    // Sauvegarder la couleur de la pièce pour l'animation de suppression
    _lastPlacedPieceColor = piece.color;

    // Jouer le son de placement
    _playPlaceSound();

    // Calculer les positions des particules avant de modifier l'état
    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    Offset? gridGlobalPosition;
    if (gridBox != null) {
      gridGlobalPosition = gridBox.localToGlobal(Offset.zero);
    }

    setState(() {
      // Marquer les cellules pour l'animation
      _animatingCells.clear();

      // Déterminer si un bloc de cette pièce deviendra une Jelly Bomb
      int? jellyBombBlockIndex;
      if (piece.blocks.length >= 2 && _jellyBombRandom.nextDouble() < _jellyBombSpawnChance) {
        jellyBombBlockIndex = _jellyBombRandom.nextInt(piece.blocks.length);
      }

      for (int i = 0; i < piece.blocks.length; i++) {
        final block = piece.blocks[i];
        final x = startX + block.x;
        final y = startY + block.y;
        _animatingCells.add('$x,$y');

        // Créer une Jelly Bomb ou un bloc normal
        if (i == jellyBombBlockIndex) {
          _gameState = _gameState.setCellAt(x, y, Cell.jellyBomb(piece.color));
        } else {
          _gameState = _gameState.setCellAt(x, y, Cell.filled(piece.color));
        }

        // Ajouter des particules pour chaque bloc
        if (gridGlobalPosition != null && _cellSize > 0) {
          final particleX = gridGlobalPosition.dx + (x + 0.5) * _cellSize;
          final particleY = gridGlobalPosition.dy + (y + 0.5) * _cellSize;
          _activeParticles.add(_ParticleData(
            id: _particleIdCounter++,
            position: Offset(particleX, particleY),
            color: piece.color,
          ));
        }
      }
      _availablePieces[pieceIndex] = null;

      if (_availablePieces.every((p) => p == null)) {
        _generateNewPieces();
      }

      // Calculer immédiatement quelles lignes seront complétées
      _pendingClearRows.clear();
      _pendingClearColumns.clear();

      // Vérifier les lignes horizontales
      for (int y = 0; y < GameState.gridSize; y++) {
        bool fullLine = true;
        for (int x = 0; x < GameState.gridSize; x++) {
          if (!_gameState.grid[y][x].occupied) {
            fullLine = false;
            break;
          }
        }
        if (fullLine) {
          _pendingClearRows.add(y);
        }
      }

      // Vérifier les colonnes verticales
      for (int x = 0; x < GameState.gridSize; x++) {
        bool fullColumn = true;
        for (int y = 0; y < GameState.gridSize; y++) {
          if (!_gameState.grid[y][x].occupied) {
            fullColumn = false;
            break;
          }
        }
        if (fullColumn) {
          _pendingClearColumns.add(x);
        }
      }
    });

    // Lancer l'animation
    _placeAnimController!.forward(from: 0.0);
  }

  void _removeParticle(int id) {
    setState(() {
      _activeParticles.removeWhere((p) => p.id == id);
    });
  }

  void _updatePreview(Offset globalPosition, Piece piece) {
    if (_draggingPiece == null) return;

    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox == null) return;

    final gridPosition = gridBox.localToGlobal(Offset.zero);

    // Calculer le centre de la pièce (en blocs)
    double minX = 0, maxX = 0, minY = 0, maxY = 0;
    for (final block in piece.blocks) {
      if (block.x < minX) minX = block.x.toDouble();
      if (block.x > maxX) maxX = block.x.toDouble();
      if (block.y < minY) minY = block.y.toDouble();
      if (block.y > maxY) maxY = block.y.toDouble();
    }
    final pieceCenterX = (maxX - minX + 1) / 2 * _cellSize;
    final pieceCenterY = (maxY - minY + 1) / 2 * _cellSize;

    // Décalage constant vers le haut (au-dessus du doigt)
    const double fingerOffsetY = 160.0;

    // Position de la pièce flottante (centrée sur le doigt, décalée vers le haut)
    final floatingX = globalPosition.dx - pieceCenterX;
    final floatingY = globalPosition.dy - fingerOffsetY - pieceCenterY;
    final newFloatingPos = Offset(floatingX, floatingY);

    // Position sur la grille - le ghost apparaît juste sous la pièce flottante
    final gridX = ((floatingX - gridPosition.dx + _cellSize * 0.5) / _cellSize).floor();
    final gridY = ((floatingY - gridPosition.dy + _cellSize * 0.5) / _cellSize).floor();

    // Vérifier si on doit mettre à jour
    final gridChanged = _previewX != gridX || _previewY != gridY;
    final posChanged = _floatingPiecePosition == null ||
        (_floatingPiecePosition!.dx - newFloatingPos.dx).abs() > 1 ||
        (_floatingPiecePosition!.dy - newFloatingPos.dy).abs() > 1;

    if (gridChanged || posChanged) {
      setState(() {
        _floatingPiecePosition = newFloatingPos;

        if (gridX >= 0 && gridX < GameState.gridSize &&
            gridY >= 0 && gridY < GameState.gridSize) {
          _previewX = gridX;
          _previewY = gridY;
          _canPlacePreview = _canPlacePiece(_draggingPiece!, gridX, gridY);

          // Calculer les lignes qui seront complétées
          if (_canPlacePreview) {
            _calculatePreviewCompletedLines(_draggingPiece!, gridX, gridY);
          } else {
            _previewCompletedRows.clear();
            _previewCompletedColumns.clear();
          }
        } else {
          _previewX = null;
          _previewY = null;
          _canPlacePreview = false;
          _previewCompletedRows.clear();
          _previewCompletedColumns.clear();
        }
      });
    }
  }

  void _clearPreview() {
    setState(() {
      _draggingPiece = null;
      _draggingIndex = -1;
      _previewX = null;
      _previewY = null;
      _canPlacePreview = false;
      _floatingPiecePosition = null;
      _previewCompletedRows.clear();
      _previewCompletedColumns.clear();
    });
  }

  int _score = 0;

  @override
  Widget build(BuildContext context) {
    const double borderRatio = 0.02;

    return Scaffold(
      body: ScreenShakeWrapper(
        child: Stack(
          children: [
            // Fond
            Positioned.fill(
              child: Image.asset(
                'assets/bg/bg.png',
                fit: BoxFit.cover,
              ),
            ),

            // Contenu avec positionnement basé sur pourcentages
            SafeArea(
            child: LayoutBuilder(
              builder: (context, safeConstraints) {
                final screenWidth = MediaQuery.of(context).size.width;
                final screenHeight = safeConstraints.maxHeight;

                // === CONFIGURATION LAYOUT (référence 380x680) ===
                // Score Gauche: x=3.2%, y=1.2%, w=39.5%, h=8.8%
                // Score Droit: x=57.4%, y=1.2%, w=39.5%, h=8.8%
                // Jauge: x=23.4%, y=11.6%, w=51.3%, h=6.6%
                // Plateau: x=3.9%, y=19.1%, w=92.1%, h=51.5%
                // Cadre Pièces: x=2.1%, y=70.4%, w=95.5%, h=25.1%

                // Tailles
                final scoreWidth = screenWidth * 0.395;
                final scoreHeight = screenHeight * 0.088;
                final gaugeWidth = screenWidth * 0.513;
                final gaugeHeight = screenHeight * 0.066;
                final boardSize = screenWidth * 0.921;
                final piecesFrameWidth = screenWidth * 0.955;
                final piecesFrameHeight = screenHeight * 0.251;

                // Positions X
                final scoreLeftX = screenWidth * 0.032;
                final scoreRightX = screenWidth * 0.574;
                final gaugeX = screenWidth * 0.234;
                final boardX = screenWidth * 0.039;
                final piecesX = screenWidth * 0.021;

                // Positions Y
                final scoreY = screenHeight * 0.012;
                final gaugeY = screenHeight * 0.116;
                final boardY = screenHeight * 0.191;
                final piecesY = screenHeight * 0.704;

                return Stack(
                  children: [
                    // Score Gauche
                    Positioned(
                      left: scoreLeftX,
                      top: scoreY,
                      child: CandyScorePanel(
                        label: 'SCORE',
                        value: _score,
                        backgroundImage: 'assets/ui/cerclesscore.png',
                        labelStrokeColor: const Color(0xFFE91E63),
                        valueColor: const Color(0xFFFFD700),
                        valueStrokeColor: const Color(0xFFB8860B),
                        width: scoreWidth,
                        height: scoreHeight,
                      ),
                    ),

                    // Score Droit (Best)
                    Positioned(
                      left: scoreRightX,
                      top: scoreY,
                      child: CandyScorePanel(
                        label: 'BEST',
                        value: _highScore,
                        backgroundImage: 'assets/ui/cerclemeilleurscrore.png',
                        labelStrokeColor: const Color(0xFF7B1FA2),
                        valueColor: const Color(0xFFFFD700),
                        valueStrokeColor: const Color(0xFFB8860B),
                        icon: Icons.emoji_events,
                        width: scoreWidth,
                        height: scoreHeight,
                      ),
                    ),

                    // Jauge Sugar Rush
                    Positioned(
                      left: gaugeX,
                      top: gaugeY,
                      child: SizedBox(
                        width: gaugeWidth,
                        height: gaugeHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            // Jauge pleine largeur (ne bouge jamais)
                            Positioned.fill(
                              child: SugarRushGauge(
                                key: _sugarGaugeKey,
                                progress: _sugarRushProgress,
                                height: gaugeHeight,
                                onFull: () {},
                              ),
                            ),
                            // Timer à gauche (superposé, aligné au centre)
                            if (_isSugarRushActive)
                              Positioned(
                                left: -gaugeHeight * 1.1,
                                top: (gaugeHeight - 38) / 2,
                                child: SugarRushTimer(
                                  remainingSeconds: _sugarRushRemainingTime,
                                  totalSeconds: _sugarRushDuration,
                                ),
                              ),
                            // x5 à droite (superposé, aligné au centre)
                            if (_isSugarRushActive)
                              Positioned(
                                right: -gaugeHeight * 1.1,
                                top: (gaugeHeight - 38) / 2,
                                child: const SugarRushMultiplier(),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Plateau de jeu
                    Positioned(
                      left: boardX,
                      top: boardY,
                      child: Builder(
                        builder: (context) {
                          final frameSize = boardSize;
                          final border = frameSize * borderRatio;
                          final gridSize = frameSize - (border * 2);
                          _cellSize = gridSize / GameState.gridSize;

                          return SizedBox(
                            width: frameSize,
                            height: frameSize,
                            child: Stack(
                              children: [
                                // Grille dans le trou
                                Positioned(
                                  left: border,
                                  top: border,
                                  width: gridSize,
                                  height: gridSize,
                                  child: Container(
                                    key: _gridKey,
                                    child: _buildGridWithPreview(),
                                  ),
                                ),

                                // Blocs qui tombent (overlay animé)
                                AnimatedBuilder(
                                  animation: _clearAnimController!,
                                  builder: (context, child) {
                                    return _buildFallingBlocksOverlay(gridSize, border);
                                  },
                                ),

                                // Cadre par-dessus
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Image.asset(
                                      'assets/ui/board_frame.png',
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // Zone des pièces avec cadre
                    Positioned(
                      left: piecesX,
                      top: piecesY,
                      child: SizedBox(
                        width: piecesFrameWidth,
                        height: piecesFrameHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Fond sombre derrière les pièces (entre le bg et le cadre)
                            Positioned(
                              left: piecesFrameWidth * 0.05,
                              right: piecesFrameWidth * 0.05,
                              top: piecesFrameHeight * 0.08,
                              bottom: piecesFrameHeight * 0.08,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            // Cadre décoratif
                            Positioned.fill(
                              child: Image.asset(
                                'assets/ui/cadrebloqueenbas.png',
                                fit: BoxFit.fill,
                              ),
                            ),
                            // Pièces à l'intérieur - 3 zones sans clipping
                            Positioned.fill(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: piecesFrameWidth * 0.10,
                                  right: piecesFrameWidth * 0.10,
                                  top: piecesFrameHeight * 0.12,
                                  bottom: piecesFrameHeight * 0.08,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: List.generate(3, (index) {
                                    return Expanded(
                                      child: UnconstrainedBox(
                                        clipBehavior: Clip.none,
                                        child: _availablePieces[index] != null
                                            ? _buildDraggablePiece(_availablePieces[index]!, index)
                                            : const SizedBox(width: 70, height: 70),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Pièce flottante au-dessus du doigt
          if (_draggingPiece != null && _floatingPiecePosition != null)
            Positioned(
              left: _floatingPiecePosition!.dx,
              top: _floatingPiecePosition!.dy,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: PieceWidget(
                    piece: _draggingPiece!,
                    blockSize: _cellSize,
                  ),
                ),
              ),
            ),

          // Particules (au-dessus de tout)
          ..._activeParticles.map((data) => Positioned.fill(
            child: IgnorePointer(
              child: ParticleEffect(
                key: ValueKey(data.id),
                position: data.position,
                color: data.color,
                onComplete: () => _removeParticle(data.id),
              ),
            ),
          )),

          // Scores flottants
          ..._floatingScores.map((data) => _FloatingScoreWidget(
            key: ValueKey('score_${data.id}'),
            data: data,
            onComplete: () => _removeFloatingScore(data.id),
          )),

          // Image Combo animée
          if (_showComboImage)
            AnimatedBuilder(
              animation: _comboImageController!,
              builder: (context, child) {
                final progress = _comboImageController!.value;

                // Animations différentes selon le niveau de combo
                double scale;
                double opacity;
                double rotation;
                double translateY;

                if (_currentComboLevel == 1) {
                  // Combo X1 : Simple zoom avec léger rebond
                  if (progress < 0.3) {
                    scale = Curves.elasticOut.transform(progress / 0.3) * 1.2;
                  } else if (progress < 0.7) {
                    scale = 1.2 - 0.2 * ((progress - 0.3) / 0.4);
                  } else {
                    scale = 1.0 * (1 - ((progress - 0.7) / 0.3));
                  }
                  opacity = progress < 0.15 ? progress / 0.15 : (progress > 0.7 ? 1 - ((progress - 0.7) / 0.3) : 1.0);
                  rotation = 0;
                  translateY = 0;
                } else if (_currentComboLevel == 2) {
                  // Combo X2 : Zoom + rotation oscillante
                  if (progress < 0.25) {
                    scale = Curves.elasticOut.transform(progress / 0.25) * 1.4;
                  } else if (progress < 0.65) {
                    scale = 1.4 - 0.3 * ((progress - 0.25) / 0.4);
                  } else {
                    scale = 1.1 * (1 - ((progress - 0.65) / 0.35));
                  }
                  opacity = progress < 0.1 ? progress / 0.1 : (progress > 0.65 ? 1 - ((progress - 0.65) / 0.35) : 1.0);
                  rotation = 0.15 * (1 - progress) * (progress < 0.5 ? 1 : -1) * (progress * 10 % 2 < 1 ? 1 : -1);
                  translateY = -20 * (1 - progress);
                } else {
                  // Combo X3 : Gros zoom + shake + montée
                  if (progress < 0.2) {
                    scale = Curves.elasticOut.transform(progress / 0.2) * 1.6;
                  } else if (progress < 0.6) {
                    scale = 1.6 - 0.4 * ((progress - 0.2) / 0.4);
                  } else {
                    scale = 1.2 * (1 - ((progress - 0.6) / 0.4));
                  }
                  opacity = progress < 0.08 ? progress / 0.08 : (progress > 0.6 ? 1 - ((progress - 0.6) / 0.4) : 1.0);
                  // Shake effect
                  final shake = (progress * 30).floor() % 2 == 0 ? 1.0 : -1.0;
                  rotation = 0.1 * shake * (1 - progress);
                  translateY = -50 * progress;
                }

                if (opacity <= 0 || scale <= 0) return const SizedBox.shrink();

                return Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(0, translateY),
                        child: Transform.rotate(
                          angle: rotation,
                          child: Transform.scale(
                            scale: scale.clamp(0.0, 2.0),
                            child: Opacity(
                              opacity: opacity.clamp(0.0, 1.0),
                              child: Image.asset(
                                _getComboImage(),
                                width: 280,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          // Explosions de Jelly Bomb
          ..._activeJellyBombExplosions.map((data) => Positioned.fill(
            child: IgnorePointer(
              child: JellyBombExplosionEffect(
                key: ValueKey('jelly_explosion_${data.id}'),
                position: data.position,
                color: data.color,
                cellSize: _cellSize,
                onComplete: () => _removeJellyBombExplosion(data.id),
              ),
            ),
          )),

          // Particules d'énergie vers la jauge Sugar Rush
          ..._energyParticles.map((data) => SugarRushEnergyParticle(
            key: ValueKey('energy_${data.id}'),
            startPosition: data.startPosition,
            endPosition: data.endPosition,
            color: data.color,
            size: 16,
            onComplete: () => _removeEnergyParticle(data.id),
          )),

          // Overlay Sugar Rush
          if (_showSugarRushOverlay)
            Positioned.fill(
              key: ValueKey('sugar_overlay_$_sugarRushOverlayId'),
              child: SugarRushOverlay(
                onComplete: _onSugarRushOverlayComplete,
              ),
            ),

          // Écran Game Over
          if (_isGameOver)
            Positioned.fill(
              child: _buildGameOverScreen(),
            ),
        ],
        ),
      ),
    );
  }

  Widget _buildDraggablePiece(Piece piece, int index) {
    // Calculer la taille des blocs pour que la pièce tienne dans son slot
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final slotWidth = screenWidth * 0.955 * 0.80 / 3;
    final slotHeight = screenHeight * 0.251 * 0.65; // Hauteur dispo dans le cadre

    final pieceWidth = piece.blocks.map((b) => b.x).reduce((a, b) => a > b ? a : b) + 1;
    final pieceHeight = piece.blocks.map((b) => b.y).reduce((a, b) => a > b ? a : b) + 1;

    final blockByWidth = (slotWidth - 16) / (pieceWidth > 3 ? pieceWidth : 3);
    final blockByHeight = (slotHeight - 16) / (pieceHeight > 3 ? pieceHeight : 3);
    final clampedBlockSize = blockByWidth < blockByHeight
        ? blockByWidth.clamp(14.0, 22.0)
        : blockByHeight.clamp(14.0, 22.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        setState(() {
          _draggingPiece = piece;
          _draggingIndex = index;
        });
        _updatePreview(details.globalPosition, piece);
      },
      onPanUpdate: (details) {
        _updatePreview(details.globalPosition, piece);
      },
      onPanEnd: (details) {
        if (_previewX != null && _previewY != null && _canPlacePreview) {
          _placePiece(piece, _previewX!, _previewY!, index);
        }
        _clearPreview();
      },
      onPanCancel: () {
        _clearPreview();
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Opacity(
          opacity: _draggingIndex == index ? 0.3 : 1.0,
          child: PieceWidget(piece: piece, blockSize: clampedBlockSize),
        ),
      ),
    );
  }

  Widget _buildGridWithPreview() {
    return AnimatedBuilder(
      animation: Listenable.merge([_placeAnimController!, _clearAnimController!]),
      builder: (context, child) {
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: GameState.gridSize,
            childAspectRatio: 1.0,
          ),
          itemCount: GameState.gridSize * GameState.gridSize,
          itemBuilder: (context, index) {
            final x = index % GameState.gridSize;
            final y = index ~/ GameState.gridSize;
            final cell = _gameState.grid[y][x];
            final cellKey = '$x,$y';
            final isAnimating = _animatingCells.contains(cellKey);
            final isClearing = _clearingCells.contains(cellKey);

            // Vérifier si cette cellule fait partie de l'aperçu
            bool isPreview = false;
            if (_draggingPiece != null && _previewX != null && _previewY != null) {
              for (final block in _draggingPiece!.blocks) {
                if (x == _previewX! + block.x && y == _previewY! + block.y) {
                  isPreview = true;
                  break;
                }
              }
            }

            // Vérifier si cette cellule fait partie d'une ligne/colonne qui sera complétée (aperçu pendant drag)
            final isInPreviewCompletedLine = _previewCompletedRows.contains(y) ||
                                              _previewCompletedColumns.contains(x);
            final isPreviewLineCell = isInPreviewCompletedLine && _canPlacePreview && _draggingPiece != null;

            // Vérifier si cette cellule fait partie d'une ligne en attente de suppression (après placement)
            final isInPendingClearLine = _pendingClearRows.contains(y) ||
                                          _pendingClearColumns.contains(x);
            final isPendingClearCell = isInPendingClearLine && _lastPlacedPieceColor != null && !isClearing;

            // Si la cellule est dans une ligne qui va être complétée, utiliser la couleur de la pièce
            Color? displayColor = cell.color;
            if (isPreviewLineCell && cell.occupied) {
              displayColor = _draggingPiece!.color;
            } else if (isPendingClearCell && cell.occupied) {
              displayColor = _lastPlacedPieceColor;
            }

            // Vérifier si c'est une Jelly Bomb
            final isJellyBomb = cell.isJellyBomb;
            final isExplodingJellyBomb = _explodingJellyBombs.contains(cellKey);

            Widget cellWidget;

            if (isJellyBomb && cell.occupied && !isClearing && !isExplodingJellyBomb) {
              // Rendu spécial pour Jelly Bomb
              cellWidget = SizedBox(
                width: _cellSize,
                height: _cellSize,
                child: Stack(
                  children: [
                    // Fond de cellule
                    CellWidget(
                      size: _cellSize,
                      x: x,
                      y: y,
                      isOccupied: false,
                      blockColor: null,
                    ),
                    // Jelly Bomb par dessus
                    Positioned.fill(
                      child: JellyBombWidget(
                        color: displayColor ?? Colors.orange,
                        size: _cellSize,
                        state: cell.blockState,
                      ),
                    ),
                  ],
                ),
              );
            } else {
              cellWidget = CellWidget(
                size: _cellSize,
                x: x,
                y: y,
                isOccupied: cell.occupied && !isExplodingJellyBomb,
                blockColor: displayColor,
              );
            }

            // Appliquer l'animation de placement
            if (isAnimating && cell.occupied && !isClearing && !isExplodingJellyBomb) {
              final scale = _scaleAnimation?.value ?? 1.0;
              final glow = _glowAnimation?.value ?? 0.0;

              cellWidget = Transform.scale(
                scale: scale,
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: (cell.color ?? Colors.white).withOpacity(glow * 0.8),
                        blurRadius: 20 * glow,
                        spreadRadius: 10 * glow,
                      ),
                    ],
                  ),
                  child: cellWidget,
                ),
              );
            }

            // Animation cascade avec particules
            if (isClearing && cell.occupied) {
              final globalProgress = _clearAnimController?.value ?? 0.0;

              // Utiliser la couleur de la dernière pièce posée pour l'animation
              final clearingColor = _lastPlacedPieceColor ?? cell.color!;

              // Déterminer si c'est une ligne ou une colonne
              final isInRow = _clearingRows.contains(y);
              final isInColumn = _clearingColumns.contains(x);

              // Cascade : direction basée sur ligne ou colonne
              double startTime;
              if (isInRow && !isInColumn) {
                startTime = x * 0.10;
              } else if (isInColumn && !isInRow) {
                startTime = y * 0.10;
              } else {
                startTime = (x + y) * 0.05;
              }

              double localProgress = 0.0;
              if (globalProgress >= startTime) {
                localProgress = ((globalProgress - startTime) / 0.25).clamp(0.0, 1.0);
              }

              double scale = 1.0;
              double opacity = 1.0;
              List<Widget> particles = [];

              if (localProgress > 0) {
                // Grossir puis disparaître
                if (localProgress < 0.3) {
                  scale = 1.0 + (0.15 * localProgress / 0.3);
                } else {
                  final shrinkProgress = (localProgress - 0.3) / 0.7;
                  scale = 1.15 * (1.0 - shrinkProgress);
                  opacity = 1.0 - shrinkProgress;

                  // Particules qui s'envolent pendant la disparition
                  final particleProgress = shrinkProgress;
                  if (particleProgress < 0.9) {
                    for (int i = 0; i < 6; i++) {
                      final angle = (i / 6) * 2 * Math.pi + (x + y) * 0.5;
                      final distance = particleProgress * _cellSize * 0.8;
                      final px = _cellSize / 2 + Math.cos(angle) * distance;
                      final py = _cellSize / 2 + Math.sin(angle) * distance;
                      final pOpacity = (1.0 - particleProgress * 1.1).clamp(0.0, 1.0);
                      final pSize = _cellSize * 0.12 * (1.0 - particleProgress * 0.5);

                      particles.add(
                        Positioned(
                          left: px - pSize / 2,
                          top: py - pSize / 2,
                          child: Opacity(
                            opacity: pOpacity,
                            child: Container(
                              width: pSize,
                              height: pSize,
                              decoration: BoxDecoration(
                                color: clearingColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: clearingColor.withOpacity(0.6),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  }
                }
              }

              if (opacity <= 0.02 || scale <= 0.02) {
                cellWidget = CellWidget(
                  size: _cellSize,
                  x: x,
                  y: y,
                  isOccupied: false,
                  blockColor: null,
                );
              } else {
                cellWidget = Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CellWidget(
                      size: _cellSize,
                      x: x,
                      y: y,
                      isOccupied: false,
                      blockColor: null,
                    ),
                    // Bloc qui disparaît avec la couleur de la pièce posée
                    Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        child: BlockWidget(
                          color: clearingColor,
                          size: _cellSize,
                        ),
                      ),
                    ),
                    // Particules
                    ...particles,
                  ],
                );
              }
            } else if (isClearing && !cell.occupied) {
              cellWidget = CellWidget(
                size: _cellSize,
                x: x,
                y: y,
                isOccupied: false,
                blockColor: null,
              );
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Cadre blanc autour des cellules de la ligne qui va être complétée (pendant drag)
                if (isPreviewLineCell && cell.occupied)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_cellSize * 0.15),
                      border: Border.all(
                        color: Colors.white,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _draggingPiece!.color.withOpacity(0.6),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                // Cadre blanc autour des cellules en attente de suppression (après placement)
                if (isPendingClearCell && cell.occupied)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_cellSize * 0.15),
                      border: Border.all(
                        color: Colors.white,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _lastPlacedPieceColor!.withOpacity(0.6),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                cellWidget,
                // Aperçu ghost (où la pièce va être posée)
                if (isPreview && !cell.occupied)
                  Positioned.fill(
                    child: Container(
                      margin: EdgeInsets.all(_cellSize * 0.08),
                      decoration: BoxDecoration(
                        color: _canPlacePreview
                            ? _draggingPiece!.color.withOpacity(0.7)
                            : Colors.red.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(_cellSize * 0.15),
                        border: Border.all(
                          color: _canPlacePreview
                              ? Colors.white.withOpacity(0.8)
                              : Colors.red.shade900,
                          width: 2,
                        ),
                        boxShadow: _canPlacePreview
                            ? [
                                BoxShadow(
                                  color: _draggingPiece!.color.withOpacity(0.6),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// Overlay simple - animation gérée dans la grille, particules par le système existant
  Widget _buildFallingBlocksOverlay(double gridSize, double border) {
    // On n'utilise plus cet overlay - tout est géré par le système de particules existant
    return const SizedBox.shrink();
  }

  Widget _buildUIButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9EC4), Color(0xFFE85A8F)],
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE85A8F).withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallUIButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9EC4), Color(0xFFE85A8F)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE85A8F).withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileWidget() {
    return GestureDetector(
      onTap: _showEditNameDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7B68EE), Color(0xFF6A5ACD)],
          ),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6A5ACD).withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar cercle
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                ),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _googlePhotoUrl != null
                  ? ClipOval(
                      child: Image.network(
                        _googlePhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Text(
                            _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    )
                  : _userAvatarPath != null
                      ? ClipOval(
                          child: Image.asset(
                            _userAvatarPath!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Center(
                          child: Text(
                            _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  offset: Offset(1, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
            ),
            const SizedBox(width: 10),
            // Nom et indicateur d'édition
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        offset: Offset(1, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Tap pour modifier',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 5),
          ],
        ),
      ),
    );
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: _userName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D1B4E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withOpacity(0.3), width: 2),
        ),
        title: const Text(
          'Ton prénom',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Entre ton prénom pour jouer.\nTu pourras te connecter plus tard pour jouer en ligne!',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              textAlign: TextAlign.center,
              maxLength: 15,
              decoration: InputDecoration(
                hintText: 'Ton prénom...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                counterStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF32CD32), Color(0xFF228B22)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextButton(
                    onPressed: () {
                      final newName = controller.text.trim();
                      if (newName.isNotEmpty) {
                        setState(() {
                          _userName = newName;
                        });
                        _saveUserName(newName);
                      }
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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

  Widget _buildScoreDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8C00).withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Score actuel
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SCORE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  shadows: [
                    Shadow(color: Colors.black26, offset: Offset(1, 1), blurRadius: 2),
                  ],
                ),
              ),
              Text(
                '$_score',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.black38, offset: Offset(2, 2), blurRadius: 4),
                  ],
                ),
              ),
            ],
          ),
          // Séparateur
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            height: 35,
            width: 2,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          // Meilleur score
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.emoji_events,
                    color: Colors.white.withOpacity(0.9),
                    size: 12,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'BEST',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              Text(
                '$_highScore',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(color: Colors.black26, offset: Offset(1, 1), blurRadius: 2),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _restartGame() {
    setState(() {
      _gameState = GameState.initial();
      _score = 0;
      _isGameOver = false;
      _generateNewPieces();
      _animatingCells.clear();
      _clearingCells.clear();
      _clearingRows.clear();
      _clearingColumns.clear();
      _pendingClearRows.clear();
      _pendingClearColumns.clear();
      _fallingBlocks.clear();
      _activeParticles.clear();
      _energyParticles.clear();
      _lastPlacedPieceColor = null;
      _sessionStartTime = DateTime.now();
      _sessionLinesCleared = 0;
      // Reset Sugar Rush
      _sugarRushProgress = 0.0;
      _isSugarRushActive = false;
      _sugarRushRemainingTime = 0.0;
      _showSugarRushOverlay = false;
      _lastSugarRushEnd = null;
      // Reset Jelly Bomb
      _activeJellyBombExplosions = [];
      _explodingJellyBombs = {};
      // Reset Duel result (au cas où)
      _opponentScore = null;
      _opponentName = null;
      _opponentPhotoUrl = null;
      _isDuelWinner = null;
    });
  }

  /// Vérifie si le jeu est terminé (aucune pièce ne peut être placée)
  void _checkGameOver() {
    // Vérifier si au moins une des pièces disponibles peut être placée
    for (final piece in _availablePieces) {
      if (piece != null && _canPlacePieceAnywhere(piece)) {
        return; // Au moins une pièce peut être placée
      }
    }

    // Aucune pièce ne peut être placée = Game Over
    _saveHighScore();
    _saveSessionStats();

    // Si mode duel, soumettre le score
    if (_isDuelMode && _duelId != null) {
      _submitDuelScore();
    }

    setState(() {
      _isGameOver = true;
    });
  }

  /// Soumet le score du duel et récupère les infos de l'adversaire
  Future<void> _submitDuelScore() async {
    final playerId = supabaseService.playerId;
    if (playerId == null || _duelId == null) return;

    final updatedDuel = await duelService.submitScore(
      duelId: _duelId!,
      playerId: playerId,
      score: _score,
    );

    if (updatedDuel != null && mounted) {
      // Déterminer qui est l'adversaire
      final isChallenger = updatedDuel.challengerId == playerId;

      setState(() {
        if (isChallenger) {
          _opponentScore = updatedDuel.challengedScore;
          _opponentName = updatedDuel.challengedName;
          _opponentPhotoUrl = updatedDuel.challengedPhotoUrl;
        } else {
          _opponentScore = updatedDuel.challengerScore;
          _opponentName = updatedDuel.challengerName;
          _opponentPhotoUrl = updatedDuel.challengerPhotoUrl;
        }

        // Déterminer le gagnant si les deux ont joué
        if (_opponentScore != null) {
          if (_score > _opponentScore!) {
            _isDuelWinner = true;
          } else if (_score < _opponentScore!) {
            _isDuelWinner = false;
          } else {
            _isDuelWinner = null; // Égalité
          }
        }
      });
    }
  }

  /// Sauvegarde les statistiques de la session
  Future<void> _saveSessionStats() async {
    // Temps de jeu
    if (_sessionStartTime != null) {
      final playTime = DateTime.now().difference(_sessionStartTime!).inSeconds;
      await statsService.addPlayTime(playTime);
    }

    // Parties jouées et score
    await statsService.incrementGamesPlayed();
    await statsService.addScore(_score);
    await statsService.updateHighScore(_score);

    // Sync avec le cloud
    await statsService.syncToCloud();
  }

  Widget _buildGameOverScreen() {
    final isNewHighScore = _score >= _highScore && _score > 0;

    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(30),
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF6B9D), Color(0xFFE85A8F)],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: const Color(0xFFFF6B9D).withOpacity(0.5),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 3,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'GAME OVER',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 3,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      offset: Offset(3, 3),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              if (isNewHighScore) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events, color: Colors.white, size: 20),
                      SizedBox(width: 5),
                      Text(
                        'NOUVEAU RECORD!',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    const Text(
                      'SCORE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      '$_score',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black38,
                            offset: Offset(2, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Afficher le résultat du duel si on est en mode duel
              if (_isDuelMode) ...[
                const SizedBox(height: 20),
                _buildDuelResult(),
              ] else if (!isNewHighScore && _highScore > 0) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 18),
                    const SizedBox(width: 5),
                    Text(
                      'Record: $_highScore',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 30),
              // Boutons d'action
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bouton Accueil
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667eea).withOpacity(0.5),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, color: Colors.white, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'QUITTER',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // En mode duel, pas de bouton rejouer
                  if (!_isDuelMode) ...[
                    const SizedBox(width: 15),
                    // Bouton Rejouer
                    GestureDetector(
                      onTap: _restartGame,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF32CD32), Color(0xFF228B22)],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF32CD32).withOpacity(0.5),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh, color: Colors.white, size: 24),
                            SizedBox(width: 8),
                            Text(
                              'REJOUER',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Construit l'affichage du résultat du duel
  Widget _buildDuelResult() {
    // Si l'adversaire n'a pas encore joué
    if (_opponentScore == null) {
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            const Icon(Icons.hourglass_empty, color: Colors.white70, size: 30),
            const SizedBox(height: 10),
            Text(
              _opponentName != null
                  ? '$_opponentName n\'a pas encore joué'
                  : 'En attente de l\'adversaire...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      );
    }

    // Affichage VS avec les deux scores
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isDuelWinner == true
              ? [const Color(0xFF32CD32).withOpacity(0.3), const Color(0xFF228B22).withOpacity(0.3)]
              : _isDuelWinner == false
                  ? [const Color(0xFFEB3349).withOpacity(0.3), const Color(0xFFF45C43).withOpacity(0.3)]
                  : [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.2)],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: _isDuelWinner == true
              ? const Color(0xFF32CD32)
              : _isDuelWinner == false
                  ? const Color(0xFFEB3349)
                  : Colors.white54,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // Texte résultat
          Text(
            _isDuelWinner == true
                ? '🏆 VICTOIRE!'
                : _isDuelWinner == false
                    ? '😢 DÉFAITE'
                    : '🤝 ÉGALITÉ',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _isDuelWinner == true
                  ? const Color(0xFF32CD32)
                  : _isDuelWinner == false
                      ? const Color(0xFFEB3349)
                      : Colors.white,
            ),
          ),
          const SizedBox(height: 15),
          // VS Layout
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mon score
              _buildPlayerScoreCard(
                name: _userName,
                score: _score,
                photoUrl: _googlePhotoUrl,
                isWinner: _isDuelWinner == true,
              ),
              // VS
              const Text(
                'VS',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              // Score adversaire
              _buildPlayerScoreCard(
                name: _opponentName ?? 'Adversaire',
                score: _opponentScore!,
                photoUrl: _opponentPhotoUrl,
                isWinner: _isDuelWinner == false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Carte de score d'un joueur dans le résultat du duel
  Widget _buildPlayerScoreCard({
    required String name,
    required int score,
    String? photoUrl,
    required bool isWinner,
  }) {
    return Column(
      children: [
        // Avatar
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isWinner ? const Color(0xFFFFD700) : Colors.white54,
              width: isWinner ? 3 : 2,
            ),
            boxShadow: isWinner
                ? [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.5),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: ClipOval(
            child: photoUrl != null
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildDefaultAvatar(name),
                  )
                : _buildDefaultAvatar(name),
          ),
        ),
        const SizedBox(height: 5),
        // Nom
        Text(
          name.length > 10 ? '${name.substring(0, 10)}...' : name,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
          ),
        ),
        // Score
        Text(
          '$score',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isWinner ? const Color(0xFFFFD700) : Colors.white,
          ),
        ),
        if (isWinner)
          const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 16),
      ],
    );
  }

  Widget _buildDefaultAvatar(String name) {
    return Container(
      color: const Color(0xFFFF6B9D),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
    );
  }
}

/// Données pour une particule active
class _ParticleData {
  final int id;
  final Offset position;
  final Color color;

  _ParticleData({
    required this.id,
    required this.position,
    required this.color,
  });
}

/// Données pour un bloc qui tombe
class _FallingBlock {
  final int x;
  final int y;
  final Color color;
  final double delay; // Délai avant de commencer à tomber

  _FallingBlock({
    required this.x,
    required this.y,
    required this.color,
    required this.delay,
  });
}

/// Données pour un score flottant
class _FloatingScore {
  final int id;
  final int score;
  final Offset startPosition;
  final Color color;
  final bool isCombo;

  _FloatingScore({
    required this.id,
    required this.score,
    required this.startPosition,
    required this.color,
    this.isCombo = false,
  });
}

/// Widget de score flottant animé
class _FloatingScoreWidget extends StatefulWidget {
  final _FloatingScore data;
  final VoidCallback onComplete;

  const _FloatingScoreWidget({
    super.key,
    required this.data,
    required this.onComplete,
  });

  @override
  State<_FloatingScoreWidget> createState() => _FloatingScoreWidgetState();
}

class _FloatingScoreWidgetState extends State<_FloatingScoreWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _positionAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _positionAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.3), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _positionAnimation.value;
        final scale = _scaleAnimation.value;
        final opacity = _opacityAnimation.value;

        // Monter de 150 pixels vers le haut
        final currentY = widget.data.startPosition.dy - (150 * progress);
        final currentX = widget.data.startPosition.dx;

        final fontSize = widget.data.isCombo ? 65.0 : 51.0;
        final scoreText = '+${widget.data.score}';
        // Couleur vive : doré pour normal, rose vif pour combo
        final baseColor = widget.data.isCombo
            ? const Color(0xFFFF1493)
            : const Color(0xFFFFD700);

        return Positioned(
          left: currentX - 90,
          top: currentY - 30,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 180,
                  alignment: Alignment.center,
                  child: Stack(
                    children: [
                      // Couche 5 : Ombre profonde (fond)
                      Transform.translate(
                        offset: const Offset(3, 5),
                        child: Text(
                          scoreText,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Colors.black.withOpacity(0.5),
                          ),
                        ),
                      ),
                      // Couche 4 : Profondeur 3D (marron foncé)
                      Transform.translate(
                        offset: const Offset(2, 4),
                        child: Text(
                          scoreText,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Color.lerp(baseColor, Colors.black, 0.7)!,
                          ),
                        ),
                      ),
                      // Couche 3 : Profondeur 3D (teinte foncée)
                      Transform.translate(
                        offset: const Offset(1.2, 2.5),
                        child: Text(
                          scoreText,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Color.lerp(baseColor, Colors.black, 0.45)!,
                          ),
                        ),
                      ),
                      // Couche 2 : Contour coloré foncé
                      Text(
                        scoreText,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 5
                            ..color = Color.lerp(baseColor, Colors.black, 0.4)!,
                        ),
                      ),
                      // Couche 1 : Dégradé principal
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.lerp(baseColor, Colors.white, 0.5)!,
                            baseColor,
                            Color.lerp(baseColor, Colors.black, 0.2)!,
                          ],
                        ).createShader(bounds),
                        child: Text(
                          scoreText,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      // Couche 0 : Reflet blanc en haut
                      Text(
                        scoreText,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 1.5
                            ..color = Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Données pour une explosion de Jelly Bomb
class _JellyBombExplosion {
  final int id;
  final Offset position;
  final Color color;

  _JellyBombExplosion({
    required this.id,
    required this.position,
    required this.color,
  });
}

/// Données pour une particule d'énergie vers la jauge
class _EnergyParticle {
  final int id;
  final Offset startPosition;
  final Offset endPosition;
  final Color color;

  _EnergyParticle({
    required this.id,
    required this.startPosition,
    required this.endPosition,
    required this.color,
  });
}

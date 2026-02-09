import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/realtime_duel_service.dart';
import '../../services/supabase_service.dart';
import '../../services/audio_service.dart';
import '../../models/duel.dart';
import 'game_screen.dart';

class DuelLobbyScreen extends StatefulWidget {
  final Duel duel;
  final String myPlayerId;
  final String opponentId;
  final String? opponentName;
  final String? opponentPhotoUrl;
  final String? myName;
  final String? myPhotoUrl;

  const DuelLobbyScreen({
    super.key,
    required this.duel,
    required this.myPlayerId,
    required this.opponentId,
    this.opponentName,
    this.opponentPhotoUrl,
    this.myName,
    this.myPhotoUrl,
  });

  @override
  State<DuelLobbyScreen> createState() => _DuelLobbyScreenState();
}

class _DuelLobbyScreenState extends State<DuelLobbyScreen>
    with TickerProviderStateMixin {
  late RealtimeDuelService _realtimeService;
  RealtimeDuelState _currentState = RealtimeDuelState.connecting;
  int _countdownValue = 3;
  bool _navigatedToGame = false;

  // Animations
  late AnimationController _pulseController;
  late AnimationController _vsController;

  // Timeout
  Timer? _lobbyTimeoutTimer;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _vsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _realtimeService = RealtimeDuelService();
    _setupRealtimeService();
  }

  void _setupRealtimeService() {
    _realtimeService.onStateChange = (newState) {
      if (!mounted) return;
      setState(() => _currentState = newState);

      // Naviguer immédiatement vers le GameScreen
      // Tout le visuel (VS, countdown) se fait dans le GameScreen
      if (newState == RealtimeDuelState.waitingOpponent && !_navigatedToGame) {
        _navigateToGame();
      } else if (newState == RealtimeDuelState.opponentLeft ||
                 newState == RealtimeDuelState.disconnected) {
        _handleOpponentLeft();
      }
    };

    // Rejoindre le channel
    _realtimeService.joinDuel(
      duelId: widget.duel.id,
      myPlayerId: widget.myPlayerId,
      opponentPlayerId: widget.opponentId,
    );

    // Timeout du lobby : 60 secondes
    _lobbyTimeoutTimer = Timer(const Duration(seconds: 60), _handleTimeout);
  }

  void _navigateToGame() {
    if (_navigatedToGame) return;
    _navigatedToGame = true;
    _lobbyTimeoutTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => GameScreen(
          duelSeed: widget.duel.seed,
          duelId: widget.duel.id,
          opponentId: widget.opponentId,
          opponentName: widget.opponentName,
          opponentPhotoUrl: widget.opponentPhotoUrl,
          realtimeDuelService: _realtimeService,
        ),
      ),
    );
  }

  void _handleTimeout() {
    if (!mounted || _navigatedToGame) return;
    if (_currentState == RealtimeDuelState.waitingOpponent ||
        _currentState == RealtimeDuelState.connecting) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2D1B4E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Adversaire absent',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            '${widget.opponentName ?? "L\'adversaire"} ne s\'est pas connecté.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _lobbyTimeoutTimer = Timer(const Duration(seconds: 60), _handleTimeout);
              },
              child: const Text('ATTENDRE', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _realtimeService.leaveDuel();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE91E63),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('QUITTER', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  void _handleOpponentLeft() {
    if (!mounted || _navigatedToGame) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D1B4E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Adversaire parti',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${widget.opponentName ?? "L\'adversaire"} a quitté le lobby.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _realtimeService.leaveDuel();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE91E63),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('RETOUR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _lobbyTimeoutTimer?.cancel();
    _pulseController.dispose();
    _vsController.dispose();
    if (!_navigatedToGame) {
      _realtimeService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Container(
        width: screenWidth,
        height: screenHeight,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/ui/fondduel.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Contenu principal
              Column(
                children: [
                  const SizedBox(height: 40),
                  // Titre
                  const Text(
                    'DUEL EN DIRECT',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: Colors.white,
                      letterSpacing: 2,
                      shadows: [
                        Shadow(color: Color(0xFFE91E63), offset: Offset(0, 2), blurRadius: 10),
                        Shadow(color: Colors.black54, offset: Offset(2, 3), blurRadius: 5),
                      ],
                    ),
                  ),
                  const SizedBox(height: 50),
                  // Cartes joueurs VS
                  _buildVSLayout(screenWidth),
                  const SizedBox(height: 40),
                  // Status
                  _buildStatusMessage(),
                ],
              ),

              // Countdown overlay
              if (_currentState == RealtimeDuelState.countdown)
                _buildCountdownOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVSLayout(double screenWidth) {
    final cardWidth = screenWidth * 0.32;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Mon avatar
        _buildPlayerCard(
          name: widget.myName ?? 'Moi',
          photoUrl: widget.myPhotoUrl,
          isReady: true,
          width: cardWidth,
        ),
        const SizedBox(width: 15),
        // VS animé
        AnimatedBuilder(
          animation: _vsController,
          builder: (context, child) {
            return Transform.scale(
              scale: 0.9 + _vsController.value * 0.2,
              child: Text(
                'VS',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF6B35), Color(0xFFE91E63)],
                    ).createShader(const Rect.fromLTWH(0, 0, 80, 50)),
                  shadows: const [
                    Shadow(color: Colors.black, offset: Offset(2, 3), blurRadius: 6),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 15),
        // Adversaire
        _buildPlayerCard(
          name: widget.opponentName ?? 'Adversaire',
          photoUrl: widget.opponentPhotoUrl,
          isReady: _realtimeService.isOpponentPresent,
          width: cardWidth,
        ),
      ],
    );
  }

  Widget _buildPlayerCard({
    required String name,
    String? photoUrl,
    required bool isReady,
    required double width,
  }) {
    return Column(
      children: [
        // Avatar
        Container(
          width: width * 0.7,
          height: width * 0.7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isReady ? const Color(0xFF4CAF50) : Colors.grey,
              width: 3,
            ),
            boxShadow: isReady
                ? [BoxShadow(color: const Color(0xFF4CAF50).withOpacity(0.5), blurRadius: 15)]
                : [],
          ),
          child: ClipOval(
            child: photoUrl != null
                ? Image.network(photoUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildDefaultAvatar())
                : _buildDefaultAvatar(),
          ),
        ),
        const SizedBox(height: 10),
        // Nom
        Text(
          name,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        // Badge ready
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isReady ? const Color(0xFF4CAF50) : Colors.grey.shade700,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            isReady ? 'PRÊT' : 'ATTENTE...',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: const Color(0xFF3D2066),
      child: const Icon(Icons.person, size: 50, color: Colors.white54),
    );
  }

  Widget _buildStatusMessage() {
    String message;
    bool showPulse = false;

    switch (_currentState) {
      case RealtimeDuelState.connecting:
        message = 'Connexion...';
        showPulse = true;
        break;
      case RealtimeDuelState.waitingOpponent:
        message = 'En attente de ${widget.opponentName ?? "l\'adversaire"}...';
        showPulse = true;
        break;
      case RealtimeDuelState.bothReady:
        message = 'Préparez-vous !';
        break;
      case RealtimeDuelState.countdown:
        message = '';
        break;
      default:
        message = '';
    }

    if (message.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Opacity(
          opacity: showPulse ? 0.5 + _pulseController.value * 0.5 : 1.0,
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCountdownOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_countdownValue),
            tween: Tween(begin: 2.5, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: Text(
                  _countdownValue > 0 ? '$_countdownValue' : 'GO!',
                  style: TextStyle(
                    fontSize: _countdownValue > 0 ? 140 : 100,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: _countdownValue > 0 ? Colors.white : const Color(0xFF4CAF50),
                    shadows: [
                      Shadow(
                        color: _countdownValue > 0
                            ? const Color(0xFFE91E63)
                            : const Color(0xFF4CAF50),
                        offset: const Offset(0, 4),
                        blurRadius: 20,
                      ),
                      const Shadow(
                        color: Colors.black,
                        offset: Offset(3, 5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

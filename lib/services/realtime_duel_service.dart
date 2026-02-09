import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// État du duel temps réel
enum RealtimeDuelState {
  connecting,
  waitingOpponent,
  bothReady,
  countdown,
  playing,
  waitingResult,
  completed,
  disconnected,
  opponentLeft,
}

/// Callbacks
typedef ScoreUpdateCallback = void Function(int opponentScore);
typedef GameOverCallback = void Function(int opponentFinalScore, int? opponentTimeSeconds);
typedef StateChangeCallback = void Function(RealtimeDuelState newState);
typedef CountdownCallback = void Function(int secondsRemaining);

class RealtimeDuelService {
  RealtimeChannel? _channel;
  String? _duelId;
  String? _myPlayerId;
  String? _opponentPlayerId;

  // État
  RealtimeDuelState _state = RealtimeDuelState.connecting;
  bool _isOpponentPresent = false;
  bool _isOpponentGameOver = false;
  int _opponentScore = 0;
  int? _opponentFinalScore;
  int? _opponentFinalTime;

  // Timers
  Timer? _heartbeatTimer;
  Timer? _disconnectTimer;
  Timer? _countdownTimer;
  DateTime? _lastScoreBroadcastTime;

  // Callbacks
  ScoreUpdateCallback? onOpponentScoreUpdate;
  GameOverCallback? onOpponentGameOver;
  StateChangeCallback? onStateChange;
  CountdownCallback? onCountdownTick;

  // Getters
  RealtimeDuelState get state => _state;
  bool get isOpponentPresent => _isOpponentPresent;
  int get opponentScore => _opponentScore;
  bool get isOpponentGameOver => _isOpponentGameOver;
  int? get opponentFinalScore => _opponentFinalScore;
  int? get opponentFinalTime => _opponentFinalTime;
  String? get duelId => _duelId;

  /// Rejoindre le channel realtime pour un duel
  Future<void> joinDuel({
    required String duelId,
    required String myPlayerId,
    required String opponentPlayerId,
  }) async {
    _duelId = duelId;
    _myPlayerId = myPlayerId;
    _opponentPlayerId = opponentPlayerId;
    _setState(RealtimeDuelState.connecting);

    try {
      _channel = Supabase.instance.client.channel(
        'duel:$duelId',
        opts: const RealtimeChannelConfig(self: true),
      );

      // Écouter les events Broadcast
      _channel!.onBroadcast(
        event: 'score_update',
        callback: _onScoreUpdate,
      );

      _channel!.onBroadcast(
        event: 'game_over',
        callback: _onGameOver,
      );

      _channel!.onBroadcast(
        event: 'countdown_start',
        callback: _onCountdownStart,
      );

      _channel!.onBroadcast(
        event: 'heartbeat',
        callback: _onHeartbeat,
      );

      // Écouter la Presence
      _channel!.onPresenceSync((payload) => _onPresenceSync());
      _channel!.onPresenceJoin((payload) => _onPresenceJoin(payload));
      _channel!.onPresenceLeave((payload) => _onPresenceLeave(payload));

      // S'abonner au channel
      _channel!.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          // Tracker ma présence
          _channel!.track({
            'player_id': _myPlayerId,
            'status': 'ready',
          });

          _setState(RealtimeDuelState.waitingOpponent);

          // Démarrer le heartbeat
          _startHeartbeat();
        } else if (status == RealtimeSubscribeStatus.closed) {
          _setState(RealtimeDuelState.disconnected);
        }
      });
    } catch (e) {
      print('Erreur joinDuel: $e');
      _setState(RealtimeDuelState.disconnected);
    }
  }

  /// Quitter le channel
  Future<void> leaveDuel() async {
    _heartbeatTimer?.cancel();
    _disconnectTimer?.cancel();
    _countdownTimer?.cancel();

    if (_channel != null) {
      try {
        await _channel!.untrack();
        await _channel!.unsubscribe();
        Supabase.instance.client.removeChannel(_channel!);
      } catch (e) {
        print('Erreur leaveDuel: $e');
      }
      _channel = null;
    }
  }

  /// Envoyer une mise à jour du score (throttled à 500ms)
  void sendScoreUpdate(int currentScore) {
    if (_channel == null || _state != RealtimeDuelState.playing) return;

    final now = DateTime.now();
    if (_lastScoreBroadcastTime != null &&
        now.difference(_lastScoreBroadcastTime!).inMilliseconds < 500) {
      return; // Throttle
    }
    _lastScoreBroadcastTime = now;

    _channel!.sendBroadcastMessage(
      event: 'score_update',
      payload: {
        'player_id': _myPlayerId,
        'score': currentScore,
      },
    );
  }

  /// Envoyer le signal game over
  void sendGameOver({required int finalScore, required int timeSeconds}) {
    if (_channel == null) return;

    _channel!.sendBroadcastMessage(
      event: 'game_over',
      payload: {
        'player_id': _myPlayerId,
        'score': finalScore,
        'time': timeSeconds,
      },
    );

    if (_isOpponentGameOver) {
      _setState(RealtimeDuelState.completed);
    } else {
      _setState(RealtimeDuelState.waitingResult);
    }
  }

  // --- Handlers internes ---

  void _onScoreUpdate(Map<String, dynamic> payload) {
    final data = payload['payload'] ?? payload;
    if (data['player_id'] == _myPlayerId) return; // Ignorer mes propres messages

    _opponentScore = data['score'] ?? 0;
    _resetDisconnectTimer(); // L'adversaire est actif
    onOpponentScoreUpdate?.call(_opponentScore);
  }

  void _onGameOver(Map<String, dynamic> payload) {
    final data = payload['payload'] ?? payload;
    if (data['player_id'] == _myPlayerId) return;

    _isOpponentGameOver = true;
    _opponentFinalScore = data['score'] ?? 0;
    _opponentFinalTime = data['time'];
    _opponentScore = _opponentFinalScore!;

    onOpponentGameOver?.call(_opponentFinalScore!, _opponentFinalTime);

    if (_state == RealtimeDuelState.waitingResult) {
      _setState(RealtimeDuelState.completed);
    }
  }

  void _onCountdownStart(Map<String, dynamic> payload) {
    // Si je suis déjà en countdown, ignorer
    if (_state == RealtimeDuelState.countdown || _state == RealtimeDuelState.playing) return;

    _startCountdownLocal();
  }

  void _onHeartbeat(Map<String, dynamic> payload) {
    final data = payload['payload'] ?? payload;
    if (data['player_id'] == _myPlayerId) return;
    _resetDisconnectTimer();
  }

  void _onPresenceSync() {
    if (_channel == null) return;

    final presenceStates = _channel!.presenceState();
    bool opponentFound = false;

    for (final state in presenceStates) {
      for (final presence in state.presences) {
        if (presence.payload['player_id'] == _opponentPlayerId) {
          opponentFound = true;
          break;
        }
      }
      if (opponentFound) break;
    }

    _isOpponentPresent = opponentFound;

    if (_isOpponentPresent && _state == RealtimeDuelState.waitingOpponent) {
      _setState(RealtimeDuelState.bothReady);

      // Le joueur avec l'ID le plus petit lance le countdown (leader election)
      if (_myPlayerId != null && _opponentPlayerId != null &&
          _myPlayerId!.compareTo(_opponentPlayerId!) < 0) {
        // Je suis le leader, attendre 1s puis lancer le countdown
        Future.delayed(const Duration(seconds: 1), () {
          if (_state == RealtimeDuelState.bothReady) {
            _channel?.sendBroadcastMessage(
              event: 'countdown_start',
              payload: {'leader': _myPlayerId},
            );
            _startCountdownLocal();
          }
        });
      }
    }
  }

  void _onPresenceJoin(dynamic payload) {
    // Géré par _onPresenceSync
  }

  void _onPresenceLeave(dynamic payload) {
    if (_state == RealtimeDuelState.countdown) {
      // Annuler si en countdown
      _countdownTimer?.cancel();
      _setState(RealtimeDuelState.opponentLeft);
    } else if (_state == RealtimeDuelState.playing ||
               _state == RealtimeDuelState.waitingResult) {
      // Pendant le jeu, marquer comme déconnecté mais laisser continuer
      _isOpponentPresent = false;
      // Le disconnect timer gérera le timeout
    } else if (_state == RealtimeDuelState.waitingOpponent ||
               _state == RealtimeDuelState.bothReady) {
      _isOpponentPresent = false;
      _setState(RealtimeDuelState.opponentLeft);
    }
  }

  void _startCountdownLocal() {
    _setState(RealtimeDuelState.countdown);
    int remaining = 5;
    onCountdownTick?.call(remaining);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining--;
      onCountdownTick?.call(remaining);

      if (remaining <= 0) {
        timer.cancel();
        _setState(RealtimeDuelState.playing);
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _channel?.sendBroadcastMessage(
        event: 'heartbeat',
        payload: {'player_id': _myPlayerId},
      );
    });

    // Timer pour détecter la déconnexion de l'adversaire
    _resetDisconnectTimer();
  }

  void _resetDisconnectTimer() {
    _disconnectTimer?.cancel();
    _disconnectTimer = Timer(const Duration(seconds: 15), () {
      if (_state == RealtimeDuelState.playing && !_isOpponentGameOver) {
        _setState(RealtimeDuelState.opponentLeft);
      }
    });
  }

  void _setState(RealtimeDuelState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChange?.call(newState);
  }

  /// Libérer les ressources
  void dispose() {
    _heartbeatTimer?.cancel();
    _disconnectTimer?.cancel();
    _countdownTimer?.cancel();
    leaveDuel();
  }
}

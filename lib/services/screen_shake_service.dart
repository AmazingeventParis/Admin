import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Service pour gérer l'effet de tremblement d'écran
class ScreenShakeService extends ChangeNotifier {
  static final ScreenShakeService _instance = ScreenShakeService._internal();
  factory ScreenShakeService() => _instance;
  ScreenShakeService._internal();

  // Offset actuel du tremblement
  Offset _shakeOffset = Offset.zero;
  Offset get shakeOffset => _shakeOffset;

  // Animation en cours
  bool _isShaking = false;
  bool get isShaking => _isShaking;

  // Paramètres du shake
  double _intensity = 0.0;
  double _traumaticIntensity = 0.0;

  final math.Random _random = math.Random();

  /// Déclenche un tremblement d'écran
  /// [intensity] : Force du tremblement (1.0 = normal, 2.0 = fort)
  /// [duration] : Durée en millisecondes
  /// [traumatic] : Si true, ajoute un effet "traumatique" plus intense
  Future<void> shake({
    double intensity = 1.0,
    int duration = 300,
    bool traumatic = false,
  }) async {
    _isShaking = true;
    _intensity = intensity;
    _traumaticIntensity = traumatic ? 1.5 : 0.0;

    final startTime = DateTime.now();
    final endTime = startTime.add(Duration(milliseconds: duration));

    while (DateTime.now().isBefore(endTime)) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      final progress = elapsed / duration;

      // Diminution progressive de l'intensité
      final currentIntensity = _intensity * (1 - progress);
      final traumaBonus = _traumaticIntensity * (1 - progress);

      // Calcul du décalage aléatoire
      final maxOffset = (2.4 * currentIntensity) + (3.6 * traumaBonus);
      _shakeOffset = Offset(
        (_random.nextDouble() * 2 - 1) * maxOffset,
        (_random.nextDouble() * 2 - 1) * maxOffset,
      );

      notifyListeners();

      // ~60 FPS
      await Future.delayed(const Duration(milliseconds: 16));
    }

    // Reset
    _shakeOffset = Offset.zero;
    _isShaking = false;
    _intensity = 0.0;
    _traumaticIntensity = 0.0;
    notifyListeners();
  }

  /// Déclenche un tremblement traumatique (explosion de Jelly Bomb)
  Future<void> traumaticShake() async {
    await shake(intensity: 2.0, duration: 400, traumatic: true);
  }

  /// Reset immédiat du shake
  void reset() {
    _shakeOffset = Offset.zero;
    _isShaking = false;
    _intensity = 0.0;
    _traumaticIntensity = 0.0;
    notifyListeners();
  }
}

/// Instance globale du service
final screenShakeService = ScreenShakeService();

/// Widget wrapper qui applique le screen shake à ses enfants
class ScreenShakeWrapper extends StatelessWidget {
  final Widget child;

  const ScreenShakeWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: screenShakeService,
      builder: (context, _) {
        return Transform.translate(
          offset: screenShakeService.shakeOffset,
          child: child,
        );
      },
    );
  }
}

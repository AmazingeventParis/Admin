import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Widget de jauge Sugar Rush avec animation Lerp fluide
class SugarRushGauge extends StatefulWidget {
  /// Progression actuelle (0.0 à 1.0)
  final double progress;

  /// Hauteur de la jauge
  final double height;

  /// Callback quand la jauge atteint 100%
  final VoidCallback? onFull;

  const SugarRushGauge({
    super.key,
    required this.progress,
    this.height = 50,
    this.onFull,
  });

  @override
  State<SugarRushGauge> createState() => _SugarRushGaugeState();
}

class _SugarRushGaugeState extends State<SugarRushGauge>
    with TickerProviderStateMixin {
  late AnimationController _lerpController;
  late AnimationController _sparkleController;
  double _displayedProgress = 0.0;
  double _targetProgress = 0.0;
  bool _wasFull = false;

  @override
  void initState() {
    super.initState();
    _displayedProgress = widget.progress;
    _targetProgress = widget.progress;

    _lerpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateLerp);

    _lerpController.repeat();

    // Animation sparkle continue (cycle de 2 secondes)
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  void _updateLerp() {
    if (!mounted) return;

    const lerpSpeed = 0.12;
    final newProgress = _lerpTowards(_displayedProgress, _targetProgress, lerpSpeed);

    if ((newProgress - _displayedProgress).abs() > 0.0005) {
      setState(() {
        _displayedProgress = newProgress;
      });
    }

    if (_displayedProgress >= 0.99 && !_wasFull) {
      _wasFull = true;
      widget.onFull?.call();
    } else if (_displayedProgress < 0.90) {
      _wasFull = false;
    }
  }

  double _lerpTowards(double current, double target, double speed) {
    final diff = target - current;
    if (diff.abs() < 0.0005) return target;
    return current + diff * speed;
  }

  @override
  void didUpdateWidget(SugarRushGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _targetProgress = widget.progress.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _lerpController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Utiliser la largeur disponible
          final availableWidth = constraints.maxWidth;
          final frameHeight = widget.height;

          // Marges intérieures du cadre (en pourcentage)
          // Ajustées pour que le remplissage soit bien visible
          final leftPadding = frameHeight * 0.42;  // Arrondi gauche
          final rightPadding = frameHeight * 0.42; // Arrondi droit
          final topPadding = frameHeight * 0.20;
          final bottomPadding = frameHeight * 0.20;

          final fillMaxWidth = availableWidth - leftPadding - rightPadding;
          final fillHeight = frameHeight - topPadding - bottomPadding;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Cadre - prend toute la largeur disponible
              Positioned.fill(
                child: Image.asset(
                  'assets/ui/sugar_gauge_frame.png',
                  fit: BoxFit.fill,
                ),
              ),

              // Remplissage (sirop doré)
              Positioned(
                left: leftPadding,
                top: topPadding,
                right: rightPadding,
                bottom: bottomPadding,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(fillHeight / 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _displayedProgress,
                      heightFactor: 1.0,
                      child: _displayedProgress > 0.01
                          ? Image.asset(
                              'assets/ui/sugar_gauge.png',
                              fit: BoxFit.cover,
                              alignment: Alignment.centerLeft,
                            )
                          : null,
                    ),
                  ),
                ),
              ),

              // Reflet brillant
              if (_displayedProgress > 0.05)
                Positioned(
                  left: leftPadding,
                  top: topPadding,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(fillHeight / 2),
                    child: Container(
                      width: fillMaxWidth * _displayedProgress,
                      height: fillHeight * 0.35,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0.35),
                            Colors.white.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Étincelles autour de l'étoile
              if (_displayedProgress > 0.05)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _sparkleController,
                    builder: (context, _) {
                      final starCenterX = leftPadding + (fillMaxWidth * _displayedProgress);
                      final starCenterY = frameHeight * 0.4;
                      return CustomPaint(
                        painter: _GaugeSparkPainter(
                          starX: starCenterX,
                          starY: starCenterY,
                          time: _sparkleController.value,
                          starSize: frameHeight * 0.6,
                          progress: _displayedProgress,
                        ),
                      );
                    },
                  ),
                ),

              // Icône étoile
              if (_displayedProgress > 0.02)
                Positioned(
                  left: leftPadding + (fillMaxWidth * _displayedProgress) - (frameHeight * 0.6),
                  top: -frameHeight * 0.2,
                  child: Image.asset(
                    'assets/ui/sugar_gauge_icon.png',
                    width: frameHeight * 1.2,
                    height: frameHeight * 1.2,
                    fit: BoxFit.contain,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Painter d'étincelles autour de l'étoile de la jauge
class _GaugeSparkPainter extends CustomPainter {
  final double starX;
  final double starY;
  final double time;
  final double starSize;
  final double progress;

  _GaugeSparkPainter({
    required this.starX,
    required this.starY,
    required this.time,
    required this.starSize,
    required this.progress,
  });

  // Couleurs des étincelles selon le niveau de progression
  static const List<Color> _lowColors = [Color(0xFFFFD700)]; // Jaune doré
  static const List<Color> _midColors = [
    Color(0xFFFFD700), Color(0xFFFF4757), Color(0xFFFFEA00), // Jaune + Rouge
  ];
  static const List<Color> _highColors = [
    Color(0xFFFFD700), Color(0xFFFF4757), Color(0xFF4169E1), // Jaune + Rouge + Bleu
    Color(0xFFFFEA00), Color(0xFFFF8C00),
  ];
  static const List<Color> _finalColors = [
    Color(0xFFFFD700), Color(0xFFFF4757), Color(0xFF4169E1),
    Color(0xFFFF69B4), Color(0xFF00CED1), Color(0xFF32CD32),
    Colors.white, Color(0xFFFF00FF), Color(0xFFFF8C00),
  ];

  List<Color> get _sparkColors {
    if (progress < 0.35) return _lowColors;
    if (progress < 0.65) return _midColors;
    if (progress < 0.90) return _highColors;
    return _finalColors; // Bouquet final !
  }

  @override
  void paint(Canvas canvas, Size size) {
    final colors = _sparkColors;
    final isFinal = progress >= 0.90;

    // Nombre d'étincelles progressif : 3 au début → 20 au bouquet final
    final sparkCount = isFinal ? 22 : (3 + progress * 13).round();
    // Nombre de traînées progressif : 2 → 14 au bouquet final
    final trailCount = isFinal ? 14 : (2 + progress * 8).round();

    // Étincelles autour de l'étoile
    for (int i = 0; i < sparkCount; i++) {
      final rng = math.Random(i * 7 + 3);
      final angle = (i / sparkCount) * math.pi * 2 + time * math.pi * 2;
      final radiusMult = 0.4 + 0.4 * math.sin(time * math.pi * 4 + i * 1.3);
      // Bouquet final : rayon beaucoup plus grand
      final radiusScale = isFinal ? (0.6 + radiusMult * 1.2) : (0.5 + radiusMult * (0.3 + progress * 0.4));
      final radius = starSize * radiusScale;
      final sparkX = starX + math.cos(angle) * radius;
      final sparkY = starY + math.sin(angle) * radius;

      final phase = (time + i / sparkCount) % 1.0;
      final sparkOpacity = phase < 0.5
          ? (phase / 0.5) * 0.9
          : (1 - (phase - 0.5) / 0.5) * 0.9;

      if (sparkOpacity <= 0) continue;

      // Bouquet final : étincelles plus grosses
      final sizeMult = isFinal ? 1.8 : (0.8 + progress * 0.5);
      final sparkSize = (2.0 + rng.nextDouble() * 2.0) * sizeMult;
      final sparkColor = colors[i % colors.length];

      // Glow coloré
      final glowPaint = Paint()
        ..color = sparkColor.withOpacity(sparkOpacity * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sparkSize * 1.5);
      canvas.drawCircle(Offset(sparkX, sparkY), sparkSize * 1.5, glowPaint);

      // Centre blanc brillant
      final centerPaint = Paint()
        ..color = Colors.white.withOpacity(sparkOpacity);
      canvas.drawCircle(Offset(sparkX, sparkY), sparkSize * 0.6, centerPaint);

      // Croix 4 branches
      final crossPaint = Paint()
        ..color = Colors.white.withOpacity(sparkOpacity * 0.7)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      final crossSize = sparkSize * 1.2;
      canvas.drawLine(
        Offset(sparkX - crossSize, sparkY),
        Offset(sparkX + crossSize, sparkY),
        crossPaint,
      );
      canvas.drawLine(
        Offset(sparkX, sparkY - crossSize),
        Offset(sparkX, sparkY + crossSize),
        crossPaint,
      );
    }

    // Traînée d'étincelles derrière l'étoile
    for (int i = 0; i < trailCount; i++) {
      final trailOffset = (i + 1) * starSize * 0.35;
      final trailX = starX - trailOffset;
      if (trailX < 0) continue;

      final trailPhase = (time * 3 + i * 0.15) % 1.0;
      final trailOpacity = (1 - i / trailCount) * 0.6 * (0.3 + 0.7 * math.sin(trailPhase * math.pi));
      final trailY = starY + math.sin(time * math.pi * 6 + i * 1.2) * starSize * 0.25;
      final trailSize = (1.5 + progress * 1.0) * (1 - i / trailCount);
      final trailColor = colors[i % colors.length];

      final trailGlow = Paint()
        ..color = trailColor.withOpacity(trailOpacity * 0.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, trailSize * 1.2);
      canvas.drawCircle(Offset(trailX, trailY), trailSize * 1.2, trailGlow);

      final trailCenter = Paint()
        ..color = Colors.white.withOpacity(trailOpacity);
      canvas.drawCircle(Offset(trailX, trailY), trailSize * 0.5, trailCenter);
    }
  }

  @override
  bool shouldRepaint(_GaugeSparkPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.starX != starX;
}

/// Particule étincelle qui vole vers la jauge Sugar Rush
class SugarRushEnergyParticle extends StatefulWidget {
  final Offset startPosition;
  final Offset endPosition;
  final Color color;
  final VoidCallback onComplete;
  final double size;

  const SugarRushEnergyParticle({
    super.key,
    required this.startPosition,
    required this.endPosition,
    required this.color,
    required this.onComplete,
    this.size = 10,
  });

  @override
  State<SugarRushEnergyParticle> createState() => _SugarRushEnergyParticleState();
}

class _SugarRushEnergyParticleState extends State<SugarRushEnergyParticle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  // Positions précédentes pour la traînée
  final List<Offset> _trail = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _controller.addListener(() {
      // Stocker les positions pour la traînée (plus longue)
      final t = Curves.easeInQuad.transform(_controller.value);
      final dx = widget.startPosition.dx +
          (widget.endPosition.dx - widget.startPosition.dx) * t;
      final arcHeight = -60.0 * math.sin(t * math.pi);
      final dy = widget.startPosition.dy +
          (widget.endPosition.dy - widget.startPosition.dy) * t + arcHeight;
      _trail.add(Offset(dx, dy));
      if (_trail.length > 14) _trail.removeAt(0);
    });

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
        final t = Curves.easeInQuad.transform(_controller.value);

        // Position actuelle en arc
        final dx = widget.startPosition.dx +
            (widget.endPosition.dx - widget.startPosition.dx) * t;
        final arcHeight = -50.0 * math.sin(t * math.pi);
        final dy = widget.startPosition.dy +
            (widget.endPosition.dy - widget.startPosition.dy) * t + arcHeight;

        final opacity = t < 0.85 ? 1.0 : (1 - (t - 0.85) / 0.15);

        return CustomPaint(
          painter: _SparkTrailPainter(
            trail: List.from(_trail),
            headPosition: Offset(dx, dy),
            color: widget.color,
            size: widget.size,
            opacity: opacity,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _SparkTrailPainter extends CustomPainter {
  final List<Offset> trail;
  final Offset headPosition;
  final Color color;
  final double size;
  final double opacity;

  _SparkTrailPainter({
    required this.trail,
    required this.headPosition,
    required this.color,
    required this.size,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (opacity <= 0) return;

    // Dessiner la traînée
    for (int i = 0; i < trail.length; i++) {
      final trailOpacity = (i / trail.length) * opacity * 0.6;
      final trailSize = size * 0.3 * (i / trail.length);

      // Point de traînée doré
      final trailPaint = Paint()
        ..color = const Color(0xFFFFD700).withOpacity(trailOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, trailSize * 0.5);
      canvas.drawCircle(trail[i], trailSize, trailPaint);

      // Point blanc au centre
      final whitePaint = Paint()
        ..color = Colors.white.withOpacity(trailOpacity * 0.8);
      canvas.drawCircle(trail[i], trailSize * 0.3, whitePaint);
    }

    // Tête de l'étincelle - glow extérieur doré
    final glowPaint = Paint()
      ..color = const Color(0xFFFFD700).withOpacity(opacity * 0.4)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 1.5);
    canvas.drawCircle(headPosition, size * 1.2, glowPaint);

    // Glow moyen blanc
    final midGlowPaint = Paint()
      ..color = Colors.white.withOpacity(opacity * 0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.8);
    canvas.drawCircle(headPosition, size * 0.8, midGlowPaint);

    // Centre brillant blanc
    final centerPaint = Paint()
      ..color = Colors.white.withOpacity(opacity * 0.9);
    canvas.drawCircle(headPosition, size * 0.4, centerPaint);

    // Étoile à 4 branches
    final starPaint = Paint()
      ..color = Colors.white.withOpacity(opacity * 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final starSize = size * 1.0;
    canvas.drawLine(
      Offset(headPosition.dx - starSize, headPosition.dy),
      Offset(headPosition.dx + starSize, headPosition.dy),
      starPaint,
    );
    canvas.drawLine(
      Offset(headPosition.dx, headPosition.dy - starSize),
      Offset(headPosition.dx, headPosition.dy + starSize),
      starPaint,
    );
  }

  @override
  bool shouldRepaint(_SparkTrailPainter oldDelegate) => true;
}

/// Overlay d'effet Sugar Rush - apparaît UNE SEULE FOIS
class SugarRushOverlay extends StatefulWidget {
  final VoidCallback? onComplete;

  const SugarRushOverlay({
    super.key,
    this.onComplete,
  });

  @override
  State<SugarRushOverlay> createState() => _SugarRushOverlayState();
}

class _SugarRushOverlayState extends State<SugarRushOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Confetti> _confettis = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _generateConfettis();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });

    _controller.forward();
  }

  void _generateConfettis() {
    final colors = [
      Colors.pink,
      Colors.yellow,
      Colors.orange,
      Colors.cyan,
      Colors.purple,
      Colors.lime,
      const Color(0xFFFFD700),
    ];

    for (int i = 0; i < 12; i++) {
      _confettis.add(_Confetti(
        x: _random.nextDouble(),
        y: -0.1 - _random.nextDouble() * 0.3,
        vx: (_random.nextDouble() - 0.5) * 0.15,
        vy: 0.35 + _random.nextDouble() * 0.25,
        size: 8 + _random.nextDouble() * 10,
        color: colors[_random.nextInt(colors.length)],
        rotation: _random.nextDouble() * math.pi,
        rotationSpeed: (_random.nextDouble() - 0.5) * 4,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _build3DText(String text, double fontSize, Color mainColor, Color darkColor, Color midColor) {
    return Stack(
      children: [
        // Couche 6 : Ombre la plus profonde
        Transform.translate(
          offset: const Offset(4, 8),
          child: Text(text, style: TextStyle(
            fontSize: fontSize, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
            color: Colors.black.withOpacity(0.5), letterSpacing: 5,
          )),
        ),
        // Couche 5 : Profondeur 3D
        Transform.translate(
          offset: const Offset(3, 6),
          child: Text(text, style: TextStyle(
            fontSize: fontSize, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
            color: Color.lerp(darkColor, Colors.black, 0.5)!, letterSpacing: 5,
          )),
        ),
        // Couche 4 : Profondeur 3D
        Transform.translate(
          offset: const Offset(2, 4),
          child: Text(text, style: TextStyle(
            fontSize: fontSize, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
            color: darkColor, letterSpacing: 5,
          )),
        ),
        // Couche 3 : Profondeur 3D
        Transform.translate(
          offset: const Offset(1, 2),
          child: Text(text, style: TextStyle(
            fontSize: fontSize, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
            color: midColor, letterSpacing: 5,
          )),
        ),
        // Couche 2 : Contour foncé
        Text(text, style: TextStyle(
          fontSize: fontSize, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
          letterSpacing: 5,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = darkColor,
        )),
        // Couche 1 : Dégradé principal
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(mainColor, Colors.white, 0.6)!,
              mainColor,
              Color.lerp(mainColor, Colors.black, 0.15)!,
            ],
          ).createShader(bounds),
          child: Text(text, style: TextStyle(
            fontSize: fontSize, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
            color: Colors.white, letterSpacing: 5,
          )),
        ),
        // Couche 0 : Reflet blanc
        Text(text, style: TextStyle(
          fontSize: fontSize, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
          letterSpacing: 5,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white.withOpacity(0.5),
        )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _controller.value;

          // Texte : apparaît vite, reste, disparaît
          double textOpacity;
          double textScale;
          if (progress < 0.10) {
            // Apparition rapide avec zoom
            textOpacity = progress / 0.10;
            textScale = 0.2 + (progress / 0.10) * 1.0;
          } else if (progress < 0.55) {
            // Reste visible
            textOpacity = 1.0;
            textScale = 1.2;
          } else {
            // Disparition
            textOpacity = 1 - (progress - 0.55) / 0.45;
            textScale = 1.2 + (progress - 0.55) / 0.45 * 0.3;
          }

          return Stack(
            children: [
              // Flash blanc initial
              if (progress < 0.15)
                Positioned.fill(
                  child: Container(
                    color: Colors.white.withOpacity((1 - progress / 0.15) * 0.4),
                  ),
                ),

              // Confettis
              CustomPaint(
                painter: _ConfettiPainter(
                  confettis: _confettis,
                  progress: progress,
                ),
                size: Size.infinite,
              ),

              // Titre SUGAR RUSH 3D
              Center(
                child: Opacity(
                  opacity: textOpacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: textScale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _build3DText('SUGAR', 56, const Color(0xFFFFD700), const Color(0xFFB8860B), const Color(0xFFFF8C00)),
                        _build3DText('RUSH!', 62, const Color(0xFFFF1493), const Color(0xFFAD1457), const Color(0xFFE91E63)),
                        const SizedBox(height: 10),
                        // Badge x5
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                offset: const Offset(2, 4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Text(
                            'SCORE x5',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              color: Colors.white,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Confetti {
  double x, y;
  double vx, vy;
  double size;
  Color color;
  double rotation;
  double rotationSpeed;

  _Confetti({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    this.rotation = 0,
    this.rotationSpeed = 0,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Confetti> confettis;
  final double progress;

  _ConfettiPainter({
    required this.confettis,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final confetti in confettis) {
      final x = (confetti.x + confetti.vx * progress) * size.width;
      final y = (confetti.y + confetti.vy * progress) * size.height;

      if (y > size.height + 30 || y < -30) continue;

      final opacity = progress > 0.75 ? (1 - (progress - 0.75) / 0.25) : 1.0;

      final paint = Paint()
        ..color = confetti.color.withOpacity(opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(confetti.rotation + confetti.rotationSpeed * progress);

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: confetti.size, height: confetti.size * 0.6),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => true;
}

/// Indicateur de multiplicateur x5
class SugarRushMultiplier extends StatefulWidget {
  const SugarRushMultiplier({super.key});

  @override
  State<SugarRushMultiplier> createState() => _SugarRushMultiplierState();
}

class _SugarRushMultiplierState extends State<SugarRushMultiplier>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + _pulseController.value * 0.1;

        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.5 + _pulseController.value * 0.3),
                  blurRadius: 8 + _pulseController.value * 4,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Text(
              'x5',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(color: Color(0xFFB8860B), blurRadius: 0, offset: Offset(1, 1)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Timer visuel pour Sugar Rush
class SugarRushTimer extends StatelessWidget {
  final double remainingSeconds;
  final double totalSeconds;

  const SugarRushTimer({
    super.key,
    required this.remainingSeconds,
    this.totalSeconds = 10,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (remainingSeconds / totalSeconds).clamp(0.0, 1.0);

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.5),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.5,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          Text(
            '${remainingSeconds.ceil()}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

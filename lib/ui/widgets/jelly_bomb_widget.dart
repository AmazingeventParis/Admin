import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/game_state.dart';

/// Widget représentant une Jelly Bomb avec animations
class JellyBombWidget extends StatefulWidget {
  /// Couleur de la bombe (teinte appliquée)
  final Color color;

  /// Taille du bloc en pixels
  final double size;

  /// État actuel de la bombe
  final BlockState state;

  /// Callback quand l'animation burst est terminée
  final VoidCallback? onBurstComplete;

  const JellyBombWidget({
    super.key,
    required this.color,
    required this.size,
    this.state = BlockState.idle,
    this.onBurstComplete,
  });

  @override
  State<JellyBombWidget> createState() => _JellyBombWidgetState();
}

class _JellyBombWidgetState extends State<JellyBombWidget>
    with TickerProviderStateMixin {
  // Animation de pulsation IDLE
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Animation de glow (alerte)
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  // Animation de burst (explosion)
  late AnimationController _burstController;
  late Animation<double> _burstScaleAnimation;
  late Animation<double> _burstOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  // Animation de brillance
  late AnimationController _shineController;
  late Animation<double> _shineAnimation;

  void _setupAnimations() {
    // Pulsation plus visible en IDLE (cycle continu)
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Animation de brillance (glow qui pulse)
    _shineController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _shineAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _shineController, curve: Curves.easeInOut),
    );

    // Animation glow (clignotement rapide)
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Animation burst (explosion)
    _burstController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _burstScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 0.0), weight: 70),
    ]).animate(CurvedAnimation(
      parent: _burstController,
      curve: Curves.easeOut,
    ));

    _burstOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 60),
    ]).animate(CurvedAnimation(
      parent: _burstController,
      curve: Curves.easeOut,
    ));

    _burstController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onBurstComplete?.call();
      }
    });

    _updateStateAnimation();
  }

  @override
  void didUpdateWidget(JellyBombWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _updateStateAnimation();
    }
  }

  void _updateStateAnimation() {
    switch (widget.state) {
      case BlockState.idle:
        _pulseController.repeat(reverse: true);
        _glowController.reset();
        _burstController.reset();
        break;
      case BlockState.glow:
        _pulseController.stop();
        _glowController.repeat(reverse: true);
        break;
      case BlockState.burst:
        _pulseController.stop();
        _glowController.stop();
        _burstController.forward(from: 0.0);
        break;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    _burstController.dispose();
    _shineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _pulseController,
        _glowController,
        _burstController,
        _shineController,
      ]),
      builder: (context, child) {
        // Déterminer les valeurs d'animation selon l'état
        double scale = 1.0;
        double glowIntensity = 0.0;
        double shineIntensity = 0.0;
        double opacity = 1.0;
        String spriteAsset = 'assets/ui/jelly_bomb_idle.png';

        switch (widget.state) {
          case BlockState.idle:
            scale = _pulseAnimation.value;
            shineIntensity = _shineAnimation.value;
            glowIntensity = 0.4 + (_shineAnimation.value * 0.4); // Toujours un peu de glow
            spriteAsset = 'assets/ui/jelly_bomb_idle.png';
            break;
          case BlockState.glow:
            scale = 1.0 + (_glowAnimation.value * 0.15);
            glowIntensity = 0.7 + (_glowAnimation.value * 0.3);
            shineIntensity = 1.0;
            spriteAsset = 'assets/ui/jelly_bomb_glow.png';
            break;
          case BlockState.burst:
            scale = _burstScaleAnimation.value;
            opacity = _burstOpacityAnimation.value;
            glowIntensity = 1.0;
            shineIntensity = 1.0;
            spriteAsset = 'assets/ui/jelly_bomb_burst.png';
            break;
        }

        if (opacity <= 0.01) {
          return SizedBox(width: widget.size, height: widget.size);
        }

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: _buildJellyBomb(spriteAsset, glowIntensity, shineIntensity),
          ),
        );
      },
    );
  }

  Widget _buildJellyBomb(String spriteAsset, double glowIntensity, double shineIntensity) {
    final borderRadius = BorderRadius.circular(widget.size * 0.15);
    final innerRadius = BorderRadius.circular(widget.size * 0.10);
    final borderWidth = widget.size * 0.06;

    // Couleur de glow basée sur la couleur du bloc - plus intense!
    final glowColor = widget.color;

    // Couleur secondaire pour effet arc-en-ciel
    final secondaryGlow = HSLColor.fromColor(widget.color)
        .withHue((HSLColor.fromColor(widget.color).hue + 40) % 360)
        .toColor();

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Padding(
        padding: EdgeInsets.all(widget.size * 0.02),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            // Cadre doré/brillant pour les Jelly Bombs
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(Colors.white, widget.color, 0.1 + shineIntensity * 0.1)!,
                Color.lerp(const Color(0xFFF5F5F5), widget.color, 0.05)!,
                Color.lerp(const Color(0xFFE0E0E0), widget.color, 0.1)!,
                Color.lerp(const Color(0xFFD0D0D0), widget.color, 0.05)!,
                Color.lerp(const Color(0xFFE8E8E8), widget.color, 0.1)!,
                Color.lerp(Colors.white, widget.color, 0.1 + shineIntensity * 0.1)!,
              ],
              stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
            ),
            boxShadow: [
              // Glow externe TRÈS visible - couleur principale
              BoxShadow(
                color: glowColor.withOpacity(0.5 + glowIntensity * 0.4),
                blurRadius: widget.size * (0.3 + glowIntensity * 0.5),
                spreadRadius: widget.size * (0.05 + glowIntensity * 0.15),
              ),
              // Glow secondaire pour effet arc-en-ciel
              BoxShadow(
                color: secondaryGlow.withOpacity(0.3 * shineIntensity),
                blurRadius: widget.size * (0.4 + shineIntensity * 0.3),
                spreadRadius: widget.size * 0.02,
              ),
              // Glow blanc brillant
              BoxShadow(
                color: Colors.white.withOpacity(0.4 + shineIntensity * 0.4),
                blurRadius: widget.size * 0.15,
                spreadRadius: widget.size * 0.02,
              ),
              // Ombre portée
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: widget.size * 0.08,
                offset: Offset(0, widget.size * 0.04),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(borderWidth),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: innerRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 2,
                    offset: const Offset(1, 1),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: innerRadius,
                child: Stack(
                  children: [
                    // Sprite de base avec teinte de couleur
                    Positioned.fill(
                      child: Image.asset(
                        spriteAsset,
                        fit: BoxFit.cover,
                        color: widget.color,
                        colorBlendMode: BlendMode.modulate,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback si l'image n'existe pas
                          return Container(
                            decoration: BoxDecoration(
                              color: widget.color,
                              borderRadius: innerRadius,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.flash_on,
                                color: Colors.white,
                                size: widget.size * 0.5,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Overlay de glow pendant l'état GLOW
                    if (glowIntensity > 0)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: innerRadius,
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withOpacity(glowIntensity * 0.6),
                                widget.color.withOpacity(glowIntensity * 0.3),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),

                    // Overlay dégradé pour effet glossy
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: innerRadius,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(0.5),
                              Colors.white.withOpacity(0.1),
                              Colors.transparent,
                              Colors.black.withOpacity(0.2),
                            ],
                            stops: const [0.0, 0.25, 0.6, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Reflet glossy en haut à gauche
                    Positioned(
                      top: widget.size * 0.06,
                      left: widget.size * 0.06,
                      child: Container(
                        width: widget.size * 0.30,
                        height: widget.size * 0.15,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(widget.size * 0.08),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.8),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Étoiles brillantes qui clignotent
                    Positioned(
                      top: widget.size * 0.12,
                      right: widget.size * 0.15,
                      child: Icon(
                        Icons.star,
                        color: Colors.white.withOpacity(0.6 + shineIntensity * 0.4),
                        size: widget.size * 0.15,
                      ),
                    ),
                    Positioned(
                      bottom: widget.size * 0.18,
                      left: widget.size * 0.12,
                      child: Icon(
                        Icons.star,
                        color: Colors.yellow.withOpacity(0.5 + (1 - shineIntensity) * 0.4),
                        size: widget.size * 0.12,
                      ),
                    ),

                    // Icône bomb au centre - plus grande et brillante
                    Center(
                      child: Icon(
                        Icons.auto_awesome,
                        color: Colors.white.withOpacity(0.9),
                        size: widget.size * 0.4,
                        shadows: [
                          Shadow(
                            color: widget.color.withOpacity(0.8),
                            blurRadius: 8,
                            offset: Offset.zero,
                          ),
                          Shadow(
                            color: Colors.white.withOpacity(0.5),
                            blurRadius: 4,
                            offset: const Offset(-1, -1),
                          ),
                          Shadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 4,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                    ),

                    // Anneau de brillance qui pulse
                    if (shineIntensity > 0.5)
                      Positioned.fill(
                        child: Container(
                          margin: EdgeInsets.all(widget.size * 0.1),
                          decoration: BoxDecoration(
                            borderRadius: innerRadius,
                            border: Border.all(
                              color: Colors.white.withOpacity((shineIntensity - 0.5) * 0.6),
                              width: 2,
                            ),
                          ),
                        ),
                      ),

                    // Étincelles animées sur la Jelly Bomb
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _JellySparkPainter(
                          time: _shineAnimation.value,
                          blockSize: widget.size,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Painter d'étincelles pour les Jelly Bombs
class _JellySparkPainter extends CustomPainter {
  final double time;
  final double blockSize;

  _JellySparkPainter({required this.time, required this.blockSize});

  @override
  void paint(Canvas canvas, Size size) {
    // 3 étincelles bien visibles
    for (int i = 0; i < 3; i++) {
      final rng = math.Random(i * 13 + 7);
      final baseX = rng.nextDouble() * size.width * 0.6 + size.width * 0.2;
      final baseY = rng.nextDouble() * size.height * 0.5 + size.height * 0.15;

      final phase = (time + i * 0.33) % 1.0;

      double opacity;
      if (phase < 0.1) {
        opacity = phase / 0.1;
      } else if (phase < 0.30) {
        opacity = 1.0;
      } else if (phase < 0.45) {
        opacity = 1.0 - (phase - 0.30) / 0.15;
      } else {
        opacity = 0.0;
      }

      if (opacity <= 0) continue;

      final sparkSize = blockSize * 0.15;

      // Glow blanc
      final glowPaint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.7)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sparkSize * 2.0);
      canvas.drawCircle(Offset(baseX, baseY), sparkSize * 1.8, glowPaint);

      // Centre blanc vif
      final centerPaint = Paint()
        ..color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(baseX, baseY), sparkSize * 0.5, centerPaint);

      // Étoile 4+4 branches
      final starPaint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.9)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      final armLen = sparkSize * 2.0 * (0.6 + 0.4 * math.sin(phase * math.pi * 2));
      canvas.drawLine(Offset(baseX - armLen, baseY), Offset(baseX + armLen, baseY), starPaint);
      canvas.drawLine(Offset(baseX, baseY - armLen), Offset(baseX, baseY + armLen), starPaint);
      final diagLen = armLen * 0.6;
      final diagPaint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.5)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(baseX - diagLen, baseY - diagLen), Offset(baseX + diagLen, baseY + diagLen), diagPaint);
      canvas.drawLine(Offset(baseX + diagLen, baseY - diagLen), Offset(baseX - diagLen, baseY + diagLen), diagPaint);
    }
  }

  @override
  bool shouldRepaint(_JellySparkPainter oldDelegate) => oldDelegate.time != time;
}

/// Widget pour l'effet de particules d'explosion de Jelly Bomb - OPTIMISÉ
class JellyBombExplosionEffect extends StatefulWidget {
  final Offset position;
  final Color color;
  final double cellSize;
  final VoidCallback onComplete;

  const JellyBombExplosionEffect({
    super.key,
    required this.position,
    required this.color,
    required this.cellSize,
    required this.onComplete,
  });

  @override
  State<JellyBombExplosionEffect> createState() => _JellyBombExplosionEffectState();
}

class _JellyBombExplosionEffectState extends State<JellyBombExplosionEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_JellyParticle> _particles = [];
  final List<_SmokeParticle> _smokeParticles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    // Animation unique plus courte
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _generateParticles();
    _generateSmoke();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });

    _controller.forward();
  }

  void _generateParticles() {
    // Moins de particules mais toujours visible (12-16)
    final count = 12 + _random.nextInt(5);

    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi + _random.nextDouble() * 0.3;
      final speed = 80 + _random.nextDouble() * 100;
      final size = 4 + _random.nextDouble() * 6;

      // Couleurs simples
      Color particleColor;
      final colorChoice = _random.nextDouble();
      if (colorChoice < 0.5) {
        particleColor = widget.color;
      } else if (colorChoice < 0.7) {
        particleColor = Colors.white;
      } else {
        particleColor = Color.lerp(widget.color, Colors.white, 0.5)!;
      }

      _particles.add(_JellyParticle(
        x: widget.position.dx,
        y: widget.position.dy,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 40,
        size: size,
        color: particleColor,
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 8,
        isJelly: true,
        delay: 0,
      ));
    }
  }

  void _generateSmoke() {
    // Particules de fumée qui montent et s'évaporent
    final count = 5 + _random.nextInt(3);

    for (int i = 0; i < count; i++) {
      final spreadX = (_random.nextDouble() - 0.5) * widget.cellSize;

      _smokeParticles.add(_SmokeParticle(
        x: widget.position.dx + spreadX,
        y: widget.position.dy,
        vx: (_random.nextDouble() - 0.5) * 15,
        vy: -40 - _random.nextDouble() * 30, // Monte vers le haut
        size: widget.cellSize * (0.4 + _random.nextDouble() * 0.3),
        opacity: 0.4 + _random.nextDouble() * 0.2,
        delay: 0.1 + _random.nextDouble() * 0.15, // Apparaît après l'explosion
      ));
    }
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
        final progress = _controller.value;

        return Stack(
          children: [
            // Flash d'explosion simple
            if (progress < 0.3)
              Positioned(
                left: widget.position.dx - widget.cellSize * 1.5,
                top: widget.position.dy - widget.cellSize * 1.5,
                child: Container(
                  width: widget.cellSize * 3,
                  height: widget.cellSize * 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withOpacity((1 - progress / 0.3) * 0.8),
                        widget.color.withOpacity((1 - progress / 0.3) * 0.4),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),

            // Un seul anneau de shockwave
            if (progress < 0.8)
              CustomPaint(
                painter: _SimpleShockwavePainter(
                  progress: progress,
                  center: widget.position,
                  color: widget.color,
                  maxRadius: widget.cellSize * 2.5,
                ),
                size: Size.infinite,
              ),

            // Particules simplifiées
            CustomPaint(
              painter: _SimpleParticlePainter(
                particles: _particles,
                progress: progress,
              ),
              size: Size.infinite,
            ),

            // Fumée qui s'évapore (apparaît après le flash)
            if (progress > 0.1)
              CustomPaint(
                painter: _SmokePainter(
                  particles: _smokeParticles,
                  progress: progress,
                  baseColor: widget.color,
                ),
                size: Size.infinite,
            ),
          ],
        );
      },
    );
  }
}

class _JellyParticle {
  double x, y;
  double vx, vy;
  double size;
  Color color;
  double rotation;
  double rotationSpeed;
  bool isJelly;
  double delay;

  _JellyParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
    required this.isJelly,
    this.delay = 0,
  });
}

/// Painter simplifié pour les particules
class _SimpleParticlePainter extends CustomPainter {
  final List<_JellyParticle> particles;
  final double progress;

  _SimpleParticlePainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final easeProgress = Curves.easeOut.transform(progress);

    for (final particle in particles) {
      // Position avec gravité légère
      final gravity = 200.0;
      final x = particle.x + particle.vx * easeProgress;
      final y = particle.y + particle.vy * easeProgress + gravity * easeProgress * easeProgress;

      // Taille qui diminue
      final currentSize = particle.size * (1 - progress * 0.6);

      // Opacité qui diminue
      final opacity = (1 - progress).clamp(0.0, 1.0);

      if (opacity <= 0 || currentSize <= 0) continue;

      final paint = Paint()
        ..color = particle.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      // Simple cercle (pas d'ovale, pas de rotation, pas de glow)
      canvas.drawCircle(Offset(x, y), currentSize / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_SimpleParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Painter simplifié pour le shockwave
class _SimpleShockwavePainter extends CustomPainter {
  final double progress;
  final Offset center;
  final Color color;
  final double maxRadius;

  _SimpleShockwavePainter({
    required this.progress,
    required this.center,
    required this.color,
    required this.maxRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final easeProgress = Curves.easeOut.transform(progress);
    final radius = maxRadius * easeProgress;
    final opacity = (1 - progress * 1.2).clamp(0.0, 1.0);

    if (opacity <= 0) return;

    final strokeWidth = (4.0 * (1 - progress * 0.5)).clamp(1.0, 4.0);

    final paint = Paint()
      ..color = color.withOpacity(opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_SimpleShockwavePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Particule de fumée pour l'explosion
class _SmokeParticle {
  double x, y;
  double vx, vy;
  double size;
  double opacity;
  double delay;

  _SmokeParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.opacity,
    required this.delay,
  });
}

/// Painter pour la fumée qui s'évapore
class _SmokePainter extends CustomPainter {
  final List<_SmokeParticle> particles;
  final double progress;
  final Color baseColor;

  _SmokePainter({
    required this.particles,
    required this.progress,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      // Appliquer le délai
      final adjustedProgress = ((progress - particle.delay) / (1 - particle.delay)).clamp(0.0, 1.0);
      if (adjustedProgress <= 0) continue;

      final easeProgress = Curves.easeOut.transform(adjustedProgress);

      // Position - monte et dérive légèrement
      final x = particle.x + particle.vx * easeProgress;
      final y = particle.y + particle.vy * easeProgress;

      // La fumée s'étend en montant (grossit de 2x)
      final currentSize = particle.size * (1 + easeProgress * 1.5);

      // Opacité - fade out progressif (s'évapore)
      final opacity = particle.opacity * (1 - adjustedProgress).clamp(0.0, 1.0);

      if (opacity <= 0.02) continue;

      // Fumée semi-transparente avec flou léger
      final paint = Paint()
        ..color = baseColor.withOpacity(opacity * 0.4)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, currentSize * 0.3);

      canvas.drawCircle(Offset(x, y), currentSize, paint);

      // Centre plus clair (coeur de fumée)
      final centerPaint = Paint()
        ..color = Color.lerp(baseColor, Colors.white, 0.4)!.withOpacity(opacity * 0.25)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, currentSize * 0.2);

      canvas.drawCircle(Offset(x, y), currentSize * 0.5, centerPaint);
    }
  }

  @override
  bool shouldRepaint(_SmokePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

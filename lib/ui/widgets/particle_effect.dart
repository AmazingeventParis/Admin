import 'dart:math';
import 'package:flutter/material.dart';

/// Particule individuelle - style étoile/sparkle
class Particle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  Color color;
  double rotation;
  double rotationSpeed;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
  });
}

/// Widget d'effet de particules subtil style étoiles
class ParticleEffect extends StatefulWidget {
  final Offset position;
  final Color color;
  final double size;
  final VoidCallback? onComplete;

  const ParticleEffect({
    super.key,
    required this.position,
    required this.color,
    this.size = 50,
    this.onComplete,
  });

  @override
  State<ParticleEffect> createState() => _ParticleEffectState();
}

class _ParticleEffectState extends State<ParticleEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _generateParticles();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete?.call();
        }
      });
    _controller.forward();
  }

  void _generateParticles() {
    // Particules style Block Puzzle - petites et rapides
    final count = 6 + _random.nextInt(4);
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi + _random.nextDouble() * 0.5;
      final speed = 40 + _random.nextDouble() * 60;
      final size = 2 + _random.nextDouble() * 3;

      // Couleur : originale ou blanche
      final newColor = _random.nextBool() ? widget.color : Colors.white;

      _particles.add(Particle(
        x: widget.position.dx,
        y: widget.position.dy,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 20,
        size: size,
        color: newColor,
        rotation: _random.nextDouble() * pi,
        rotationSpeed: (_random.nextDouble() - 0.5) * 8,
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

        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            progress: progress,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double progress;

  _ParticlePainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      // Animation rapide
      final easeProgress = Curves.easeOut.transform(progress);

      // Position
      final x = particle.x + particle.vx * easeProgress;
      final y = particle.y + particle.vy * easeProgress + 30 * easeProgress * easeProgress;

      // Taille qui diminue vite
      final currentSize = particle.size * (1 - progress * 0.7);

      // Opacité - fade out rapide
      final opacity = (1 - progress * 1.2).clamp(0.0, 1.0);

      if (opacity <= 0.05 || currentSize <= 0.3) continue;

      // Particule simple - petit cercle
      final paint = Paint()
        ..color = particle.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), currentSize, paint);

      // Point blanc au centre pour l'éclat
      if (particle.color != Colors.white) {
        final centerPaint = Paint()
          ..color = Colors.white.withOpacity(opacity * 0.8);
        canvas.drawCircle(Offset(x, y), currentSize * 0.4, centerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Particule de fumée
class _SmokeParticle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  double opacity;
  double expansionRate;

  _SmokeParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.opacity,
    required this.expansionRate,
  });
}

/// Widget d'effet de fumée qui s'évapore
class SmokeEffect extends StatefulWidget {
  final Offset position;
  final Color color;
  final double intensity; // 1.0 = normal, 2.0 = intense
  final VoidCallback? onComplete;

  const SmokeEffect({
    super.key,
    required this.position,
    this.color = const Color(0xFF888888), // Gris par défaut
    this.intensity = 1.0,
    this.onComplete,
  });

  @override
  State<SmokeEffect> createState() => _SmokeEffectState();
}

class _SmokeEffectState extends State<SmokeEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_SmokeParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _generateSmokeParticles();
    _controller = AnimationController(
      duration: Duration(milliseconds: (800 * widget.intensity).toInt()),
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete?.call();
        }
      });
    _controller.forward();
  }

  void _generateSmokeParticles() {
    // Nombre de particules basé sur l'intensité
    final count = (8 + _random.nextInt(5) * widget.intensity).toInt();

    for (int i = 0; i < count; i++) {
      // Dispersion horizontale légère, mouvement vers le haut
      final spreadX = (_random.nextDouble() - 0.5) * 30 * widget.intensity;
      final speedY = -30 - _random.nextDouble() * 40 * widget.intensity; // Monte vers le haut
      final driftX = (_random.nextDouble() - 0.5) * 20; // Dérive latérale

      _particles.add(_SmokeParticle(
        x: widget.position.dx + spreadX,
        y: widget.position.dy,
        vx: driftX,
        vy: speedY,
        size: 8 + _random.nextDouble() * 12 * widget.intensity,
        opacity: 0.4 + _random.nextDouble() * 0.3,
        expansionRate: 1.5 + _random.nextDouble() * 1.0, // La fumée s'étend
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
        return CustomPaint(
          painter: _SmokePainter(
            particles: _particles,
            progress: _controller.value,
            baseColor: widget.color,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

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
      // Courbe de progression douce pour la fumée
      final easeProgress = Curves.easeOut.transform(progress);

      // Position - monte et dérive
      final x = particle.x + particle.vx * easeProgress;
      final y = particle.y + particle.vy * easeProgress;

      // La fumée s'étend en montant
      final currentSize = particle.size * (1 + easeProgress * particle.expansionRate);

      // Opacité - fade out progressif (s'évapore)
      final opacity = particle.opacity * (1 - easeProgress).clamp(0.0, 1.0);

      if (opacity <= 0.02) continue;

      // Dessiner plusieurs cercles flous pour simuler la fumée
      final paint = Paint()
        ..color = baseColor.withOpacity(opacity * 0.5)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, currentSize * 0.4);

      // Cercle principal de fumée
      canvas.drawCircle(Offset(x, y), currentSize, paint);

      // Cercle intérieur plus clair (coeur de la fumée)
      final innerPaint = Paint()
        ..color = Color.lerp(baseColor, Colors.white, 0.3)!.withOpacity(opacity * 0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, currentSize * 0.3);

      canvas.drawCircle(Offset(x, y), currentSize * 0.6, innerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SmokePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Effet de fumée colorée (pour les explosions de Jelly Bomb)
class ColoredSmokeEffect extends StatefulWidget {
  final Offset position;
  final Color color;
  final double size;
  final VoidCallback? onComplete;

  const ColoredSmokeEffect({
    super.key,
    required this.position,
    required this.color,
    this.size = 40,
    this.onComplete,
  });

  @override
  State<ColoredSmokeEffect> createState() => _ColoredSmokeEffectState();
}

class _ColoredSmokeEffectState extends State<ColoredSmokeEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_SmokeParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _generateParticles();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete?.call();
        }
      });
    _controller.forward();
  }

  void _generateParticles() {
    final count = 6 + _random.nextInt(4);

    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi;
      final spread = 10 + _random.nextDouble() * 15;

      _particles.add(_SmokeParticle(
        x: widget.position.dx + cos(angle) * spread,
        y: widget.position.dy + sin(angle) * spread,
        vx: cos(angle) * 15 + (_random.nextDouble() - 0.5) * 10,
        vy: -25 - _random.nextDouble() * 20, // Monte
        size: widget.size * (0.3 + _random.nextDouble() * 0.4),
        opacity: 0.5 + _random.nextDouble() * 0.3,
        expansionRate: 1.2 + _random.nextDouble() * 0.8,
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
        return CustomPaint(
          painter: _ColoredSmokePainter(
            particles: _particles,
            progress: _controller.value,
            baseColor: widget.color,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _ColoredSmokePainter extends CustomPainter {
  final List<_SmokeParticle> particles;
  final double progress;
  final Color baseColor;

  _ColoredSmokePainter({
    required this.particles,
    required this.progress,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final easeProgress = Curves.easeOut.transform(progress);

      final x = particle.x + particle.vx * easeProgress;
      final y = particle.y + particle.vy * easeProgress;

      // S'étend en s'évaporant
      final currentSize = particle.size * (1 + easeProgress * particle.expansionRate);

      // Fade out
      final opacity = particle.opacity * pow(1 - progress, 1.5).clamp(0.0, 1.0);

      if (opacity <= 0.02) continue;

      // Fumée colorée avec flou
      final paint = Paint()
        ..color = baseColor.withOpacity(opacity * 0.6)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, currentSize * 0.5);

      canvas.drawCircle(Offset(x, y), currentSize, paint);

      // Centre plus lumineux
      final centerPaint = Paint()
        ..color = Color.lerp(baseColor, Colors.white, 0.5)!.withOpacity(opacity * 0.4)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, currentSize * 0.3);

      canvas.drawCircle(Offset(x, y), currentSize * 0.5, centerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ColoredSmokePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

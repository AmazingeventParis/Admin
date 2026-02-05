import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Widget représentant une brique 1x1 avec effet glossy "bonbon" et étincelles
class BlockWidget extends StatefulWidget {
  /// Couleur de la brique
  final Color color;

  /// Taille de la brique en pixels
  final double size;

  /// Afficher les étincelles (seulement pour les briques jelly sur le plateau)
  final bool showSparkle;

  const BlockWidget({
    super.key,
    required this.color,
    required this.size,
    this.showSparkle = false,
  });

  @override
  State<BlockWidget> createState() => _BlockWidgetState();
}

class _BlockWidgetState extends State<BlockWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _sparkleController;
  late int _seed;

  @override
  void initState() {
    super.initState();
    _seed = (widget.color.value + widget.size.hashCode) % 10000;
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _sparkleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final color = widget.color;
    final borderRadius = BorderRadius.circular(size * 0.15);
    final innerRadius = BorderRadius.circular(size * 0.10);
    final borderWidth = size * 0.06;

    return SizedBox(
      width: size,
      height: size,
      child: Padding(
        padding: EdgeInsets.all(size * 0.02),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            // Cadre blanc avec dégradé argenté
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFFFFF), // Blanc pur
                Color(0xFFF5F5F5), // Gris très clair
                Color(0xFFE0E0E0), // Gris clair
                Color(0xFFD0D0D0), // Gris moyen
                Color(0xFFE8E8E8), // Gris clair
                Color(0xFFFFFFFF), // Blanc pur
              ],
              stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
            ),
            boxShadow: [
              // Glow blanc externe
              BoxShadow(
                color: Colors.white.withOpacity(0.6),
                blurRadius: size * 0.10,
                spreadRadius: size * 0.01,
              ),
              // Ombre portée
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: size * 0.08,
                offset: Offset(0, size * 0.04),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(borderWidth),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: innerRadius,
                boxShadow: [
                  // Ombre interne du cadre
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
                    // Image de base colorée
                    Positioned.fill(
                      child: Image.asset(
                        'assets/blocks/block_base2.png',
                        fit: BoxFit.cover,
                        color: color,
                        colorBlendMode: BlendMode.modulate,
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
                      top: size * 0.06,
                      left: size * 0.06,
                      child: Container(
                        width: size * 0.30,
                        height: size * 0.15,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(size * 0.08),
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

                    // Étincelle animée (seulement jelly sur le plateau)
                    if (widget.showSparkle)
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _sparkleController,
                          builder: (context, _) {
                            return CustomPaint(
                              painter: _BlockSparklePainter(
                                time: _sparkleController.value,
                                seed: _seed,
                                blockSize: size - borderWidth * 2 - size * 0.04,
                              ),
                            );
                          },
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

/// Painter pour les étincelles sur les briques jelly
class _BlockSparklePainter extends CustomPainter {
  final double time;
  final int seed;
  final double blockSize;

  _BlockSparklePainter({
    required this.time,
    required this.seed,
    required this.blockSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);

    // 3 étincelles par brique, bien visibles
    for (int i = 0; i < 3; i++) {
      // Positions réparties sur la surface
      final baseX = rng.nextDouble() * size.width * 0.6 + size.width * 0.2;
      final baseY = rng.nextDouble() * size.height * 0.5 + size.height * 0.15;

      // Phase décalée pour chaque étincelle (apparition en décalé)
      final phase = (time + i * 0.33 + seed * 0.001) % 1.0;

      // Visible pendant une bonne partie du cycle
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

      final sparkSize = blockSize * 0.18;

      // Glow blanc large
      final glowPaint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.7)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sparkSize * 2.0);
      canvas.drawCircle(Offset(baseX, baseY), sparkSize * 1.8, glowPaint);

      // Centre blanc vif
      final centerPaint = Paint()
        ..color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(baseX, baseY), sparkSize * 0.5, centerPaint);

      // Étoile 4 branches bien visible
      final starPaint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.9)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      final armLen = sparkSize * 2.0 * (0.6 + 0.4 * math.sin(phase * math.pi * 2));
      // Branches horizontales et verticales
      canvas.drawLine(
        Offset(baseX - armLen, baseY),
        Offset(baseX + armLen, baseY),
        starPaint,
      );
      canvas.drawLine(
        Offset(baseX, baseY - armLen),
        Offset(baseX, baseY + armLen),
        starPaint,
      );
      // Branches diagonales (plus petites)
      final diagLen = armLen * 0.6;
      final diagPaint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.5)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(baseX - diagLen, baseY - diagLen),
        Offset(baseX + diagLen, baseY + diagLen),
        diagPaint,
      );
      canvas.drawLine(
        Offset(baseX + diagLen, baseY - diagLen),
        Offset(baseX - diagLen, baseY + diagLen),
        diagPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_BlockSparklePainter oldDelegate) =>
      oldDelegate.time != time;
}

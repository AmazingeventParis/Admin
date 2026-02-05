import 'package:flutter/material.dart';
import 'block_widget.dart';

/// Couleurs damier rose (style référence) - ORIGINALES
// const Color kCellPinkDark = Color(0xFFE85A8F);
// const Color kCellPinkLight = Color(0xFFF598B6);

/// Couleurs damier gris foncé (TEST)
const Color kCellPinkDark = Color(0xFF3A3A3A);
const Color kCellPinkLight = Color(0xFF4A4A4A);

/// Widget représentant une cellule de la grille (vide ou occupée)
class CellWidget extends StatelessWidget {
  /// Taille de la cellule en pixels (utilisée pour les proportions)
  final double size;

  /// Position X dans la grille (pour le damier)
  final int x;

  /// Position Y dans la grille (pour le damier)
  final int y;

  /// True si la cellule est occupée
  final bool isOccupied;

  /// Couleur de la brique (si occupée)
  final Color? blockColor;

  const CellWidget({
    super.key,
    required this.size,
    required this.x,
    required this.y,
    this.isOccupied = false,
    this.blockColor,
  });

  @override
  Widget build(BuildContext context) {
    // Alterner les couleurs en damier
    final isLightCell = (x + y) % 2 == 0;
    final baseColor = isLightCell ? kCellPinkLight : kCellPinkDark;

    // Couleurs pour l'effet 3D
    final highlightColor = Color.lerp(baseColor, Colors.white, 0.3)!;
    final shadowColor = Color.lerp(baseColor, Colors.black, 0.3)!;
    final topLeftColor = Color.lerp(baseColor, Colors.white, 0.15)!;
    final bottomRightColor = Color.lerp(baseColor, Colors.black, 0.15)!;

    return Container(
      decoration: BoxDecoration(
        // Gradient pour effet de profondeur
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            topLeftColor,
            baseColor,
            bottomRightColor,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        // Bordures 3D
        border: Border(
          top: BorderSide(color: highlightColor, width: 2),
          left: BorderSide(color: highlightColor, width: 2),
          bottom: BorderSide(color: shadowColor, width: 2),
          right: BorderSide(color: shadowColor, width: 2),
        ),
      ),
      child: isOccupied && blockColor != null
          ? BlockWidget(
              color: blockColor!,
              size: size,
            )
          : null,
    );
  }
}

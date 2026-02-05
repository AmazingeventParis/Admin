import 'package:flutter/material.dart';
import '../../models/piece.dart';
import 'piece_widget.dart';

/// Couleurs du tray
const Color kTrayBackgroundColor = Color(0xFF1A1A1A);
const Color kSlotBackgroundColor = Color(0xFF252525);
const Color kSlotBorderColor = Color(0xFF333333);

/// Widget affichant la zone des 3 pièces disponibles en bas de l'écran
class PiecesTrayWidget extends StatelessWidget {
  /// Liste des pièces disponibles (max 3)
  final List<Piece?> pieces;

  /// Taille d'une brique dans les pièces du tray
  final double blockSize;

  /// Hauteur totale de la zone
  final double height;

  const PiecesTrayWidget({
    super.key,
    required this.pieces,
    required this.blockSize,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        // Fond sombre doux
        color: kTrayBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        // Bordure subtile
        border: Border.all(
          color: kSlotBorderColor.withOpacity(0.5),
          width: 1,
        ),
        // Ombre douce
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (index) {
          final piece = index < pieces.length ? pieces[index] : null;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _buildSlot(piece),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSlot(Piece? piece) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        decoration: BoxDecoration(
          // Fond du slot légèrement plus clair
          color: kSlotBackgroundColor,
          borderRadius: BorderRadius.circular(14),
          // Bordure douce
          border: Border.all(
            color: kSlotBorderColor,
            width: 1,
          ),
          // Effet légèrement enfoncé
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
              blurStyle: BlurStyle.inner,
            ),
          ],
        ),
        child: Center(
          child: piece != null
              ? PieceWidget(
                  piece: piece,
                  blockSize: blockSize,
                )
              : null,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../models/piece.dart';
import 'block_widget.dart';

/// Widget pour afficher une pièce de puzzle avec effet glossy/candy
class PieceWidget extends StatelessWidget {
  final Piece piece;
  final double blockSize;

  const PieceWidget({
    super.key,
    required this.piece,
    this.blockSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    // Calculer les dimensions de la pièce
    int minX = 0, maxX = 0, minY = 0, maxY = 0;
    for (final block in piece.blocks) {
      if (block.x < minX) minX = block.x;
      if (block.x > maxX) maxX = block.x;
      if (block.y < minY) minY = block.y;
      if (block.y > maxY) maxY = block.y;
    }

    final width = (maxX - minX + 1) * blockSize;
    final height = (maxY - minY + 1) * blockSize;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: piece.blocks.map((block) {
          return Positioned(
            left: (block.x - minX) * blockSize,
            top: (block.y - minY) * blockSize,
            child: BlockWidget(
              color: piece.color,
              size: blockSize,
            ),
          );
        }).toList(),
      ),
    );
  }
}

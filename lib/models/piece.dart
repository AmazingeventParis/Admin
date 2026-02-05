import 'dart:ui';

/// Représente une position relative dans une pièce
class BlockPosition {
  final int x;
  final int y;

  const BlockPosition(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockPosition && x == other.x && y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;

  @override
  String toString() => 'BlockPosition($x, $y)';
}

/// Représente une pièce composée de plusieurs briques
class Piece {
  /// Liste des positions relatives des briques qui composent la pièce
  final List<BlockPosition> blocks;

  /// Couleur de la pièce
  final Color color;

  const Piece({
    required this.blocks,
    required this.color,
  });

  /// Largeur de la pièce (nombre de colonnes)
  int get width {
    if (blocks.isEmpty) return 0;
    final maxX = blocks.map((b) => b.x).reduce((a, b) => a > b ? a : b);
    final minX = blocks.map((b) => b.x).reduce((a, b) => a < b ? a : b);
    return maxX - minX + 1;
  }

  /// Hauteur de la pièce (nombre de lignes)
  int get height {
    if (blocks.isEmpty) return 0;
    final maxY = blocks.map((b) => b.y).reduce((a, b) => a > b ? a : b);
    final minY = blocks.map((b) => b.y).reduce((a, b) => a < b ? a : b);
    return maxY - minY + 1;
  }

  /// Normalise les positions pour que la pièce commence à (0,0)
  Piece normalize() {
    if (blocks.isEmpty) return this;

    final minX = blocks.map((b) => b.x).reduce((a, b) => a < b ? a : b);
    final minY = blocks.map((b) => b.y).reduce((a, b) => a < b ? a : b);

    return Piece(
      blocks: blocks
          .map((b) => BlockPosition(b.x - minX, b.y - minY))
          .toList(),
      color: color,
    );
  }
}

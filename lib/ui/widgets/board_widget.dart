import 'package:flutter/material.dart';
import '../../models/game_state.dart';
import 'cell_widget.dart';

/// Widget représentant le plateau de jeu 10x10
class BoardWidget extends StatelessWidget {
  final GameState gameState;
  final double size;

  const BoardWidget({
    super.key,
    required this.gameState,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        children: List.generate(GameState.gridSize, (y) {
          return Expanded(
            child: Row(
              children: List.generate(GameState.gridSize, (x) {
                final cell = gameState.grid[y][x];
                return Expanded(
                  child: CellWidget(
                    size: size / GameState.gridSize,
                    x: x,
                    y: y,
                    isOccupied: cell.occupied,
                    blockColor: cell.color,
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}

import '../models/models.dart';

/// Logique du jeu Block Puzzle
/// Cette classe contiendra les règles du jeu (à implémenter)
class GameLogic {
  /// Vérifie si une pièce peut être placée à une position donnée
  static bool canPlacePiece(GameState state, Piece piece, int startX, int startY) {
    for (final block in piece.blocks) {
      final x = startX + block.x;
      final y = startY + block.y;

      // Vérifie si la position est hors de la grille
      if (!state.isValidPosition(x, y)) {
        return false;
      }

      // Vérifie si la cellule est déjà occupée
      if (state.isCellOccupied(x, y)) {
        return false;
      }
    }

    return true;
  }

  /// Place une pièce sur le plateau
  static GameState placePiece(GameState state, Piece piece, int startX, int startY) {
    if (!canPlacePiece(state, piece, startX, startY)) {
      return state;
    }

    var newState = state;
    for (final block in piece.blocks) {
      newState = newState.setCellAt(
        startX + block.x,
        startY + block.y,
        Cell.filled(piece.color),
      );
    }

    return newState;
  }

  /// Vérifie si une ligne est complète (à implémenter)
  static List<int> getCompleteRows(GameState state) {
    final completeRows = <int>[];

    for (int y = 0; y < GameState.gridSize; y++) {
      bool isComplete = true;
      for (int x = 0; x < GameState.gridSize; x++) {
        if (!state.grid[y][x].occupied) {
          isComplete = false;
          break;
        }
      }
      if (isComplete) {
        completeRows.add(y);
      }
    }

    return completeRows;
  }

  /// Vérifie si une colonne est complète (à implémenter)
  static List<int> getCompleteColumns(GameState state) {
    final completeColumns = <int>[];

    for (int x = 0; x < GameState.gridSize; x++) {
      bool isComplete = true;
      for (int y = 0; y < GameState.gridSize; y++) {
        if (!state.grid[y][x].occupied) {
          isComplete = false;
          break;
        }
      }
      if (isComplete) {
        completeColumns.add(x);
      }
    }

    return completeColumns;
  }

  /// Efface les lignes et colonnes complètes (à implémenter)
  static GameState clearCompleteLinesAndColumns(GameState state) {
    final completeRows = getCompleteRows(state);
    final completeColumns = getCompleteColumns(state);

    if (completeRows.isEmpty && completeColumns.isEmpty) {
      return state;
    }

    var newState = state;

    // Efface les lignes complètes
    for (final row in completeRows) {
      for (int x = 0; x < GameState.gridSize; x++) {
        newState = newState.setCellAt(x, row, Cell.empty);
      }
    }

    // Efface les colonnes complètes
    for (final col in completeColumns) {
      for (int y = 0; y < GameState.gridSize; y++) {
        newState = newState.setCellAt(col, y, Cell.empty);
      }
    }

    return newState;
  }
}

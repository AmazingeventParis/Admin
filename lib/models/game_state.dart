import 'dart:ui';

/// Types de blocs disponibles
enum BlockType {
  normal,    // Bloc standard
  jellyBomb, // Bombe gelée qui explose en 3x3
}

/// États d'un bloc spécial (JellyBomb)
enum BlockState {
  idle,  // État normal avec légère pulsation
  glow,  // Phase d'alerte avant explosion (200ms)
  burst, // Explosion en cours
}

/// Représente une cellule du plateau
class Cell {
  /// True si la cellule est occupée par une brique
  final bool occupied;

  /// Couleur de la brique (null si non occupée)
  final Color? color;

  /// Type de bloc (normal ou spécial)
  final BlockType blockType;

  /// État du bloc (pour les blocs spéciaux)
  final BlockState blockState;

  const Cell({
    this.occupied = false,
    this.color,
    this.blockType = BlockType.normal,
    this.blockState = BlockState.idle,
  });

  /// Cellule vide
  static const Cell empty = Cell(occupied: false, color: null);

  /// Crée une cellule occupée avec une couleur (bloc normal)
  factory Cell.filled(Color color) => Cell(
    occupied: true,
    color: color,
    blockType: BlockType.normal,
    blockState: BlockState.idle,
  );

  /// Crée une cellule avec une Jelly Bomb
  factory Cell.jellyBomb(Color color) => Cell(
    occupied: true,
    color: color,
    blockType: BlockType.jellyBomb,
    blockState: BlockState.idle,
  );

  /// Vérifie si c'est une Jelly Bomb
  bool get isJellyBomb => blockType == BlockType.jellyBomb;

  /// Crée une copie avec un nouvel état
  Cell copyWith({
    bool? occupied,
    Color? color,
    BlockType? blockType,
    BlockState? blockState,
  }) {
    return Cell(
      occupied: occupied ?? this.occupied,
      color: color ?? this.color,
      blockType: blockType ?? this.blockType,
      blockState: blockState ?? this.blockState,
    );
  }

  @override
  String toString() => occupied ? (isJellyBomb ? 'B' : 'X') : '.';
}

/// État du jeu contenant la grille et les données
class GameState {
  /// Taille de la grille (8x8)
  static const int gridSize = 8;

  /// La grille 10x10 de cellules
  /// grid[y][x] - y = ligne (0 = haut), x = colonne (0 = gauche)
  final List<List<Cell>> grid;

  GameState({required this.grid});

  /// Crée un état initial avec une grille vide
  factory GameState.initial() {
    return GameState(
      grid: List.generate(
        gridSize,
        (_) => List.generate(gridSize, (_) => Cell.empty),
      ),
    );
  }

  /// Vérifie si une position est valide sur la grille
  bool isValidPosition(int x, int y) {
    return x >= 0 && x < gridSize && y >= 0 && y < gridSize;
  }

  /// Vérifie si une cellule est occupée
  bool isCellOccupied(int x, int y) {
    if (!isValidPosition(x, y)) return true;
    return grid[y][x].occupied;
  }

  /// Crée une copie de l'état avec une cellule modifiée
  GameState setCellAt(int x, int y, Cell cell) {
    if (!isValidPosition(x, y)) return this;

    final newGrid = List<List<Cell>>.generate(
      gridSize,
      (row) => List<Cell>.from(grid[row]),
    );
    newGrid[y][x] = cell;

    return GameState(grid: newGrid);
  }

  /// Affiche la grille dans la console (pour debug)
  void printGrid() {
    for (var row in grid) {
      print(row.map((c) => c.toString()).join(' '));
    }
  }
}

import 'dart:math';

/// Générateur de pièces déterministe basé sur un seed
/// Garantit que deux joueurs avec le même seed reçoivent
/// exactement la même séquence de pièces
class SeededPieceGenerator {
  late Random _pieceRandom;
  late Random _jellyBombRandom;
  final int seed;

  SeededPieceGenerator(this.seed) {
    // Utilise des sous-seeds différents pour éviter les interférences
    _pieceRandom = Random(seed);
    _jellyBombRandom = Random(seed + 1000000);
  }

  /// Réinitialise le générateur (même seed = même séquence)
  void reset() {
    _pieceRandom = Random(seed);
    _jellyBombRandom = Random(seed + 1000000);
  }

  /// Mélange une liste de manière déterministe (Fisher-Yates)
  void shuffleList<T>(List<T> list) {
    for (int i = list.length - 1; i > 0; i--) {
      int j = _pieceRandom.nextInt(i + 1);
      T temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  /// Vérifie si une JellyBomb doit apparaître (déterministe)
  bool shouldSpawnJellyBomb() {
    return _jellyBombRandom.nextDouble() < 0.25; // 25% de chance
  }

  /// Récupère l'index du bloc qui devient JellyBomb
  int getJellyBombBlockIndex(int pieceBlockCount) {
    return _jellyBombRandom.nextInt(pieceBlockCount);
  }

  /// Génère un seed aléatoire pour un nouveau duel
  static int generateDuelSeed() {
    return Random().nextInt(2147483647);
  }
}

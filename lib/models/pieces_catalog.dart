import 'dart:ui';
import 'piece.dart';

/// Catalogue des pièces disponibles dans le jeu
/// Toutes les pièces avec leurs 4 rotations (quand applicable)
class PiecesCatalog {
  /// Couleurs des pièces - style bonbon vibrant
  static const Color yellow = Color(0xFFFFD700);    // Jaune doré
  static const Color blue = Color(0xFF4169E1);      // Bleu royal
  static const Color purple = Color(0xFF9932CC);    // Violet orchidée
  static const Color orange = Color(0xFFFF8C00);    // Orange vif
  static const Color green = Color(0xFF32CD32);     // Vert lime
  static const Color cyan = Color(0xFF00CED1);      // Cyan turquoise
  static const Color red = Color(0xFFFF4757);       // Rouge candy
  static const Color pink = Color(0xFFFF69B4);      // Rose bonbon
  static const Color fuchsia = Color(0xFFFF00FF);   // Fuchsia vif

  // ============================================
  // CARRÉS (symétriques - 1 seule rotation)
  // ============================================

  /// 1 bloc unique
  static Piece get square1 => const Piece(
        blocks: [BlockPosition(0, 0)],
        color: yellow,
      );

  /// Carré 2x2
  static Piece get square2 => const Piece(
        blocks: [
          BlockPosition(0, 0), BlockPosition(1, 0),
          BlockPosition(0, 1), BlockPosition(1, 1),
        ],
        color: yellow,
      );

  // ============================================
  // DOMINOS (2 rotations)
  // ============================================

  /// Domino horizontal
  static Piece get domino2H => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0)],
        color: blue,
      );

  /// Domino vertical
  static Piece get domino2V => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(0, 1)],
        color: blue,
      );

  // ============================================
  // LIGNES 3 (2 rotations)
  // ============================================

  static Piece get line3H => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(2, 0)],
        color: cyan,
      );

  static Piece get line3V => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(0, 1), BlockPosition(0, 2)],
        color: cyan,
      );

  // ============================================
  // LIGNES 4 (2 rotations)
  // ============================================

  static Piece get line4H => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(2, 0), BlockPosition(3, 0)],
        color: cyan,
      );

  static Piece get line4V => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(0, 1), BlockPosition(0, 2), BlockPosition(0, 3)],
        color: cyan,
      );

  // ============================================
  // LIGNES 5 (2 rotations)
  // ============================================

  static Piece get line5H => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(2, 0), BlockPosition(3, 0), BlockPosition(4, 0)],
        color: cyan,
      );

  static Piece get line5V => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(0, 1), BlockPosition(0, 2), BlockPosition(0, 3), BlockPosition(0, 4)],
        color: cyan,
      );

  // ============================================
  // L DE 3 BLOCS (4 rotations)
  // ============================================

  /// ■
  /// ■■
  static Piece get l3_0 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(0, 1), BlockPosition(1, 1)],
        color: orange,
      );

  /// ■■
  /// ■
  static Piece get l3_90 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(0, 1)],
        color: orange,
      );

  /// ■■
  ///  ■
  static Piece get l3_180 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(1, 1)],
        color: orange,
      );

  ///  ■
  /// ■■
  static Piece get l3_270 => const Piece(
        blocks: [BlockPosition(1, 0), BlockPosition(0, 1), BlockPosition(1, 1)],
        color: orange,
      );

  // ============================================
  // L DE 4 BLOCS (4 rotations)
  // ============================================

  /// ■
  /// ■
  /// ■■
  static Piece get l4_0 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(0, 1), BlockPosition(0, 2), BlockPosition(1, 2)],
        color: orange,
      );

  /// ■■■
  /// ■
  static Piece get l4_90 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(2, 0), BlockPosition(0, 1)],
        color: orange,
      );

  /// ■■
  ///  ■
  ///  ■
  static Piece get l4_180 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(1, 1), BlockPosition(1, 2)],
        color: orange,
      );

  ///     ■
  /// ■■■
  static Piece get l4_270 => const Piece(
        blocks: [BlockPosition(2, 0), BlockPosition(0, 1), BlockPosition(1, 1), BlockPosition(2, 1)],
        color: orange,
      );

  // ============================================
  // J DE 4 BLOCS (4 rotations)
  // ============================================

  ///  ■
  ///  ■
  /// ■■
  static Piece get j4_0 => const Piece(
        blocks: [BlockPosition(1, 0), BlockPosition(1, 1), BlockPosition(0, 2), BlockPosition(1, 2)],
        color: blue,
      );

  /// ■
  /// ■■■
  static Piece get j4_90 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(0, 1), BlockPosition(1, 1), BlockPosition(2, 1)],
        color: blue,
      );

  /// ■■
  /// ■
  /// ■
  static Piece get j4_180 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(0, 1), BlockPosition(0, 2)],
        color: blue,
      );

  /// ■■■
  ///     ■
  static Piece get j4_270 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(2, 0), BlockPosition(2, 1)],
        color: blue,
      );

  // ============================================
  // T DE 4 BLOCS (4 rotations)
  // ============================================

  /// ■■■
  ///  ■
  static Piece get t4_0 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(2, 0), BlockPosition(1, 1)],
        color: purple,
      );

  /// ■
  /// ■■
  /// ■
  static Piece get t4_90 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(0, 1), BlockPosition(1, 1), BlockPosition(0, 2)],
        color: purple,
      );

  ///  ■
  /// ■■■
  static Piece get t4_180 => const Piece(
        blocks: [BlockPosition(1, 0), BlockPosition(0, 1), BlockPosition(1, 1), BlockPosition(2, 1)],
        color: purple,
      );

  ///  ■
  /// ■■
  ///  ■
  static Piece get t4_270 => const Piece(
        blocks: [BlockPosition(1, 0), BlockPosition(0, 1), BlockPosition(1, 1), BlockPosition(1, 2)],
        color: purple,
      );

  // ============================================
  // S DE 4 BLOCS (2 rotations)
  // ============================================

  ///  ■■
  /// ■■
  static Piece get s4_0 => const Piece(
        blocks: [BlockPosition(1, 0), BlockPosition(2, 0), BlockPosition(0, 1), BlockPosition(1, 1)],
        color: fuchsia,
      );

  /// ■
  /// ■■
  ///  ■
  static Piece get s4_90 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(0, 1), BlockPosition(1, 1), BlockPosition(1, 2)],
        color: fuchsia,
      );

  // ============================================
  // Z DE 4 BLOCS (2 rotations)
  // ============================================

  /// ■■
  ///  ■■
  static Piece get z4_0 => const Piece(
        blocks: [BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(1, 1), BlockPosition(2, 1)],
        color: red,
      );

  ///  ■
  /// ■■
  /// ■
  static Piece get z4_90 => const Piece(
        blocks: [BlockPosition(1, 0), BlockPosition(0, 1), BlockPosition(1, 1), BlockPosition(0, 2)],
        color: red,
      );

  // ============================================
  // RECTANGLES 2x3 / 3x2
  // ============================================

  /// Rectangle 2x3 (vertical)
  /// ■■
  /// ■■
  /// ■■
  static Piece get rect2x3 => const Piece(
        blocks: [
          BlockPosition(0, 0), BlockPosition(1, 0),
          BlockPosition(0, 1), BlockPosition(1, 1),
          BlockPosition(0, 2), BlockPosition(1, 2),
        ],
        color: orange,
      );

  /// Rectangle 3x2 (horizontal)
  /// ■■■
  /// ■■■
  static Piece get rect3x2 => const Piece(
        blocks: [
          BlockPosition(0, 0), BlockPosition(1, 0), BlockPosition(2, 0),
          BlockPosition(0, 1), BlockPosition(1, 1), BlockPosition(2, 1),
        ],
        color: orange,
      );

  // ============================================
  // CARRÉ 3x3 (symétrique)
  // ============================================

  static Piece get square3 => Piece(
        blocks: [
          for (int y = 0; y < 3; y++)
            for (int x = 0; x < 3; x++) BlockPosition(x, y),
        ],
        color: pink,
      );

  // ============================================
  // LISTE PRINCIPALE (toutes les rotations)
  // ============================================

  static List<Piece> get main => [
        // Carrés (2 chacun pour équilibrer)
        square1,
        square1,
        square2,
        square2,
        // Dominos (2 chacun)
        domino2H,
        domino2H,
        domino2V,
        domino2V,
        // Lignes 3 (2 chacun)
        line3H,
        line3H,
        line3V,
        line3V,
        // Lignes 4 (2 chacun)
        line4H,
        line4H,
        line4V,
        line4V,
        // Lignes 5 (2 chacun)
        line5H,
        line5H,
        line5V,
        line5V,
        // L de 3 (1 chaque rotation)
        l3_0,
        l3_90,
        l3_180,
        l3_270,
        // L de 4 (1 chaque rotation)
        l4_0,
        l4_90,
        l4_180,
        l4_270,
        // J de 4 (1 chaque rotation)
        j4_0,
        j4_90,
        j4_180,
        j4_270,
        // T de 4 (1 chaque rotation)
        t4_0,
        t4_90,
        t4_180,
        t4_270,
        // S de 4 (2 chacun pour équilibrer)
        s4_0,
        s4_0,
        s4_90,
        s4_90,
        // Z de 4 (2 chacun pour équilibrer)
        z4_0,
        z4_0,
        z4_90,
        z4_90,
        // Rectangles (2 chacun pour équilibrer)
        rect2x3,
        rect2x3,
        rect3x2,
        rect3x2,
      ];

  /// Liste de toutes les pièces
  static List<Piece> get all => [
        ...main,
        square3,
      ];

  /// TEST: Seulement lignes 4 et 5 (horizontal et vertical)
  static List<Piece> get testLongLines => [
        line4H,
        line4V,
        line5H,
        line5V,
      ];

  /// TEST: Seulement ligne 5 horizontale (3 copies pour remplir les 3 slots)
  static List<Piece> get testLine5H => [
        line5H,
        line5H,
        line5H,
      ];
}

import 'package:flutter/material.dart';

/// Texte style candy avec détourage (outline)
class CandyText extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color textColor;
  final Color strokeColor;
  final double strokeWidth;
  final FontWeight fontWeight;

  const CandyText({
    super.key,
    required this.text,
    this.fontSize = 16,
    this.textColor = Colors.white,
    this.strokeColor = const Color(0xFFE91E63),
    this.strokeWidth = 2,
    this.fontWeight = FontWeight.bold,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Stroke (outline)
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = strokeColor,
          ),
        ),
        // Fill
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: textColor,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.3),
                offset: const Offset(1, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Panel de score avec image de fond
class CandyScorePanel extends StatelessWidget {
  final String label;
  final int value;
  final String backgroundImage;
  final Color labelStrokeColor;
  final Color valueColor;
  final Color valueStrokeColor;
  final IconData? icon;
  final double width;
  final double height;

  const CandyScorePanel({
    super.key,
    required this.label,
    required this.value,
    required this.backgroundImage,
    this.labelStrokeColor = const Color(0xFFE91E63),
    this.valueColor = const Color(0xFFFFD700),
    this.valueStrokeColor = const Color(0xFFB8860B),
    this.icon,
    this.width = 130,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(backgroundImage),
          fit: BoxFit.fill,
        ),
      ),
      child: Stack(
        children: [
          // Label (descendu de 20%)
          Positioned(
            top: height * 0.20,
            left: 0,
            right: 0,
            child: Center(
              child: CandyText(
                text: label,
                fontSize: 12,
                textColor: Colors.white,
                strokeColor: labelStrokeColor,
                strokeWidth: 1.5,
              ),
            ),
          ),
          // Valeur (positionnée à 38%)
          Positioned(
            top: height * 0.38,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: valueColor, size: 20),
                    const SizedBox(width: 4),
                  ],
                  CandyText(
                    text: value.toString(),
                    fontSize: 22,
                    textColor: valueColor,
                    strokeColor: valueStrokeColor,
                    strokeWidth: 2.5,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton avatar avec image de fond
class CandyAvatarButton extends StatelessWidget {
  final String letter;
  final String backgroundImage;
  final VoidCallback? onTap;
  final double size;
  final String? profilePhotoUrl; // URL de la photo de profil Google

  const CandyAvatarButton({
    super.key,
    required this.letter,
    required this.backgroundImage,
    this.onTap,
    this.size = 60,
    this.profilePhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final photoSize = size * 0.97;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Photo de profil (en dessous)
            if (profilePhotoUrl != null)
              Transform.translate(
                offset: Offset.zero,
                child: Container(
                  width: photoSize,
                  height: photoSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                      image: NetworkImage(profilePhotoUrl!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              )
            else
              Transform.translate(
                offset: Offset.zero,
                child: Container(
                  width: photoSize * 0.78,
                  height: photoSize * 0.78,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF9EC4), Color(0xFFE85A8F)],
                    ),
                  ),
                  child: Center(
                    child: CandyText(
                      text: letter.toUpperCase(),
                      fontSize: size * 0.35,
                      textColor: Colors.white,
                      strokeColor: const Color(0xFFD84315),
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
            // Cadre par dessus
            Positioned.fill(
              child: Image.asset(
                backgroundImage,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton circulaire avec image de fond (pour settings)
class CandyCircleButton extends StatelessWidget {
  final IconData icon;
  final String backgroundImage;
  final VoidCallback? onTap;
  final double size;

  const CandyCircleButton({
    super.key,
    required this.icon,
    required this.backgroundImage,
    this.onTap,
    this.size = 50,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(backgroundImage),
            fit: BoxFit.contain,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: Colors.white,
            size: size * 0.45,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.4),
                offset: const Offset(1, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cadre candy stripe pour la zone des pièces
class CandyStripeBorder extends StatelessWidget {
  final Widget child;
  final double borderWidth;

  const CandyStripeBorder({
    super.key,
    required this.child,
    this.borderWidth = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFB6C1),
            Color(0xFF87CEEB),
            Color(0xFFFFE4B5),
            Color(0xFFFFB6C1),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        margin: EdgeInsets.all(borderWidth),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }
}

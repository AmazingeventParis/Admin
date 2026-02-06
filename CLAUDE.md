# Historique de Session Claude - Jeu Puzzle (Candy Puzzle)

## Date: 5 Février 2026 - Déploiement TestFlight iOS

---

## Session du 5 Février 2026 - Partie 3 : Déploiement iOS via TestFlight

### 1. Configuration Codemagic (CI/CD pour iOS)

#### Pourquoi Codemagic ?
- L'utilisateur est sur **Windows** (pas de Mac)
- Codemagic permet de compiler iOS dans le cloud sur des Mac M2
- Gratuit : 500 minutes/mois

#### Étapes réalisées
1. Création du repo GitHub : `https://github.com/aschercohen-a11y/candy-puzzle`
2. Connexion Codemagic au repo GitHub
3. Création de l'API Key App Store Connect (KZBZXWQ5YW)
4. Configuration du code signing automatique
5. Création du Bundle ID : `com.amazingevent.candypuzzle`
6. Création de l'app sur App Store Connect

### 2. Problèmes rencontrés et solutions

#### Erreur 1 : Icône iOS avec transparence
```
Invalid large app icon. The large app icon can't be transparent or contain an alpha channel.
```
**Solution :**
- Ajout de `IconeIOS.png` dans assets
- Configuration `flutter_launcher_icons` avec :
```yaml
flutter_launcher_icons:
  ios: true
  image_path: "assets/ui/IconeIOS.png"
  remove_alpha_ios: true
  background_color_ios: "#87CEEB"
```
- Régénération des icônes : `dart run flutter_launcher_icons`

#### Erreur 2 : Numéro de build dupliqué
```
The bundle version must be higher than the previously uploaded version.
```
**Solution :**
- Incrémenter la version dans `pubspec.yaml` :
- `version: 1.0.0+1` → `1.0.0+2` → `1.0.0+3`

#### Erreur 3 : App crash au lancement sur iPhone
**Cause probable :** Device Preview incompatible avec iOS release

**Solution :**
1. Suppression complète de `device_preview` du projet
2. Nettoyage de `main.dart` (suppression des imports et code Device Preview)
3. Retrait de la dépendance dans `pubspec.yaml`
4. Ajout de try-catch autour de :
   - `SupabaseService.initialize()`
   - `audioService.playIntroMusic()`
   - Méthodes du service audio

### 3. Configuration TestFlight

#### Question Chiffrement (Export Compliance)
- Réponse : **"Aucun des algorithmes mentionnés ci-dessus"**
- L'app utilise HTTPS standard fourni par iOS (pas de crypto personnalisée)

#### Groupe de testeurs
- Groupe interne créé : "Candy"
- Testeur : Dominique Cohen (iPhone 12 Pro Max, iOS 18.1)

### 4. Fichiers modifiés

| Fichier | Modification |
|---------|-------------|
| `pubspec.yaml` | Retrait device_preview, incrémentation version |
| `lib/main.dart` | Suppression Device Preview, ajout try-catch Supabase |
| `lib/services/audio_service.dart` | Ajout try-catch playIntroMusic |
| `lib/ui/screens/splash_screen.dart` | Ajout try-catch audioService |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/*` | Nouvelles icônes sans transparence |

### 5. Commandes Codemagic

```bash
# Le build se fait automatiquement sur Codemagic
# Workflow : Default Workflow
# Machine : Mac mini M2
# Durée moyenne : ~9-10 minutes
```

### 6. Flux TestFlight

```
Code → GitHub Push → Codemagic Build → App Store Connect → TestFlight
                                                              ↓
                                              Testeurs reçoivent notification
                                                              ↓
                                              Mise à jour via app TestFlight
```

### 7. État actuel

- ✅ Build iOS compilé avec succès
- ✅ App uploadée sur App Store Connect
- ✅ Groupe de testeurs créé
- ⏳ Test en cours (build 3 avec corrections crash)
- ❓ Lien public TestFlight (à activer dans Réglages du groupe)

### 8. Pour activer le lien public TestFlight

1. App Store Connect → TestFlight → Groupe "Candy"
2. Onglet **"Réglages"**
3. Activer **"Lien public"**
4. Copier le lien `testflight.apple.com/join/XXXXX`
5. Partager à n'importe qui !

---

## Date: 5 Février 2026 (Suite)

---

## Session du 5 Février 2026 - Partie 2

### 1. Sugar Rush Overlay - Refonte complète

#### Problème
- L'overlay Sugar Rush se répétait plusieurs fois
- Le titre était petit et peu attrayant

#### Solution
- **Apparition unique** par activation (ne se répète plus)
- **Titre en 2 lignes** :
  - "SUGAR" (52px, dégradé doré, italic, w900)
  - "RUSH!" (58px, dégradé rose/fuchsia, italic, w900)
- **Badge "SCORE x5"** avec dégradé doré en dessous
- **Animation** : zoom rapide → reste visible → fondu sortie (2000ms)
- **Confettis** multicolores en arrière-plan
- **Flash blanc** initial

### 2. Layout Jauge Sugar Rush - Timer et x5

#### Problème
- Le timer (secondes) et le badge x5 écrasaient la jauge dans un Row
- La jauge devenait minuscule pendant le Sugar Rush

#### Solution - Passage à Stack
```dart
// AVANT : Row qui compressait la jauge
Row(children: [Timer, Expanded(Gauge), x5])

// APRÈS : Stack avec superposition
Stack(
  children: [
    Positioned.fill(child: Gauge),           // Jauge pleine largeur
    Positioned(left: -offset, child: Timer), // Timer superposé à gauche
    Positioned(right: -offset, child: x5),   // x5 superposé à droite
  ],
)
```

#### Ajustements visuels
- **Timer** réduit : 48px → 38px, texte 18px → 14px
- **Badge x5** réduit : padding 12/6 → 8/4, texte 22px → 16px
- **Positionnement** : écartés de `gaugeHeight * 1.1` et centrés verticalement avec `top: (gaugeHeight - 38) / 2`

### 3. Étincelles sur l'étoile de la jauge

#### Implémentation
- Nouveau `AnimationController` (`_sparkleController`, cycle 2s)
- Changement de `SingleTickerProviderStateMixin` → `TickerProviderStateMixin`
- `_GaugeSparkPainter` dessine les étincelles autour de l'étoile

#### Progression des étincelles
| Jauge | Nb étincelles | Nb traînées | Couleurs |
|-------|--------------|-------------|----------|
| 0-35% | 3 | 2 | Jaune doré |
| 35-65% | ~9 | ~7 | Jaune + Rouge |
| 65-90% | ~13 | ~9 | Jaune + Rouge + Bleu |
| 90-100% | **22** | **14** | **Bouquet final** : 9 couleurs (doré, rouge, bleu, rose, cyan, vert, blanc, fuchsia, orange) |

#### Bouquet final (≥90%)
- Rayon d'étincelles x1.8
- Taille des étincelles x1.8
- 22 étincelles + 14 traînées multicolores
- Effet spectaculaire avant activation du Sugar Rush

### 4. Étincelles sur les Jelly Bombs

#### Implémentation
- Ajout de `_JellySparkPainter` dans `jelly_bomb_widget.dart`
- 3 étincelles par Jelly Bomb (étoile 8 branches)
- Glow blanc + centre blanc vif
- Animation avec `_shineAnimation.value` existant
- Apparition/disparition en décalé

#### Distinction briques normales vs Jelly
- Paramètre `showSparkle` ajouté à `BlockWidget` (défaut: `false`)
- `CellWidget` ne passe **PAS** `showSparkle: true` (briques normales)
- Étincelles uniquement sur `JellyBombWidget`
- `BlockWidget` converti en `StatefulWidget` (pour supporter l'animation si nécessaire)

### 5. Particules d'énergie (ligne → jauge) - Améliorées

#### Changements
| Paramètre | Avant | Après |
|-----------|-------|-------|
| Max particules/clear | 5 | **12** |
| Délai entre particules | 50ms | **25ms** (quasi continu) |
| Taille particule | 10px | **16px** |
| Longueur traînée | 8 positions | **14 positions** |
| Arc de trajectoire | -50px | **-60px** |

### 6. Fond sombre derrière les pièces

#### Problème
- Le fond arc-en-ciel rendait les pièces difficiles à voir dans le cadre du bas

#### Solution
- Ajout d'un `Container` noir semi-transparent (35% opacité)
- Positionné entre le fond et le cadre décoratif
- Coins arrondis (borderRadius: 16)
- Marges intérieures : 5% horizontal, 8% vertical

```dart
// Fond sombre derrière les pièces
Positioned(
  left: piecesFrameWidth * 0.05,
  right: piecesFrameWidth * 0.05,
  top: piecesFrameHeight * 0.08,
  bottom: piecesFrameHeight * 0.08,
  child: Container(
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.35),
      borderRadius: BorderRadius.circular(16),
    ),
  ),
),
```

---

## Fichiers Modifiés (5 Février - Partie 2)

| Fichier | Modification |
|---------|-------------|
| `lib/ui/screens/game_screen.dart` | Layout jauge Stack, fond sombre pièces, particules x12 size 16 |
| `lib/ui/widgets/sugar_rush_widget.dart` | Overlay unique, étincelles progressives jauge, particules traînée 14 |
| `lib/ui/widgets/block_widget.dart` | Converti en StatefulWidget, paramètre `showSparkle` |
| `lib/ui/widgets/cell_widget.dart` | Pas de sparkle sur briques normales |
| `lib/ui/widgets/jelly_bomb_widget.dart` | Ajout `_JellySparkPainter` pour étincelles Jelly Bombs |

---

## Session du 5 Février 2026 - Partie 1

### 1. Système Sugar Rush

#### Fonctionnalités
- **Jauge Sugar Rush** : Barre de progression qui se remplit quand on complète des lignes
- **Animation Lerp** : Remplissage fluide avec interpolation linéaire
- **Mode Fever** : Quand la jauge atteint 100% :
  - Multiplicateur x5 pendant 10 secondes
  - Effet confettis à l'écran
  - Timer visuel circulaire
- **Particules d'énergie** : Volent des lignes complétées vers la jauge

#### Fichiers créés/modifiés
- `lib/ui/widgets/sugar_rush_widget.dart` - Widgets: SugarRushGauge, SugarRushOverlay, SugarRushMultiplier, SugarRushTimer, SugarRushEnergyParticle

### 2. Effets de fumée pour Jelly Bomb

- Ajout de particules de fumée lors des explosions
- Classes ajoutées dans `lib/ui/widgets/particle_effect.dart` :
  - `SmokeEffect` : Fumée grise qui s'évapore
  - `ColoredSmokeEffect` : Fumée colorée pour les explosions

### 3. Éditeur de Layout HTML

#### Outil créé : `layout_editor.html`
- Page web locale pour ajuster le positionnement des éléments UI
- Fonctionnalités :
  - **Glisser-déposer** : Déplacer les éléments avec la souris
  - **Redimensionnement** : Coin cyan pour changer la taille
  - **Clavier** : Flèches pour déplacer (1px), Shift+Flèches (10px)
  - **Export** : Génère les mesures et pourcentages Flutter

#### Éléments configurables
- Score Gauche / Score Droit
- Jauge Sugar Rush
- Plateau de Jeu
- Cadre Pièces
- Zones Pièce 1, 2, 3

### 4. Refonte du Layout Game Screen

#### Changement majeur : Positionnement absolu
- Passage de `Column` avec `Expanded` à `Stack` avec `Positioned`
- Permet un contrôle précis basé sur les pourcentages de l'écran

#### Configuration actuelle (référence 380x680)
```dart
// === CONFIGURATION LAYOUT ===
final scoreWidth = screenWidth * 0.395;
final scoreHeight = screenHeight * 0.088;
final gaugeWidth = screenWidth * 0.513;
final gaugeHeight = screenHeight * 0.066;
final boardSize = screenWidth * 0.921;
final piecesFrameWidth = screenWidth * 0.955;
final piecesFrameHeight = screenHeight * 0.251;

final scoreLeftX = screenWidth * 0.032;
final scoreRightX = screenWidth * 0.574;
final gaugeX = screenWidth * 0.234;
final boardX = screenWidth * 0.039;
final piecesX = screenWidth * 0.021;

final scoreY = screenHeight * 0.012;
final gaugeY = screenHeight * 0.116;
final boardY = screenHeight * 0.191;
final piecesY = screenHeight * 0.704;
```

### 5. Simplification de l'écran de jeu

- **Supprimé** : Avatar profil, nom du joueur, bouton paramètres
- **Conservé** : Scores (actuel et best) uniquement en haut
- **Ajouté** : Cadre décoratif `cadrebloqueenbas.png` autour des pièces

### 6. Fix du clipping des pièces longues

#### Problème
- Les pièces horizontales de 4-5 blocs étaient coupées à droite

#### Solution
- Utilisation de `UnconstrainedBox` avec `clipBehavior: Clip.none`

### 7. Nouvelles pièces et équilibrage

#### Pièces ajoutées dans `pieces_catalog.dart`
- `rect2x3` : Rectangle 2x3 (vertical, couleur orange)
- `rect3x2` : Rectangle 3x2 (horizontal, couleur orange)

#### Distribution équilibrée
- Chaque type de pièce a ~4 entrées dans la liste `main`
- Pièces simples (carrés, dominos, lignes) : doublées
- Pièces à rotations (L/J/T) : 1 par rotation = 4 entrées
- S/Z : 2 par rotation = 4 entrées
- Rectangles : 2 par orientation = 4 entrées

### 8. Taille dynamique des blocs de pièces
```dart
final blockByWidth = (slotWidth - 16) / (pieceWidth > 3 ? pieceWidth : 3);
final blockByHeight = (slotHeight - 16) / (pieceHeight > 3 ? pieceHeight : 3);
final clampedBlockSize = blockByWidth < blockByHeight
    ? blockByWidth.clamp(14.0, 22.0)
    : blockByHeight.clamp(14.0, 22.0);
```

---

## Date: 4 Février 2026

---

## Session du 4 Février 2026

### Améliorations Page Leaderboard

#### 1. Cadre candy autour des photos
- Nouveau cadre `Cerclevidepourphoto.png` autour de toutes les photos
- Structure Stack : photo en dessous (75% de la taille), cadre par-dessus

#### 2. Liste des joueurs (4ème position et après)
- Liste scrollable avec les joueurs à partir de la 4ème position
- Style du texte avec contour (stroke effect)

#### 3. Menu de navigation en bas
- 3 boutons : Accueil, Leader, Messages
- Bouton page courante : statique (opacité 60%)
- Autres boutons : animés avec effet vague

#### 4. Mode plein écran
- `SystemUiMode.immersiveSticky` dans `main.dart`

#### 5. Prénoms et scores du podium

### Améliorations Page Admin

#### 1. Contrôle des scores des faux profils
- Score minimum et maximum configurables

#### 2. Modification des scores pour tous les profils

#### 3. Tri des utilisateurs par score

### Correction du Classement dans l'APK
- Le tri `order('high_score', ascending: false)` côté serveur
- Requête part de `player_stats` au lieu de `players`

---

## Date: 3 Février 2026

---

## Session du 3 Février 2026

### 1. Authentification Google Sign-In
### 2. Page Profil / Statistiques
### 3. Gestion du Profil
### 4. Synchronisation des Stats
### 5. Photo de Profil sur l'Écran de Jeu
### 6. Page Menu (Accueil)
### 7. Page Administration Web

---

## Flux de Navigation

```
Splash Screen
     ↓
Auth Screen (Connexion Google ou Sans compte)
     ↓
Menu Screen
  ├── Bouton JOUER → Game Screen
  ├── Bouton Profil → Profile Screen
  ├── Bouton Classement → Leaderboard Screen
  ├── Bouton Paramètres → (À venir)
  └── Bouton Déconnexion → Auth Screen
```

---

## Configuration Supabase

### URL et Clés
```dart
static const String _supabaseUrl = 'https://icujwpwicsmyuyidubqf.supabase.co';
static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
static const String _webClientId = '329868845376-hbh8plnscagl2smu97pphatm0kanmdg2.apps.googleusercontent.com';
```

### Tables SQL
```sql
CREATE TABLE players (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  device_id TEXT UNIQUE,
  username TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE player_stats (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID REFERENCES players(id),
  games_played INTEGER DEFAULT 0,
  high_score INTEGER DEFAULT 0,
  total_score INTEGER DEFAULT 0,
  total_lines_cleared INTEGER DEFAULT 0,
  total_play_time_seconds INTEGER DEFAULT 0,
  best_combo INTEGER DEFAULT 0,
  updated_at TIMESTAMP DEFAULT NOW()
);
```

---

## Commandes Utiles

```bash
# Générer l'APK
flutter build apk --release

# Clean build
flutter clean && flutter build apk --release

# Emplacement de l'APK
build\app\outputs\flutter-apk\app-release.apk
```

---

## Dépendances

```yaml
dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.2.2
  audioplayers: ^5.2.1
  supabase_flutter: ^2.3.0
  google_sign_in: ^6.1.6
```

---

## Tous les fichiers du projet

### Services
- `lib/services/supabase_service.dart` - Service Supabase + Google Sign-In
- `lib/services/stats_service.dart` - Gestion des statistiques avec sync cloud
- `lib/services/audio_service.dart` - Service audio (musique, effets sonores)
- `lib/services/screen_shake_service.dart` - Service de tremblement d'écran

### Écrans
- `lib/ui/screens/auth_screen.dart` - Écran de connexion
- `lib/ui/screens/menu_screen.dart` - Page menu principal
- `lib/ui/screens/game_screen.dart` - Écran de jeu principal
- `lib/ui/screens/profile_screen.dart` - Écran profil/statistiques
- `lib/ui/screens/splash_screen.dart` - Écran de démarrage
- `lib/ui/screens/leaderboard_screen.dart` - Classement des joueurs

### Widgets
- `lib/ui/widgets/candy_ui.dart` - CandyAvatarButton, CandyText, CandyCircleButton
- `lib/ui/widgets/block_widget.dart` - Brique 1x1 glossy (StatefulWidget avec sparkle optionnel)
- `lib/ui/widgets/cell_widget.dart` - Cellule de grille (vide ou occupée)
- `lib/ui/widgets/piece_widget.dart` - Pièce de puzzle complète
- `lib/ui/widgets/sugar_rush_widget.dart` - Jauge, overlay, timer, multiplicateur, particules
- `lib/ui/widgets/jelly_bomb_widget.dart` - Jelly Bomb avec étincelles + explosion
- `lib/ui/widgets/particle_effect.dart` - Effets de particules et fumée

### Modèles
- `lib/models/game_state.dart` - État du jeu, grille, cellules, BlockType
- `lib/models/piece.dart` - Modèle de pièce (blocs + couleur)
- `lib/models/pieces_catalog.dart` - Catalogue de toutes les pièces et rotations

### Admin Web
- `admin/index.html` - Page HTML
- `admin/style.css` - Styles CSS
- `admin/admin.js` - Logique JavaScript + Supabase

### Outils
- `layout_editor.html` - Éditeur de layout web (drag & drop)

---

## Assets

```yaml
assets:
  - assets/ui/cerclevidephoto.png
  - assets/ui/fondpageaccueil.png
  - assets/ui/cercleparametres.png
  - assets/ui/cerclesscore.png
  - assets/ui/cerclemeilleurscrore.png
  - assets/ui/Logo titre.png
  - assets/ui/Menu.png
  - assets/ui/Boutonaccueil.png
  - assets/ui/boutonleader.png
  - assets/ui/boutonmessages.png
  - assets/ui/Cerclevidepourphoto.png
  - assets/ui/sugar_gauge_frame.png
  - assets/ui/sugar_gauge.png
  - assets/ui/sugar_gauge_icon.png
  - assets/ui/cadrebloqueenbas.png
  - assets/ui/jelly_bomb_idle.png
  - assets/ui/jelly_bomb_glow.png
  - assets/ui/jelly_bomb_burst.png
  - assets/bg/bg.png
  - assets/blocks/block_base2.png
```

---

## Prochaines Étapes Possibles

1. ~~**Classement (Leaderboard)**~~ - FAIT
2. ~~**Sugar Rush**~~ - FAIT - Jauge avec multiplicateur x5, étincelles progressives
3. ~~**Jelly Bombs**~~ - FAIT - Bombes avec explosion 3x3, étincelles
4. **Page Paramètres** - Son, musique, vibrations, langue
5. **Page Messages** - Chat entre joueurs, communication en temps réel
6. **Notifications push** - Alertes et rappels
7. **Nouveaux modes de jeu** - Défis, tournois, etc.
8. **Power-ups** - Bonus spéciaux dans le jeu

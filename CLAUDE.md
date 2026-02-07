# Historique de Session Claude - Jeu Puzzle (Candy Puzzle)

## Date: 6 Février 2026 - Résolution Crash iOS + Google Sign-In iOS

---

## Session du 6 Février 2026 - Débogage et Google Sign-In iOS

### 1. Problème Principal : App Crash au Lancement (Builds 1-7)

#### Symptôme
L'application se fermait immédiatement après l'ouverture sur iPhone, sans aucun message d'erreur visible dans App Store Connect.

#### Cause Racine Identifiée
L'application était compilée en mode **DEBUG** au lieu de **RELEASE**.

#### Message d'erreur sur iPhone (Build 7)
```
In iOS 14+, debug mode Flutter apps can only be launched from Flutter tooling...
```

#### Solution
Dans **Codemagic** → Build settings → **Mode: Release** (pas Debug)

#### Approche de débogage utilisée
1. Retrait de Device Preview ❌ (pas la cause)
2. Ajout try-catch autour de Supabase/Audio ❌ (pas la cause)
3. Splash screen minimaliste ❌ (pas la cause)
4. Création du Podfile iOS ❌ (pas la cause)
5. **Build 8 en mode RELEASE** ✅ **SOLUTION**

---

### 2. Problème Secondaire : Crash Google Sign-In (Builds 8-9)

#### Symptôme
L'app fonctionnait en mode "Jouer sans compte" mais crashait lors du clic sur "Connexion Google".

#### Cause
iOS nécessite un **Client ID spécifique** différent d'Android/Web.

#### Solution en 3 étapes

**Étape 1 : Créer un iOS Client ID dans Google Cloud Console**
1. Google Cloud Console → APIs & Services → Credentials
2. Create Credentials → OAuth client ID
3. Application type: **iOS**
4. Bundle ID: `com.amazingevent.candypuzzle`
5. Copier le Client ID généré

**Étape 2 : Configurer `ios/Runner/Info.plist`**
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.329868845376-mlj0g6jsgpqkglocvbc87h6vprosnb40</string>
    </array>
  </dict>
</array>
<key>GIDClientID</key>
<string>329868845376-mlj0g6jsgpqkglocvbc87h6vprosnb40.apps.googleusercontent.com</string>
```

**Étape 3 : Mettre à jour `supabase_service.dart`**
```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

// iOS Client ID from Google Cloud Console
static const String _iosClientId = '329868845376-mlj0g6jsgpqkglocvbc87h6vprosnb40.apps.googleusercontent.com';

// Dans signInWithGoogle():
final GoogleSignIn googleSignIn = GoogleSignIn(
  clientId: !kIsWeb && Platform.isIOS ? _iosClientId : null,
  serverClientId: _webClientId,
);
```

---

### 3. Client IDs Google OAuth - Récapitulatif

| Plateforme | Client ID | Utilisation |
|------------|-----------|-------------|
| Web/Android | `329868845376-hbh8plnscagl2smu97pphatm0kanmdg2.apps.googleusercontent.com` | `serverClientId` |
| iOS | `329868845376-mlj0g6jsgpqkglocvbc87h6vprosnb40.apps.googleusercontent.com` | `clientId` sur iOS |

**Important** : Le URL Scheme iOS = Client ID inversé : `com.googleusercontent.apps.XXX`

---

### 4. Historique des Builds TestFlight

| Build | Version | Mode | Résultat | Notes |
|-------|---------|------|----------|-------|
| 1 | 1.0.0+1 | Debug | ❌ Crash | Premier test |
| 2 | 1.0.0+2 | Debug | ❌ Crash | Sans Device Preview |
| 3 | 1.0.0+3 | Debug | ❌ Crash | Avec try-catch |
| 4 | 1.0.0+4 | Debug | ❌ Crash | Splash minimaliste |
| 5 | 1.0.0+5 | Debug | ❌ Crash | Test audio |
| 6 | 1.0.0+6 | Debug | ❌ Crash | Avec Podfile |
| 7 | 1.0.0+7 | Debug | ❌ Crash | Message debug visible |
| 8 | 1.0.0+8 | **Release** | ⚠️ Partiel | App OK, Google crash |
| 9 | 1.0.0+9 | Release | ⚠️ Partiel | iOS Client ID ajouté |
| 10 | 1.0.0+10 | Release | ✅ **OK** | **Tout fonctionne !** |

---

### 5. Fichiers Modifiés (6 Février)

| Fichier | Modification |
|---------|-------------|
| `pubspec.yaml` | Version 1.0.0+10 |
| `lib/services/supabase_service.dart` | Ajout iOS Client ID + détection plateforme |
| `ios/Runner/Info.plist` | URL Schemes + GIDClientID pour Google Sign-In |

---

### 6. Leçons Apprises - iOS TestFlight

1. **Toujours compiler en RELEASE** pour TestFlight (mode Debug = crash immédiat sur iOS 14+)
2. **iOS et Android ont des Client ID différents** pour Google Sign-In
3. **Le URL Scheme iOS** doit être le Client ID inversé (`com.googleusercontent.apps.XXX`)
4. **Incrémenter la version** à chaque upload (le bundle version doit être unique)
5. **Pas de rapport de crash** dans App Store Connect pour les apps Debug (elles ne démarrent pas)

---

### 7. Configuration Codemagic Finale

```
Platform: iOS
Mode: Release ← CRITIQUE
Build type: App Store / TestFlight
Code Signing: Automatic
Publishing: App Store Connect
```

---

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

---

## Date: 7 Février 2026

---

## Session du 7 Février 2026 - Module Duel & Système d'Amis

### 1. Système de Duel - Améliorations UI

#### Page Duel (duel_screen.dart)
- **Onglets** : Duels, Amis, En Ligne, Tous
- **Barre de recherche** : Texte brun foncé (#5D3A1A) pour meilleure lisibilité
- **Cartes joueurs** : Utilisation de `Stack` avec `Positioned` pour positionnement précis des éléments

#### Éditeurs de Layout HTML
- `layout_editor.html` - Éditeur pour carte joueur standard
- `layout_editor_amis.html` - Éditeur pour carte ami (avec bouton Messages)
- Fonctionnalités : Drag & drop souris + déplacement clavier (flèches 1px, Shift+flèches 5px)

### 2. Positionnement des Cartes Joueurs

#### Carte Standard (Onglets En Ligne / Tous)
```dart
// Positions finales
Photo: left=20, top=22 (46x46px)
Nom: left=70, top=33
Pastille: left=208, top=37 (16x16px)
Bouton DÉFIER: left=249, top=26
```

#### Carte Ami (Onglet Amis)
```dart
// Positions finales
Photo: left=20, top=22 (46x46px)
Nom: left=70, top=33
Pastille: left=160, top=37 (16x16px)
Bouton Messages: left=182, top=29 (vert, non cliquable)
Bouton DÉFIER: left=266, top=29
```

### 3. Pastille En Ligne / Hors Ligne
- **Vert** : Joueur en ligne (actif < 5 minutes)
- **Rouge** : Joueur hors ligne
- Badge "Ami" supprimé (redondant dans l'onglet Amis)

### 4. Boutons Accepter/Refuser
- Remplacement des icônes ✓/✕ par des boutons texte
- **Bouton Refuser** : Dégradé rouge (#FF6B6B → #EE5A5A)
- **Bouton Accepter** : Dégradé vert (#66BB6A → #43A047)
- Style candy avec bordure blanche et ombre

### 5. Badge Notification Défis
- Déplacé de l'onglet "Duels" vers le header "DÉFIS REÇUS"
- Plus grand et centré à droite du titre
- Affiche le nombre de défis en attente

### 6. Système de Notifications en Temps Réel

#### Rafraîchissement Automatique
- Timer toutes les 5 secondes pour vérifier nouveaux duels/demandes d'amis
- Fonctionne sur toutes les pages (Duel, Jeu)

#### Notifications MaterialBanner (en haut)
- **Style** : Marges 16px horizontal, padding 10px vertical, elevation 6
- **Défi reçu** : Fond rose (#E91E63), icône manette
- **Demande d'ami** : Fond orange, icône person_add
- **Auto-fermeture** : 5 secondes
- **Conditions** : Ne s'affiche pas si déjà sur l'onglet correspondant

#### Pendant le Jeu
- Notification non cliquable (bouton "OK" seulement)
- Ne sort pas du jeu en cours
- Même style élégant

### 7. Exclusion des Amis de l'Onglet "Tous"
- `getAllPlayers()` filtre maintenant les amis existants
- Évite les doublons entre onglets

### 8. Recherche Instantanée
- Correction : recherche déclenche pour l'onglet index 3 (Tous) au lieu de 2
- Recherche en temps réel sans bouton

### 9. Icône de l'Application
- Nouvelle icône "Sugar Rush" : `app_icon.png`
- Fond adaptatif : `#1a0a2e` (violet foncé)

---

## Fichiers Modifiés (7 Février)

| Fichier | Modification |
|---------|-------------|
| `lib/ui/screens/duel_screen.dart` | Refonte complète UI, Stack/Positioned, notifications, temps réel |
| `lib/ui/screens/game_screen.dart` | Notifications pendant le jeu |
| `lib/services/friend_service.dart` | `acceptFriendRequestByPlayerId`, `declineFriendRequestByPlayerId`, exclusion amis |
| `admin/admin.js` | Gestion demandes d'amis pour faux profils |
| `admin/index.html` | Section demandes d'amis |
| `pubspec.yaml` | Asset Cadreonline.png, nouvelle icône app |
| `layout_editor.html` | Éditeur layout carte standard |
| `layout_editor_amis.html` | Éditeur layout carte ami |

---

## Tables Supabase (Rappel)

### Table `duels`
```sql
CREATE TABLE duels (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  challenger_id UUID REFERENCES players(id),
  challenged_id UUID REFERENCES players(id),
  seed INTEGER NOT NULL,
  status TEXT DEFAULT 'pending',
  challenger_score INTEGER,
  challenged_score INTEGER,
  winner_id UUID REFERENCES players(id),
  created_at TIMESTAMP DEFAULT NOW(),
  expires_at TIMESTAMP DEFAULT (NOW() + INTERVAL '24 hours')
);
```

### Table `friends`
```sql
CREATE TABLE friends (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID REFERENCES players(id),
  friend_id UUID REFERENCES players(id),
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(player_id, friend_id)
);
```

---

---

## Date: 7 Février 2026 (Suite)

---

## Session du 7 Février 2026 - Notifications Push OneSignal

### 1. Configuration OneSignal

#### Pourquoi OneSignal ?
- Plus simple que Firebase Cloud Messaging + Supabase Edge Functions
- Interface web pour configurer iOS et Android
- SDK Flutter officiel (`onesignal_flutter`)

#### Identifiants OneSignal
```
App ID: 01e66a57-6563-4572-b396-ad338b648ddf
REST API Key: os_v2_app_ahtguv3fmncxfm4wvuzywzen34cc2kxpxnsezp55pu5efdzorqujkxrvasncfgnjgjs62pt2pibtjihkuypdt7new5v6jaa3zuzosja
```

### 2. Configuration iOS (APNs)

#### Clé APNs créée dans Apple Developer
- **Nom** : CandyPuzzlePush
- **Key ID** : 999274RLFU
- **Team ID** : Z8MD4FCA29
- **Bundle ID** : com.amazingevent.candypuzzle

#### Fichiers iOS modifiés
```
ios/Runner/Runner.entitlements → aps-environment = production
ios/Runner/Info.plist → UIBackgroundModes (fetch, remote-notification)
ios/Runner/Info.plist → FirebaseAppDelegateProxyEnabled = false
```

### 3. Configuration Android

#### Icône de notification personnalisée
- Fichier : `ic_stat_onesignal_default.png`
- Format : Blanc sur fond transparent (règle Android)
- Emplacements :
  - `android/app/src/main/res/drawable-mdpi/` (24x24)
  - `android/app/src/main/res/drawable-hdpi/` (36x36)
  - `android/app/src/main/res/drawable-xhdpi/` (48x48)
  - `android/app/src/main/res/drawable-xxhdpi/` (72x72)
  - `android/app/src/main/res/drawable-xxxhdpi/` (96x96)

### 4. Service de Notifications (Flutter)

#### Fichier : `lib/services/notification_service.dart`
```dart
class NotificationService {
  static const String _oneSignalAppId = '01e66a57-6563-4572-b396-ad338b648ddf';

  static Future<void> initialize() async {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(_oneSignalAppId);
    OneSignal.Notifications.requestPermission(true);
  }

  static Future<void> updateTokenAfterLogin() async {
    final playerId = supabaseService.playerId;
    if (playerId == null) return;
    await OneSignal.login(playerId);
    await OneSignal.User.addTags({'player_id': playerId});
  }

  static Future<void> sendNewMessage({...}) async {
    await _sendNotification(
      targetPlayerId: targetPlayerId,
      title: senderName,
      body: preview,
      data: {'type': 'new_message'},
    );
  }
}
```

### 5. Edge Function Supabase

#### Fichier : `supabase/functions/send-onesignal-notification/index.ts`
- Reçoit les paramètres : target_player_id, title, body, image_url, data
- Appelle l'API REST OneSignal pour envoyer la notification
- Secret requis : `ONESIGNAL_REST_API_KEY` (dans Supabase Dashboard → Edge Functions → Secrets)

### 6. Admin Panel - Envoi de notifications

#### Modification : `admin/admin.js`
- Fonction `sendChatMessage()` appelle maintenant l'Edge Function
- Envoi automatique de notification push quand un message est envoyé depuis l'admin

```javascript
// Après insertion du message
await supabaseClient.functions.invoke('send-onesignal-notification', {
  body: {
    target_player_id: chatPartnerId,
    title: sender.username || 'Nouveau message',
    body: content.length > 50 ? content.substring(0, 50) + '...' : content,
    data: { type: 'new_message' }
  }
});
```

### 7. TestFlight - Tests Externes

#### Problème rencontré
- Les testeurs externes ne recevaient pas d'invitation
- Cause : Le build n'était pas assigné au groupe externe

#### Solution
1. App Store Connect → TestFlight → Builds iOS
2. Cliquer sur le build (ex: 1.0.0 build 20)
3. Section "Groupes" → Cliquer sur "+"
4. Ajouter le groupe externe "Candy"
5. Les testeurs externes doivent attendre l'approbation Apple (Beta App Review)

#### Types de testeurs
- **Internes** : Membres de l'équipe App Store Connect (pas d'approbation requise)
- **Externes** : N'importe quelle adresse email (approbation Apple requise)

### 8. Dépendances ajoutées

```yaml
# pubspec.yaml
dependencies:
  firebase_core: ^3.8.0
  firebase_messaging: ^15.1.5
  onesignal_flutter: ^5.1.0
```

---

## Fichiers Modifiés/Créés (7 Février - Notifications)

| Fichier | Modification |
|---------|-------------|
| `lib/services/notification_service.dart` | Réécrit pour OneSignal |
| `lib/services/message_service.dart` | Appel NotificationService.sendNewMessage |
| `lib/main.dart` | Initialisation OneSignal |
| `admin/admin.js` | Envoi notifications depuis admin |
| `ios/Runner/Runner.entitlements` | aps-environment = production |
| `ios/Runner/Info.plist` | Background Modes + FirebaseAppDelegateProxyEnabled |
| `android/app/src/main/res/drawable-*/ic_stat_onesignal_default.png` | Icône notification |
| `supabase/functions/send-onesignal-notification/index.ts` | Edge Function |
| `supabase/config.toml` | Configuration Edge Function |
| `pubspec.yaml` | Version 1.0.0+20, dépendances OneSignal |

---

## Checklist iOS Notifications Push

| Élément | Status |
|---------|--------|
| Clé APNs (.p8) créée dans Apple Developer | ✅ |
| Clé APNs configurée dans OneSignal | ✅ |
| Push Notifications activé dans App ID | ✅ |
| Runner.entitlements → aps-environment = production | ✅ |
| Info.plist → UIBackgroundModes | ✅ |
| Info.plist → FirebaseAppDelegateProxyEnabled = false | ✅ |
| CODE_SIGN_ENTITLEMENTS dans project.pbxproj | ✅ |

---

## Checklist Android Notifications Push

| Élément | Status |
|---------|--------|
| Firebase configuré dans OneSignal | ✅ |
| ic_stat_onesignal_default.png (blanc/transparent) | ✅ |
| onesignal_flutter dans pubspec.yaml | ✅ |

---

## Date: 8 Février 2026

---

## Session du 8 Février 2026 - Corrections UI Game Over

### 1. Boutons Game Over trop grands

#### Problème
- Les boutons QUITTER et REJOUER étaient trop grands
- Le bouton REJOUER sortait de l'écran (coupé à droite)

#### Solution - Réduction des tailles
```dart
// Avant → Après
padding: horizontal: 22, vertical: 14 → horizontal: 14, vertical: 10
icon container padding: 6 → 4
icon size: 22 → 18
font size: 16 → 14
letter spacing: 1.5 → 1.2
SizedBox width: 10 → 8
```

### 2. Best Score en temps réel

#### Problème
- Quand le joueur dépasse son meilleur score, l'affichage "BEST" ne se mettait pas à jour pendant le jeu
- Le Best score restait figé jusqu'au Game Over

#### Solution
- Ajout d'une vérification après chaque mise à jour du score :
```dart
// Dans setState après _score += ...
if (_score > _highScore) {
  _highScore = _score;
}
```
- Ajouté à 2 endroits :
  1. Score des lignes complétées (ligne ~948)
  2. Score des explosions Jelly Bomb (ligne ~676)

### 3. TestFlight - Lien Public

#### Fonctionnement du lien public
- Le lien reste **toujours le même** : `testflight.apple.com/join/Kpujctb1`
- Le lien est lié au **groupe**, pas au build
- Les nouvelles versions sont automatiquement disponibles via le même lien

#### Beta App Review
- Première soumission : peut prendre 24-48h
- Versions suivantes : généralement approuvées automatiquement (quelques minutes/heures)
- Statut visible : "En attente de vérification" → "Approuvé"

#### Types de testeurs
| Type | Approbation Apple | Ajout |
|------|------------------|-------|
| Internes | Non requise | Membres équipe App Store Connect |
| Externes | Requise (Beta Review) | N'importe quel email |

### 4. Avertissement iOS Info.plist

#### Message
```
90683: Missing purpose string in Info.plist - NSLocationWhenInUseUsageDescription
```

#### Explication
- C'est un **avertissement**, pas une erreur
- Provient de OneSignal qui inclut la capacité de localisation
- N'empêche pas le build de fonctionner
- Peut être ignoré si l'app n'utilise pas la localisation

---

## Fichiers Modifiés (8 Février)

| Fichier | Modification |
|---------|-------------|
| `lib/ui/screens/game_screen.dart` | Boutons plus petits + Best score temps réel |
| `pubspec.yaml` | Version 1.0.0+21 |

---

## Historique des Builds TestFlight (Récent)

| Build | Version | Contenu | Status |
|-------|---------|---------|--------|
| 20 | 1.0.0+20 | Notifications push OneSignal | En attente de vérification |
| 21 | 1.0.0+21 | Fix boutons + Best score temps réel | À compiler |

---

## Prochaines Étapes

1. ~~**Notifications push**~~ - FAIT - OneSignal configuré
2. **Tester les notifications** - Envoyer un message et vérifier réception
3. **Résultat duel VS** - Écran comparatif après duel
4. **Page Paramètres** - Son, musique, vibrations, langue

# Candy Puzzle - Référence Projet

## Stack Technique

- **Framework** : Flutter/Dart
- **Backend** : Supabase (Auth, DB, Realtime, Edge Functions)
- **Auth** : Google Sign-In (Web/Android + iOS Client IDs séparés) + mode anonyme
- **Notifications** : OneSignal (push iOS via APNs + Android via FCM)
- **CI/CD iOS** : Codemagic (Mac M2 cloud, mode RELEASE obligatoire)
- **Distribution iOS** : TestFlight (lien public : `testflight.apple.com/join/Kpujctb1`)
- **Bundle ID** : `com.amazingevent.candypuzzle`

---

## Configuration & Identifiants

### Supabase
```dart
static const String _supabaseUrl = 'https://icujwpwicsmyuyidubqf.supabase.co';
static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
```

### Google OAuth Client IDs
| Plateforme | Client ID | Usage |
|------------|-----------|-------|
| Web/Android | `329868845376-hbh8plnscagl2smu97pphatm0kanmdg2.apps.googleusercontent.com` | `serverClientId` |
| iOS | `329868845376-mlj0g6jsgpqkglocvbc87h6vprosnb40.apps.googleusercontent.com` | `clientId` sur iOS uniquement |

**iOS** : Le URL Scheme = Client ID inversé (`com.googleusercontent.apps.XXX`) dans Info.plist.

### OneSignal
```
App ID: 01e66a57-6563-4572-b396-ad338b648ddf
REST API Key: os_v2_app_ahtguv3fmncxfm4wvuzywzen34cc2kxpxnsezp55pu5efdzorqujkxrvasncfgnjgjs62pt2pibtjihkuypdt7new5v6jaa3zuzosja
```

### APNs iOS
- Key ID : `999274RLFU`
- Team ID : `Z8MD4FCA29`

### Codemagic
```
Platform: iOS
Mode: Release (CRITIQUE - Debug crash sur iOS 14+)
Build type: App Store / TestFlight
Code Signing: Automatic
API Key App Store Connect: KZBZXWQ5YW
Dernier build TestFlight : 1.0.0+27 (Build 27)
```

---

## Structure du Projet

### Services
- `lib/services/supabase_service.dart` — Auth Google + gestion joueurs + détection plateforme iOS
- `lib/services/stats_service.dart` — Stats avec sync cloud
- `lib/services/audio_service.dart` — Musique (mutable) + effets sonores (toujours actifs)
- `lib/services/screen_shake_service.dart` — Tremblement écran
- `lib/services/notification_service.dart` — OneSignal (init, login, envoi push)
- `lib/services/friend_service.dart` — Amis + simulation bots en ligne
- `lib/services/duel_service.dart` — Duels + détection bots (`device_id.startsWith('fake_')`)
- `lib/services/message_service.dart` — Messages + notifications push

### Écrans
- `lib/ui/screens/splash_screen.dart` — Démarrage
- `lib/ui/screens/auth_screen.dart` — Connexion (Google / Apple / Sans compte avec dialogue prénom)
- `lib/ui/screens/menu_screen.dart` — Menu principal + simulation bots en ligne + vérif duels bots en attente
- `lib/ui/screens/game_screen.dart` — Jeu + Sugar Rush + duels temps réel + bot intelligent
- `lib/ui/screens/profile_screen.dart` — Profil (prénom non modifiable pour anonymes)
- `lib/ui/screens/leaderboard_screen.dart` — Classement
- `lib/ui/screens/duel_screen.dart` — Onglets Duels/Amis/En Ligne/Tous + notifications temps réel

### Widgets
- `sugar_rush_widget.dart` — Jauge, overlay (unique), timer, multiplicateur x5, particules énergie
- `block_widget.dart` — Brique 1x1 (StatefulWidget, sparkle optionnel)
- `cell_widget.dart` — Cellule grille
- `piece_widget.dart` — Pièce puzzle complète
- `jelly_bomb_widget.dart` — Bombe Jelly avec étincelles + explosion 3x3
- `particle_effect.dart` — Particules et fumée
- `candy_ui.dart` — Composants UI réutilisables

### Modèles
- `game_state.dart` — État du jeu, grille, cellules, BlockType
- `piece.dart` — Modèle pièce (blocs + couleur)
- `pieces_catalog.dart` — Catalogue pièces et rotations (~4 entrées par type)

### Admin Web
- `admin/index.html` + `admin/style.css` + `admin/admin.js`
- Fonctions : gestion scores, suppression profils (cascade), envoi messages + push, demandes d'amis

### Edge Functions
- `supabase/functions/send-onesignal-notification/index.ts` — Envoi push via API OneSignal

### Outils
- `layout_editor.html` — Éditeur layout (drag & drop)
- `layout_editor_amis.html` — Éditeur carte ami

---

## Schéma Base de Données

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
  candies INTEGER DEFAULT 500,
  last_login_date DATE,
  login_streak INTEGER DEFAULT 0,
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE duels (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  challenger_id UUID REFERENCES players(id),
  challenged_id UUID REFERENCES players(id),
  seed INTEGER NOT NULL,
  status TEXT DEFAULT 'pending',
  challenger_score INTEGER,
  challenged_score INTEGER,
  winner_id UUID REFERENCES players(id),
  bet_amount INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  expires_at TIMESTAMP DEFAULT (NOW() + INTERVAL '24 hours')
);

CREATE TABLE friends (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID REFERENCES players(id),
  friend_id UUID REFERENCES players(id),
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(player_id, friend_id)
);

-- Aussi : messages, typing_status (avec FK vers players)
```

### Suppression cascade d'un joueur
Ordre : messages → typing_status → duels → friends → player_stats → players

---

## Flux de Navigation

```
Splash → Auth (Google / Apple / Sans compte + prénom) → Menu
  ├── JOUER → Game Screen
  ├── Profil → Profile Screen
  ├── Classement → Leaderboard Screen
  ├── Duels → Duel Screen (4 onglets)
  └── Déconnexion → Auth Screen
```

### Session anonyme
- Premier lancement : dialogue prénom obligatoire → sauvegarde SharedPreferences + DB
- Lancements suivants : main.dart détecte prénom dans SharedPreferences → menu direct
- `getOrCreatePlayer()` appelé dans `_loadUserData()` pour initialiser playerId

### Session Apple Sign-In (Build 25)
- `checkSession()` détecte le provider via `appMetadata['provider']` (apple vs google)
- Apple : `device_id` = `'apple_$email'` (préfixe `apple_`) — Google : `device_id` = `email`
- Le nom Apple n'est fourni qu'à la **première connexion** → sauvegardé dans SharedPreferences (`apple_user_name`)
- `_appleUserName` : champ en mémoire pour le getter `userName` (Apple n'a pas `full_name` dans userMetadata)
- Le prénom est aussi sauvegardé sous clé `'userName'` pour que `menu_screen` le retrouve
- `signOut()` nettoie `userName`, `apple_user_name` et `_appleUserName`

---

## Système Bot (Faux Profils)

### Détection
Bots identifiés par `device_id.startsWith('fake_')` dans la table `players`.

### Algorithme de duel bot (simulation locale sur le téléphone)
- **Score typique** = 40-60% du `_highScore` du joueur
- **Limite** : max 25 pts/seconde

| Scénario | Probabilité | Score bot | Durée |
|----------|-------------|-----------|-------|
| Bot PERD | 45% | 40-80% du score typique | 40s-120s |
| Bot GAGNE | 45% | 110-150% du score typique | 80s-220s |
| Match serré | 10% | 85-115% du score typique | 60s-180s |

### Score par bursts progressifs
| Phase | Lignes | Points/burst | Pause |
|-------|--------|-------------|-------|
| 0-25% | 1 | 100-250 | 8-18s |
| 25-50% | 1-2 | 100-550 | 5-14s |
| 50-75% | 1-3 | 100-900 | 5-14s |
| 75-100% | 1-4 | 100-1500 | 3-10s |

Première ligne entre 12 et 22 secondes.

### Soumission différée
Si le joueur quitte avant la fin du bot : infos sauvées dans SharedPreferences (`pending_bot_*`), score soumis au retour via `_checkPendingBotCompletion()`.

### Simulation présence en ligne
- **Démarrage** : 20-50% des bots mis en ligne (min 1, max 8), refresh toutes les 45s
- **Rotation** : changement de groupe toutes les 3-5 minutes
- **Mouvement live** : toutes les 15-40s, un bot se connecte/déconnecte
- **Auto-équilibrage** : <15% en ligne → 85% chance connexion ; >45% → 70% chance déconnexion

---

## Système Sugar Rush

- Jauge se remplit en complétant des lignes (animation Lerp)
- À 100% : multiplicateur x5 pendant 10 secondes, overlay unique avec confettis
- Étincelles progressives sur l'étoile (3 à 22 selon remplissage, bouquet final ≥90%)
- Particules d'énergie des lignes vers la jauge (12 max, taille 16px, traînée 14 positions)

---

## Système Audio

- **Musique** (mutable via bouton) : intro + game music
- **Effets** (toujours actifs) : placement (`place.mp3`), combos, explosions
- Bouton mute : cercle 40px en haut à droite, rose = actif, gris = coupé

---

## Notifications Temps Réel

- Timer 5s pour vérifier nouveaux duels/demandes d'amis
- MaterialBanner en haut : rose (défi reçu), orange (demande ami), auto-fermeture 5s
- Pendant le jeu : notification non cliquable (bouton OK uniquement)

---

## Commandes Build

```bash
# APK Android
flutter build apk --release

# Clean build
flutter clean && flutter build apk --release

# APK location
build/app/outputs/flutter-apk/app-release.apk

# Icônes
dart run flutter_launcher_icons

# iOS via Codemagic : push GitHub → build automatique → TestFlight
```

---

## Dépendances Principales

```yaml
dependencies:
  flutter: { sdk: flutter }
  shared_preferences: ^2.2.2
  audioplayers: ^5.2.1
  supabase_flutter: ^2.3.0
  google_sign_in: ^6.1.6
  firebase_core: ^3.8.0
  firebase_messaging: ^15.1.5
  onesignal_flutter: ^5.1.0
```

---

## Points Importants à Retenir

- **iOS TestFlight** : toujours compiler en mode RELEASE (Debug = crash immédiat iOS 14+)
- **Google Sign-In iOS** : nécessite un Client ID spécifique + URL Scheme inversé dans Info.plist
- **Joueurs anonymes** : prénom obligatoire, non modifiable, session via SharedPreferences
- **Best score** : mis à jour en temps réel pendant le jeu (`if (_score > _highScore)`)
- **Game Screen layout** : positionnement absolu via Stack/Positioned (pourcentages écran)
- **Boutons Game Over** : layout avec `Expanded` dans un `Row` pour éviter dépassement
- **Icône iOS** : pas de transparence (`remove_alpha_ios: true`, fond `#87CEEB`)
- **Icône notification Android** : blanc sur transparent (`ic_stat_onesignal_default.png`)
- **Suppression profil admin** : cascade obligatoire (messages → typing → duels → friends → stats → player)
- **Chiffrement TestFlight** : répondre "Aucun des algorithmes mentionnés" (HTTPS standard iOS)
- **Apple Sign-In** : `checkSession()` DOIT détecter le provider Apple vs Google (sinon boucle navigation infinie)
- **Apple Sign-In** : le nom n'est donné qu'à la 1ère connexion → toujours sauvegarder dans SharedPreferences

---

## Système de Bonbons (Build 26 — Implémenté)

### Monnaie du jeu
- **500 bonbons** offerts à l'inscription (valeur par défaut dans `player_stats.candies`)
- Sources de gain :
  - Partie solo terminée : 10-50 bonbons (score / 200, clamped)
  - Compléter une ligne : 2 bonbons par ligne
  - Combo (2+ lignes en enchaînement) : 5 × comboCount bonbons
  - Connexion quotidienne : 30 bonbons (+10/jour consécutif, max 100)
  - Gagner un duel : mise × 2 + 10 bonbons bonus
  - Nouveau record perso : +100 bonbons
- **Mise en duel** : minimum 20, défaut 50, max = solde. Popup sélection (20/50/100/Tout)
- **Pas de bonbons = pas de duel** (< 20 → message "Joue en solo pour gagner des bonbons !")
- Solde affiché dans le header du menu + carte dorée dans le profil + badge mise sur les duels
- `stats_service.dart` : `candies`, `addCandies()`, `removeCandies()`, `canAffordDuel`, `checkDailyLogin()`
- `game_screen.dart` : `_sessionCandiesEarned` accumulé pendant la partie, affiché au game over

### Connexion quotidienne
- `checkDailyLogin()` dans stats_service, appelé dans `menu_screen._loadUserData()`
- Compare `last_login_date` (YYYY-MM-DD) avec aujourd'hui
- Streak incrémenté si jour consécutif, reset sinon
- Popup "Bonus quotidien !" avec montant et jour de streak

---

## Système de Combo (Build 26 — 3 coups de grâce)

- **Ancien** : combo reset si pas de ligne au coup suivant immédiat (`_lastMoveWasLine`)
- **Nouveau** : `_comboGraceMovesLeft` = 3 coups de grâce
  - Ligne complétée → `_comboCount += linesCleared`, `_comboGraceMovesLeft = 3`
  - Placement sans ligne → `_comboGraceMovesLeft--`
  - Si atteint 0 → `_comboCount = 0` (combo perdu)
- Multiplicateur inchangé : `_comboCount * 0.5 + 0.5` (x2=1.5, x3=2.0, x5=3.0)
- Plus accessible, plus stratégique, moins frustrant

---

## Bouton "JOUER EN LIGNE" (Build 26 — Connecté aux bonbons)

- Bouton violet empilé sous le bouton JOUER
- Popup joueurs en ligne + bouton DÉFIER
- **Flux** : vérif solde ≥ 20 → popup mise → déduction bonbons → création duel avec `betAmount`
- Bot = auto-accept, joueur réel en ligne = DuelLobbyScreen
- `duel.dart` : champ `betAmount` (int, défaut 0)
- `duel_service.dart` : paramètre `betAmount` dans `createDuel()`
- `duel_screen.dart` : badge 🍬 avec mise affichée sur chaque carte de duel

---

## Prochaines Étapes

- [ ] Tester les notifications push (envoi message → vérifier réception)
- [ ] Page Paramètres (son, musique, vibrations, langue)
- [ ] Nouveaux modes de jeu (défis, tournois)
- [ ] Power-ups
- [ ] Sugar Rush : mis de côté pour l'instant

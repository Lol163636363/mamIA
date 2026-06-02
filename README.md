<div align="center">

```
███╗   ███╗ █████╗ ███╗   ███╗ █████╗ ██╗
████╗ ████║██╔══██╗████╗ ████║██╔══██╗██║
██╔████╔██║███████║██╔████╔██║███████║██║
██║╚██╔╝██║██╔══██║██║╚██╔╝██║██╔══██║██║
██║ ╚═╝ ██║██║  ██║██║ ╚═╝ ██║██║  ██║██║
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝
```

**Memory · Agenda · Master · AI**

*Assistant vocal 100 % local — parole → IA → voix, zéro cloud.*

---

[![Flutter](https://img.shields.io/badge/Flutter-≥3.29-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-≥3.0-0175C2?style=flat-square&logo=dart&logoColor=white)](https://dart.dev)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=flat-square&logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-backend-009688?style=flat-square&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![NixOS](https://img.shields.io/badge/Nix-shell-5277C3?style=flat-square&logo=nixos&logoColor=white)](https://nixos.org)
[![License](https://img.shields.io/badge/Licence-MIT-white?style=flat-square)](LICENSE)

</div>

---

## Vue d'ensemble

mamAI est un assistant vocal personnel qui tourne **entièrement en local**, sans aucune donnée envoyée vers un serveur tiers. Vous parlez, l'IA réfléchit sur votre machine, et vous répond à voix haute.

```
┌─────────────┐     mot-clé     ┌──────────────┐     HTTP/JSON     ┌─────────────────┐
│   🎙️  Voix  │ ─────────────► │  Flutter App │ ────────────────► │  FastAPI + LLM  │
│  (Android)  │                 │  speech_to_  │                   │  (local Python) │
│             │ ◄───────────── │  text + STT  │ ◄──────────────── │  Piper TTS      │
└─────────────┘    audio WAV    └──────────────┘    audio bytes    └─────────────────┘
```

---

## Fonctionnalités

| | Fonctionnalité | Détail |
|---|---|---|
| 🎙️ | **Mot-clé personnalisé** | Choisissez votre propre wake word — "Hey mamAI", "Jarvis", n'importe quoi |
| 🔁 | **Écoute en boucle** | Détection continue du mot-clé sans appui de bouton |
| 🤖 | **IA 100 % locale** | Backend FastAPI, aucun appel vers OpenAI ou équivalent |
| 🔊 | **Synthèse vocale** | Réponses lues avec Piper TTS, qualité naturelle |
| 💾 | **Persistance** | Mot-clé et historique sauvegardés localement |
| 📱 | **Android arm64** | Optimisé pour téléphones récents (Pixel, Samsung, etc.) |

---

## Stack technique

```
┌─────────────────────────────────────────────────┐
│  MOBILE (Flutter / Dart)                        │
│  ├── speech_to_text  ^7.1.0   reconnaissance    │
│  ├── audioplayers    ^5.2.1   lecture TTS       │
│  ├── http            ^1.2.0   appels backend    │
│  ├── permission_handler ^11   micro runtime     │
│  └── shared_preferences ^2    stockage local    │
├─────────────────────────────────────────────────┤
│  BACKEND (Python 3.12)                          │
│  ├── FastAPI + Uvicorn        API REST          │
│  ├── httpx                    client HTTP async │
│  └── Piper TTS                synthèse vocale   │
├─────────────────────────────────────────────────┤
│  BUILD                                          │
│  ├── Android SDK 34 · NDK 27 · JDK 17           │
│  └── Nix shell (NixOS reproducible build)       │
└─────────────────────────────────────────────────┘
```

---

## Installation

### Prérequis

- [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.29 + Dart ≥ 3.0
- Python 3.12
- Android SDK 34, NDK 27, JDK 17
- *(ou simplement NixOS + `nix-shell`)*

### 1 — Cloner

```bash
git clone https://github.com/Lol163636363/mamIA.git
cd mamIA
```

### 2 — Dépendances Flutter

```bash
flutter pub get
```

### 3 — Démarrer le backend

```bash
cd backend
pip install fastapi uvicorn httpx
uvicorn main:app --host 0.0.0.0 --port 8000
```

> **Note :** si vous utilisez un tunnel Cloudflare pour exposer le backend depuis votre PC vers le téléphone, remplacez l'URL dans `lib/pages/chat_page.dart` :
> ```dart
> const String _apiUrl = 'https://VOTRE-TUNNEL.trycloudflare.com/chat';
> ```

### 4 — Lancer l'application

```bash
# Debug sur appareil connecté
flutter run

# Build release APK arm64
flutter build apk --release --target-platform android-arm64
```

L'APK se trouve dans `build/app/outputs/flutter-apk/app-release.apk`.

---

## Environnement NixOS

Un `shell.nix` reproduit l'intégralité de l'environnement de build, incluant Flutter, le SDK Android 34, NDK 27, JDK 17, Python 3.12 et Piper TTS.

```bash
nix-shell
# ANDROID_HOME, ANDROID_NDK_HOME et JAVA_HOME sont configurés automatiquement
# AAPT2 est patché pour la compatibilité NixOS

flutter build apk --release --target-platform android-arm64
```

---

## Permissions Android

| Permission | Raison |
|---|---|
| `RECORD_AUDIO` | Capture microphone pour la reconnaissance vocale |
| `INTERNET` | Communication avec le backend local (ou tunnel) |
| `BLUETOOTH_CONNECT` | Support casques et écouteurs Bluetooth |

---

## Structure du projet

```
mamIA/
├── lib/
│   ├── main.dart              # Entrée app, routing setup → chat
│   └── pages/
│       ├── setup_page.dart    # Choix du mot-clé (1ère ouverture)
│       └── chat_page.dart     # Boucle écoute → IA → TTS
├── android/                   # Config Android (SDK, NDK, permissions)
├── ios/                       # Support iOS (optionnel)
├── backend/                   # Serveur FastAPI + Piper TTS
├── shell.nix                  # Environnement NixOS reproductible
├── pubspec.yaml               # Dépendances Flutter
└── codemagic.yaml             # CI/CD (build APK automatique)
```

---

## CI/CD

Le fichier `codemagic.yaml` à la racine configure deux workflows automatiques sur [Codemagic](https://codemagic.io) :

- **`android-release`** — APK signé arm64 sur `main` et les tags
- **`android-debug`** — APK debug rapide sur `develop` et `feature/*`

---

## Contribuer

Les contributions sont bienvenues.

```bash
git checkout -b feature/ma-fonctionnalite
git commit -m 'feat: description claire'
git push origin feature/ma-fonctionnalite
# → ouvrir une Pull Request
```

---

## Licence

MIT — voir [LICENSE](LICENSE).

---

<div align="center">
<sub>Fait tourner l'IA chez toi. Pas dans le cloud de quelqu'un d'autre.</sub>
</div>

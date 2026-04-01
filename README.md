# 🧠 mamAI — Memory Agenda Master AI

> Assistant vocal intelligent, entièrement **local** — parole → IA → voix, sans cloud.

[![Flutter](https://img.shields.io/badge/Flutter-≥3.29-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-≥3.0-0175C2?logo=dart)](https://dart.dev)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-backend-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![NixOS](https://img.shields.io/badge/Nix-shell-5277C3?logo=nixos)](https://nixos.org)

---

## ✨ Fonctionnalités

- 🎙️ **Reconnaissance vocale** — capture la voix en temps réel via `speech_to_text`
- 🤖 **IA locale** — traitement des requêtes via un backend FastAPI (aucun envoi vers le cloud)
- 🔊 **Synthèse vocale** — réponses lues à voix haute avec [Piper TTS](https://github.com/rhasspy/piper) et `audioplayers`
- 💾 **Persistance** — préférences et historique sauvegardés localement (`shared_preferences`)
- 📱 **Multi-plateforme** — Android (arm64 prioritaire), avec support potentiel iOS/desktop

---

## 🗂️ Structure du projet

```
mamIA/
├── lib/                        # Code source Flutter (Dart)
├── android/                    # Configuration Android (SDK, NDK)
├── shell.nix                   # Environnement de développement NixOS
├── pubspec.yaml                # Dépendances Flutter
└── analysis_options.yaml       # Règles de linting Dart
```

---

## 🛠️ Stack technique

| Couche | Technologie |
|---|---|
| Frontend / Mobile | Flutter + Dart |
| Backend IA | Python 3.12 · FastAPI · Uvicorn |
| Reconnaissance vocale | `speech_to_text` ^6.6.0 |
| Synthèse vocale | Piper TTS · `audioplayers` ^5.2.1 |
| Réseau | `http` ^1.2.0 · `httpx` |
| Permissions | `permission_handler` ^11.3.0 |
| Stockage local | `shared_preferences` ^2.2.3 |
| Env. de build | Nix shell · Android SDK 34 · NDK 27 · JDK 17 |

---

## 🚀 Installation & Lancement

### Prérequis

- [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.29
- Dart ≥ 3.0
- Python 3.12
- Android SDK 34 + NDK 27 (ou utiliser le `shell.nix` sur NixOS)

---

### 1. Cloner le dépôt

```bash
git clone https://github.com/Lol163636363/mamIA.git
cd mamIA
```

### 2. Installer les dépendances Flutter

```bash
flutter pub get
```

### 3. Démarrer le backend Python

```bash
cd backend         # ou le dossier contenant le serveur FastAPI
pip install fastapi uvicorn httpx
uvicorn main:app --host 0.0.0.0 --port 8000
```

### 4. Lancer l'application Flutter

```bash
# En mode debug sur un appareil connecté
flutter run

# Build release Android arm64
flutter build apk --release --target-platform android-arm64
```

---

## ❄️ Environnement NixOS (optionnel)

Un `shell.nix` est fourni pour reproduire l'environnement de build complet sur NixOS, incluant Flutter, Android SDK 34, NDK 27, JDK 17, Python 3.12 et Piper TTS.

```bash
nix-shell
# Le shell configure automatiquement ANDROID_HOME, ANDROID_NDK_HOME, JAVA_HOME
# et patche AAPT2 pour la compatibilité NixOS

flutter build apk --release --target-platform android-arm64
```

---

## 🔐 Permissions requises

L'application demande les permissions suivantes à l'exécution :

| Permission | Usage |
|---|---|
| `RECORD_AUDIO` | Capture vocale (speech-to-text) |
| `INTERNET` | Communication avec le backend local |

---

## 📦 Dépendances principales

```yaml
dependencies:
  speech_to_text: ^6.6.0      # Reconnaissance vocale
  audioplayers: ^5.2.1        # Lecture audio (réponses TTS)
  http: ^1.2.0                # Appels vers le backend FastAPI
  permission_handler: ^11.3.0 # Gestion des permissions runtime
  shared_preferences: ^2.2.3  # Stockage local des préférences
```

---

## 🤝 Contribuer

Les contributions sont les bienvenues !

1. Forker le projet
2. Créer une branche (`git checkout -b feature/ma-fonctionnalite`)
3. Commiter les changements (`git commit -m 'feat: ajout de ...'`)
4. Pousser la branche (`git push origin feature/ma-fonctionnalite`)
5. Ouvrir une Pull Request

---

## 📄 Licence

Ce projet est sous licence **MIT** — voir le fichier [LICENSE](LICENSE) pour plus de détails.

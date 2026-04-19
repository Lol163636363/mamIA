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
[![License](https://img.shields.io/badge/Licence-MIT-white?style=flat-square)](LICENSE)

</div>

---

## Vue d'ensemble

mamAI est un assistant vocal personnel qui tourne **entièrement en local**. Vous parlez, l'IA réfléchit sur votre machine, et vous répond à voix haute.

```
┌─────────────┐     mot-clé     ┌──────────────┐     HTTP/JSON     ┌─────────────────┐
│   🎙️  Voix  │ ─────────────► │  Flutter App │ ────────────────► │  FastAPI + LLM  │
│  (Android)  │                 │  Vosk (local)│                   │  (local Python) │
│             │ ◄───────────── │  audio WAV   │ ◄──────────────── │  Piper TTS      │
└─────────────┘    audio WAV    └──────────────┘    audio bytes    └─────────────────┘
```

---

## Installation de Flutter (Méthode 100% fiable)

Si l'AUR (`yay`) vous propose des choix confus comme `flutter-artifacts-engine`, utilisez cette méthode manuelle qui fonctionne sur **Arch, Ubuntu, Fedora**, etc.

### 1. Télécharger le SDK
```bash
# Créer un dossier pour vos outils
mkdir -p ~/development
`cd ~/development`

# Télécharger Flutter (Stable)
git clone https://github.com/flutter/flutter.git -b stable
```

### 2. Ajouter au PATH
Ajoutez Flutter à votre PATH pour qu'il soit accessible partout.

**Pour Bash ou Zsh :**
Ajoutez ceci à la fin de votre `~/.bashrc` ou `~/.zshrc` :
```bash
export PATH="$PATH:$HOME/development/flutter/bin"
```

**Pour Fish :**
Lancez cette commande :
```fish
fish_add_path $HOME/development/flutter/bin
```

### 3. Configurer Android
```bash
# Vérifier l'installation
flutter doctor

# Accepter les licences (indispensable pour l'APK)
flutter doctor --android-licenses
```

---[app-release.apk](android/app/build/outputs/apk/release/app-release.apk)

## Installation du projet

```bash
git clone https://github.com/Lol163636363/mamIA.git
cd mamIA

# Récupérer les dépendances du projet
flutter pub get
```

---

## Lancement & Build

### 1. Démarrer le backend (Serveur IA)
```bash
cd backend
pip install fastapi uvicorn httpx
uvicorn main:app --host 0.0.0.0 --port 8000
```

### 2. Compiler l'APK (Android)
Assurez-vous d'avoir bien mis le modèle Vosk dans `assets/models/vosk-model-small-fr/`.
```bash
flutter build apk --release --target-platform android-arm64
```
L'APK sera généré dans : `build/app/outputs/flutter-apk/app-release.apk`

---

## Pourquoi Vosk ?
Nous avons migré vers **Vosk** pour supprimer la limite des 10 secondes imposée par Google STT. mamIA peut maintenant vous écouter indéfiniment sans coupure, tout en restant 100 % locale.

---

## Licence
MIT — voir [LICENSE](LICENSE).

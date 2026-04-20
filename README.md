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

[![Android Native](https://img.shields.io/badge/Android-Native-3DDC84?style=flat-square&logo=android&logoColor=white)](https://developer.android.com)
[![Kotlin](https://img.shields.io/badge/Kotlin-1.9-7F52FF?style=flat-square&logo=kotlin&logoColor=white)](https://kotlinlang.org)
[![Jetpack Compose](https://img.shields.io/badge/Jetpack-Compose-4285F4?style=flat-square&logo=jetpackcompose&logoColor=white)](https://developer.android.com/jetpack/compose)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=flat-square&logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-backend-009688?style=flat-square&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)

</div>

---

## Vue d'ensemble

mamAI est un assistant vocal personnel qui tourne **entièrement en local**. Initialement développé en Flutter, le projet a migré vers une architecture **Android Native (Kotlin + Compose)** pour une stabilité et une réactivité maximale.

```
┌─────────────┐     mot-clé     ┌──────────────┐     HTTP/JSON     ┌─────────────────┐
│   🎙️  Voix  │ ─────────────► │ Native App   │ ────────────────► │  FastAPI + LLM  │
│  (Android)  │                 │ Vosk (Kotlin)│                   │  (local Python) │
│             │ ◄───────────── │ AudioTrack   │ ◄──────────────── │  Piper TTS      │
└─────────────┘    audio PCM    └──────────────┘    audio bytes    └─────────────────┘
```

---

## Installation (Développement Native)

### 1. Prérequis
- **Android SDK** (installé dans `~/Android/Sdk`).
- **Java 17+**.
- **ADB** pour l'installation sur périphérique.

### 2. Configuration du Modèle Vosk
Le modèle français doit être placé dans :
`android/app/src/main/assets/model-fr/`

---

## Lancement & Build

### 1. Démarrer le backend (Serveur IA)
Le serveur doit être configuré pour renvoyer le texte de réponse dans le header `X-Response-Text` et les octets audio (PCM 22050Hz) dans le corps de la réponse.
```bash
# Exemple de lancement
cd backend
python main.py
```

### 2. Compiler l'APK
Depuis la racine du projet :
```bash
cd android
./gradlew assembleDebug
```
L'APK sera généré dans : `android/app/build/outputs/apk/debug/app-debug.apk`

### 3. Installation
```bash
adb install android/app/build/outputs/apk/debug/app-debug.apk
```

---

## Pourquoi le passage au Natif (Kotlin) ?
- **Performance** : Suppression de la latence du bridge Flutter/Dart.
- **Vosk Direct** : Utilisation de l'API Android native de Vosk pour une écoute continue sans faille.
- **Stabilité** : Meilleure gestion des ressources système sur Arch Linux et Android.

---

## Licence
MIT — voir [LICENSE](LICENSE).

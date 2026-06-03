<div align="center">

```
███╗   ███╗ █████╗ ███╗   ███╗ █████╗ ██╗
████╗ ████║██╔══██╗████╗ ████║██╔══██╗██║
██╔████╔██║███████║██╔████╔██║███████║██║
██║╚██╔╝██║██╔══██║██║╚██╔╝██║██╔══██║██║
██║ ╚═╝ ██║██║  ██║██║ ╚═╝ ██║██║  ██║██║
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝
```

**Intelligence Artificielle Personnelle Native**

*Assistant vocal Android Natif — Vosk (STT) · Groq (LLM) · Android TTS*

---

[![Android Native](https://img.shields.io/badge/Platform-Android_Native-3DDC84?style=flat-square&logo=android&logoColor=white)](https://developer.android.com)
[![Kotlin](https://img.shields.io/badge/Kotlin-1.9-7F52FF?style=flat-square&logo=kotlin&logoColor=white)](https://kotlinlang.org)
[![Compose](https://img.shields.io/badge/Jetpack_Compose-UI-4285F4?style=flat-square&logo=jetpackcompose&logoColor=white)](https://developer.android.com/jetpack/compose)
[![Groq](https://img.shields.io/badge/LLM-Groq_Llama_3.3-orange?style=flat-square)](https://groq.com)
[![License](https://img.shields.io/badge/Licence-MIT-white?style=flat-square)](LICENSE)

</div>

---

## Vue d'ensemble

mamIA est un assistant vocal personnel **Android Natif** conçu pour la rapidité et l'intégration profonde avec le système. Il utilise **Vosk** pour une reconnaissance vocale hors-ligne et l'API **Groq** pour une intelligence de pointe.

```
┌─────────────┐      Audio      ┌──────────────┐     Action/Text    ┌──────────────┐
│   🎙️  STT   │ ─────────────► │   Android    │ ────────────────► │   Agenda     │
│   (Vosk)    │   (Offline)     │   (Kotlin)   │    (Native SDK)    │   Local      │
└─────────────┘                 └──────┬───────┘                    └──────────────┘
                                       │
                                       ▼
                                ┌──────────────┐
                                │   Groq API   │
                                │   (LLM)      │
                                └──────────────┘
```

---

## Fonctionnalités

| | Fonctionnalité | Détail |
|---|---|---|
| 🎙️ | **Wake Word** | Détection du mot-clé personnalisé ("mamai" par défaut). |
| 📅 | **Gestion Agenda** | Lecture, ajout sécurisé avec pop-up de confirmation et redirection. |
| 🤖 | **Llama 3.3 (Groq)** | Intelligence ultra-rapide pour des réponses concises. |
| 🔊 | **Synthèse Vocale** | Utilisation du moteur Text-To-Speech natif d'Android. |
| 🔏 | **Confidentialité** | Pas de backend tiers complexe; intégration directe API. |
| ✨ | **UI Moderne** | Interface Jetpack Compose avec animations réactives. |

---

## Stack technique

- **Langage :** Kotlin 1.9
- **UI :** Jetpack Compose (Material 3)
- **STT :** Vosk (Modèle français hors-ligne)
- **LLM :** Groq Cloud API (Llama 3.3 70B)
- **TTS :** Android TextToSpeech API
- **Permissions :** Record Audio, Calendar (Read/Write)

---

## Installation

### 1 — Configuration Groq
Obtenez une clé API sur [Groq Cloud](https://console.groq.com/) et remplacez-la dans `MainActivity.kt`.

### 2 — Build & Run
Ouvrez le projet dans **Android Studio Jellyfish** (ou plus récent) et lancez l'application sur un appareil physique pour de meilleures performances STT.

```bash
./gradlew assembleDebug
```

---

## Structure du projet

```
mamIA/
├── app/
│   ├── src/main/kotlin/com/example/mamai/
│   │   └── MainActivity.kt    # Cœur de l'application (Vosk, TTS, Groq, UI)
│   ├── src/main/assets/       # Modèles Vosk (model-fr)
│   └── build.gradle.kts       # Dépendances Android Native
├── rapport_04-06-2026.md      # Dernier état d'avancement
└── README.md                  # Documentation (vous êtes ici)
```

---

## Licence

MIT — voir [LICENSE](LICENSE).

---

<div align="center">
<sub>mamIA — L'IA qui connaît votre agenda, pas vos secrets.</sub>
</div>

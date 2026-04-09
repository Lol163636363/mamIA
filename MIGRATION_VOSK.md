# 🎙️ Migration vers Vosk (Reconnaissance Vocale Locale)

Ce document explique le passage de la bibliothèque `speech_to_text` standard d'Android vers **Vosk**, pour une expérience "100 % locale" et sans interruptions.

## ⚠️ Le Problème Initial
L'ancienne implémentation utilisait `speech_to_text`, qui repose sur les services Google (STT) d'Android. Cela posait deux problèmes majeurs pour **mamIA** :
1. **La limite des 10 secondes** : Le moteur Google coupait automatiquement l'écoute après 10 secondes de silence ou d'activité, rendant la détection du "mot-clé" (wake word) instable et nécessitant des relances permanentes du micro.
2. **Dépendance Cloud** : Bien que partiellement local, la qualité dépendait souvent de la connexion internet et des mises à jour des services Google Play.

## ✅ La Solution : Vosk
Vosk est une bibliothèque de reconnaissance vocale **entièrement hors-ligne**.
- **Écoute continue** : Le micro reste ouvert indéfiniment. Plus de coupure après 10 secondes.
- **Zéro Cloud** : Aucune donnée ne quitte jamais le téléphone.
- **Réactivité** : Détection du mot-clé quasi-instantanée grâce à un modèle léger chargé en mémoire.

---

## 🛠️ Démarche d'Installation

### 1. Dépendances (`pubspec.yaml`)
Nous avons remplacé `speech_to_text` par `vosk_flutter` :
```yaml
dependencies:
  vosk_flutter: ^0.2.1
```

### 2. Téléchargement du Modèle (Obligatoire)
Vosk nécessite un modèle de langue pour comprendre le français.
1. Téléchargez le modèle : [vosk-model-small-fr-0.22.zip](https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip)
2. Extrayez le contenu dans le dossier du projet :
   `assets/models/vosk-model-small-fr/`
   
*Note : Le dossier doit contenir les sous-dossiers `am`, `conf`, `graph`, etc.*

### 3. Déclaration des Assets
Le modèle est déclaré dans le `pubspec.yaml` pour être embarqué dans l'APK :
```yaml
flutter:
  assets:
    - assets/models/vosk-model-small-fr/
```

### 4. Code : Changement de Logique
- **Anciennement** : On lançait une "session" d'écoute qui s'arrêtait seule.
- **Maintenant** : On initialise un `SpeechService` qui tourne en tâche de fond. On écoute le flux de `partial results` pour détecter le mot-clé, puis on capture le `final result` pour envoyer la commande au backend.

---

## 🚀 Résultat pour l'utilisateur
- **Stabilité** : mamIA vous écoute en permanence sans jamais se fatiguer.
- **Rapidité** : La transition entre "J'écoute le mot-clé" et "Je traite la commande" est immédiate.
- **Confidentialité** : Même en mode avion, la reconnaissance vocale fonctionne.

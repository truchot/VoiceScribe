# VoiceScribe — Transcription locale + Coach commercial empathique

Application macOS native pour la transcription en temps réel avec analyse émotionnelle et coaching empathique.

## Architecture

```
Audio Sources
  Microphone ──→ Mic VAD ──→ Whisper #1 (→ Moi 🔵) ──→ Session Segments
  System Audio ─┬→ Sys VAD ──→ Whisper #2 (→ Participant 🟢) ─┘     │
                └→ Sentiment Analyzer (~50ms) ──→ Coach Suggestions   │
                                                                      ↓
                                                             SQLite Auto-Save
```

## Fonctionnalités

- **whisper.cpp** Metal GPU + Silero VAD + déduplication
- **Analyse sentiment temps réel** (~50ms) : pitch, énergie, pauses, jitter, prosodie
- **Coach empathique** : phrases contextuelles selon l'état émotionnel du prospect
- **SQLite** auto-save + recherche plein texte FTS5
- **Raccourcis globaux** : ⌥⇧R/S/N depuis Zoom/Teams

## Coach commercial

| Émotion | Le coach suggère |
|---------|------------------|
| 😤 Frustré | Validation, empathie, nommer la préoccupation |
| 🤔 Hésitant | Questions ouvertes, réassurance, espace de parole |
| 😶 Désengagé | Recentrage sur leurs priorités |
| 🤩 Enthousiaste | Ancrage positif, passage à l'action |
| 😊 Satisfait | Approfondissement, verbalisation du positif |
| 😎 Confiant | Avancement vers le closing |

Chaque suggestion : phrase + rationale + 3 variantes + niveau d'urgence.

## Installation

```bash
chmod +x setup.sh && ./setup.sh
open VoiceScribe.xcodeproj
```

Xcode : Bridging Header, whisper.cpp headers/libs, Accelerate + Metal + ScreenCaptureKit.

## 20 fichiers Swift, ~4 900 lignes. 100% local.

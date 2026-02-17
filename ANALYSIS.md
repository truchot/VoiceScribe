# Analyse approfondie de VoiceScribe — Améliorations proposées

> Date : 2026-02-16

---

## 1. État actuel de l'application

### Architecture

VoiceScribe est une application macOS native (~10 900 lignes Swift) organisée en 4 couches :

| Couche | Fichiers | Rôle |
|--------|----------|------|
| **Domain** | 12 | Modèles purs, protocoles, logique métier (Foundation only) |
| **Application** | 9 | Stores, coordinateur, injection de dépendances |
| **Infrastructure** | 14 | Implémentations concrètes (audio, persistence, transcription) |
| **Presentation** | 14 | SwiftUI, overlays, UI |

**Stack technique :**
- SwiftUI (macOS 26.0), architecture MVVM + protocoles
- **STT** : whisper.cpp (Whisper large-v3-turbo) avec accélération Metal GPU
- **VAD** : Silero VAD (implémentation heuristique intégrée)
- **Sentiment** : Analyse prosodique custom (pitch, énergie, débit, pauses, jitter)
- **Coaching** : Moteur de coaching commercial par phases (BANT)
- **Persistence** : SQLite WAL + FTS5

### Pipeline actuel

```
Microphone (16kHz) ──→ Silero VAD ──→ Whisper #1 ──→ Segments ("Moi")
Audio Système (16kHz) ──→ Silero VAD ──→ Whisper #2 ──→ Segments ("Participant")
                              ↓
                     SentimentAnalyzer ──→ Émotions (~50ms)
                              ↓
                     CommercialCoachEngine ──→ Suggestions
```

### Points forts actuels
- Architecture post-refactor propre (0 force unwrap, DI par protocoles, composition root)
- Dual-stream (micro + audio système) via ScreenCaptureKit
- Coaching commercial contextuel par phases de vente
- Analyse de sentiment en temps réel par prosodie
- Persistence automatique avec recherche full-text
- Hotkeys globaux et overlay flottant

### Limitations identifiées
- **Pas de tests** : Aucune suite de tests unitaires ou d'intégration
- **Pas de vrai diarization** : On assume "moi" = micro, "participant" = audio système
- **Pas de streaming** : Whisper traite les chunks séquentiellement
- **Sentiment uniquement prosodique** : Pas d'analyse sémantique du texte
- **Français hardcodé** par défaut, changement nécessite un redémarrage
- **Phase detection** par mots-clés heuristiques uniquement
- **Blueprints.json** (78KB) chargé entièrement au démarrage

---

## 2. Modèles STT alternatifs à Whisper

### 2.1 Voxtral (Mistral AI) — Recommandation #1 pour le français

**Pourquoi c'est le meilleur candidat :**

- **Développé par une entreprise française** (Mistral AI, Paris), optimisé nativement pour le français
- **Surpasse Whisper large-v3** sur tous les benchmarks (FLEURS, Common Voice)
- **Surpasse GPT-4o mini Transcribe et Gemini 2.5 Flash**
- **~4% WER** sur FLEURS (vs ~5-6% pour Whisper large-v3 en français)
- **Apache 2.0** — licence pleinement open source
- **Deux variantes** :
  - **Voxtral Mini Transcribe V2** (3B params) — idéal pour edge/local, 4 GB RAM
  - **Voxtral Realtime** — 480ms de latence, conçu pour les appels en temps réel
- **Speaker diarization intégrée** dans Voxtral Realtime
- **13 langues** dont le français avec détection automatique
- **$0.003/min** via API (ou self-hosted gratuit)

**Impact pour VoiceScribe :** Remplacement direct de whisper.cpp avec meilleure précision en français, latence réduite, et diarization native.

**Défi d'intégration :** Voxtral est un modèle PyTorch/Transformers. Pas de port C++ natif type whisper.cpp. Deux options :
1. Intégration via un serveur local Python (mlx ou vllm) communiquant par WebSocket
2. Attendre un éventuel port GGML/llama.cpp (la communauté y travaille)

### 2.2 NVIDIA Parakeet TDT 1.1B — Meilleur pour la vitesse

- **RTFx >2000** — le plus rapide du marché open source
- Architecture RNN-Transducer native streaming (pas de chunking)
- Latence minimale pour le temps réel
- **Limitation** : anglais uniquement pour l'instant
- Potentiel futur si NVIDIA ajoute le français

### 2.3 Distil-Whisper — Amélioration directe du setup actuel

- **6x plus rapide** que Whisper large-v3, **1% WER de différence**
- 756M paramètres (vs 1.55B pour large-v3)
- **Compatible whisper.cpp** — remplacement quasi drop-in
- Supporte le français (hérité de Whisper)
- **Impact** : Gain de performance immédiat sans refactoring majeur

### 2.4 Moonshine — Pour une version ultra-légère

- Modèles à partir de **27M paramètres**
- Surpasse Whisper Tiny/Small malgré une taille bien inférieure
- Idéal si on veut une version "lite" de VoiceScribe
- Port ONNX disponible, potentiellement intégrable via CoreML

### 2.5 Pingala V1 — Leader Open ASR Leaderboard

- **3.10% WER** — le meilleur score absolu
- **200+ langues** dont le français
- Excellente gestion du code-switching (mélange de langues dans une phrase)
- Modèle récent, écosystème encore jeune

### Tableau comparatif

| Modèle | WER (fr) | Latence | Taille | Streaming | Licence | Intégration |
|--------|----------|---------|--------|-----------|---------|-------------|
| **Whisper large-v3-turbo** (actuel) | ~5-6% | Moyenne | 809M | ❌ Chunks | MIT | ✅ whisper.cpp |
| **Voxtral Mini V2** | ~4% | Faible | 3B | ✅ | Apache 2.0 | ⚠️ Python/API |
| **Voxtral Realtime** | ~4-5% | **480ms** | ~3B | ✅ Natif | Apache 2.0 | ⚠️ Python/API |
| **Distil-Whisper** | ~6% | **6x plus rapide** | 756M | ❌ Chunks | MIT | ✅ whisper.cpp |
| **Moonshine** | ~8-10% | Très faible | 27-300M | ✅ | MIT | ⚠️ ONNX/CoreML |
| **Pingala V1** | ~4% | Moyenne | Large | ❌ | Apache 2.0 | ⚠️ Python |

---

## 3. Améliorations de fiabilité

### 3.1 Speaker Diarization — FluidAudio (Swift natif)

**Problème actuel** : VoiceScribe assume que micro = "Moi" et audio système = "Participant". Ça fonctionne en 1v1, mais :
- Impossible de distinguer plusieurs participants sur un call
- Si le micro capte l'audio du haut-parleur, les segments sont mal attribués

**Solution recommandée : FluidAudio**
- SDK Swift natif pour macOS
- CoreML / Apple Neural Engine — performance optimale, CPU minimal
- Diarization en temps réel (streaming) ET batch
- Open source (MIT/Apache 2.0)
- S'intègre naturellement dans l'architecture Swift existante

**Alternative : pyannote-audio**
- Plus mature, large communauté
- Python (nécessiterait un processus bridge)
- Nécessite un token HuggingFace

### 3.2 Analyse de sentiment hybride (prosodie + sémantique)

**Problème actuel** : L'analyse de sentiment est purement prosodique. Un prospect qui dit calmement "Je ne suis pas du tout intéressé" sera détecté comme neutre.

**Amélioration proposée :**
1. **Garder l'analyse prosodique** pour la détection rapide (~50ms)
2. **Ajouter une couche sémantique** sur le texte transcrit :
   - Modèle léger type `camembert-base` (français) ou `distilbert-multilingual`
   - Classification sentiment sur les segments transcrits
   - Fusion pondérée : `sentiment_final = α × prosodie + (1-α) × sémantique`
3. Le code a déjà un `HybridSentimentProvider` dans les protocoles — il suffit de l'implémenter complètement

### 3.3 Suite de tests

**Problème actuel** : Zéro test. Tout changement risque des régressions silencieuses.

**Plan de test recommandé :**

| Couche | Type de test | Priorité |
|--------|-------------|----------|
| Domain (modèles, protocoles) | Tests unitaires | **P0** |
| SentimentAnalyzer | Tests unitaires + fixtures audio | **P0** |
| CommercialCoachEngine | Tests unitaires (phases, transitions) | **P0** |
| WhisperTranscriber | Tests d'intégration (mock model) | P1 |
| SessionPersistence | Tests d'intégration (SQLite in-memory) | P1 |
| RecordingCoordinator | Tests d'intégration (mocks) | P2 |
| UI (ContentView, etc.) | Snapshot tests | P2 |

### 3.4 Gestion d'erreurs et résilience

- **Reconnexion audio automatique** : Si le micro se déconnecte pendant un enregistrement, tenter une reconnexion au lieu de crash silencieux
- **Fallback modèle** : Si large-v3-turbo échoue au chargement, tenter automatiquement un modèle plus petit
- **Health monitoring** : Exposer le RTF (Real-Time Factor) dans l'UI pour que l'utilisateur voie si la transcription prend du retard

---

## 4. Améliorations fonctionnelles

### 4.1 Mode multi-participants

**Situation actuelle** : Deux flux (moi + 1 participant). En réalité, les calls de vente impliquent souvent 3-5 personnes.

**Proposition :**
- Intégrer la diarization (FluidAudio) sur le flux audio système
- Identifier et labéliser dynamiquement les speakers ("Participant 1", "Participant 2", etc.)
- Permettre à l'utilisateur de nommer les speakers après identification

### 4.2 Résumé automatique post-session

**Proposition :**
- À la fin d'une session, générer automatiquement :
  - Un résumé structuré de l'appel (points clés, objections soulevées, engagements pris)
  - Les action items identifiés
  - Le score BANT complété
- Utiliser un LLM local (ex : Llama 3.1 8B via llama.cpp, ou Mistral 7B) pour la génération
- Ou offrir l'option d'envoyer à une API Claude/GPT pour un résumé plus riche

### 4.3 Intégration CRM

**Proposition :**
- Export direct vers les CRM courants (HubSpot, Salesforce, Pipedrive)
- Mapping automatique : transcription → notes d'appel, BANT → champs custom
- Webhook configurable pour envoyer les données de session en temps réel

### 4.4 Transcription streaming (mot par mot)

**Problème actuel** : La transcription arrive par chunks après traitement complet. L'utilisateur voit du texte apparaître par blocs.

**Solution** : Implémenter le mode streaming :
- **Option A** : Voxtral Realtime (480ms latence, streaming natif)
- **Option B** : whisper.cpp avec le nouveau mode VAD intégré + sliding window
- Afficher les mots au fur et à mesure avec un indicateur de confiance

### 4.5 Mode entraînement / replay

**Proposition :**
- Permettre de rejouer une session enregistrée avec les coaching suggestions
- Mode "simulation" : l'utilisateur peut pratiquer ses réponses
- Scoring de performance basé sur les métriques de la session (temps de parole, émotions détectées, phases couvertes, BANT complété)

### 4.6 Détection de langue automatique et multilingue

**Amélioration** :
- Passer de `language: "fr"` hardcodé à `language: "auto"`
- Supporter le code-switching (mélange français/anglais fréquent en vente B2B tech)
- Whisper et Voxtral supportent tous deux la détection automatique

### 4.7 Amélioration de la détection de phase commerciale

**Problème actuel** : Détection par mots-clés heuristiques.

**Proposition** :
- Utiliser un classifieur NLP léger entraîné sur des transcriptions de vente annotées
- Ou utiliser un LLM local pour classifier les segments en phases
- Prendre en compte le contexte temporel (la phase "closing" vient rarement au début)

---

## 5. Améliorations d'utilité

### 5.1 Dashboard d'analytics

- Statistiques agrégées sur toutes les sessions : taux de conversion, durée moyenne, ratio de parole, émotions moyennes
- Tendances temporelles (amélioration du commercial au fil des sessions)
- Comparaison entre sessions / entre commerciaux

### 5.2 Recherche sémantique dans l'historique

**Actuel** : FTS5 (recherche full-text par mots-clés).

**Amélioration** : Recherche sémantique par embeddings :
- Vectoriser les segments de transcription avec un modèle d'embedding (ex : `e5-small`)
- Stocker dans une base vectorielle locale (SQLite + extension vec0, ou FAISS)
- Permettre des requêtes comme "montre-moi les fois où le prospect a parlé de budget"

### 5.3 Suggestions de réponse en temps réel par LLM

**Actuel** : Le coaching est basé sur des templates dans `Blueprints.json`.

**Amélioration** :
- Intégrer un LLM local (Mistral 7B, Llama 3.1) ou API pour générer des suggestions contextuelles
- Le LLM recevrait : la transcription récente, l'émotion détectée, la phase actuelle
- Réponses plus pertinentes et naturelles que les templates statiques

### 5.4 Export et partage enrichis

- Export PDF avec graphique de sentiment et timeline
- Partage de session par lien (export HTML self-contained)
- Intégration Notion / Google Docs

---

## 6. Roadmap recommandée

### Phase 1 — Fiabilité (fondations)
1. Ajouter une suite de tests unitaires sur Domain + SentimentAnalyzer + CoachEngine
2. Remplacer Whisper large-v3-turbo par **Distil-Whisper** (gain de vitesse immédiat, intégration whisper.cpp compatible)
3. Activer la détection automatique de langue (`"auto"`)
4. Ajouter fallback automatique de modèle et reconnexion audio

### Phase 2 — Précision et streaming
5. Intégrer **Voxtral Realtime** comme backend STT alternatif (serveur local Python + WebSocket)
6. Implémenter le sentiment hybride (prosodie + sémantique via camembert)
7. Intégrer **FluidAudio** pour la diarization multi-speakers

### Phase 3 — Fonctionnalités avancées
8. Résumé automatique post-session (LLM local ou API)
9. Suggestions de réponse en temps réel par LLM
10. Dashboard d'analytics et recherche sémantique

### Phase 4 — Intégrations
11. Intégration CRM (HubSpot, Salesforce)
12. Mode entraînement / replay avec scoring
13. Export enrichi (PDF, HTML, Notion)

---

## 7. Sources

### Modèles STT
- [Top Open Source STT Models 2025 — Modal](https://modal.com/blog/open-source-stt)
- [Best Open Source STT Model 2026 (with benchmarks) — Northflank](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
- [Best Open Source STT Models — Gladia](https://www.gladia.io/blog/best-open-source-speech-to-text-models)
- [Top APIs for Real-Time Speech Recognition 2026 — AssemblyAI](https://www.assemblyai.com/blog/best-api-models-for-real-time-speech-recognition-and-transcription)

### Voxtral (Mistral AI)
- [Voxtral — Mistral AI (annonce officielle)](https://mistral.ai/news/voxtral)
- [Voxtral Transcribe 2 — Mistral AI](https://mistral.ai/news/voxtral-transcribe-2)
- [Mistral drops Voxtral Transcribe 2 — VentureBeat](https://venturebeat.com/technology/mistral-drops-voxtral-transcribe-2-an-open-source-speech-model-that-runs-on)

### Speaker Diarization
- [FluidAudio — CoreML Speaker Diarization (GitHub)](https://github.com/FluidInference/FluidAudio)
- [Top Speaker Diarization Libraries 2026 — AssemblyAI](https://www.assemblyai.com/blog/top-speaker-diarization-libraries-and-apis)
- [Picovoice Falcon Speaker Diarization](https://picovoice.ai/platform/falcon/)

### Alternatives whisper.cpp
- [whisper.cpp — GitHub](https://github.com/ggml-org/whisper.cpp)
- [Vosk — Offline Speech Recognition](https://alphacephei.com/vosk/models)
- [Whisper Showdown C++ vs Native — Better Programming](https://betterprogramming.pub/whisper-showdown-427ce5f486ea)

### Benchmarks et comparaisons
- [Voxtral vs Whisper — Apidog](https://apidog.com/blog/voxtral-open-source-whisper-alternative/)
- [Best Whisper Alternatives 2025 — Sally.io](https://www.sally.io/blog/the-best-whisper-alternatives)
- [Benchmarking Open Source Speech Recognition — Shunya Labs](https://www.shunyalabs.ai/blog/benchmarking-top-open-source-speech-recognition-models)

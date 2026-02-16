import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @AppStorage("whisperLanguage") private var language = "fr"
    @AppStorage("modelSize") private var modelSize = "large-v3-turbo"
    @AppStorage("globalHotkeysEnabled") private var globalHotkeysEnabled = true
    @AppStorage("vadSensitivity") private var vadSensitivity = 0.5
    @AppStorage("sentimentSmoothingFactor") private var sentimentSmoothing = 0.7
    
    var body: some View {
        TabView {
            generalTab.tabItem { Label("Général", systemImage: "gear") }
            audioTab.tabItem { Label("Audio & VAD", systemImage: "waveform") }
            commercialTab.tabItem { Label("Coach Commercial", systemImage: "chart.line.uptrend.xyaxis") }
            empathyTab.tabItem { Label("Coach Empathie", systemImage: "brain.head.profile") }
            hotkeysTab.tabItem { Label("Raccourcis", systemImage: "keyboard") }
            storageTab.tabItem { Label("Stockage", systemImage: "externaldrive") }
            aboutTab.tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 560)
    }
    
    // MARK: - General
    
    var generalTab: some View {
        Form {
            Section("Modèle Whisper") {
                Picker("Taille", selection: $modelSize) {
                    Text("Tiny (~75 Mo) — Rapide").tag("tiny")
                    Text("Base (~142 Mo)").tag("base")
                    Text("Small (~466 Mo)").tag("small")
                    Text("Medium (~1.5 Go)").tag("medium")
                    Text("Large V3 Turbo (~1.6 Go) ⭐").tag("large-v3-turbo")
                }
                HStack {
                    Text("État:"); Text(engine.modelLoaded ? "✅ Chargé (×2)" : "⚪ Non chargé")
                        .foregroundStyle(engine.modelLoaded ? .green : .secondary)
                    Spacer(); Button("Recharger") { Task { await engine.loadModel() } }
                }
            }
            Section("Langue") {
                Picker("Transcription", selection: $language) {
                    Text("Français").tag("fr"); Text("English").tag("en"); Text("Deutsch").tag("de")
                    Text("Español").tag("es"); Text("Auto").tag("auto")
                }
            }
        }.formStyle(.grouped)
    }
    
    // MARK: - Audio
    
    var audioTab: some View {
        Form {
            Section("VAD") {
                HStack {
                    Text("Sensibilité:")
                    Slider(value: $vadSensitivity, in: 0.2...0.8, step: 0.05)
                    Text("\(vadSensitivity, specifier: "%.2f")").font(.system(.body, design: .monospaced)).frame(width: 40)
                }
                Text("Bas = capte plus (+ faux positifs). Haut = strict.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Audio système") {
                HStack {
                    Text("Permission:")
                    if engine.systemCaptureAvailable { Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    else { Label("Non accordée", systemImage: "xmark.circle").foregroundStyle(.orange) }
                }
                Toggle("Capturer l'audio des participants", isOn: $engine.captureSystemAudio)
            }
        }.formStyle(.grouped)
    }
    
    // MARK: - Commercial Coach (NEW)
    
    var commercialTab: some View {
        Form {
            Section("Coach Commercial") {
                Toggle("Coaching par phase de vente", isOn: $engine.commercialCoachEnabled)
                
                Text("Le coach commercial détecte automatiquement la phase de votre call (ouverture, découverte, qualification, présentation, objections, closing) et vous guide avec des techniques adaptées.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            
            Section("Les 7 phases du call commercial") {
                PhaseInfoRow(emoji: "👋", name: "Ouverture", detail: "Créer le rapport, poser l'agenda, obtenir l'accord", techniques: "Mini-contrat, icebreaker, objectif du call")
                PhaseInfoRow(emoji: "🔍", name: "Découverte", detail: "Identifier la douleur, quantifier l'impact, vision du résultat", techniques: "SPIN, questions ouvertes, écoute 70%")
                PhaseInfoRow(emoji: "✅", name: "Qualification", detail: "Budget, décideur, timeline, critères (BANT)", techniques: "Questions directes, budget tôt, processus décision")
                PhaseInfoRow(emoji: "🎯", name: "Présentation", detail: "Connecter features aux besoins, cas clients, démo", techniques: "Feature→Bénéfice→Valeur, storytelling")
                PhaseInfoRow(emoji: "🛡️", name: "Objections", detail: "Écouter, reformuler, répondre avec preuves", techniques: "Feel-Felt-Found, isoler l'objection, social proof")
                PhaseInfoRow(emoji: "🤝", name: "Closing", detail: "Résumer la valeur, proposer l'action, silence", techniques: "Closing assumptif, échelle 1-10, urgence naturelle")
                PhaseInfoRow(emoji: "📋", name: "Suivi", detail: "Récap, prochaine étape, CR dans l'heure", techniques: "Actions réparties, deadline, engagement écrit")
            }
            
            Section("Détection automatique") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Le détecteur utilise :").font(.caption).fontWeight(.medium)
                    SignalRow(icon: "text.magnifyingglass", text: "Mots-clés dans la transcription (\"budget\", \"trop cher\", \"prochaine étape\"...)")
                    SignalRow(icon: "person.2", text: "Équilibre de parole (qui parle combien)")
                    SignalRow(icon: "clock", text: "Temps écoulé dans le call")
                    SignalRow(icon: "face.smiling", text: "Émotions détectées (hésitation → objections, enthousiasme → closing)")
                    SignalRow(icon: "arrow.right", text: "Biais de progression (ne revient pas en arrière)")
                }
                
                Text("Vous pouvez aussi changer de phase manuellement en cliquant sur la barre de progression.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            
            Section("Checklists intelligentes") {
                Text("Le coach maintient des checklists par phase qui se cochent automatiquement quand les sujets sont abordés dans la conversation :")
                    .font(.caption).foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Découverte : douleur identifiée, impact quantifié, résultat souhaité, reformulation").font(.caption2)
                    Text("Qualification : budget évoqué, décideur identifié, timeline connue, critères").font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }.formStyle(.grouped)
    }
    
    // MARK: - Empathy Coach
    
    var empathyTab: some View {
        Form {
            Section("Analyse de sentiment") {
                Toggle("Analyse émotionnelle temps réel", isOn: $engine.sentimentEnabled)
                HStack {
                    Text("Lissage:")
                    Slider(value: $sentimentSmoothing, in: 0.3...0.95, step: 0.05)
                    Text("\(sentimentSmoothing, specifier: "%.2f")").font(.system(.body, design: .monospaced)).frame(width: 40)
                }
            }
            Section("Coach empathique") {
                Toggle("Suggestions de phrases empathiques", isOn: $engine.coachingEnabled)
                Text("Réagit aux émotions du prospect pour suggérer des phrases d'empathie, de réassurance ou de réengagement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Émotions détectées") {
                CoachingFeatureRow(emoji: "😤", label: "Frustré", detail: "Validation et empathie")
                CoachingFeatureRow(emoji: "🤔", label: "Hésitant", detail: "Questions ouvertes, réassurance")
                CoachingFeatureRow(emoji: "😶", label: "Désengagé", detail: "Recentrage sur les priorités")
                CoachingFeatureRow(emoji: "🤩", label: "Enthousiaste", detail: "Ancrage positif, closing")
                CoachingFeatureRow(emoji: "😊", label: "Satisfait", detail: "Approfondissement")
                CoachingFeatureRow(emoji: "😎", label: "Confiant", detail: "Avancement vers l'action")
            }
            Section("Latence") {
                HStack { Text("Sentiment:"); Spacer(); Text("~50ms").monospaced().foregroundStyle(.green) }
                HStack { Text("Suggestion:"); Spacer(); Text("~500ms").monospaced().foregroundStyle(.green) }
                HStack { Text("Transcription:"); Spacer(); Text("~1-2s").monospaced().foregroundStyle(.orange) }
            }
        }.formStyle(.grouped)
    }
    
    // MARK: - Hotkeys
    
    var hotkeysTab: some View {
        Form {
            Section("Raccourcis globaux") {
                Toggle("Activer", isOn: $globalHotkeysEnabled)
                    .onChange(of: globalHotkeysEnabled) { _, v in if v { engine.hotkeys.enable() } else { engine.hotkeys.disable() } }
            }
            if globalHotkeysEnabled {
                Section("Raccourcis actifs") {
                    shortcutRow("Enregistrer / Pause", "⌥⇧R")
                    shortcutRow("Arrêter", "⌥⇧S")
                    shortcutRow("Nouvelle session", "⌥⇧N")
                }
            }
        }.formStyle(.grouped)
    }
    
    // MARK: - Storage
    
    var storageTab: some View {
        Form {
            Section("Base de données") {
                let stats = SessionPersistence.shared.stats()
                HStack { Text("Sessions:"); Spacer(); Text("\(stats.sessions)").monospaced() }
                HStack { Text("Segments:"); Spacer(); Text("\(stats.segments)").monospaced() }
                HStack { Text("Taille:"); Spacer(); Text("\(stats.dbSizeMB, specifier: "%.1f") Mo").monospaced() }
            }
        }.formStyle(.grouped)
    }
    
    // MARK: - About
    
    var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile").font(.system(size: 64)).foregroundStyle(.accent)
            Text("VoiceScribe").font(.title).fontWeight(.bold)
            Text("Transcription + Coach Commercial + Coach Empathique").foregroundStyle(.secondary)
            
            HStack(spacing: 6) {
                FeaturePill(text: "VAD", color: .orange)
                FeaturePill(text: "Dual Audio", color: .green)
                FeaturePill(text: "Sentiment", color: .red)
                FeaturePill(text: "Empathie", color: .purple)
                FeaturePill(text: "Commercial", color: .blue)
                FeaturePill(text: "Auto-Save", color: .cyan)
                FeaturePill(text: "Hotkeys", color: .gray)
            }
            Divider().frame(width: 300)
            
            VStack(alignment: .leading, spacing: 6) {
                Label("3 couches de coaching en temps réel", systemImage: "brain")
                Label("Détection automatique des phases de vente", systemImage: "chart.line.uptrend.xyaxis")
                Label("Checklists BANT et découverte auto-cochées", systemImage: "checklist")
                Label("Phrases empathiques contextuelles", systemImage: "quote.opening")
                Label("100% local — aucune donnée envoyée", systemImage: "lock.shield")
            }.font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }
    
    // MARK: - Helpers
    
    func shortcutRow(_ label: String, _ key: String) -> some View {
        HStack {
            Text(label); Spacer()
            Text(key).font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15)).cornerRadius(4)
        }
    }
}

// MARK: - Row Components

struct PhaseInfoRow: View {
    let emoji: String; let name: String; let detail: String; let techniques: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(emoji).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption).fontWeight(.bold)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
                Text("💡 \(techniques)").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct SignalRow: View {
    let icon: String; let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 16)
            Text(text).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct CoachingFeatureRow: View {
    let emoji: String; let label: String; let detail: String
    var body: some View {
        HStack(spacing: 8) {
            Text(emoji)
            VStack(alignment: .leading) {
                Text(label).font(.caption).fontWeight(.medium)
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

struct FeaturePill: View {
    let text: String; let color: Color
    var body: some View {
        Text(text).font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15)).foregroundStyle(color).clipShape(Capsule())
    }
}

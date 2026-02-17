import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var recording: RecordingStore
    @EnvironmentObject var audio: AudioStore
    @EnvironmentObject var coaching: CoachingStore
    @EnvironmentObject var sentiment: SentimentStore
    @EnvironmentObject var overlay: OverlayManager
    @EnvironmentObject var transcription: TranscriptionStore
    @EnvironmentObject var summary: SummaryStore

    @AppStorage("whisperLanguage") private var language = "auto"
    @AppStorage("modelSize") private var modelSize = "distil-large-v3"
    @AppStorage("sttBackend") private var sttBackend = STTBackend.whisperLocal.rawValue
    @AppStorage("globalHotkeysEnabled") private var globalHotkeysEnabled = true
    @AppStorage("vadSensitivity") private var vadSensitivity = 0.5
    @AppStorage("sentimentSmoothingFactor") private var sentimentSmoothing = 0.7
    @AppStorage("sttServerHost") private var sttServerHost = "localhost"
    @AppStorage("sttServerPort") private var sttServerPort = 8765
    
    var body: some View {
        TabView {
            generalTab.tabItem { Label("Général", systemImage: "gear") }
            coachingTab.tabItem { Label("Coaching", systemImage: "brain.head.profile") }
            llmTab.tabItem { Label("IA", systemImage: "sparkles") }
            analyticsTab.tabItem { Label("Analytics", systemImage: "chart.bar.xaxis") }
            frameworkTab.tabItem { Label("Framework", systemImage: "list.bullet.indent") }
            audioTab.tabItem { Label("Audio", systemImage: "waveform") }
            hotkeysTab.tabItem { Label("Raccourcis", systemImage: "keyboard") }
            aboutTab.tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 580)
    }
    
    // MARK: - General
    
    var generalTab: some View {
        Form {
            Section("Modèle Whisper") {
                Picker("Taille", selection: $modelSize) {
                    Text("Distil Large V3 ⭐ (6x plus rapide)").tag("distil-large-v3")
                    Text("Large V3 Turbo").tag("large-v3-turbo")
                    Text("Medium (~1.5 Go)").tag("medium")
                    Text("Small (~466 Mo)").tag("small")
                    Text("Base (~142 Mo)").tag("base")
                    Text("Tiny (~75 Mo)").tag("tiny")
                }
                HStack {
                    Text("État:")
                    Text(recording.modelLoaded ? "✅ Chargé" : "⚪ Non chargé")
                        .foregroundStyle(recording.modelLoaded ? .green : .secondary)
                    Spacer()
                    Button("Recharger") { Task { await env.loadModel() } }
                }
            }
            Section("Langue") {
                Picker("Transcription", selection: $language) {
                    Text("Auto-detect ⭐").tag("auto")
                    Text("Français").tag("fr"); Text("English").tag("en")
                    Text("Deutsch").tag("de"); Text("Español").tag("es")
                }
            }
            Section("Stockage") {
                let stats = SessionPersistence.shared.stats()
                let cStats = SessionPersistence.shared.coachingStats()
                HStack { Text("Sessions:"); Spacer(); Text("\(stats.sessions)").monospaced() }
                HStack { Text("Segments:"); Spacer(); Text("\(stats.segments)").monospaced() }
                HStack { Text("Coaching:"); Spacer(); Text("\(cStats.snapshots) snapshots, \(cStats.memorySlots) slots, \(cStats.tips) tips, \(cStats.alerts) alertes, \(cStats.reports) rapports").font(.caption).monospaced() }
                HStack { Text("Taille:"); Spacer(); Text("\(stats.dbSizeMB, specifier: "%.1f") Mo").monospaced() }
            }
        }.formStyle(.grouped)
    }
    
    // MARK: - Coaching
    
    var coachingTab: some View {
        Form {
            Section("Coach conversationnel") {
                Toggle("Coaching en temps réel", isOn: $coaching.coachingEnabled)
                Text("Le coach vous guide à travers 11 mouvements conversationnels en 3 actes. Il détecte automatiquement où vous en êtes et adapte ses conseils à ce qui a été dit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Analyse de sentiment") {
                Toggle("Analyse émotionnelle", isOn: $sentiment.sentimentEnabled)
                HStack {
                    Text("Lissage:"); Slider(value: $sentimentSmoothing, in: 0.3...0.95, step: 0.05)
                    Text("\(sentimentSmoothing, specifier: "%.2f")").monospaced().frame(width: 40)
                }
            }
            Section("Latence") {
                latencyRow("Sentiment prosodique", "~50ms", .green)
                latencyRow("Analyse sémantique", "~5ms", .green)
                latencyRow("Diarisation", "~10ms", .green)
                latencyRow("Coaching suggestion", "~100ms", .green)
                latencyRow("Transcription Whisper", "~1-2s", .orange)
                latencyRow("Extraction mémoire", "~200ms", .green)
            }
            Section("Overlay compact") {
                Toggle("Afficher automatiquement à l'enregistrement", isOn: $overlay.autoShowOnRecord)
                HStack {
                    Text("Opacité:")
                    Slider(value: $overlay.overlayOpacity, in: 0.5...1.0, step: 0.05)
                    Text("\(Int(overlay.overlayOpacity * 100))%").monospaced().frame(width: 40)
                }
                Text("Fenêtre flottante toujours visible (⌥⇧O). Se positionne au-dessus de Zoom, Teams ou Chrome pendant le call. Déplaçable par glisser, accrochage aux bords de l'écran.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Philosophie") {
                Text("Le coaching est conçu comme un accompagnement de CONVERSATION, pas un script de vente. Le prospect ne doit jamais se sentir interrogé. Chaque suggestion est une invitation à la curiosité, pas une instruction à suivre aveuglément.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }.formStyle(.grouped)
    }
    
    // MARK: - LLM / IA

    var llmTab: some View {
        Form {
            Section("Backend IA") {
                Picker("Moteur", selection: $summary.llmBackendRaw) {
                    Text("Local (template)").tag(LLMBackend.local.rawValue)
                    Text("Claude API (Anthropic)").tag(LLMBackend.claudeAPI.rawValue)
                    Text("OpenAI API (GPT-4)").tag(LLMBackend.openAIAPI.rawValue)
                }
                if summary.llmBackend != .local {
                    SecureField("Clé API", text: $summary.apiKey)
                    if summary.apiKey.isEmpty {
                        Text("Sans clé API, le moteur local sera utilisé en fallback.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Section("Résumé automatique") {
                Toggle("Générer un résumé après chaque appel", isOn: $summary.autoSummaryEnabled)
                Text("Un résumé structuré est généré automatiquement à la fin de chaque session : points clés, actions, feedback coaching.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Suggestions en temps réel") {
                Toggle("Suggestions IA pendant l'appel", isOn: $summary.suggestionsEnabled)
                Text("Le moteur IA propose des réponses contextuelles pendant la conversation (gestion d'objection, questions à poser, opportunités de closing).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Latence") {
                latencyRow("Résumé local", "~200ms", .green)
                latencyRow("Suggestions locales", "~50ms", .green)
                latencyRow("Résumé API", "~3-5s", .orange)
                latencyRow("Suggestions API", "~1-2s", .orange)
            }
        }.formStyle(.grouped)
    }

    // MARK: - Analytics

    var analyticsTab: some View {
        CoachingAnalyticsView()
    }
    
    // MARK: - Framework Reference
    
    var frameworkTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Le Framework Conversationnel")
                    .font(.title2).fontWeight(.bold).padding(.bottom, 4)
                Text("3 actes, 11 mouvements. Comme une conversation naturelle.")
                    .font(.callout).foregroundStyle(.secondary)
                actSection(act: "Acte I — Connexion", color: .cyan, description: "Créer le lien, comprendre leur monde", movements: [.accueil, .cadrage, .univers])
                actSection(act: "Acte II — Exploration", color: .blue, description: "Trouver le vrai besoin, quantifier, visualiser", movements: [.enjeux, .profondeur, .vision, .qualification])
                actSection(act: "Acte III — Solution", color: .purple, description: "Présenter, dialoguer, engager", movements: [.proposition, .dialogue, .engagement])
                actSection(act: "Suivi", color: .mint, description: "Verrouiller et suivre", movements: [.suivi])
            }.padding(20)
        }
    }
    
    func actSection(act: String, color: Color, description: String, movements: [ConversationMovement]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 20)
                VStack(alignment: .leading) {
                    Text(act).font(.headline).foregroundStyle(color)
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(movements, id: \.rawValue) { m in
                let bp = ConversationFramework.blueprint(for: m)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(m.emoji).font(.title3)
                        VStack(alignment: .leading) {
                            Text(m.name).font(.callout).fontWeight(.semibold)
                            Text(bp.goldenRule).font(.caption).foregroundStyle(.secondary).italic()
                        }
                    }
                    Text("🎯 " + bp.intent.components(separatedBy: ".").first!)
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("😊 Prospect : \"\(bp.prospectExperience)\"")
                        .font(.caption2).foregroundStyle(.tertiary).italic()
                    if !bp.antiPatterns.isEmpty {
                        Text("🚫 " + bp.antiPatterns.first!)
                            .font(.caption2).foregroundStyle(.red.opacity(0.6))
                    }
                }
                .padding(8).background(Color.primary.opacity(0.02)).cornerRadius(6)
            }
        }
    }
    
    // MARK: - Audio

    var audioTab: some View {
        Form {
            Section("Moteur STT") {
                Picker("Backend", selection: $sttBackend) {
                    ForEach(STTBackend.allCases, id: \.rawValue) { backend in
                        Text(backend.displayName).tag(backend.rawValue)
                    }
                }
                if STTBackend(rawValue: sttBackend)?.requiresServer == true {
                    HStack {
                        Text("Serveur:")
                        TextField("Host", text: $sttServerHost).frame(width: 120)
                        Text(":")
                        TextField("Port", value: $sttServerPort, format: .number).frame(width: 60)
                    }
                    HStack {
                        Text("État:")
                        Text(transcription.sttConnectionState.displayText)
                            .foregroundStyle(transcription.sttConnectionState.isConnected ? .green : .secondary)
                        Spacer()
                        if transcription.sttConnectionState.isConnected {
                            Button("Déconnecter") { env.disconnectStreamingSTT() }
                        } else {
                            Button("Connecter") {
                                Task {
                                    try? await env.connectStreamingSTT(
                                        config: STTServerConfig(host: sttServerHost, port: sttServerPort)
                                    )
                                }
                            }
                        }
                    }
                    Text("Le serveur Voxtral ou Whisper doit tourner localement. Voir le script server/start.sh.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("VAD") {
                HStack { Text("Sensibilité:"); Slider(value: $vadSensitivity, in: 0.2...0.8, step: 0.05); Text("\(vadSensitivity, specifier: "%.2f")").monospaced().frame(width: 40) }
            }
            Section("Diarisation (multi-locuteurs)") {
                HStack {
                    Text("Locuteurs détectés:")
                    Spacer()
                    Text("\(transcription.activeSpeakers.count)").monospaced()
                }
                if !transcription.activeSpeakers.isEmpty {
                    ForEach(transcription.activeSpeakers) { speaker in
                        HStack {
                            Text(speaker.label).font(.caption)
                            Spacer()
                            Text("\(speaker.segmentCount) seg.").font(.caption).foregroundStyle(.secondary)
                            Text(formatDuration(speaker.totalSpeakingTime)).font(.caption).monospaced()
                        }
                    }
                }
                let balance = transcription.speakerBalance
                if balance.totalTime > 0 {
                    HStack {
                        Text("Équilibre:")
                        Spacer()
                        Text(balance.isBalanced ? "Équilibré" : "Déséquilibré")
                            .foregroundStyle(balance.isBalanced ? .green : .orange)
                    }
                }
                Text("La diarisation identifie automatiquement les différents participants par leur empreinte vocale.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Audio système") {
                HStack {
                    Text("Permission:")
                    if audio.systemCaptureAvailable {
                        Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Non accordée", systemImage: "xmark.circle").foregroundStyle(.orange)
                    }
                }
                Toggle("Capturer l'audio", isOn: $audio.captureSystemAudio)
            }
        }.formStyle(.grouped)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
    
    // MARK: - Hotkeys
    
    var hotkeysTab: some View {
        Form {
            Section("Raccourcis globaux") {
                Toggle("Activer", isOn: $globalHotkeysEnabled)
                    .onChange(of: globalHotkeysEnabled) { _, v in
                        if v { env.coordinator.hotkeys.enable() } else { env.coordinator.hotkeys.disable() }
                    }
            }
            if globalHotkeysEnabled {
                Section("Actifs") {
                    shortcutRow("Enregistrer / Pause", "⌥⇧R")
                    shortcutRow("Arrêter", "⌥⇧S")
                    shortcutRow("Nouvelle session", "⌥⇧N")
                    shortcutRow("Overlay compact", "⌥⇧O")
                }
            }
        }.formStyle(.grouped)
    }
    
    // MARK: - About
    
    var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile").font(.system(size: 64)).foregroundStyle(.blue)
            Text("VoiceScribe").font(.title).fontWeight(.bold)
            Text("Coaching conversationnel en temps réel").foregroundStyle(.secondary)
            HStack(spacing: 6) {
                FeaturePill(text: "11 mouvements", color: .blue)
                FeaturePill(text: "Multi-STT", color: .purple)
                FeaturePill(text: "Diarisation", color: .green)
                FeaturePill(text: "Sémantique", color: .red)
                FeaturePill(text: "IA / LLM", color: .indigo)
                FeaturePill(text: "Overlay", color: .cyan)
                FeaturePill(text: "100% local", color: .orange)
            }
            Divider().frame(width: 300)
            VStack(alignment: .leading, spacing: 6) {
                Label("3 actes, 11 mouvements de conversation", systemImage: "brain")
                Label("Multi-backend STT: Whisper local + Voxtral serveur", systemImage: "network")
                Label("Diarisation multi-locuteurs (empreinte vocale)", systemImage: "person.2")
                Label("Sentiment 3 canaux: prosodie + patterns + sémantique", systemImage: "waveform")
                Label("Mémoire conversationnelle cross-mouvement", systemImage: "memorychip")
                Label("Overlay compact toujours visible (⌥⇧O)", systemImage: "pip.enter")
                Label("Rapport post-call avec scores", systemImage: "doc.text")
                Label("Résumé IA auto + suggestions temps réel", systemImage: "sparkles")
                Label("Analytics cross-session + recherche sémantique", systemImage: "chart.bar.xaxis")
                Label("Aucune donnée envoyée (mode local)", systemImage: "lock.shield")
            }.font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }
    
    // Helpers
    func latencyRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack { Text(label); Spacer(); Text(value).monospaced().foregroundStyle(color) }
    }
    func shortcutRow(_ label: String, _ key: String) -> some View {
        HStack { Text(label); Spacer(); Text(key).font(.system(.caption, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 3).background(Color.secondary.opacity(0.15)).cornerRadius(4) }
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

import Foundation

/// Phase-specific commercial coaching.
///
/// For each sales phase, provides:
/// - Objectives: what you're trying to achieve
/// - Techniques: how to handle the phase
/// - Questions to ask: ready-made questions to keep in your pocket
/// - Signals to watch: what tells you it's working (or not)
/// - Live tips: contextual advice based on conversation dynamics
///
/// This is complementary to the empathetic coach:
/// - Empathetic coach → reacts to prospect's EMOTION → "say this to them"
/// - Commercial coach → reacts to PHASE + DYNAMICS → "do this now"
final class CommercialCoachEngine {
    
    // MARK: - Output
    
    struct CommercialAdvice {
        let phase: SalesPhaseDetector.SalesPhase
        
        /// What you should focus on RIGHT NOW (1 sentence)
        let focusNow: String
        
        /// Ready-to-use question or phrase
        let suggestedAction: SuggestedAction
        
        /// Phase objectives checklist with completion tracking
        let objectives: [Objective]
        
        /// What to watch for
        let watchFor: [WatchSignal]
        
        /// Speaker balance feedback
        let balanceFeedback: BalanceFeedback?
        
        /// Transition nudge if applicable
        let transitionNudge: String?
    }
    
    struct SuggestedAction {
        let phrase: String
        let type: ActionType
        let rationale: String
        let alternatives: [String]
        
        enum ActionType: String {
            case question = "❓ Question"
            case technique = "💡 Technique"
            case transition = "➡️ Transition"
            case reaction = "⚡ Réaction"
        }
    }
    
    struct Objective {
        let label: String
        let completed: Bool
        let hint: String
    }
    
    struct WatchSignal {
        let signal: String
        let detected: Bool
    }
    
    struct BalanceFeedback {
        let message: String
        let prospectRatio: Float
        let idealRatio: Float
        let isGood: Bool
    }
    
    // MARK: - State
    
    private var discoveryChecklist = DiscoveryChecklist()
    private var qualificationChecklist = QualificationChecklist()
    private var objectionHistory: [String] = []
    private var closingAttempts: Int = 0
    
    // MARK: - Public API
    
    func advise(
        phaseResult: SalesPhaseDetector.DetectionResult,
        recentSegments: [TranscriptionSegment],
        emotion: EmotionalState
    ) -> CommercialAdvice {
        
        let phase = phaseResult.currentPhase
        
        // Update checklists from transcript
        updateChecklists(recentSegments)
        
        let action = suggestAction(
            phase: phase,
            emotion: emotion,
            recentSegments: recentSegments,
            progress: phaseResult.phaseProgress
        )
        
        let objectives = buildObjectives(phase: phase)
        let watchSignals = buildWatchSignals(phase: phase, recentSegments: recentSegments)
        
        let balanceFeedback: BalanceFeedback? = {
            guard let advice = phaseResult.balanceAdvice else { return nil }
            return BalanceFeedback(
                message: advice,
                prospectRatio: phaseResult.speakerBalance,
                idealRatio: phase.idealProspectRatio,
                isGood: abs(phaseResult.speakerBalance - phase.idealProspectRatio) < 0.15
            )
        }()
        
        return CommercialAdvice(
            phase: phase,
            focusNow: focusStatement(phase: phase, progress: phaseResult.phaseProgress, emotion: emotion),
            suggestedAction: action,
            objectives: objectives,
            watchFor: watchSignals,
            balanceFeedback: balanceFeedback,
            transitionNudge: phaseResult.transitionReason
        )
    }
    
    func reset() {
        discoveryChecklist = DiscoveryChecklist()
        qualificationChecklist = QualificationChecklist()
        objectionHistory.removeAll()
        closingAttempts = 0
    }
    
    // MARK: - Focus Statement
    
    private func focusStatement(
        phase: SalesPhaseDetector.SalesPhase,
        progress: Float,
        emotion: EmotionalState
    ) -> String {
        switch phase {
        case .ouverture:
            return "Créez le lien. Donnez l'agenda. Obtenez leur accord sur le déroulé."
            
        case .decouverte:
            if progress < 0.3 {
                return "Posez des questions ouvertes. Écoutez 70% du temps. Ne vendez rien encore."
            } else if !discoveryChecklist.painIdentified {
                return "Creusez la douleur. Vous n'avez pas encore identifié le vrai problème."
            } else if !discoveryChecklist.impactQuantified {
                return "Quantifiez l'impact. Combien ça leur coûte de ne rien faire ?"
            }
            return "Bonne découverte. Reformulez ce que vous avez compris avant de passer à la suite."
            
        case .qualification:
            if !qualificationChecklist.budgetDiscussed {
                return "Abordez le budget. Sans budget, pas de deal."
            } else if !qualificationChecklist.deciderIdentified {
                return "Identifiez le décideur. Qui signe ?"
            } else if !qualificationChecklist.timelineKnown {
                return "Clarifiez le timing. Quand veulent-ils avancer ?"
            }
            return "BANT OK. Vous pouvez présenter en confiance."
            
        case .presentation:
            if emotion.label == .disengaged || emotion.label == .neutral {
                return "⚠️ Le prospect décroche. Revenez à ses besoins. Pas de feature-dump."
            }
            return "Connectez chaque feature à un besoin exprimé en découverte. Pas de bénéfice sans contexte."
            
        case .objections:
            if emotion.label == .frustrated {
                return "⚠️ Frustration. Validez d'abord, argumentez après. Pas de confrontation."
            }
            return "Écoutez l'objection complètement. Reformulez. Puis répondez avec un cas concret."
            
        case .closing:
            if emotion.label == .hesitant {
                return "Hésitation = il manque un élément. Demandez ce qui bloque."
            } else if emotion.label == .enthusiastic || emotion.label == .confident {
                return "🟢 Signal d'achat fort. Proposez la prochaine étape concrète. Maintenant."
            }
            return "Résumez la valeur. Proposez l'action. Taisez-vous et attendez."
            
        case .suivi:
            return "Récapitulez les décisions. Envoyez un CR dans l'heure. Calez le prochain RDV."
        }
    }
    
    // MARK: - Suggest Action
    
    private func suggestAction(
        phase: SalesPhaseDetector.SalesPhase,
        emotion: EmotionalState,
        recentSegments: [TranscriptionSegment],
        progress: Float
    ) -> SuggestedAction {
        
        switch phase {
            
        case .ouverture:
            return SuggestedAction(
                phrase: "Voilà ce que je vous propose : d'abord je vous pose quelques questions pour bien comprendre votre contexte, ensuite je vous montre comment on pourrait vous aider. Ça vous va ?",
                type: .technique,
                rationale: "Le 'mini-contrat' donne le contrôle et réduit l'anxiété du prospect.",
                alternatives: [
                    "Avant de commencer, qu'est-ce qui vous a donné envie de prendre ce call ?",
                    "En 30 secondes, quel serait le meilleur résultat possible de cet échange pour vous ?",
                    "Je veux être sûr de ne pas vous faire perdre votre temps. Qu'attendez-vous de cette conversation ?"
                ]
            )
            
        case .decouverte:
            if !discoveryChecklist.painIdentified {
                return SuggestedAction(
                    phrase: "Quel est votre plus gros challenge sur [sujet] aujourd'hui ?",
                    type: .question,
                    rationale: "Question de douleur. Sans douleur identifiée, pas de vente.",
                    alternatives: [
                        "Si vous pouviez changer une seule chose dans votre process actuel, ce serait quoi ?",
                        "Qu'est-ce qui vous empêche d'atteindre vos objectifs sur ce sujet ?",
                        "Qu'est-ce qui a déclenché cette recherche de solution maintenant ?"
                    ]
                )
            }
            if !discoveryChecklist.impactQuantified {
                return SuggestedAction(
                    phrase: "Concrètement, ça représente combien en temps perdu / argent / opportunités manquées ?",
                    type: .question,
                    rationale: "Quantifier la douleur crée l'urgence et justifie l'investissement.",
                    alternatives: [
                        "Si on ne fait rien, qu'est-ce que ça coûte sur les 12 prochains mois ?",
                        "Combien de temps votre équipe perd chaque semaine sur ça ?",
                        "Quel impact ça a sur votre chiffre d'affaires / croissance / satisfaction client ?"
                    ]
                )
            }
            if !discoveryChecklist.desiredOutcome {
                return SuggestedAction(
                    phrase: "À quoi ressemblerait la situation idéale pour vous dans 6 mois ?",
                    type: .question,
                    rationale: "Faites-les visualiser le résultat. La vision crée le désir.",
                    alternatives: [
                        "Si on résolvait ce problème demain, qu'est-ce qui changerait pour vous au quotidien ?",
                        "Quel serait votre critère de succès numéro 1 ?",
                        "Comment vous sauriez que la solution fonctionne ?"
                    ]
                )
            }
            return SuggestedAction(
                phrase: "Si je résume : votre problème principal c'est [X], ça vous coûte [Y], et vous voulez [Z]. C'est bien ça ?",
                type: .technique,
                rationale: "Reformulation = preuve d'écoute + validation avant de passer à la suite.",
                alternatives: [
                    "J'ai bien noté 3 points clés : [A], [B], [C]. Il y a autre chose que j'aurais dû vous demander ?",
                    "Avant qu'on avance, est-ce que j'ai bien compris votre situation ?"
                ]
            )
            
        case .qualification:
            if !qualificationChecklist.budgetDiscussed {
                return SuggestedAction(
                    phrase: "Pour être transparent, nos solutions se situent entre [X] et [Y]. Est-ce que c'est dans votre enveloppe ?",
                    type: .question,
                    rationale: "Abordez le budget tôt. Mieux vaut un 'non' maintenant qu'après 1h de présentation.",
                    alternatives: [
                        "Avez-vous déjà une idée du budget que vous pouvez allouer à ce sujet ?",
                        "Vous aviez budgété quelque chose pour résoudre ce problème ?",
                        "Est-ce que le coût est un critère décisif ou c'est surtout la valeur qui compte ?"
                    ]
                )
            }
            if !qualificationChecklist.deciderIdentified {
                return SuggestedAction(
                    phrase: "Qui d'autre serait impliqué dans cette décision ?",
                    type: .question,
                    rationale: "Identifiez tous les stakeholders maintenant, pas au moment du closing.",
                    alternatives: [
                        "Comment se passe le processus de décision chez vous en général ?",
                        "Y a-t-il d'autres personnes qu'il faudrait impliquer dans la réflexion ?",
                        "Si on arrive à un accord, quelles seraient les étapes de validation ?"
                    ]
                )
            }
            if !qualificationChecklist.timelineKnown {
                return SuggestedAction(
                    phrase: "Quel serait le timing idéal pour mettre ça en place ?",
                    type: .question,
                    rationale: "Le timing crée l'urgence naturelle. Pas de deadline = pas de priorité.",
                    alternatives: [
                        "Vous avez une date butoir pour résoudre ce problème ?",
                        "Si on commençait demain, ça serait trop tôt ou c'est ce que vous voulez ?",
                        "Qu'est-ce qui pourrait retarder le projet ?"
                    ]
                )
            }
            return SuggestedAction(
                phrase: "On a le budget, le timing, et les bons interlocuteurs. Je vous montre concrètement comment on peut vous aider ?",
                type: .transition,
                rationale: "Transition naturelle vers la présentation. Demandez la permission d'avancer.",
                alternatives: []
            )
            
        case .presentation:
            if emotion.label == .disengaged || emotion.label == .neutral {
                return SuggestedAction(
                    phrase: "Attendez, je veux être sûr que c'est pertinent pour vous. Quel aspect vous intéresse le plus ?",
                    type: .reaction,
                    rationale: "Le prospect décroche. Redonnez-lui le contrôle.",
                    alternatives: [
                        "Je m'arrête là — est-ce que ça correspond à ce que vous cherchez ?",
                        "Plutôt que de tout vous montrer, qu'est-ce qui serait le plus utile ?"
                    ]
                )
            }
            return SuggestedAction(
                phrase: "Ce que ça veut dire concrètement pour vous : [bénéfice lié à leur douleur spécifique]",
                type: .technique,
                rationale: "Feature → Bénéfice → Valeur personnalisée. Jamais de feature isolée.",
                alternatives: [
                    "Un de nos clients avait exactement le même problème. En 3 mois, il a [résultat].",
                    "Par rapport à [douleur mentionnée en découverte], ça vous permettrait de [solution].",
                    "Vous voyez comment ça s'appliquerait dans votre cas ?"
                ]
            )
            
        case .objections:
            let recentText = recentSegments.suffix(5).map { $0.text.lowercased() }.joined(separator: " ")
            
            if recentText.contains("cher") || recentText.contains("prix") || recentText.contains("budget") {
                return SuggestedAction(
                    phrase: "Je comprends. Par curiosité, vous comparez par rapport à quoi exactement ?",
                    type: .technique,
                    rationale: "Objection prix → ne jamais défendre le prix directement. Recontextualisez la valeur.",
                    alternatives: [
                        "C'est vrai que c'est un investissement. Mais rappelez-vous, [douleur] vous coûte [montant] aujourd'hui.",
                        "Si le prix n'était pas un sujet, ce serait la bonne solution pour vous ?",
                        "On peut regarder ensemble ce qui est essentiel vs optionnel pour adapter."
                    ]
                )
            }
            
            if recentText.contains("réfléchir") || recentText.contains("temps") || recentText.contains("pas sûr") {
                return SuggestedAction(
                    phrase: "Bien sûr. Pour que votre réflexion soit la plus utile possible, qu'est-ce qui vous fait encore hésiter ?",
                    type: .technique,
                    rationale: "\"Je dois réfléchir\" = objection cachée. Faites-la sortir maintenant.",
                    alternatives: [
                        "C'est tout à fait normal. Si vous deviez me donner un point qui vous bloque, ce serait lequel ?",
                        "Je comprends. Sur une échelle de 1 à 10, où en êtes-vous ? Qu'est-ce qui manque pour être à 10 ?",
                        "Qu'est-ce qui se passerait si vous ne preniez pas de décision cette semaine ?"
                    ]
                )
            }
            
            if recentText.contains("concurrent") || recentText.contains("autre solution") || recentText.contains("prestataire") {
                return SuggestedAction(
                    phrase: "C'est bien de comparer. Quels sont vos critères de décision les plus importants ?",
                    type: .technique,
                    rationale: "Ne critiquez jamais le concurrent. Ramenez sur VOS critères de valeur.",
                    alternatives: [
                        "Qu'est-ce que vous avez aimé / pas aimé dans ce que vous avez vu ailleurs ?",
                        "Si je peux vous poser la question : qu'est-ce qui ferait pencher la balance ?",
                        "Nos clients qui ont comparé disent souvent que la différence c'est [différenciateur clé]."
                    ]
                )
            }
            
            return SuggestedAction(
                phrase: "C'est une bonne remarque. Dites-m'en plus pour que je puisse bien y répondre.",
                type: .technique,
                rationale: "Technique du miroir : laissez l'objection se développer complètement avant de répondre.",
                alternatives: [
                    "Si on résolvait ce point, on serait bons ?",
                    "Je vois. Qu'est-ce qui vous rassurerait le plus sur ce sujet ?",
                    "C'est un point que beaucoup de nos clients avaient aussi. Voici ce qu'on a fait..."
                ]
            )
            
        case .closing:
            if closingAttempts == 0 {
                closingAttempts += 1
                return SuggestedAction(
                    phrase: "On a vu que [résumé valeur]. Concrètement, comment on avance ensemble ?",
                    type: .technique,
                    rationale: "Closing assumptif. Résumez la valeur, proposez l'action, silence.",
                    alternatives: [
                        "On est alignés sur [besoin]. Je vous prépare la proposition pour validation ?",
                        "Si je vous envoie le contrat cette semaine, ça vous irait ?",
                        "Quelle serait la meilleure date pour démarrer ?"
                    ]
                )
            }
            return SuggestedAction(
                phrase: "Qu'est-ce qu'il vous faudrait pour pouvoir dire oui aujourd'hui ?",
                type: .question,
                rationale: "2e tentative de closing. Identifiez le dernier obstacle.",
                alternatives: [
                    "Sur une échelle de 1 à 10, où vous situez-vous ? Que manque-t-il pour atteindre 10 ?",
                    "Si je pouvais [offre de concession], ça débloquerait la situation ?",
                    "Quel serait le risque de ne rien faire pendant encore 3 mois ?"
                ]
            )
            
        case .suivi:
            return SuggestedAction(
                phrase: "Je vous envoie un récap par email dans l'heure avec les prochaines étapes. On cale un point [date] ?",
                type: .technique,
                rationale: "Cadrez le suivi immédiatement. Un deal sans prochaine étape est un deal mort.",
                alternatives: [
                    "Je vous propose : je vous envoie [livrable], et on se revoit [date] pour avancer.",
                    "Côté actions : moi je fais [A], vous faites [B], et on se redit [date]. OK ?",
                    "Merci pour cet échange. Le CR part dans l'heure."
                ]
            )
        }
    }
    
    // MARK: - Objectives
    
    private func buildObjectives(phase: SalesPhaseDetector.SalesPhase) -> [Objective] {
        switch phase {
        case .ouverture:
            return [
                Objective(label: "Rapport humain créé", completed: false, hint: "Icebreaker, sourire, écoute"),
                Objective(label: "Agenda posé", completed: false, hint: "\"Voilà comment je vous propose qu'on procède\""),
                Objective(label: "Accord prospect", completed: false, hint: "\"Ça vous va ?\" — obtenir un mini-oui")
            ]
        case .decouverte:
            return [
                Objective(label: "Douleur identifiée", completed: discoveryChecklist.painIdentified, hint: "Quel est le problème principal ?"),
                Objective(label: "Impact quantifié", completed: discoveryChecklist.impactQuantified, hint: "Combien ça coûte ? En temps, argent, stress"),
                Objective(label: "Résultat souhaité", completed: discoveryChecklist.desiredOutcome, hint: "À quoi ressemble le succès ?"),
                Objective(label: "Reformulation validée", completed: discoveryChecklist.reformulated, hint: "\"Si je résume...\"")
            ]
        case .qualification:
            return [
                Objective(label: "Budget évoqué", completed: qualificationChecklist.budgetDiscussed, hint: "Fourchette ou enveloppe"),
                Objective(label: "Décideur identifié", completed: qualificationChecklist.deciderIdentified, hint: "Qui signe ?"),
                Objective(label: "Timeline connue", completed: qualificationChecklist.timelineKnown, hint: "Quand veulent-ils avancer ?"),
                Objective(label: "Critères de décision", completed: qualificationChecklist.criteriaKnown, hint: "Sur quoi comparent-ils ?")
            ]
        case .presentation:
            return [
                Objective(label: "Lié au besoin exprimé", completed: false, hint: "Chaque feature → bénéfice client"),
                Objective(label: "Cas client cité", completed: false, hint: "Social proof = crédibilité"),
                Objective(label: "Prospect engagé", completed: false, hint: "Questions, réactions, acquiescements")
            ]
        case .objections:
            return [
                Objective(label: "Objection écoutée complètement", completed: false, hint: "Ne coupez pas. Laissez finir."),
                Objective(label: "Reformulée", completed: false, hint: "\"Si je comprends bien, votre inquiétude c'est...\""),
                Objective(label: "Répondue avec preuve", completed: false, hint: "Cas client, data, garantie")
            ]
        case .closing:
            return [
                Objective(label: "Valeur résumée", completed: false, hint: "Rappel du pain → solution → résultat"),
                Objective(label: "Action proposée", completed: false, hint: "Contrat, démo, essai, RDV"),
                Objective(label: "Silence observé", completed: false, hint: "Après la question de closing : taisez-vous")
            ]
        case .suivi:
            return [
                Objective(label: "Prochaine étape calée", completed: false, hint: "Date + action concrète"),
                Objective(label: "CR envoyé", completed: false, hint: "Dans l'heure, pas demain"),
                Objective(label: "Actions réparties", completed: false, hint: "Moi → X, Vous → Y")
            ]
        }
    }
    
    // MARK: - Watch Signals
    
    private func buildWatchSignals(
        phase: SalesPhaseDetector.SalesPhase,
        recentSegments: [TranscriptionSegment]
    ) -> [WatchSignal] {
        let text = recentSegments.suffix(10).map { $0.text.lowercased() }.joined(separator: " ")
        
        switch phase {
        case .decouverte:
            return [
                WatchSignal(signal: "Prospect parle +60%", detected: false),
                WatchSignal(signal: "Mot \"problème\" ou \"difficulté\"", detected: text.contains("problème") || text.contains("difficulté")),
                WatchSignal(signal: "Chiffre ou montant mentionné", detected: text.range(of: #"\d+[€$k]"#, options: .regularExpression) != nil),
                WatchSignal(signal: "Soupir ou hésitation longue", detected: false)
            ]
        case .objections:
            return [
                WatchSignal(signal: "\"Trop cher\"", detected: text.contains("cher") || text.contains("prix")),
                WatchSignal(signal: "\"Je dois réfléchir\"", detected: text.contains("réfléchir") || text.contains("temps")),
                WatchSignal(signal: "Mention concurrent", detected: text.contains("concurrent") || text.contains("autre solution")),
                WatchSignal(signal: "\"Pas le bon moment\"", detected: text.contains("pas le moment") || text.contains("plus tard"))
            ]
        case .closing:
            return [
                WatchSignal(signal: "Questions pratiques (livraison, planning)", detected: text.contains("quand") || text.contains("comment on")),
                WatchSignal(signal: "Projection dans l'usage", detected: text.contains("on pourrait") || text.contains("ça nous permettrait")),
                WatchSignal(signal: "Accord verbal", detected: text.contains("ok") || text.contains("d'accord") || text.contains("ça marche")),
                WatchSignal(signal: "Demande de prix / devis", detected: text.contains("devis") || text.contains("proposition") || text.contains("tarif"))
            ]
        default:
            return []
        }
    }
    
    // MARK: - Checklists
    
    private func updateChecklists(_ segments: [TranscriptionSegment]) {
        let allText = segments.map { $0.text.lowercased() }.joined(separator: " ")
        
        // Discovery
        discoveryChecklist.painIdentified = allText.contains("problème") || allText.contains("difficulté")
            || allText.contains("challenge") || allText.contains("galère") || allText.contains("bloqué")
        discoveryChecklist.impactQuantified = allText.range(of: #"\d+\s*(€|euros?|k€|heures?|jours?|%)"#, options: .regularExpression) != nil
        discoveryChecklist.desiredOutcome = allText.contains("idéal") || allText.contains("objectif")
            || allText.contains("résultat") || allText.contains("succès")
        discoveryChecklist.reformulated = allText.contains("si je résume") || allText.contains("si j'ai bien compris")
        
        // Qualification (BANT)
        qualificationChecklist.budgetDiscussed = allText.contains("budget") || allText.contains("investissement")
            || allText.contains("enveloppe") || allText.contains("€") || allText.contains("tarif")
        qualificationChecklist.deciderIdentified = allText.contains("décideur") || allText.contains("qui décide")
            || allText.contains("direction") || allText.contains("comité") || allText.contains("validation")
        qualificationChecklist.timelineKnown = allText.contains("quand") || allText.contains("deadline")
            || allText.contains("échéance") || allText.contains("timeline") || allText.contains("urgent")
        qualificationChecklist.criteriaKnown = allText.contains("critère") || allText.contains("compare")
            || allText.contains("important pour") || allText.contains("priorité")
    }
    
    struct DiscoveryChecklist {
        var painIdentified = false
        var impactQuantified = false
        var desiredOutcome = false
        var reformulated = false
    }
    
    struct QualificationChecklist {
        var budgetDiscussed = false
        var deciderIdentified = false
        var timelineKnown = false
        var criteriaKnown = false
    }
}

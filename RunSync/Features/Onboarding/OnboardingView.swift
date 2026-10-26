import SwiftUI

/// Onboarding (E01) : expliquer Follow/Pace et les limites des sources musicales,
/// proposer un mode démo sans permission, et ne demander aucune permission par
/// anticipation. Aucune permission n'est requise en phase 1 (capteurs = RS-010/RS-012),
/// donc aucun refus ne peut casser l'application (FR-002).
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var stepIndex = 0

    private struct Step {
        let systemImage: String
        let title: String
        let message: String
    }

    private let steps: [Step] = [
        Step(
            systemImage: "figure.run",
            title: "Bienvenue dans RunSync",
            message: "La musique suit tes pas et t'accompagne vers ton rythme idéal. "
                + "Tout fonctionne en local : aucun compte, aucune connexion obligatoire."
        ),
        Step(
            systemImage: "metronome",
            title: "Deux façons de courir",
            message: "Follow : le tempo suit ta cadence réelle, dans la limite d'ajustement choisie. "
                + "Pace : le tempo suit une cadence cible que tu déclares, et l'écart réel s'affiche à part."
        ),
        Step(
            systemImage: "music.note",
            title: "Tes musiques, sous ta responsabilité",
            message: "Cette version n'utilise que des morceaux de démonstration. Seuls des fichiers "
                + "légalement importés et dont le droit d'adaptation est établi pourront être traités. "
                + "Aucun service de streaming n'est branché."
        ),
        Step(
            systemImage: "checkmark.seal",
            title: "Permissions demandées au bon moment",
            message: "Aucune permission n'est demandée maintenant. Le mouvement et la localisation "
                + "seront demandés quand ils deviendront utiles, et un refus laissera l'application utilisable."
        )
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            Spacer(minLength: 0)

            Image(systemName: steps[stepIndex].systemImage)
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.small) {
                Text(steps[stepIndex].title)
                    .font(Theme.Typography.metric)
                    .multilineTextAlignment(.center)
                Text(steps[stepIndex].message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.large)

            Spacer(minLength: 0)

            HStack(spacing: Theme.Spacing.small) {
                ForEach(steps.indices, id: \.self) { index in
                    Circle()
                        .fill(index == stepIndex ? Theme.accent : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
            }

            PrimaryActionButton(
                title: stepIndex == steps.count - 1 ? "Continuer" : "Suivant",
                systemImage: stepIndex == steps.count - 1 ? "checkmark" : "arrow.right",
                action: advance
            )

            Button("Explorer le mode démo") { onFinish() }
                .font(Theme.Typography.caption)
                .padding(.bottom, Theme.Spacing.medium)
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.screenBackground)
    }

    private func advance() {
        if stepIndex == steps.count - 1 {
            onFinish()
        } else {
            stepIndex += 1
        }
    }
}

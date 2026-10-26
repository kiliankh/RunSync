import SwiftUI

/// Point d'entrée de l'application (§06). Aucun compte, aucune connexion
/// obligatoire : l'application démarre sur l'écran Accueil, hors ligne (FR-001).
@main
struct RunSyncApp: App {
    @State private var container = DependencyContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(container)
                .tint(Theme.accent)
        }
    }
}

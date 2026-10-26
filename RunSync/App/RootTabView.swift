import SwiftUI

/// Les quatre onglets produits (§03) : Accueil, Musique, Courir, Statistiques.
/// Le profil/réglages est accessible par l'engrenage, pas par un onglet.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case music
    case run
    case statistics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Accueil"
        case .music: return "Musique"
        case .run: return "Courir"
        case .statistics: return "Statistiques"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .music: return "music.note.list"
        case .run: return "figure.run"
        case .statistics: return "chart.bar"
        }
    }
}

struct RootTabView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var selection: AppTab = .home

    var body: some View {
        @Bindable var settings = container.settings

        TabView(selection: $selection) {
            HomeView(selectedTab: $selection)
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                .tag(AppTab.home)

            MusicLibraryView()
                .tabItem { Label(AppTab.music.title, systemImage: AppTab.music.systemImage) }
                .tag(AppTab.music)

            RunSetupView()
                .tabItem { Label(AppTab.run.title, systemImage: AppTab.run.systemImage) }
                .tag(AppTab.run)

            StatisticsView()
                .tabItem {
                    Label(AppTab.statistics.title, systemImage: AppTab.statistics.systemImage)
                }
                .tag(AppTab.statistics)
        }
        .fullScreenCover(isPresented: .init(
            get: { !settings.onboardingCompleted },
            set: { settings.onboardingCompleted = !$0 }
        )) {
            OnboardingView { settings.onboardingCompleted = true }
        }
    }
}

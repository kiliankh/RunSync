// swift-tools-version: 5.9
//
// RunSync — noyau portable (Domain + Simulation).
//
// Ce manifeste existe pour une raison précise (voir Docs/ARCHITECTURE.md) :
// le Domain et le simulateur déterministe sont du Swift pur (Foundation +
// concurrence), sans SwiftUI, CoreMotion, CoreLocation ni AVFAudio. Ils peuvent
// donc être compilés et testés par `swift test` sur macOS (et Linux), c'est-à-dire
// sans projet Xcode ni simulateur iPhone, ce que la spec §11/§16.H exige de
// pouvoir exécuter. L'application iOS elle-même est générée via XcodeGen
// (project.yml) et dépend de ces deux bibliothèques.
import PackageDescription

let package = Package(
    name: "RunSyncCore",
    platforms: [
        // Cible provisoire, à réviser (§15) selon les API réellement retenues.
        .iOS(.v17),
        // macOS 13, délibérément, et non 14 : ce plancher ne décrit pas seulement la
        // disponibilité des API, il fixe la version **minimale d'exécution** des
        // binaires produits (outil de démonstration `runsync-demo` et bundle de
        // tests). Déclaré en 14, `swift build` réussissait encore sur macOS 13 mais
        // plus rien ne s'exécutait : « Symbol not found … built for macOS 14.0 which
        // is newer than running OS », et `swift test` ne lançait silencieusement
        // aucun test. Constaté sur macOS 13.7.8 + Xcode 15.2.
        .macOS(.v13)
    ],
    products: [
        .library(name: "RunSyncDomain", targets: ["RunSyncDomain"]),
        .library(name: "RunSyncSimulation", targets: ["RunSyncSimulation"]),
        .library(name: "RunSyncPersistence", targets: ["RunSyncPersistence"]),
        // Outil de diagnostic en ligne de commande : rejoue un scénario de cadence et
        // affiche toute la chaîne de décision, sans capteur, sans audio, sans iPhone.
        .executable(name: "runsync-demo", targets: ["runsync-demo"])
    ],
    targets: [
        // Domain pur : modèles, contrats, algorithmes tempo. Aucun framework iOS.
        .target(
            name: "RunSyncDomain",
            path: "RunSync/Domain"
        ),
        // Simulateur de cadence déterministe (RS-004) : scénarios horodatés,
        // fixtures JSON/CSV, source factice. Utilisé par la démo sans capteur (FR-004)
        // et par les tests.
        .target(
            name: "RunSyncSimulation",
            dependencies: ["RunSyncDomain"],
            path: "RunSync/Simulation"
        ),
        // Stockage disque des fichiers importés (RS-020). Foundation pur : il est
        // réellement testable sans iPhone (copie, taille, espace, suppression,
        // réconciliation). Confiné à un sous-répertoire privé de l'application.
        .target(
            name: "RunSyncPersistence",
            dependencies: ["RunSyncDomain"],
            path: "RunSync/Infrastructure/Persistence"
        ),
        .testTarget(
            name: "RunSyncDomainTests",
            dependencies: ["RunSyncDomain", "RunSyncSimulation"],
            path: "RunSync/Tests/DomainTests"
        ),
        .testTarget(
            name: "RunSyncSimulationTests",
            dependencies: ["RunSyncDomain", "RunSyncSimulation"],
            path: "RunSync/Tests/SimulationTests"
        ),
        .testTarget(
            name: "RunSyncPersistenceTests",
            dependencies: ["RunSyncDomain", "RunSyncPersistence", "RunSyncSimulation"],
            path: "RunSync/Tests/StorageTests"
        ),
        .executableTarget(
            name: "runsync-demo",
            dependencies: ["RunSyncDomain", "RunSyncSimulation"],
            path: "RunSync/Tools/DemoTrace"
        )
    ]
)

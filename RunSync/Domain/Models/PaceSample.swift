import Foundation

/// Échantillon d'allure/distance GPS horodaté (FR-005, §08).
/// Aucune vitesse fictive : si le signal est absent, les champs restent `nil`
/// et la qualité passe à `unavailable`.
public struct PaceSample: Sendable, Equatable {
    public let timestamp: Date
    public let secondsPerKilometer: Double?
    public let distanceMeters: Double?
    public let quality: DataQuality

    public init(
        timestamp: Date,
        secondsPerKilometer: Double?,
        distanceMeters: Double?,
        quality: DataQuality
    ) {
        self.timestamp = timestamp
        self.secondsPerKilometer = secondsPerKilometer
        self.distanceMeters = distanceMeters
        self.quality = quality
    }

    public static func unavailable(timestamp: Date) -> PaceSample {
        PaceSample(
            timestamp: timestamp,
            secondsPerKilometer: nil,
            distanceMeters: nil,
            quality: .unavailable
        )
    }
}

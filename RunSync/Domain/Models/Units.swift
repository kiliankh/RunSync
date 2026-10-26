import Foundation

/// Conversions et validations d'unités. Vocabulaire figé par la spec §05 :
/// `SPM` = pas/minute (cadence), `BPM` = battements/minute (musique),
/// `paceSecondsPerKilometer` = secondes par kilomètre. Ne jamais confondre SPM et allure.
public enum CadenceUnits {
    /// Plage large de plausibilité. Configurable dans les filtres ; rejeter n'est
    /// pas masquer : les rejets sont journalisés dans le diagnostic (§05).
    public static let plausibleRangeSPM: ClosedRange<Double> = 80...240

    /// Conversion CoreMotion : `CMPedometerData.currentCadence` est en pas/seconde.
    /// Retourne `nil` si la valeur n'est pas exploitable (nil, NaN, infini, <= 0).
    /// T001 : 2.833333 pas/s => 170 SPM.
    public static func stepsPerSecondToSPM(_ stepsPerSecond: Double?) -> Double? {
        guard let stepsPerSecond else { return nil }
        guard stepsPerSecond.isFinite, stepsPerSecond > 0 else { return nil }
        let spm = stepsPerSecond * 60
        guard spm.isFinite, spm > 0 else { return nil }
        return spm
    }

    /// Validité d'une cadence en SPM dans une plage donnée.
    public static func isPlausibleSPM(
        _ spm: Double,
        in range: ClosedRange<Double> = plausibleRangeSPM
    ) -> Bool {
        guard spm.isFinite else { return false }
        return range.contains(spm)
    }
}

/// Conversions d'allure. L'allure ne se convertit **pas** en cadence sans modèle
/// individuel calibré (§05, R6) : aucune fonction ici ne le fait.
public enum PaceUnits {
    public static let plausibleRangeSecondsPerKilometer: ClosedRange<Double> = 120...1200

    /// Allure depuis distance et durée ; `nil` si les entrées ne sont pas exploitables.
    public static func secondsPerKilometer(
        distanceMeters: Double?,
        durationSeconds: Double?
    ) -> Double? {
        guard let distanceMeters, let durationSeconds else { return nil }
        guard distanceMeters.isFinite, durationSeconds.isFinite else { return nil }
        guard distanceMeters > 0, durationSeconds > 0 else { return nil }
        let secondsPerKilometer = durationSeconds / (distanceMeters / 1000)
        guard secondsPerKilometer.isFinite, secondsPerKilometer > 0 else { return nil }
        return secondsPerKilometer
    }

    /// Allure depuis une vitesse en mètres par seconde ; `nil` si vitesse absente ou nulle.
    public static func secondsPerKilometer(metersPerSecond: Double?) -> Double? {
        guard let metersPerSecond else { return nil }
        guard metersPerSecond.isFinite, metersPerSecond > 0 else { return nil }
        return 1000 / metersPerSecond
    }

    /// `300` => "5:00 /km". Aucune valeur inventée : `nil` => "—".
    public static func formattedPace(secondsPerKilometer: Double?) -> String {
        guard let secondsPerKilometer, secondsPerKilometer.isFinite, secondsPerKilometer > 0 else {
            return "—"
        }
        let totalSeconds = Int(secondsPerKilometer.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    /// `170.4` => "170 SPM". `nil` => "—" (jamais 0 : §05 exemple D).
    public static func formattedSPM(_ spm: Double?) -> String {
        guard let spm, spm.isFinite else { return "—" }
        return String(format: "%.0f SPM", spm)
    }

    /// `1.0119` => "+1.2 %".
    public static func formattedRatePercent(_ rate: Double?) -> String {
        guard let rate, rate.isFinite else { return "—" }
        return String(format: "%+.1f %%", (rate - 1) * 100)
    }
}

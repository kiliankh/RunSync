import Foundation

/// Encodage/décodage des scénarios de cadence (RS-004 : fixtures JSON et CSV).
///
/// Toute valeur décodée est revalidée (`validated()`) : les fixtures sont une
/// entrée externe non fiable (§14).
public enum CadenceScenarioCodec {

    public enum Format: String, Sendable, CaseIterable {
        case json
        case csv
    }

    public static func decode(_ data: Data, format: Format) throws -> CadenceScenario {
        switch format {
        case .json:
            return try decodeJSON(data)
        case .csv:
            guard let text = String(data: data, encoding: .utf8) else {
                throw CadenceScenarioError.malformedLine(lineNumber: 0, content: "<encodage non UTF-8>")
            }
            return try decodeCSV(text)
        }
    }

    public static func decodeJSON(_ data: Data) throws -> CadenceScenario {
        let scenario = try JSONDecoder().decode(CadenceScenario.self, from: data)
        return try scenario.validated()
    }

    /// Format CSV :
    /// ```
    /// # commentaires ignorés
    /// id=demo.follow
    /// name=libellé lisible
    /// duration=60
    /// offsetSeconds,stepsPerMinute,note
    /// 0,170,croisière
    /// 28,,capteur indisponible
    /// ```
    /// Une valeur `stepsPerMinute` vide, `nil` ou `none` signifie « capteur sans valeur ».
    public static func decodeCSV(_ text: String) throws -> CadenceScenario {
        var identifier: String?
        var name: String?
        var duration: TimeInterval?
        var steps: [CadenceScenario.Step] = []
        var headerSkipped = false

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let beforeEquals = line.split(separator: "=", maxSplits: 1).first.map(String.init) ?? line
            if line.contains("="), Double(beforeEquals) == nil {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                switch key {
                case "id": identifier = value
                case "name": name = value
                case "duration", "durationseconds": duration = Double(value)
                default: continue
                }
                continue
            }

            let fields = line.components(separatedBy: ",")
            guard let offset = Double(fields[0].trimmingCharacters(in: .whitespaces)) else {
                // Première ligne non numérique : en-tête de colonnes, ignoré une seule fois.
                if !headerSkipped {
                    headerSkipped = true
                    continue
                }
                throw CadenceScenarioError.malformedLine(lineNumber: lineNumber, content: line)
            }
            guard fields.count >= 2 else {
                throw CadenceScenarioError.malformedLine(lineNumber: lineNumber, content: line)
            }
            let cadenceField = fields[1].trimmingCharacters(in: .whitespaces).lowercased()
            let cadence: Double?
            if cadenceField.isEmpty || cadenceField == "nil" || cadenceField == "none" {
                cadence = nil
            } else if let parsed = Double(cadenceField) {
                cadence = parsed
            } else {
                throw CadenceScenarioError.malformedLine(lineNumber: lineNumber, content: line)
            }
            let note = fields.count >= 3
                ? fields[2].trimmingCharacters(in: .whitespaces)
                : ""
            steps.append(
                CadenceScenario.Step(
                    offsetSeconds: offset,
                    stepsPerMinute: cadence,
                    note: note.isEmpty ? nil : note
                )
            )
        }

        guard let duration else { throw CadenceScenarioError.missingDuration }
        let scenario = CadenceScenario(
            id: identifier ?? "csv.unnamed",
            name: name ?? "Scénario CSV",
            steps: steps,
            durationSeconds: duration
        )
        return try scenario.validated()
    }
}

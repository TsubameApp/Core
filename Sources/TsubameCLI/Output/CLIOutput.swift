import Foundation
import TsubameCore

enum CLIOutput {
    static func printEntry(
        _ entry: DictionaryEntry,
        debug: Bool,
        indentation: String = "  "
    ) {
        let headword: String
        if entry.reading.isEmpty || entry.reading == entry.expression {
            headword = entry.expression
        } else {
            headword = "\(entry.expression)【\(entry.reading)】"
        }
        print("\(indentation)\(headword)")
        if debug {
            let matches = entry.matches.map {
                "\($0.keyType.rawValue):\($0.key)"
            }.joined(separator: ", ")
            print(
                "\(indentation)  [debug] score=\(entry.score) sequence=\(entry.sequence) "
                    + "rules=\(quoted(entry.rules)) "
                    + "definitionTags=\(quoted(entry.definitionTags ?? "")) "
                    + "termTags=\(quoted(entry.termTags)) matches=[\(matches)]"
            )
        }
        for definition in entry.definitions {
            let content = definition.text
                ?? String(decoding: definition.contentJSON, as: UTF8.self)
            print("\(indentation)  - \(content)")
        }
    }

    static func sourceText(in text: String, range: UTF8TextRange) -> String {
        let utf8 = text.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: range.start)
        let end = utf8.index(utf8.startIndex, offsetBy: range.end)
        return String(decoding: utf8[start..<end], as: UTF8.self)
    }

    static func printElapsedTimeIfNeeded(
        label: String,
        startedAt: ContinuousClock.Instant,
        debug: Bool
    ) {
        guard debug else { return }
        print("[debug] \(label): \(formattedMilliseconds(since: startedAt))")
    }

    static func milliseconds(since startedAt: ContinuousClock.Instant) -> Double {
        let components = startedAt.duration(to: .now).components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    static func formattedMilliseconds(since startedAt: ContinuousClock.Instant) -> String {
        formatted(milliseconds: milliseconds(since: startedAt))
    }

    static func formatted(milliseconds: Double) -> String {
        String(format: "%.3f ms", milliseconds)
    }

    private static func quoted(_ value: String) -> String {
        String(reflecting: value)
    }
}

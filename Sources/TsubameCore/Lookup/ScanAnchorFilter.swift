import Foundation

struct ScanAnchorFilter: Sendable {
    func shouldScan(_ character: Character, normalized: String) -> Bool {
        containsLexicalScalar(character.unicodeScalars)
            || containsLexicalScalar(normalized.unicodeScalars)
    }

    private func containsLexicalScalar<S: Sequence>(
        _ scalars: S
    ) -> Bool where S.Element == Unicode.Scalar {
        var containsLexicalScalar = false
        for scalar in scalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter,
                 .lowercaseLetter,
                 .titlecaseLetter,
                 .modifierLetter,
                 .otherLetter,
                 .nonspacingMark,
                 .spacingMark,
                 .enclosingMark,
                 .decimalNumber,
                 .letterNumber,
                 .otherNumber:
                containsLexicalScalar = true
            default:
                continue
            }
        }
        return containsLexicalScalar
    }
}

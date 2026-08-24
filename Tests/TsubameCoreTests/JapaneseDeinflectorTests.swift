import Foundation
import Testing
@testable import TsubameCore

@Suite
struct JapaneseDeinflectorTests {
    @Test func loadsCompletePinnedRuleCorpus() throws {
        let rules = try JapaneseDeinflectionRules.load()

        #expect(rules.conditionSetsByID.count == 22)
        #expect(rules.leafConditionCount == 18)
        #expect(!rules.rules.isEmpty)
        #expect(rules.conditionSet(for: "v1") != nil)
        #expect(rules.conditionSet(for: "-ゃ") != nil)
    }

    @Test func producesRequiredBasicForms() throws {
        let deinflector = JapaneseDeinflector(rules: try JapaneseDeinflectionRules.load())
        let cases = [
            ("食べました", "食べる"),
            ("食べなかった", "食べる"),
            ("読んだ", "読む"),
            ("書いた", "書く"),
            ("話した", "話す"),
        ]
        for (source, expected) in cases {
            let result = deinflector.transform(source)
            #expect(result.candidates.contains { $0.lemma == expected })
        }
    }

    @Test func matchesPinnedYomitanFixtureCorpus() throws {
        let rules = try JapaneseDeinflectionRules.load()
        let deinflector = JapaneseDeinflector(rules: rules)
        let fixtures = try loadFixtures()
        var checked = 0
        var mismatches: [String] = []
        var truncationCount = 0

        for group in fixtures.groups {
            for fixture in group.tests {
                checked += 1
                let result = deinflector.transform(fixture.source)
                if result.wasTruncated { truncationCount += 1 }
                let hasExpectedCandidate = result.candidates.contains { candidate in
                    guard candidate.lemma.utf8.elementsEqual(fixture.term.utf8) else {
                        return false
                    }
                    if let rule = fixture.rule {
                        guard let expected = rules.conditionSet(for: rule),
                              candidate.conditions.isEmpty
                                || candidate.conditions.intersects(expected) else {
                            return false
                        }
                    }
                    if let reasons = fixture.reasons,
                       candidate.path.reasons != reasons {
                        return false
                    }
                    return true
                }
                if hasExpectedCandidate != group.valid, mismatches.count < 20 {
                    mismatches.append(
                        "\(group.category): \(fixture.source) -> \(fixture.term), " +
                        "rule=\(fixture.rule ?? "nil"), reasons=\(fixture.reasons ?? []), " +
                        "valid=\(group.valid), states=\(result.visitedStateCount)"
                    )
                }
            }
        }

        #expect(checked > 1_000)
        #expect(truncationCount == 0)
        #expect(mismatches.isEmpty)
    }

    @Test func enforcesDepthAndStateLimits() throws {
        let rules = try JapaneseDeinflectionRules.load()
        let depthLimited = JapaneseDeinflector(
            rules: rules,
            maximumDepth: 1,
            maximumStateCount: 256
        ).transform("食べませんでした")
        #expect(depthLimited.maximumDepthReached <= 1)

        let stateLimited = JapaneseDeinflector(
            rules: rules,
            maximumDepth: 16,
            maximumStateCount: 2
        ).transform("食べませんでした")
        #expect(stateLimited.visitedStateCount == 2)
        #expect(stateLimited.wasTruncated)
    }

    private func loadFixtures() throws -> FixtureFile {
        let url = try #require(
            Bundle.module.url(
                forResource: "YomitanJapaneseDeinflectionFixtures",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url))
    }
}

@Suite
struct DeinflectionConditionSetTests {
    @Test func supportsBothSixtyFourBitWords() {
        let bit0 = DeinflectionConditionSet(bitIndex: 0)
        let bit63 = DeinflectionConditionSet(bitIndex: 63)
        let bit64 = DeinflectionConditionSet(bitIndex: 64)
        let bit127 = DeinflectionConditionSet(bitIndex: 127)

        #expect(bit0.intersects(bit0))
        #expect(bit63.intersects(bit63))
        #expect(bit64.intersects(bit64))
        #expect(bit127.intersects(bit127))
        #expect(!bit63.intersects(bit64))
        #expect(bit0.union(bit127).intersects(bit127))
    }

    @Test func canonicalizesGranularDictionaryRules() {
        #expect(DictionaryRuleSet.parse("v5k v5r-i") == .godan)
        #expect(DictionaryRuleSet.parse("v1-s") == .ichidan)
        #expect(DictionaryRuleSet.parse("vs-i") == .suru)
        #expect(DictionaryRuleSet.parse("vk vz adj-ix") == [
            .kuru, .zuru, .iAdjective,
        ])
        #expect(DictionaryRuleSet.parse("adj-na n") == [])
    }
}

private struct FixtureFile: Decodable {
    let schemaVersion: Int
    let upstreamCommit: String
    let groups: [FixtureGroup]
}

private struct FixtureGroup: Decodable {
    let category: String
    let valid: Bool
    let tests: [Fixture]
}

private struct Fixture: Decodable {
    let term: String
    let source: String
    let rule: String?
    let reasons: [String]?
}

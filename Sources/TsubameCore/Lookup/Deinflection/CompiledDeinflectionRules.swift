/*
 * Copyright (C) 2024-2026 Yomitan Authors
 * Copyright (C) 2026 Tsubame Authors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

enum DictionaryRuleConstraint: Sendable, Equatable, Hashable {
    case any
    case required(DictionaryRuleSet)
}

struct CompiledDeinflectionRule: Sendable {
    let kind: DeinflectionRuleKind
    let input: Data
    let output: Data
    let conditionsIn: DeinflectionConditionSet
    let conditionsOut: DeinflectionConditionSet
    let transformID: String
    let transformIndex: Int
    let ruleIndex: Int
    let stableOrder: Int

    func matches(_ bytes: Data) -> Bool {
        switch kind {
        case .suffix:
            guard input.count <= bytes.count else { return false }
            return bytes.suffix(input.count).elementsEqual(input)
        case .wholeWord:
            return bytes == input
        }
    }

    func apply(to bytes: Data) -> Data {
        switch kind {
        case .suffix:
            var result = Data()
            result.reserveCapacity(bytes.count - input.count + output.count)
            result.append(bytes.prefix(bytes.count - input.count))
            result.append(output)
            return result
        case .wholeWord:
            return output
        }
    }
}

struct CompiledDeinflectionRules: Sendable {
    static let supportedSchemaVersion = 1
    static let expectedUpstreamCommit = "77e200428902abf4fa48284df92da7af3dcb4162"

    let rules: [CompiledDeinflectionRule]
    let conditionSetsByID: [String: DeinflectionConditionSet]
    let ruleIndicesByLastByte: [UInt8: [Int]]
    let dictionaryConditionSets: [(DictionaryRuleSet, DeinflectionConditionSet)]
    let leafConditionCount: Int

    init(file: DeinflectionRuleFile) throws {
        guard file.schemaVersion == Self.supportedSchemaVersion else {
            throw DeinflectionRuleError.unsupportedSchemaVersion(file.schemaVersion)
        }
        guard file.upstream.commit == Self.expectedUpstreamCommit else {
            throw DeinflectionRuleError.unexpectedUpstreamCommit(file.upstream.commit)
        }
        guard file.language == "ja" else {
            throw DeinflectionRuleError.unsupportedLanguage(file.language)
        }

        var recordsByID: [String: DeinflectionConditionRecord] = [:]
        recordsByID.reserveCapacity(file.conditions.count)
        for record in file.conditions {
            guard recordsByID.updateValue(record, forKey: record.id) == nil else {
                throw DeinflectionRuleError.duplicateCondition(record.id)
            }
        }

        let leaves = file.conditions.filter { $0.subConditions == nil }
        guard leaves.count <= 128 else {
            throw DeinflectionRuleError.tooManyLeafConditions(leaves.count)
        }
        var resolved: [String: DeinflectionConditionSet] = [:]
        for (index, record) in leaves.enumerated() {
            resolved[record.id] = DeinflectionConditionSet(bitIndex: index)
        }

        var visiting: Set<String> = []
        func resolve(_ id: String) throws -> DeinflectionConditionSet {
            if let value = resolved[id] { return value }
            guard let record = recordsByID[id] else {
                throw DeinflectionRuleError.unknownCondition(id)
            }
            guard visiting.insert(id).inserted else {
                throw DeinflectionRuleError.conditionCycle(id)
            }
            defer { visiting.remove(id) }

            guard let subConditions = record.subConditions else {
                throw DeinflectionRuleError.unknownCondition(id)
            }
            var value = DeinflectionConditionSet.empty
            for child in subConditions {
                value.formUnion(try resolve(child))
            }
            resolved[id] = value
            return value
        }

        for record in file.conditions {
            _ = try resolve(record.id)
        }

        var seenTransforms: Set<String> = []
        var compiledRules: [CompiledDeinflectionRule] = []
        var indicesByLastByte: [UInt8: [Int]] = [:]
        for (transformIndex, transform) in file.transforms.enumerated() {
            guard seenTransforms.insert(transform.id).inserted else {
                throw DeinflectionRuleError.duplicateTransform(transform.id)
            }
            for (ruleIndex, rule) in transform.rules.enumerated() {
                let input = Data(rule.input.utf8)
                guard !input.isEmpty else {
                    throw DeinflectionRuleError.emptyRuleInput(
                        transform: transform.id,
                        ruleIndex: ruleIndex
                    )
                }
                var conditionsIn = DeinflectionConditionSet.empty
                for id in rule.conditionsIn {
                    conditionsIn.formUnion(try resolve(id))
                }
                var conditionsOut = DeinflectionConditionSet.empty
                for id in rule.conditionsOut {
                    conditionsOut.formUnion(try resolve(id))
                }
                let compiled = CompiledDeinflectionRule(
                    kind: rule.kind,
                    input: input,
                    output: Data(rule.output.utf8),
                    conditionsIn: conditionsIn,
                    conditionsOut: conditionsOut,
                    transformID: transform.id,
                    transformIndex: transformIndex,
                    ruleIndex: ruleIndex,
                    stableOrder: compiledRules.count
                )
                let index = compiledRules.count
                compiledRules.append(compiled)
                if let lastByte = input.last {
                    indicesByLastByte[lastByte, default: []].append(index)
                }
            }
        }

        let dictionaryMappings: [(String, DictionaryRuleSet)] = [
            ("v1", .ichidan),
            ("v5", .godan),
            ("vk", .kuru),
            ("vs", .suru),
            ("vz", .zuru),
            ("adj-i", .iAdjective),
        ]
        var dictionarySets: [(DictionaryRuleSet, DeinflectionConditionSet)] = []
        for (id, dictionaryRule) in dictionaryMappings {
            guard let conditionSet = resolved[id],
                  recordsByID[id]?.isDictionaryForm == true else {
                throw DeinflectionRuleError.unknownCondition(id)
            }
            dictionarySets.append((dictionaryRule, conditionSet))
        }

        rules = compiledRules
        conditionSetsByID = resolved
        ruleIndicesByLastByte = indicesByLastByte
        dictionaryConditionSets = dictionarySets
        leafConditionCount = leaves.count
    }

    func dictionaryConstraint(
        for conditions: DeinflectionConditionSet
    ) -> DictionaryRuleConstraint? {
        if conditions.isEmpty {
            return .any
        }
        var rules: DictionaryRuleSet = []
        for (dictionaryRule, conditionSet) in dictionaryConditionSets
            where conditions.intersects(conditionSet) {
            rules.insert(dictionaryRule)
        }
        return rules.isEmpty ? nil : .required(rules)
    }

    func conditionSet(for id: String) -> DeinflectionConditionSet? {
        conditionSetsByID[id]
    }
}

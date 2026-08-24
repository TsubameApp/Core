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

struct DeinflectionRuleFile: Decodable, Sendable {
    struct Upstream: Decodable, Sendable {
        let repository: String
        let commit: String
        let source: String
    }

    let schemaVersion: Int
    let upstream: Upstream
    let language: String
    let conditions: [DeinflectionConditionRecord]
    let transforms: [DeinflectionTransformRecord]
}

struct DeinflectionConditionRecord: Decodable, Sendable {
    let id: String
    let isDictionaryForm: Bool
    let subConditions: [String]?
}

struct DeinflectionTransformRecord: Decodable, Sendable {
    let id: String
    let rules: [DeinflectionRuleRecord]
}

enum DeinflectionRuleKind: String, Decodable, Sendable {
    case suffix
    case wholeWord
}

struct DeinflectionRuleRecord: Decodable, Sendable {
    let kind: DeinflectionRuleKind
    let input: String
    let output: String
    let conditionsIn: [String]
    let conditionsOut: [String]
}

enum DeinflectionRuleError: LocalizedError, Sendable, Equatable {
    case missingResource
    case unsupportedSchemaVersion(Int)
    case unexpectedUpstreamCommit(String)
    case unsupportedLanguage(String)
    case duplicateCondition(String)
    case duplicateTransform(String)
    case unknownCondition(String)
    case conditionCycle(String)
    case tooManyLeafConditions(Int)
    case emptyRuleInput(transform: String, ruleIndex: Int)
    case invalidRuleOutput(transform: String, ruleIndex: Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            "The bundled Japanese deinflection rule resource is missing."
        case .unsupportedSchemaVersion(let version):
            "Unsupported Japanese deinflection rule schema version: \(version)."
        case .unexpectedUpstreamCommit(let commit):
            "Unexpected Yomitan deinflection commit: \(commit)."
        case .unsupportedLanguage(let language):
            "Unsupported deinflection language: \(language)."
        case .duplicateCondition(let id):
            "Duplicate deinflection condition: \(id)."
        case .duplicateTransform(let id):
            "Duplicate deinflection transform: \(id)."
        case .unknownCondition(let id):
            "Unknown deinflection condition: \(id)."
        case .conditionCycle(let id):
            "Cycle in deinflection condition graph at: \(id)."
        case .tooManyLeafConditions(let count):
            "Deinflection rules contain \(count) leaf conditions; maximum is 128."
        case let .emptyRuleInput(transform, index):
            "Deinflection transform \(transform) rule \(index) has an empty input."
        case let .invalidRuleOutput(transform, index):
            "Deinflection transform \(transform) rule \(index) has invalid UTF-8 output."
        case .decodingFailed(let message):
            "Unable to decode Japanese deinflection rules: \(message)"
        }
    }
}

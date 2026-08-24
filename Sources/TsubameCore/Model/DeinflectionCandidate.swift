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

struct DeinflectionStep: Sendable, Equatable {
    let transformID: String
    let transformIndex: Int
    let ruleIndex: Int
    let sourceBytes: Data
}

struct DeinflectionPath: Sendable, Equatable {
    let steps: [DeinflectionStep]

    static let empty = DeinflectionPath(steps: [])

    var depth: Int { steps.count }
    var reasons: [String] { steps.map(\.transformID) }
}

struct DeinflectionCandidate: Sendable, Equatable {
    let lemma: String
    let lemmaBytes: Data
    let conditions: DeinflectionConditionSet
    let path: DeinflectionPath
    let stableOrder: Int
}

struct DeinflectionResult: Sendable, Equatable {
    let candidates: [DeinflectionCandidate]
    let wasTruncated: Bool
    let visitedStateCount: Int
    let maximumDepthReached: Int
}

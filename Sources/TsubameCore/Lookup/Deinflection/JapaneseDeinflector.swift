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

enum DeinflectionLimits {
    static let maximumDepth = 8
    static let maximumStateCountPerSurface = 256
}

struct JapaneseDeinflector: Sendable {
    let rules: CompiledDeinflectionRules
    let maximumDepth: Int
    let maximumStateCount: Int

    init(
        rules: CompiledDeinflectionRules,
        maximumDepth: Int = DeinflectionLimits.maximumDepth,
        maximumStateCount: Int = DeinflectionLimits.maximumStateCountPerSurface
    ) {
        self.rules = rules
        self.maximumDepth = maximumDepth
        self.maximumStateCount = maximumStateCount
    }

    func transform(_ source: String) -> DeinflectionResult {
        let sourceBytes = Data(source.utf8)
        let seed = DeinflectionCandidate(
            lemma: source,
            lemmaBytes: sourceBytes,
            conditions: .empty,
            path: .empty,
            stableOrder: 0
        )
        guard !sourceBytes.isEmpty, maximumStateCount > 1 else {
            return DeinflectionResult(
                candidates: [seed],
                wasTruncated: !sourceBytes.isEmpty && maximumStateCount <= 1,
                visitedStateCount: 1,
                maximumDepthReached: 0
            )
        }

        var candidates = [seed]
        candidates.reserveCapacity(min(maximumStateCount, 64))
        var cursor = 0
        var wasTruncated = false
        var maximumDepthReached = 0

        traversal: while cursor < candidates.count {
            let candidate = candidates[cursor]
            cursor += 1
            let depth = candidate.path.depth
            maximumDepthReached = max(maximumDepthReached, depth)
            guard depth < maximumDepth,
                  let lastByte = candidate.lemmaBytes.last,
                  let ruleIndices = rules.ruleIndicesByLastByte[lastByte] else {
                continue
            }

            for ruleIndex in ruleIndices {
                let rule = rules.rules[ruleIndex]
                guard conditionsMatch(
                    current: candidate.conditions,
                    required: rule.conditionsIn
                ), rule.matches(candidate.lemmaBytes) else {
                    continue
                }
                let isCycle = candidate.path.steps.contains { step in
                    step.transformIndex == rule.transformIndex
                        && step.ruleIndex == rule.ruleIndex
                        && step.sourceBytes == candidate.lemmaBytes
                }
                guard !isCycle else { continue }

                guard candidates.count < maximumStateCount else {
                    wasTruncated = true
                    break traversal
                }
                let resultBytes = rule.apply(to: candidate.lemmaBytes)
                guard let resultText = String(data: resultBytes, encoding: .utf8) else {
                    continue
                }
                var steps = [
                    DeinflectionStep(
                        transformID: rule.transformID,
                        transformIndex: rule.transformIndex,
                        ruleIndex: rule.ruleIndex,
                        sourceBytes: candidate.lemmaBytes
                    ),
                ]
                steps.append(contentsOf: candidate.path.steps)
                candidates.append(
                    DeinflectionCandidate(
                        lemma: resultText,
                        lemmaBytes: resultBytes,
                        conditions: rule.conditionsOut,
                        path: DeinflectionPath(steps: steps),
                        stableOrder: candidates.count
                    )
                )
            }
        }

        return DeinflectionResult(
            candidates: candidates,
            wasTruncated: wasTruncated,
            visitedStateCount: candidates.count,
            maximumDepthReached: maximumDepthReached
        )
    }

    private func conditionsMatch(
        current: DeinflectionConditionSet,
        required: DeinflectionConditionSet
    ) -> Bool {
        current.isEmpty || current.intersects(required)
    }
}

/*
 * Copyright (C) 2024-2026 Yomitan Authors
 * Copyright (C) 2026 Tsubame Authors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

struct DeinflectionConditionSet: Hashable, Sendable {
    private(set) var low: UInt64
    private(set) var high: UInt64

    static let empty = DeinflectionConditionSet()

    init(low: UInt64 = 0, high: UInt64 = 0) {
        self.low = low
        self.high = high
    }

    init(bitIndex: Int) {
        precondition((0..<128).contains(bitIndex))
        if bitIndex < 64 {
            low = UInt64(1) << UInt64(bitIndex)
            high = 0
        } else {
            low = 0
            high = UInt64(1) << UInt64(bitIndex - 64)
        }
    }

    var isEmpty: Bool {
        low == 0 && high == 0
    }

    func intersects(_ other: Self) -> Bool {
        (low & other.low) != 0 || (high & other.high) != 0
    }

    func union(_ other: Self) -> Self {
        Self(low: low | other.low, high: high | other.high)
    }

    mutating func formUnion(_ other: Self) {
        low |= other.low
        high |= other.high
    }
}

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

enum JapaneseDeinflectionRules {
    private static let loaded: Result<CompiledDeinflectionRules, Error> = Result {
        guard let url = Bundle.module.url(
            forResource: "JapaneseDeinflectionRules",
            withExtension: "json"
        ) else {
            throw DeinflectionRuleError.missingResource
        }
        do {
            let file = try JSONDecoder().decode(
                DeinflectionRuleFile.self,
                from: Data(contentsOf: url)
            )
            return try CompiledDeinflectionRules(file: file)
        } catch let error as DeinflectionRuleError {
            throw error
        } catch {
            throw DeinflectionRuleError.decodingFailed(String(describing: error))
        }
    }

    static func load() throws -> CompiledDeinflectionRules {
        try loaded.get()
    }
}

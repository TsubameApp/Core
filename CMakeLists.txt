cmake_minimum_required(VERSION 3.29)

project(TsubameCore LANGUAGES C Swift)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(SQLite3 REQUIRED)

# ---------------------------------------------------------------------------
# CMiniz
# ---------------------------------------------------------------------------

add_library(TsubameCMiniz STATIC
    Sources/ThirdParty/CMiniz/miniz.c
)

target_include_directories(TsubameCMiniz
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ThirdParty/CMiniz/include"
)

target_compile_definitions(TsubameCMiniz
    PRIVATE
        MINIZ_NO_DEFLATE_APIS
        MINIZ_NO_ZLIB_APIS
        MINIZ_NO_ZLIB_COMPATIBLE_NAMES
)

# ---------------------------------------------------------------------------
# CTsubameZIP
# ---------------------------------------------------------------------------

add_library(TsubameZIP STATIC
    Sources/Interop/CTsubameZIP/tsubame_zip.c
)

target_include_directories(TsubameZIP
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/Interop/CTsubameZIP/include"

    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ThirdParty/CMiniz/include"
)

target_link_libraries(TsubameZIP
    PRIVATE
        TsubameCMiniz
)

# ---------------------------------------------------------------------------
# Swift C module map
#
# Swift imports these as:
#
#   import CTsubameZIP
#   import CSQLiteSystem
#
# SwiftPM normally generates/provides the necessary Clang-module plumbing.
# CMake needs to provide it explicitly.
# ---------------------------------------------------------------------------

set(
    TSUBAME_GENERATED_DIR
    "${CMAKE_CURRENT_BINARY_DIR}/generated"
)

file(MAKE_DIRECTORY "${TSUBAME_GENERATED_DIR}")

set(
    TSUBAME_C_MODULE_MAP
    "${TSUBAME_GENERATED_DIR}/TsubameCModules.modulemap"
)

set(
    TSUBAME_ZIP_HEADER
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/Interop/CTsubameZIP/include/tsubame_zip.h"
)

set(
    TSUBAME_SQLITE_HEADER
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ThirdParty/CSQLiteSystem/sqlite3_shim.h"
)

file(
    WRITE
    "${TSUBAME_C_MODULE_MAP}"
"module CTsubameZIP {
    header \"${TSUBAME_ZIP_HEADER}\"
    export *
}

module CSQLiteSystem [system] {
    header \"${TSUBAME_SQLITE_HEADER}\"
    link \"sqlite3\"
    export *
}
"
)

# ---------------------------------------------------------------------------
# Japanese deinflection rules resource
#
# SwiftPM provides Bundle.module automatically. CMake does not.
#
# Rather than introducing runtime resource-path assumptions, embed the JSON
# into a generated Swift source for the CMake build.
# ---------------------------------------------------------------------------

set(
    TSUBAME_DEINFLECTION_RULES_JSON
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/TsubameCore/Resources/JapaneseDeinflectionRules.json"
)

file(
    READ
    "${TSUBAME_DEINFLECTION_RULES_JSON}"
    TSUBAME_DEINFLECTION_RULES_CONTENT
)

set(
    TSUBAME_DEINFLECTION_RULES_SWIFT
    "${TSUBAME_GENERATED_DIR}/JapaneseDeinflectionRules.swift"
)

file(
    WRITE
    "${TSUBAME_DEINFLECTION_RULES_SWIFT}"
"import Foundation

private let tsubameJapaneseDeinflectionRulesJSON = ################\"\"\"
${TSUBAME_DEINFLECTION_RULES_CONTENT}
\"\"\"################

enum JapaneseDeinflectionRules {
    private static let loaded: Result<CompiledDeinflectionRules, Error> = Result {
        do {
            let data = Data(tsubameJapaneseDeinflectionRulesJSON.utf8)

            let file = try JSONDecoder().decode(
                DeinflectionRuleFile.self,
                from: data
            )

            return try CompiledDeinflectionRules(file: file)
        } catch let error as DeinflectionRuleError {
            throw error
        } catch {
            throw DeinflectionRuleError.decodingFailed(
                String(describing: error)
            )
        }
    }

    static func load() throws -> CompiledDeinflectionRules {
        try loaded.get()
    }
}
"
)

# ---------------------------------------------------------------------------
# TsubameCore Swift sources
# ---------------------------------------------------------------------------

file(
    GLOB_RECURSE
    TSUBAME_CORE_SWIFT_SOURCES
    CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/TsubameCore/*.swift"
)

# Linux talks to Core through the native Swift API.
# The C ABI implementation is a separate boundary and is not part of this
# target.
list(
    FILTER
    TSUBAME_CORE_SWIFT_SOURCES
    EXCLUDE
    REGEX "/ABI/"
)

# SwiftPM implementation uses Bundle.module. Replace only this source with
# the generated embedded-resource implementation above.
list(
    FILTER
    TSUBAME_CORE_SWIFT_SOURCES
    EXCLUDE
    REGEX "/Lookup/Deinflection/JapaneseDeinflectionRules\\.swift$"
)

list(
    APPEND
    TSUBAME_CORE_SWIFT_SOURCES
    "${TSUBAME_DEINFLECTION_RULES_SWIFT}"
)

# ---------------------------------------------------------------------------
# TsubameCore
# ---------------------------------------------------------------------------

add_library(
    TsubameCore
    STATIC
    ${TSUBAME_CORE_SWIFT_SOURCES}
)

add_library(
    Tsubame::Core
    ALIAS
    TsubameCore
)

set_target_properties(
    TsubameCore
    PROPERTIES
        Swift_MODULE_NAME TsubameCore
        Swift_LANGUAGE_VERSION 6
)

# Let Swift's Clang importer see CTsubameZIP and CSQLiteSystem.
target_compile_options(
    TsubameCore
    PUBLIC
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${TSUBAME_C_MODULE_MAP}>"
)

# FindSQLite3 used SQLite::SQLite3 before CMake 4.3 and SQLite3::SQLite3
# starting with CMake 4.3.
if(TARGET SQLite3::SQLite3)
    set(TSUBAME_SQLITE_TARGET SQLite3::SQLite3)
else()
    set(TSUBAME_SQLITE_TARGET SQLite::SQLite3)
endif()

target_link_libraries(
    TsubameCore
    PUBLIC
        TsubameZIP
        ${TSUBAME_SQLITE_TARGET}
)

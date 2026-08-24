import Foundation

enum TsubameABIConstants {
    static let version: UInt32 = 1
    static let payloadSchemaVersion: UInt32 = 1
    static let jsonSerialization: UInt32 = 1
    static let maximumPathByteCount: UInt = 65_536
    static let maximumRequestByteCount: UInt = 1_048_576
    static let maximumResultByteCount = 67_108_864
}

enum TsubameABIStatus: Int32 {
    case ok = 0
    case invalidArgument = 1
    case invalidUTF8 = 2
    case invalidJSON = 3
    case unsupported = 4
    case invalidRequest = 5
    case engineOpenFailed = 6
    case executionFailed = 7
    case resultTooLarge = 8
    case internalError = 255
}

enum TsubameABIError: Error, Equatable {
    case invalidArgument(code: String, message: String)
    case invalidUTF8(code: String, message: String)
    case invalidJSON(code: String, message: String)
    case unsupported(code: String, message: String)
    case invalidRequest(code: String, message: String)
    case engineOpenFailed(code: String, message: String)
    case executionFailed(code: String, message: String)
    case resultTooLarge(code: String, message: String)
    case internalError(code: String, message: String)

    var status: TsubameABIStatus {
        switch self {
        case .invalidArgument: .invalidArgument
        case .invalidUTF8: .invalidUTF8
        case .invalidJSON: .invalidJSON
        case .unsupported: .unsupported
        case .invalidRequest: .invalidRequest
        case .engineOpenFailed: .engineOpenFailed
        case .executionFailed: .executionFailed
        case .resultTooLarge: .resultTooLarge
        case .internalError: .internalError
        }
    }

    var code: String {
        switch self {
        case .invalidArgument(let code, _),
             .invalidUTF8(let code, _),
             .invalidJSON(let code, _),
             .unsupported(let code, _),
             .invalidRequest(let code, _),
             .engineOpenFailed(let code, _),
             .executionFailed(let code, _),
             .resultTooLarge(let code, _),
             .internalError(let code, _):
            code
        }
    }

    var message: String {
        switch self {
        case .invalidArgument(_, let message),
             .invalidUTF8(_, let message),
             .invalidJSON(_, let message),
             .unsupported(_, let message),
             .invalidRequest(_, let message),
             .engineOpenFailed(_, let message),
             .executionFailed(_, let message),
             .resultTooLarge(_, let message),
             .internalError(_, let message):
            message
        }
    }
}

private final class TsubameABIEngine {
    private let lock = NSLock()
    private let lookup: DictionaryLookup

    init(databaseURL: URL) throws {
        lookup = DictionaryLookup(store: try SQLiteDictionaryStore(databaseURL: databaseURL))
    }

    func execute(_ request: TsubameABIV1Request) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let data: Data
        switch request {
        case .positioned(let dto):
            let coreRequest: PositionedLookupRequest
            do {
                coreRequest = try PositionedLookupRequest(
                    text: dto.text,
                    position: dto.position,
                    resultLimit: dto.resultLimit
                )
            } catch {
                throw TsubameABIError.invalidRequest(
                    code: "invalid_positioned_lookup",
                    message: error.localizedDescription
                )
            }
            do {
                let result = try lookup.lookup(coreRequest)
                data = try encoder.encode(
                    TsubameABIV1PositionedResponse(
                        result: try TsubameABILookupResultDTO(result)
                    )
                )
            } catch let error as TsubameABIError {
                throw error
            } catch {
                throw TsubameABIError.executionFailed(
                    code: "lookup_failed",
                    message: "Positioned lookup failed."
                )
            }

        case .rangeScan(let dto):
            let coreRequest: ScanLookupRequest
            do {
                coreRequest = try ScanLookupRequest(
                    text: dto.text,
                    range: UTF8TextRange(start: dto.range.start, end: dto.range.end),
                    resultGroupLimit: dto.resultGroupLimit,
                    entriesPerGroupLimit: dto.entriesPerGroupLimit
                )
            } catch {
                throw TsubameABIError.invalidRequest(
                    code: "invalid_range_scan",
                    message: error.localizedDescription
                )
            }
            do {
                let results = try lookup.scan(coreRequest)
                data = try encoder.encode(
                    TsubameABIV1RangeScanResponse(
                        results: try results.map(TsubameABILookupResultDTO.init)
                    )
                )
            } catch let error as TsubameABIError {
                throw error
            } catch {
                throw TsubameABIError.executionFailed(
                    code: "range_scan_failed",
                    message: "Dictionary range scan failed."
                )
            }
        }

        guard data.count <= TsubameABIConstants.maximumResultByteCount else {
            throw TsubameABIError.resultTooLarge(
                code: "result_too_large",
                message: "Serialized result exceeds the ABI v1 size limit."
            )
        }
        return data
    }
}

@c(tsubame_swift_abi_version)
public func tsubameSwiftABIVersion() -> UInt32 {
    TsubameABIConstants.version
}

@c(tsubame_swift_engine_create)
public func tsubameSwiftEngineCreate(
    _ databasePath: UnsafePointer<UInt8>?,
    _ databasePathLength: UInt,
    _ outEngine: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ outErrorData: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ outErrorLength: UnsafeMutablePointer<UInt>?
) -> Int32 {
    outEngine?.pointee = nil
    clearBuffer(data: outErrorData, length: outErrorLength)

    guard let outEngine, outErrorData != nil, outErrorLength != nil else {
        return TsubameABIStatus.invalidArgument.rawValue
    }

    do {
        let pathData = try copyInput(
            databasePath,
            length: databasePathLength,
            maximumLength: TsubameABIConstants.maximumPathByteCount,
            name: "database path"
        )
        guard !pathData.isEmpty else {
            throw TsubameABIError.invalidArgument(
                code: "empty_database_path",
                message: "Dictionary database path must not be empty."
            )
        }
        guard let path = String(data: pathData, encoding: .utf8) else {
            throw TsubameABIError.invalidUTF8(
                code: "invalid_database_path_utf8",
                message: "Dictionary database path is not valid UTF-8."
            )
        }
        guard !path.contains("\0") else {
            throw TsubameABIError.invalidArgument(
                code: "invalid_database_path",
                message: "Dictionary database path contains a null byte."
            )
        }
        guard (path as NSString).isAbsolutePath else {
            throw TsubameABIError.invalidArgument(
                code: "relative_database_path",
                message: "Dictionary database path must be absolute."
            )
        }

        let engine: TsubameABIEngine
        do {
            engine = try TsubameABIEngine(
                databaseURL: URL(fileURLWithPath: path, isDirectory: false)
            )
        } catch {
            throw TsubameABIError.engineOpenFailed(
                code: "engine_open_failed",
                message: "Dictionary database could not be opened."
            )
        }
        outEngine.pointee = Unmanaged.passRetained(engine).toOpaque()
        return TsubameABIStatus.ok.rawValue
    } catch let error as TsubameABIError {
        writeError(error, data: outErrorData, length: outErrorLength)
        return error.status.rawValue
    } catch {
        let abiError = TsubameABIError.internalError(
            code: "internal_error",
            message: "TsubameCore encountered an internal error."
        )
        writeError(abiError, data: outErrorData, length: outErrorLength)
        return abiError.status.rawValue
    }
}

@c(tsubame_swift_engine_destroy)
public func tsubameSwiftEngineDestroy(_ engine: UnsafeMutableRawPointer?) {
    guard let engine else { return }
    Unmanaged<TsubameABIEngine>.fromOpaque(engine).release()
}

@c(tsubame_swift_engine_execute)
public func tsubameSwiftEngineExecute(
    _ engine: UnsafeMutableRawPointer?,
    _ serialization: UInt32,
    _ request: UnsafePointer<UInt8>?,
    _ requestLength: UInt,
    _ outResultData: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ outResultLength: UnsafeMutablePointer<UInt>?,
    _ outErrorData: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ outErrorLength: UnsafeMutablePointer<UInt>?
) -> Int32 {
    clearBuffer(data: outResultData, length: outResultLength)
    clearBuffer(data: outErrorData, length: outErrorLength)

    guard let engine,
          outResultData != nil,
          outResultLength != nil,
          outErrorData != nil,
          outErrorLength != nil else {
        return TsubameABIStatus.invalidArgument.rawValue
    }

    do {
        guard serialization == TsubameABIConstants.jsonSerialization else {
            throw TsubameABIError.unsupported(
                code: "unsupported_serialization",
                message: "Requested serialization format is unsupported."
            )
        }
        let requestData = try copyInput(
            request,
            length: requestLength,
            maximumLength: TsubameABIConstants.maximumRequestByteCount,
            name: "request"
        )
        let decoded = try TsubameABIV1RequestDecoder.decode(requestData)
        let abiEngine = Unmanaged<TsubameABIEngine>.fromOpaque(engine).takeUnretainedValue()
        let result = try abiEngine.execute(decoded)
        writeBuffer(result, data: outResultData, length: outResultLength)
        return TsubameABIStatus.ok.rawValue
    } catch let error as TsubameABIError {
        writeError(error, data: outErrorData, length: outErrorLength)
        return error.status.rawValue
    } catch {
        let abiError = TsubameABIError.internalError(
            code: "internal_error",
            message: "TsubameCore encountered an internal error."
        )
        writeError(abiError, data: outErrorData, length: outErrorLength)
        return abiError.status.rawValue
    }
}

@c(tsubame_swift_buffer_free)
public func tsubameSwiftBufferFree(_ data: UnsafeMutablePointer<UInt8>?) {
    data?.deallocate()
}

private func copyInput(
    _ pointer: UnsafePointer<UInt8>?,
    length: UInt,
    maximumLength: UInt,
    name: String
) throws -> Data {
    guard length <= maximumLength else {
        throw TsubameABIError.invalidArgument(
            code: "input_too_large",
            message: "ABI \(name) exceeds its size limit."
        )
    }
    guard let count = Int(exactly: length) else {
        throw TsubameABIError.invalidArgument(
            code: "length_overflow",
            message: "ABI \(name) length cannot be represented by TsubameCore."
        )
    }
    guard count > 0 else { return Data() }
    guard let pointer else {
        throw TsubameABIError.invalidArgument(
            code: "null_input",
            message: "ABI \(name) pointer is null while its length is nonzero."
        )
    }
    return Data(bytes: pointer, count: count)
}

private func clearBuffer(
    data: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    length: UnsafeMutablePointer<UInt>?
) {
    data?.pointee = nil
    length?.pointee = 0
}

private func writeBuffer(
    _ bytes: Data,
    data: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    length: UnsafeMutablePointer<UInt>?
) {
    guard let data, let length else { return }
    guard !bytes.isEmpty else {
        clearBuffer(data: data, length: length)
        return
    }
    let allocation = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
    bytes.copyBytes(to: allocation, count: bytes.count)
    data.pointee = allocation
    length.pointee = UInt(bytes.count)
}

private func writeError(
    _ error: TsubameABIError,
    data: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    length: UnsafeMutablePointer<UInt>?
) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let encoded = try? encoder.encode(
        TsubameABIErrorDTO(
            status: error.status.rawValue,
            code: error.code,
            message: error.message
        )
    ) else {
        clearBuffer(data: data, length: length)
        return
    }
    writeBuffer(encoded, data: data, length: length)
}

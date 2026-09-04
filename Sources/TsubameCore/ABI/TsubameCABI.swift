import CTsubameABITypes
import Foundation

struct TsubameABIFailure: Error {
    let status: Int32
    let code: String
    let message: String
}

private final class ABIEngine {
    private let lock = NSLock()
    private let lookup: DictionaryLookup

    init(path: String) throws {
        lookup = DictionaryLookup(
            store: try SQLiteDictionaryStore(databaseURL: URL(fileURLWithPath: path))
        )
    }

    func read<T>(_ body: (DictionaryLookup) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(lookup)
    }
}

@c(tsubame_swift_abi_version)
public func tsubameSwiftABIVersion() -> UInt32 { 1 }

@c(tsubame_swift_engine_create)
public func tsubameSwiftEngineCreate(
    _ path: UnsafePointer<UInt8>?, _ length: UInt,
    _ outEngine: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ outError: UnsafeMutablePointer<TsubameError>?
) -> Int32 {
    outEngine?.pointee = nil
    return abiCall(outError) {
        guard let outEngine else { throw invalidArgument("null_output") }
        let path = try readText(path, length: length, maximum: 65_536)
        guard !path.isEmpty, !path.contains("\0"), (path as NSString).isAbsolutePath else {
            throw invalidArgument("invalid_database_path")
        }
        let engine: ABIEngine
        do { engine = try ABIEngine(path: path) }
        catch {
            throw TsubameABIFailure(
                status: Int32(TSUBAME_STATUS_ENGINE_OPEN_FAILED),
                code: "engine_open_failed", message: "Dictionary database could not be opened."
            )
        }
        outEngine.pointee = Unmanaged.passRetained(engine).toOpaque()
    }
}

@c(tsubame_swift_engine_destroy)
public func tsubameSwiftEngineDestroy(_ engine: UnsafeMutableRawPointer?) {
    guard let engine else { return }
    Unmanaged<ABIEngine>.fromOpaque(engine).release()
}

@c(tsubame_swift_lookup)
public func tsubameSwiftLookup(
    _ engine: UnsafeMutableRawPointer?,
    _ text: UnsafePointer<UInt8>?, _ length: UInt,
    _ position: UInt, _ limit: UInt,
    _ outResult: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ outError: UnsafeMutablePointer<TsubameError>?
) -> Int32 {
    outResult?.pointee = nil
    return abiCall(outError) {
        guard let engine, let outResult else { throw invalidArgument("null_argument") }
        let request = try PositionedLookupRequest(
            text: readText(text, length: length, maximum: LookupRequestLimits.maximumTextUTF8Length),
            position: checkedInt(position), resultLimit: checkedInt(limit)
        )
        let owner = Unmanaged<ABIEngine>.fromOpaque(engine).takeUnretainedValue()
        let group = try owner.read { try $0.lookup(request) }
        let result = TsubameABIResult(groups: [group])
        outResult.pointee = Unmanaged.passRetained(result).toOpaque()
    }
}

@c(tsubame_swift_scan)
public func tsubameSwiftScan(
    _ engine: UnsafeMutableRawPointer?,
    _ text: UnsafePointer<UInt8>?, _ length: UInt,
    _ start: UInt, _ end: UInt, _ groupLimit: UInt, _ entriesLimit: UInt,
    _ outResult: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ outError: UnsafeMutablePointer<TsubameError>?
) -> Int32 {
    outResult?.pointee = nil
    return abiCall(outError) {
        guard let engine, let outResult else { throw invalidArgument("null_argument") }
        let request = try ScanLookupRequest(
            text: readText(text, length: length, maximum: LookupRequestLimits.maximumTextUTF8Length),
            range: UTF8TextRange(start: checkedInt(start), end: checkedInt(end)),
            resultGroupLimit: checkedInt(groupLimit),
            entriesPerGroupLimit: checkedInt(entriesLimit)
        )
        let owner = Unmanaged<ABIEngine>.fromOpaque(engine).takeUnretainedValue()
        let groups = try owner.read { try $0.scan(request) }
        let result = TsubameABIResult(groups: groups)
        outResult.pointee = Unmanaged.passRetained(result).toOpaque()
    }
}

@c(tsubame_swift_result_get_view)
public func tsubameSwiftResultGetView(
    _ result: UnsafeRawPointer?, _ outView: UnsafeMutablePointer<TsubameResultView>?
) -> Int32 {
    outView?.pointee = TsubameResultView()
    guard let result, let outView else { return Int32(TSUBAME_STATUS_INVALID_ARGUMENT) }
    outView.pointee = Unmanaged<TsubameABIResult>.fromOpaque(result).takeUnretainedValue().view
    return Int32(TSUBAME_STATUS_OK)
}

@c(tsubame_swift_result_destroy)
public func tsubameSwiftResultDestroy(_ result: UnsafeMutableRawPointer?) {
    guard let result else { return }
    Unmanaged<TsubameABIResult>.fromOpaque(result).release()
}

@c(tsubame_swift_content_get)
public func tsubameSwiftContentGet(
    _ content: UnsafeRawPointer?,
    _ outValue: UnsafeMutablePointer<UnsafePointer<TsubameValue>?>?,
    _ outError: UnsafeMutablePointer<TsubameError>?
) -> Int32 {
    outValue?.pointee = nil
    return abiCall(outError) {
        guard let content, let outValue else { throw invalidArgument("null_argument") }
        let owner = Unmanaged<TsubameABIContent>.fromOpaque(content).takeUnretainedValue()
        outValue.pointee = try owner.get()
    }
}

@c(tsubame_swift_error_free)
public func tsubameSwiftErrorFree(_ error: UnsafeMutablePointer<TsubameError>?) {
    guard let error else { return }
    error.pointee.code.data?.deallocate()
    error.pointee.message.data?.deallocate()
    error.pointee = TsubameError()
}

private func abiCall(
    _ outError: UnsafeMutablePointer<TsubameError>?,
    body: () throws -> Void
) -> Int32 {
    guard let outError else { return Int32(TSUBAME_STATUS_INVALID_ARGUMENT) }
    outError.pointee = TsubameError()
    do {
        try body()
        return Int32(TSUBAME_STATUS_OK)
    } catch {
        let failure: TsubameABIFailure
        if let value = error as? TsubameABIFailure {
            failure = value
        } else if let value = error as? LookupRequestError {
            failure = TsubameABIFailure(
                status: Int32(TSUBAME_STATUS_INVALID_REQUEST),
                code: "invalid_request", message: value.localizedDescription
            )
        } else {
            failure = TsubameABIFailure(
                status: Int32(TSUBAME_STATUS_EXECUTION_FAILED),
                code: "execution_failed", message: "Dictionary operation failed."
            )
        }
        outError.pointee = TsubameError(
            status: failure.status,
            code: TsubameABIMemory.copyString(failure.code),
            message: TsubameABIMemory.copyString(failure.message)
        )
        return failure.status
    }
}

private func checkedInt(_ value: UInt) throws -> Int {
    guard let value = Int(exactly: value) else { throw invalidArgument("integer_overflow") }
    return value
}

private func readText(
    _ bytes: UnsafePointer<UInt8>?, length: UInt, maximum: Int
) throws -> String {
    guard length <= UInt(maximum) else { throw invalidArgument("input_too_large") }
    guard length != 0 else { return "" }
    guard let bytes else { throw invalidArgument("null_input") }
    guard let text = String(
        bytes: UnsafeBufferPointer(start: bytes, count: Int(length)), encoding: .utf8
    ) else {
        throw TsubameABIFailure(
            status: Int32(TSUBAME_STATUS_INVALID_UTF8),
            code: "invalid_utf8", message: "Input is not valid UTF-8."
        )
    }
    return text
}

private func invalidArgument(_ code: String) -> TsubameABIFailure {
    TsubameABIFailure(
        status: Int32(TSUBAME_STATUS_INVALID_ARGUMENT),
        code: code, message: "Invalid C API argument."
    )
}

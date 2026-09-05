import Foundation

public struct DictionaryImageReference: Sendable, Equatable {
    public let path: DictionaryResourcePath
    public let title: String
    public let width: Double?
    public let height: Double?
    public let sizeUnits: String
    public let collapsed: Bool
    public let collapsible: Bool
    public let pixelated: Bool
    public let monochrome: Bool
    public let background: Bool
}

/// A presentation-neutral, bounded projection of Yomitan structured content.
public indirect enum GlossaryNode: Sendable, Equatable {
    case text(String)
    case lineBreak
    case image(DictionaryImageReference)
    case element(GlossaryElement)

    public var plainText: String {
        switch self {
        case .text(let text): return text
        case .lineBreak: return "\n"
        case .image(let image): return image.title
        case .element(let element):
            let separator = ["div", "ol", "ul", "li", "table", "tr"].contains(element.tag) ? "\n" : ""
            return element.children.map(\.plainText).joined(separator: separator)
        }
    }

    public var images: [DictionaryImageReference] {
        switch self {
        case .image(let image): return [image]
        case .element(let element): return element.children.flatMap(\.images)
        default: return []
        }
    }
}

public struct GlossaryElement: Sendable, Equatable {
    public let tag: String
    public let children: [GlossaryNode]
    public let style: GlossaryStyle
    public let title: String
    public let language: String?
    public let isOpen: Bool
    public let columnSpan: Int
    public let rowSpan: Int
}

public struct GlossaryStyle: Sendable, Equatable {
    public let bold: Bool
    public let italic: Bool
    public let underline: Bool
    public let strikethrough: Bool
    public let color: String?
    public let backgroundColor: String?
    public let alignment: String?
}

public enum GlossaryDecodingError: Error, LocalizedError, Sendable {
    case limitExceeded
    case invalidImage
    public var errorDescription: String? {
        switch self {
        case .limitExceeded: "Dictionary glossary exceeds safe size or nesting limits."
        case .invalidImage: "Dictionary glossary contains an invalid image reference."
        }
    }
}

public struct DictionaryGlossaryDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> [GlossaryNode] {
        guard data.count <= 4 * 1_024 * 1_024 else { throw GlossaryDecodingError.limitExceeded }
        // Preflight before recursive decoding: JSONDecoder's own nesting limit is too
        // generous for a UI tree. Ignore braces inside escaped JSON strings.
        var depth = 0
        var quoted = false
        var escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 {
                depth += 1
                guard depth <= 64 else { throw GlossaryDecodingError.limitExceeded }
            } else if byte == 125 || byte == 93 { depth -= 1 }
        }
        let value = try JSONDecoder().decode(YomitanJSONValue.self, from: data)
        var remaining = 16_384
        return try nodes(value, depth: 0, remaining: &remaining)
    }

    private func nodes(_ value: YomitanJSONValue, depth: Int, remaining: inout Int) throws -> [GlossaryNode] {
        remaining -= 1
        guard depth <= 32, remaining >= 0 else { throw GlossaryDecodingError.limitExceeded }
        switch value {
        case .string(let text): return [.text(text)]
        case .array(let values):
            return try values.flatMap { try nodes($0, depth: depth + 1, remaining: &remaining) }
        case .object(let object):
            let tag = object["tag"]?.stringValue ?? object["type"]?.stringValue ?? "unknown"
            if tag == "image" || tag == "img" {
                guard let path = object["path"]?.stringValue else { throw GlossaryDecodingError.invalidImage }
                func dimension(_ key: String) throws -> Double? {
                    guard let value = object[key] else { return nil }
                    guard let number = value.doubleValue, number.isFinite, number >= 0, number <= 65_536 else {
                        throw GlossaryDecodingError.invalidImage
                    }
                    return number > 0 ? number : nil
                }
                let rendering = object["imageRendering"]?.stringValue
                return [.image(try DictionaryImageReference(
                    path: DictionaryResourcePath(path),
                    title: object["alt"]?.stringValue ?? object["description"]?.stringValue ?? object["title"]?.stringValue ?? "",
                    width: dimension("width"), height: dimension("height"),
                    sizeUnits: object["sizeUnits"]?.stringValue == "em" ? "em" : "px",
                    collapsed: object["collapsed"]?.boolValue ?? false,
                    collapsible: object["collapsible"]?.boolValue ?? false,
                    pixelated: rendering.map { $0 == "pixelated" || $0 == "crisp-edges" } ?? (object["pixelated"]?.boolValue ?? false),
                    monochrome: object["appearance"]?.stringValue == "monochrome",
                    background: object["background"]?.boolValue ?? true
                ))]
            }
            if tag == "br" { return [.lineBreak] }
            let children = try nodes(object["content"] ?? .string(object["text"]?.stringValue ?? ""), depth: depth + 1, remaining: &remaining)
            if tag == "structured-content" || tag == "text" { return children }
            let style = object["style"]?.objectValue ?? [:]
            let decorations = style["textDecorationLine"].map { value in
                value.stringValue.map { [$0] } ?? value.arrayValue?.compactMap(\.stringValue) ?? []
            } ?? []
            return [.element(GlossaryElement(
                tag: tag, children: children,
                style: GlossaryStyle(
                    bold: style["fontWeight"]?.stringValue == "bold" || ["b", "strong", "th"].contains(tag),
                    italic: style["fontStyle"]?.stringValue == "italic" || ["i", "em"].contains(tag),
                    underline: decorations.contains("underline"), strikethrough: decorations.contains("line-through"),
                    color: style["color"]?.stringValue, backgroundColor: style["backgroundColor"]?.stringValue,
                    alignment: style["textAlign"]?.stringValue
                ), title: object["title"]?.stringValue ?? "", language: object["lang"]?.stringValue,
                isOpen: object["open"]?.boolValue ?? false,
                columnSpan: Int(min(32, max(1, object["colSpan"]?.doubleValue ?? 1))),
                rowSpan: Int(min(32, max(1, object["rowSpan"]?.doubleValue ?? 1)))
            ))]
        default: return []
        }
    }
}

extension YomitanJSONValue {
    var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    var boolValue: Bool? { if case .boolean(let value) = self { value } else { nil } }
    var doubleValue: Double? {
        switch self { case .integer(let value): Double(value); case .number(let value): value; default: nil }
    }
    var objectValue: [String: Self]? { if case .object(let value) = self { value } else { nil } }
    var arrayValue: [Self]? { if case .array(let value) = self { value } else { nil } }
}

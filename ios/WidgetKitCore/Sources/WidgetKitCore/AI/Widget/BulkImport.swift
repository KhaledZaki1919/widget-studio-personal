import Compression
import Foundation

/// Many designs at once (ADR-027): files, a .zip, a folder, a JSON array or several objects pasted
/// together. Each one goes through the same pipeline as a single import (`ExternalAI`: fences,
/// validation, layout fix, auto-wire), and valid ones are saved straight to My widgets.
public enum BulkImport {
    public static let maxFiles = 200
    /// Uncompressed, over everything in one import.
    public static let maxTotalBytes = 20_000_000

    /// One candidate design: where it came from, and its text.
    public struct Source: Sendable, Equatable {
        public let name: String
        public let text: String

        public init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    public struct Failure: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let error: ExternalAI.ImportError

        public init(name: String, error: ExternalAI.ImportError) {
            self.name = name
            self.error = error
        }
    }

    public struct Added: Sendable, Equatable, Identifiable {
        public var id: String { design.id }
        public let design: SavedDesign
        /// The layout was repaired or the post-pass wired something.
        public let fixed: Bool
        public let needsEditing: Bool
    }

    public struct Summary: Sendable, Equatable {
        public var added: [Added] = []
        public var failed: [Failure] = []
        /// Identical to a design already saved.
        public var duplicates: [String] = []

        public init() {}

        public var fixedCount: Int { added.filter(\.fixed).count }
    }

    public enum ZipError: Error, Equatable, Sendable {
        case notAZip, tooManyFiles, tooLarge, encrypted
    }

    // MARK: Splitting text

    /// The designs in one text: a single object, a JSON array, several objects in a row, or an
    /// object that wraps a list (`{"widgets": […]}`). Text around them and code fences are ignored.
    public static func split(_ text: String) -> [String] {
        let objects = topLevelObjects(text)
        guard objects.count == 1, let only = objects.first else { return objects.isEmpty ? [text] : objects }
        if let data = only.data(using: .utf8), case .object(let root)? = try? JSONDecoder().decode(JSONValue.self, from: data), root["layers"] == nil {
            for value in root.values {
                if case .array(let items) = value, !items.isEmpty {
                    // ADR-029: each widget keeps the reply's specVersion.
                    let nested = items.compactMap { item -> String? in
                        guard case .object(var widget) = item else { return nil }
                        if widget["specVersion"] == nil, let version = root["specVersion"] { widget["specVersion"] = version }
                        return JSONValue.object(widget).jsonString()
                    }
                    if !nested.isEmpty { return nested }
                }
            }
        }
        return objects
    }

    /// Every `{…}` that isn't inside another one, respecting strings and escapes.
    static func topLevelObjects(_ text: String) -> [String] {
        var objects: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var start: String.UnicodeScalarView.Index?
        let scalars = text.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if inString {
                if escaped { escaped = false } else if scalar == "\\" { escaped = true } else if scalar == "\"" { inString = false }
            } else if depth > 0, scalar == "\"" {
                inString = true
            } else if scalar == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if scalar == "}", depth > 0 {
                depth -= 1
                if depth == 0, let begin = start {
                    objects.append(String(scalars[begin...index]))
                }
            }
            index = scalars.index(after: index)
        }
        return objects
    }

    // MARK: Files

    /// The `Source`s in one file's bytes: a zip by its signature, anything else as text.
    public static func sources(data: Data, name: String) throws -> [Source] {
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || data.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            return try zipEntries(data).flatMap { entry in sources(text: entry.text, name: entry.name) }
        }
        return sources(text: decoded(data), name: name)
    }

    public static func sources(text: String, name: String) -> [Source] {
        let parts = split(text)
        return parts.enumerated().map { index, part in
            Source(name: parts.count > 1 ? "\(name) #\(index + 1)" : name, text: part)
        }
    }

    /// Text in UTF-8 (with or without a BOM), or UTF-16 with a BOM.
    static func decoded(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) ?? "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Everything importable at `urls`: files, zips and folders (nested too), with limits.
    public static func load(urls: [URL]) -> (sources: [Source], failed: [Failure]) {
        var sources: [Source] = []
        var failed: [Failure] = []
        var total = 0

        func read(_ url: URL, name: String) {
            guard sources.count < maxFiles else { return }
            guard let data = try? Data(contentsOf: url) else {
                failed.append(Failure(name: name, error: .unreadable))
                return
            }
            total += data.count
            if total > maxTotalBytes {
                failed.append(Failure(name: name, error: .tooLarge))
                return
            }
            do {
                sources += try Self.sources(data: data, name: name)
            } catch let error as ExternalAI.ImportError {
                failed.append(Failure(name: name, error: error))
            } catch ZipError.tooLarge, ZipError.tooManyFiles {
                failed.append(Failure(name: name, error: .tooLarge))
            } catch {
                failed.append(Failure(name: name, error: .invalid("this zip can't be read: \(error)")))
            }
        }

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
            if isFolder.boolValue {
                let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let file = walker?.nextObject() as? URL {
                    guard ["json", "zip"].contains(file.pathExtension.lowercased()) else { continue }
                    read(file, name: file.path.replacingOccurrences(of: url.path + "/", with: ""))
                }
            } else {
                read(url, name: url.lastPathComponent)
            }
        }
        if sources.count > maxFiles { sources = Array(sources.prefix(maxFiles)) }
        return (sources, failed)
    }

    // MARK: Zip

    /// A safe name inside a zip: relative, no `..`, no backslashes or drive letters.
    public static func isSafe(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":") else { return false }
        return !name.split(separator: "/").contains("..")
    }

    /// The `.json` files in a zip, nested folders too. Other files are ignored; a name that tries to
    /// leave the archive fails the whole zip, and so do the limits.
    public static func zipEntries(_ data: Data) throws -> [Source] {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        // End of central directory: searched backward, past an optional comment.
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        var end = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while end >= lowest, !(bytes[end] == 0x50 && bytes[end + 1] == 0x4B && bytes[end + 2] == 0x05 && bytes[end + 3] == 0x06) { end -= 1 }
        guard end >= lowest else { throw ZipError.notAZip }
        let count = u16(end + 10)
        var cursor = u32(end + 16)
        guard count <= maxFiles * 5 else { throw ZipError.tooManyFiles }

        var entries: [Source] = []
        var total = 0
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, u32(cursor) == 0x0201_4B50 else { throw ZipError.notAZip }
            let flags = u16(cursor + 8)
            let method = u16(cursor + 10)
            let compressed = u32(cursor + 20)
            let size = u32(cursor + 24)
            let nameLength = u16(cursor + 28)
            let extra = u16(cursor + 30)
            let comment = u16(cursor + 32)
            let offset = u32(cursor + 42)
            guard cursor + 46 + nameLength <= bytes.count else { throw ZipError.notAZip }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            cursor += 46 + nameLength + extra + comment

            guard isSafe(name) else { throw ExternalAI.ImportError.invalid("unsafe path in the zip: \(name)") }
            let leaf = name.split(separator: "/").last.map(String.init) ?? name
            guard !name.hasSuffix("/"), !name.hasPrefix("__MACOSX/"), !leaf.hasPrefix("."), leaf.lowercased().hasSuffix(".json") else { continue }
            guard entries.count < maxFiles else { throw ZipError.tooManyFiles }
            guard flags & 1 == 0 else { throw ZipError.encrypted }
            total += size
            guard total <= maxTotalBytes, size <= maxTotalBytes else { throw ZipError.tooLarge }
            guard offset + 30 <= bytes.count, u32(offset) == 0x0403_4B50 else { throw ZipError.notAZip }
            let start = offset + 30 + u16(offset + 26) + u16(offset + 28)
            guard start + compressed <= bytes.count else { throw ZipError.notAZip }
            let stored = Array(bytes[start..<(start + compressed)])
            let content: [UInt8]
            switch method {
            case 0: content = stored
            case 8: content = try inflate(stored, size: size)
            default: throw ExternalAI.ImportError.invalid("unsupported compression in \(name)")
            }
            entries.append(Source(name: name, text: decoded(Data(content))))
        }
        return entries
    }

    /// Raw DEFLATE, into exactly the size the archive declares (so a bomb can't grow past it).
    static func inflate(_ input: [UInt8], size: Int) throws -> [UInt8] {
        guard size > 0 else { return [] }
        var output = [UInt8](repeating: 0, count: size)
        let written = input.withUnsafeBufferPointer { source -> Int in
            output.withUnsafeMutableBufferPointer { destination -> Int in
                guard let from = source.baseAddress, let into = destination.baseAddress else { return 0 }
                return compression_decode_buffer(into, size, from, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ExternalAI.ImportError.invalid("a file in the zip is damaged") }
        return output
    }

    // MARK: The pipeline

    /// What makes two designs the same: everything but ids and dates.
    public static func fingerprint(spec: WidgetSpec, colors: [String: String]) -> String {
        var plain = spec
        plain.id = ""
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = (try? encoder.encode(plain)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return body + colors.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// Runs every source through the import pipeline. Duplicates of `existing` (or of an earlier
    /// source) are skipped; a new design with a taken name gets " (2)".
    public static func run(_ sources: [Source], existing: [SavedDesign], language: String, size: SizeChoice = .auto,
                           progress: (Int) -> Void = { _ in }) -> Summary {
        var summary = Summary()
        var seen = Set(existing.map { fingerprint(spec: $0.spec, colors: $0.colors) })
        var names = Set(existing.map(\.name))
        for (index, source) in sources.enumerated() {
            progress(index)
            do {
                let widget = try ExternalAI.importWidget(source.text, size: size)
                guard seen.insert(fingerprint(spec: widget.spec, colors: widget.colors)).inserted else {
                    summary.duplicates.append(source.name)
                    continue
                }
                var design = widget.design(language: language)
                design.name = uniqueName(design.name, taken: names)
                names.insert(design.name)
                var fixed = !widget.autoWired.isEmpty
                if case .fixed = widget.layout { fixed = true }
                summary.added.append(Added(design: design, fixed: fixed, needsEditing: widget.needsEditing))
            } catch let error as ExternalAI.ImportError {
                summary.failed.append(Failure(name: source.name, error: error))
            } catch {
                summary.failed.append(Failure(name: source.name, error: .noJSON))
            }
        }
        progress(sources.count)
        return summary
    }

    static func uniqueName(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        var number = 2
        while taken.contains("\(name) (\(number))") { number += 1 }
        return "\(name) (\(number))"
    }

    /// One message for the AI that wrote the files, naming each failure.
    public static func fixRequest(_ failures: [Failure]) -> String {
        let lines = failures.map { "\($0.name): \(ExternalAI.fixRequest(for: $0.error))" }
        return "Widget Studio could not import these widgets. Fix each one and reply with the corrected JSON objects only, as a JSON array.\n\n"
            + lines.joined(separator: "\n\n")
    }
}

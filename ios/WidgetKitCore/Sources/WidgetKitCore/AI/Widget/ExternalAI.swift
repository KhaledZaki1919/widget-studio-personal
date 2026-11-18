import Foundation

/// "Use another AI" (ADR-023): the user copies self-contained instructions into ChatGPT, Claude or
/// Gemini on the web together with their image, and imports the JSON that comes back. The reply
/// goes through exactly the checks of the app's own AI flow: fences and extra text are stripped,
/// it is validated in AI mode (recreate only: the external AI never sends a photo), and the
/// layout is repaired locally (`AILayoutFix`). It is only ever a widget spec, never code.
public enum ExternalAI {
    /// Larger replies are rejected before parsing (a widget spec is a few KB).
    public static let maxImportBytes = 200_000

    public enum ImportError: Error, Equatable, Sendable {
        case empty
        case tooLarge
        /// No `{ … }` object in the text.
        case noJSON
        /// The JSON failed the checks; the text says what (English, for the fix request).
        case invalid(String)
        /// A picked or shared file couldn't be read.
        case unreadable
    }

    /// Everything the external AI needs, in one paste: our rules (the app's system prompt), the
    /// task for `options`, the JSON Schema of the answer, a short example and the reply rules.
    public static func instructions(options: GenerationOptions, today: Date = .now) -> String {
        var recreate = options
        recreate.mode = .recreate
        var task = WidgetPrompt.userText(options: recreate, imageWidth: 0, imageHeight: 0, today: today)
        if recreate.size.family == nil, let line = task.components(separatedBy: "\n\n").first(where: { $0.hasPrefix("Size: the image is") }) {
            task = task.replacingOccurrences(of: line, with: "Size: pick \"family\" and \"card.aspect\" from the card's shape in the image "
                + "(see Card and canvas).")
        }
        // ADR-029: a readable reference of the schema instead of the 30 000-character JSON Schema on one line,
        // so any chat model (ChatGPT, Claude, Gemini) can follow it.
        let reply = recreate.allWidgets ? "Reply with only the JSON object {\"specVersion\": 2, \"widgets\": [ … ]}, one widget object per widget"
            : "Reply with only the JSON object"
        return [
            "You are designing a home-screen widget for the app Widget Studio (iPhone and Android). The user attached an image of the "
                + "widget they want. Follow every rule below and answer with JSON that the app imports.",
            WidgetPrompt.system,
            "# Task\n\n" + task,
            "# Answer format\n\n\(reply): no explanation before or after it, no code fences, no code of any kind. The structure:\n\n"
                + schemaReference,
            "# Example of the shape (not of the design)\n\n" + example,
        ].joined(separator: "\n\n")
    }

    /// The schema as the copied instructions show it (exported for Android as `schema_reference.md`).
    public static var schemaReference: String { AISchemaReference.text(AIWidgetSchema.schema(mode: .recreate)) }

    /// A small valid answer (texts inside a stack, palette tokens), so the external AI sees the exact shape.
    /// A small valid v2 answer (ADR-029): a card with its ratio, texts in a stack, a run with a raised "AM",
    /// a plain string where both languages agree, palette tokens and a tap action.
    static let example = """
    {"specVersion":2,"inventory":["big dot-matrix time, digits 0.3 of the height, with a small raised AM","weekday under it, accent color"],\
    "wiring":[{"element":"big time","shows":"{{time.hh}}:{{time.mm}}","tap":"clock.open","states":null,"decorative":null},\
    {"element":"weekday","shows":"{{date.EEEE}}","tap":null,"states":null,"decorative":null}],\
    "name":{"en":"Clock","ar":"الساعة"},"family":"small","theme":"dark","card":{"shape":"roundedRect","aspect":1,"cornerRadius":28},\
    "palette":{"bg":"#101418","fg":"#F5F5F5","accent":"#FF5A36"},"background":{"type":"solid","color":"@bg"},"fields":[],\
    "layers":[{"type":"stack","axis":"vertical","spacing":4,"alignItems":"center","justify":"center","frame":{"x":12,"y":40,"w":146,"h":90},\
    "children":[{"type":"text","spans":[{"text":"{{time.hh}}:{{time.mm}}"},\
    {"text":"{{time.ampm}}","font":{"family":"system","size":13,"weight":"bold"},"baselineOffset":18,"color":"@accent"}],\
    "font":{"family":"dot","size":56,"weight":"black"},"color":"@fg","align":"center","maxLines":1},\
    {"type":"text","value":"{{date.EEEE}}","font":{"family":"system","size":14,"weight":"semibold"},"color":"@accent","align":"center"}]},\
    {"type":"button","action":"clock.open","arg":null,"frame":{"x":0,"y":0,"w":170,"h":170}}]}
    """

    /// Every widget of a reply: one object or `{"widgets": [...]}` (ADR-029). All widgets' problems come back
    /// at once, each named with its widget and path.
    public static func importAll(_ text: String, size: SizeChoice = .auto) throws -> [GeneratedWidget] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }
        guard trimmed.utf8.count <= maxImportBytes else { throw ImportError.tooLarge }
        guard StructuredAI.extractJSON(trimmed) != nil else { throw ImportError.noJSON }
        let id = "ai." + UUID().uuidString.prefix(8).lowercased()
        do {
            let parsed = try AIWidgetParser.parseAll(trimmed, options: GenerationOptions(mode: .recreate, size: size), idPrefix: id,
                                                     enforceLayout: false)
            return parsed.map { item in
                GeneratedWidget(spec: item.spec, colors: item.colors, model: "external", attempts: 1, layout: item.layout, autoWired: item.autoWired)
            }
        } catch let error as AIValidationError {
            if error.description.contains("no JSON object found") { throw ImportError.noJSON }
            throw ImportError.invalid(error.description)
        }
    }

    /// The pasted or opened reply → a validated widget, with the layout repaired like the app's
    /// own AI results. Throws `ImportError`.
    public static func importWidget(_ text: String, size: SizeChoice = .auto) throws -> GeneratedWidget {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }
        guard trimmed.utf8.count <= maxImportBytes else { throw ImportError.tooLarge }
        guard StructuredAI.extractJSON(trimmed) != nil else { throw ImportError.noJSON }
        let id = "ai." + UUID().uuidString.prefix(8).lowercased()
        do {
            let parsed = try AIWidgetParser.parseWidget(trimmed, options: GenerationOptions(mode: .recreate, size: size), id: id,
                                                        enforceLayout: false)
            return GeneratedWidget(spec: parsed.spec, colors: parsed.colors, model: "external", attempts: 1, layout: parsed.layout,
                                   autoWired: parsed.autoWired)
        } catch let error as AIValidationError {
            if error.description.contains("no JSON object found") { throw ImportError.noJSON }
            throw ImportError.invalid(error.description)
        }
    }

    /// What the user sends back to the external AI when the import fails.
    public static func fixRequest(for error: ImportError) -> String {
        switch error {
        case .empty, .noJSON:
            return "Reply again with only the widget JSON object, exactly as the schema in my first message describes: "
                + "no explanation, no code fences."
        case .unreadable:
            return "The file could not be read. Reply again with the whole JSON object as text."
        case .tooLarge:
            return "That reply is too long. Simplify the design (fewer layers) and reply with only the JSON object."
        case .invalid(let problems):
            // ADR-029: every problem at once, one per line, with its widget and path.
            let lines = problems.split(whereSeparator: { $0 == "\n" }).flatMap { $0.components(separatedBy: "; ") }
                .map { "- " + $0.trimmingCharacters(in: .whitespaces) }
            return "Widget Studio could not import your JSON. Fix every problem below (each names its widget or its path), keep "
                + "everything else, and reply with the whole corrected JSON only:\n\n" + lines.joined(separator: "\n")
        }
    }

    /// ADR-029: sent with a render of the imported widget, so the other AI can compare it with the original image.
    public static func previewRequest(names: [String], notes: [String] = []) -> String {
        var text = "The picture shows how Widget Studio draws your JSON"
            + (names.count > 1 ? " (\(names.count) widgets: \(names.joined(separator: ", ")))" : "") + ". Compare it with my original "
            + "image, element by element: position, size (font size ≈ 1.4 × cap height), font, color, card shape and ratio, missing or "
            + "extra elements, and live data. Fix every difference and reply with the whole corrected JSON only, in the same format."
        if !notes.isEmpty { text += "\n\nThe app also noted:\n" + notes.map { "- " + $0 }.joined(separator: "\n") }
        return text
    }
}

import Foundation

/// The tool list `exhibit mcp` returns from `tools/list`: names, descriptions and JSON Schemas for the arguments.
extension MCPTools {
    static func definitions() -> [[String: Any]] {
        [targetsTool(), markTool(), applyTool(), sayTool()]
    }

    private static var input: [String: Any] { [
        "type": "string",
        "description": "Absolute path to a PNG or JPEG file, or to a .exhibit capture bundle. A relative path is read "
            + "from the server's working directory."
    ] }

    private static var output: [String: Any] { [
        "type": "string",
        "description": "Absolute path for the new PNG; must end in .png. Default: next to the input, named "
            + "<name>-marked.png (or -marked-2.png and up when taken). The result's \"output\" names the file written."
    ] }

    private static var force: [String: Any] { [
        "type": "boolean",
        "description": "Overwrite \"output\" if it exists, even when it is the input. Default false: an existing file "
            + "is an output_exists error."
    ] }

    private static var point: [String: Any] { [
        "type": "object",
        "properties": ["x": ["type": "number"], "y": ["type": "number"]],
        "required": ["x", "y"],
        "additionalProperties": false
    ] }

    private static var rect: [String: Any] { [
        "type": "object",
        "properties": ["x": ["type": "number"], "y": ["type": "number"], "width": ["type": "number"],
                       "height": ["type": "number"]],
        "required": ["x", "y", "width", "height"],
        "additionalProperties": false
    ] }

    private static let errors = "On failure the result has isError true and holds the CLI's error JSON: "
        + "{\"error\": {\"code\", \"exitCode\", \"message\", ...}}. Branch on \"code\": usage, io, output_exists, "
        + "invalid_marks, no_match, nth_out_of_range, ambiguous (with \"candidates\"), needs_model, model_failed."

    private static func tool(_ name: String, _ description: String, properties: [String: Any], required: [String],
                             readOnly: Bool) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required,
                            "additionalProperties": false],
            "annotations": ["readOnlyHint": readOnly, "destructiveHint": false, "openWorldHint": false]
        ]
    }

    private static func targetsTool() -> [String: Any] {
        tool("targets", """
            List what is on a screenshot: every line of text, email, key, card number, phone number and face, with \
            an id, a kind, a rect in pixels (origin top-left) and, for text lines, the text. Use it to read the \
            screen without image tokens and to choose selectors for "mark". Sensitive values never appear: their \
            targets have no text and their characters are masked in the line. Writes nothing. \(untrusted) \(errors)
            """, properties: ["input": input], required: ["input"], readOnly: true)
    }

    private static func markTool() -> [String: Any] {
        let strings: [String: Any] = ["type": "array", "items": ["type": "string"]]
        func list(_ description: String) -> [String: Any] { strings.merging(["description": description]) { $1 } }
        let properties: [String: Any] = [
            "input": input,
            "kind": ["type": "string", "enum": ["blur", "highlight", "circle", "box", "arrow", "text", "step"],
                     "description": "The mark. blur hides every match (nothing under it can be recovered); "
                        + "highlight marks every match; circle, box, arrow, text (a label) and step (a numbered "
                        + "disc) mark one match per selector."],
            "text": list("Case-insensitive substrings of a line of screen text to mark. Sensitive text is masked, so "
                         + "use kinds for emails, keys, cards and phone numbers."),
            "regex": list("ICU regular expressions over each line of screen text. Case-sensitive; start with (?i) "
                          + "to ignore case."),
            "kinds": ["type": "array", "description": "Every target of these kinds; text means whole lines.",
                      "items": ["type": "string", "enum": ["email", "key", "card", "phone", "face", "text"]]],
            "rect": ["type": "array", "items": rect, "description": "Exact pixel rects to mark, origin top-left."],
            "from": point.merging(["description": "arrow only: where the tail starts, in pixels. Default: placed "
                                   + "automatically."]) { $1 },
            "label": ["type": "string", "description": "arrow: a caption at the tail. text: the words to show "
                      + "(required for text). Not for other kinds."],
            "color": ["type": "string", "enum": ["red", "yellow", "blue", "green"],
                      "description": "Not for blur. Default red (yellow for highlight)."],
            "number": ["type": "integer", "description": "step only: the number on the first disc. Default 1."],
            "all": ["type": "boolean", "description": "Mark every match of each selector instead of failing with "
                    + "ambiguous. blur and highlight always do."],
            "nth": ["type": "integer", "minimum": 1, "description": "Mark only the nth match of each selector, "
                    + "counting from 1 in reading order (top to bottom, then left to right)."],
            "allowMissing": ["type": "boolean", "description": "Succeed when some selectors match nothing, as long "
                             + "as one matches."],
            "output": output,
            "force": force
        ]
        return tool("mark", """
            Draw one kind of mark on a screenshot and write a new PNG; the input is left alone. Give at least one \
            selector (text, regex, kinds or rect); each is resolved and reported on its own. A selector that \
            matches nothing fails with no_match and nothing is written. The result's "output" is the PNG path; \
            "marks" and "selectors" say what was marked. To combine kinds, chain on "output" or use "apply". \
            \(untrusted) \(errors)
            """, properties: properties, required: ["input", "kind"], readOnly: false)
    }

    private static func applyTool() -> [String: Any] {
        let entry: [String: Any] = [
            "type": "object",
            "description": "One mark, the same fields as the mark tool: kind (required), text, to, regex, kinds, "
                + "rect, from, label, color, number, all, nth, allowMissing. \"to\" is like text, or a point "
                + "{x, y} for an arrow drawn by coordinates with \"from\". Unknown fields are an error.",
            "properties": ["kind": ["type": "string",
                                    "enum": ["blur", "highlight", "circle", "box", "arrow", "text", "step"]]],
            "required": ["kind"]
        ]
        let properties: [String: Any] = [
            "input": input,
            "marks": ["type": "array", "minItems": 1, "items": entry,
                      "description": "The marks, in order. Example: [{\"kind\": \"blur\", \"kinds\": [\"email\", "
                        + "\"key\"]}, {\"kind\": \"arrow\", \"to\": \"Pricing\", \"label\": \"Here\"}]"],
            "output": output,
            "force": force
        ]
        return tool("apply", """
            Draw several marks on a screenshot in one render and write a new PNG. If any entry fails, nothing is \
            written and the error message starts with the entry, like marks[2]. The result's "output" is the PNG \
            path; each mark reports its "entry". \(untrusted) \(errors)
            """, properties: properties, required: ["input", "marks"], readOnly: false)
    }

    private static func sayTool() -> [String: Any] {
        let properties: [String: Any] = [
            "input": input,
            "instruction": ["type": "string", "description": "What to do, in plain words, naming text on the screen: "
                            + "\"blur the emails and circle pricing\", \"point at Sign up and label it start here\"."],
            "pointer": point.merging(["description": "Where the pointer is, in pixels, for \"this\" and \"here\"."]) {
                $1
            },
            "output": output,
            "force": force
        ]
        return tool("say", """
            Mark up a screenshot from an instruction in plain words and write a new PNG. A built-in grammar reads \
            usual instructions; anything it cannot read fails with needs_model unless the person running this \
            server configured a local model. Partial results succeed with "complete" false and "notFound" listing \
            what is missing. "summary" says what was done. \(untrusted) \(errors)
            """, properties: properties, required: ["input", "instruction"], readOnly: false)
    }
}

import Foundation

/// A JSON Schema of the settings file, for editors that complete keys and flag mistakes while
/// the user types, such as Zed, or Visual Studio Code with the YAML extension.
extension LauncherConfigFile {
    /// The schema's file name, next to the settings file.
    static let schemaName = "settings.schema.json"

    /// Where the schema goes for the settings file at `path`.
    public static func schemaPath(nextTo path: String = defaultPath()) -> String {
        ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(schemaName)
    }

    /// Writes ``schema`` next to the settings file at `path`, so it matches the app that reads
    /// the file; a file that matches already is left alone.
    public static func writeSchema(nextTo path: String = defaultPath()) throws {
        let url = URL(filePath: schemaPath(nextTo: path))
        guard (try? String(contentsOf: url, encoding: .utf8)) != schema else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try schema.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Every setting with its type, its allowed values and its explanation, as JSON Schema
    /// (draft 2020-12).
    public static let schema: String = {
        let object: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": "Plaincontrol settings",
            "description": "Written by Plaincontrol each time it starts; changes to this file have no effect.",
            "type": ["object", "null"],
            "additionalProperties": false,
            "properties": Dictionary(uniqueKeysWithValues: Setting.allCases.map { ($0.key, $0.schema) }),
        ]
        let data = try! JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }()
}

extension LauncherConfigFile.Setting {
    /// The setting's explanation in the template, as one paragraph.
    var summary: String {
        switch self {
        case .activeDays:
            "How many days a project in one of the roots stays listed after its last change or use."
        case .actionOrder:
            """
            How a project's actions are ordered: fixed, always the same order with the first action selected; \
            selected, the same order with the action you use most in that project selected, so Return runs it; \
            or usage, the actions you use most in that project first, their digits moving with them. A project \
            you haven't used an action in yet follows your use in all projects.
            """
        default: explanation.map { $0.dropFirst(2) }.joined(separator: " ").replacing(/\s+/, with: " ")
        }
    }

    /// The setting's part of ``LauncherConfigFile/schema``.
    var schema: [String: Any] {
        var schema: [String: Any]
        switch self {
        case .holdKey: schema = ["enum": HoldKey.allCases.map(\.rawValue)]
        case .terminal, .editor, .browser: schema = ["type": ["string", "null"]]
        case .claudeCommand: schema = ["type": "string", "pattern": "\\S"]
        case .actionOrder: schema = ["enum": ActionOrder.allCases.map(\.rawValue)]
        case .zoxide: schema = ["type": "boolean"]
        case .roots: schema = ["type": ["array", "null"], "items": ["type": "string"]]
        case .activeDays: schema = ["type": "integer", "minimum": LauncherConfigFile.minimumActiveDays]
        case .projects:
            schema = [
                "type": ["array", "null"],
                "items": Self.object(
                    [
                        "name": [
                            "type": ["string", "null"], "description": "The name to show; without one, the folder's.",
                        ],
                        "path": ["type": "string", "description": "The project's folder; ~ is the home folder."],
                        "devCommand": [
                            "type": ["string", "null"],
                            "description":
                                "What starts the project's dev server, instead of the one the launcher finds.",
                        ],
                    ], required: ["path"]),
            ]
        case .windows:
            let columns = LauncherConfigFile.columnRange
            let count: (String) -> [String: Any] = { note in
                [
                    "type": "integer", "minimum": columns.lowerBound, "maximum": columns.upperBound,
                    "description": Self.sentence(note),
                ]
            }
            let gap = LauncherConfigFile.gapRange
            schema = Self.object([
                "builtIn": count(WindowNotes.builtIn),
                "external": count(WindowNotes.external),
                "gap": [
                    "type": "number", "minimum": gap.lowerBound, "maximum": gap.upperBound,
                    "description": Self.sentence(WindowNotes.gap),
                ],
                "editor": Self.object(
                    ["builtIn": count(WindowNotes.builtIn), "external": count(WindowNotes.external)],
                    description: Self.sentence(WindowNotes.editor)),
            ])
            // false leaves the windows to each app; true is the default layout.
            schema["type"] = ["object", "boolean", "null"]
        }
        schema["description"] = summary
        return schema
    }

    /// `note`, such as one after a value in the file, as a sentence.
    private static func sentence(_ note: String) -> String {
        note.prefix(1).uppercased() + note.dropFirst() + "."
    }

    private static func object(
        _ properties: [String: [String: Any]], required: [String] = [], description: String? = nil
    ) -> [String: Any] {
        var object: [String: Any] = ["type": "object", "additionalProperties": false, "properties": properties]
        if !required.isEmpty { object["required"] = required }
        if let description { object["description"] = description }
        return object
    }
}

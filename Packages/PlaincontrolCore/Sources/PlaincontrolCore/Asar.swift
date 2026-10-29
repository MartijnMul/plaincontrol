import Foundation

/// An Electron app's archive (`.asar`): its files laid end to end after an index of them.
///
/// The index comes first, as JSON in a Chromium pickle: a 32-bit size of the pickle header (4),
/// the index pickle's size, that pickle's payload size, then the length of the JSON and the
/// JSON itself. The files follow the index pickle, each at the offset the index gives. Only the
/// index is read up front, as an archive can be hundreds of megabytes.
struct Asar {
    private let url: URL
    private let index: [String: Any]
    /// Where the files start in the archive.
    private let base: UInt64

    init?(contentsOf url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16), header.count == 16 else { return nil }
        let words = (0..<4).map { i in header[i * 4..<i * 4 + 4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
        guard words[0] == 4, let json = try? handle.read(upToCount: Int(words[3])), json.count == Int(words[3]),
            let index = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        else { return nil }
        self.url = url
        self.index = index
        base = 8 + UInt64(words[1])
    }

    /// The names of the files directly in `directory`, a path inside the archive such as
    /// `resources/i18n`; not those of folders, nor of files kept outside the archive.
    func files(in directory: String) -> [String] {
        let entries = entry(at: directory)?["files"] as? [String: Any] ?? [:]
        return entries.compactMap { name, entry in
            guard let entry = entry as? [String: Any], entry["offset"] != nil else { return nil }
            return name
        }
    }

    /// The contents of the file at `path` inside the archive.
    func contents(of path: String) -> Data? {
        guard let entry = entry(at: path), let size = entry["size"] as? Int,
            let offset = (entry["offset"] as? String).flatMap(UInt64.init),
            let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: base + offset)) != nil, let data = try? handle.read(upToCount: size),
            data.count == size
        else { return nil }
        return data
    }

    private func entry(at path: String) -> [String: Any]? {
        var entry: [String: Any]? = index
        for name in path.split(separator: "/") {
            entry = (entry?["files"] as? [String: Any])?[String(name)] as? [String: Any]
        }
        return entry
    }
}

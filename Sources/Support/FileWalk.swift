import Foundation

/// Directory traversal used by providers to discover session files cheaply
/// (without reading their contents).
enum FileWalk {
    /// Recursively list regular files under `root` whose last path component
    /// satisfies `matches`, paired with their modification date. A missing root
    /// yields an empty list rather than an error. Set `includeHidden` to descend
    /// into dot-directories (e.g. antigravity's `.system_generated`).
    static func files(
        under root: URL,
        includeHidden: Bool = false,
        matches: (String) -> Bool
    ) -> [(url: URL, modified: Date?)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: options
        ) else { return [] }

        var out: [(url: URL, modified: Date?)] = []
        for case let url as URL in enumerator {
            guard matches(url.lastPathComponent) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == false { continue }
            out.append((url, values?.contentModificationDate))
        }
        return out
    }
}

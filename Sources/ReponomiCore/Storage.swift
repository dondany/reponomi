import Foundation

public enum AppPaths {
    /// Where config, cache and usage live. `REPONOMI_HOME` overrides the
    /// default of `~/Library/Application Support/Reponomi`.
    public static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["REPONOMI_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Reponomi", isDirectory: true)
    }

    public static var config: URL { directory.appendingPathComponent("config.json") }
    public static var cache: URL { directory.appendingPathComponent("repos.json") }
    public static var usage: URL { directory.appendingPathComponent("usage.json") }
}

public enum JSONFile {
    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            NSLog("Reponomi: ignoring unreadable %@: %@", url.path, String(describing: error))
            return nil
        }
    }

    @discardableResult
    public static func save<T: Encodable>(_ value: T, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            // Private to the user: the files name private repositories, and
            // the config decides which command gets run.
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
            try encoder.encode(value).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            NSLog("Reponomi: could not write %@: %@", url.path, String(describing: error))
            return false
        }
    }
}

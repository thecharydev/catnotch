import CryptoKit
import Foundation

public struct ReleaseFile: Equatable, Sendable {
    public let url: String
    /// Base64 sha512, as in `latest-mac.yml`.
    public let sha512: String

    public init(url: String, sha512: String) {
        self.url = url
        self.sha512 = sha512
    }
}

public enum UpdateError: Error, Equatable, Sendable {
    /// The feed has no version or no zip.
    case feed
    /// The download does not match its checksum.
    case checksum
    /// The app's folder is read-only, as on a disk image.
    case unwritable
    case failed
}

/// What Settings shows for the Update button.
public enum UpdateState: Equatable, Sendable {
    case idle, checking, upToDate
    /// The check itself failed (offline, bad feed); nothing was installed.
    case checkFailed
    case available(version: String)
    case downloading(percent: Int)
    case installing
    /// The new app is already in place; the old one runs until the user restarts.
    case installed(version: String)
    case unwritable
    case failed
}

/// A Release's `latest-mac.yml`: the version and the zip to install.
public enum UpdateFeed {

    /// ponytail: reads only the `version`, `url` and `sha512` lines electron-builder writes, not YAML in general.
    public static func parse(_ text: String) throws -> (version: String, zip: ReleaseFile) {
        var version: String?
        var files: [ReleaseFile] = []
        var url: String?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if raw.hasPrefix("version:") { version = value(line, "version:") }
            else if line.hasPrefix("- url:") { url = value(line, "- url:") }
            else if raw.hasPrefix(" "), line.hasPrefix("sha512:"), let file = url {
                files.append(ReleaseFile(url: file, sha512: value(line, "sha512:")))
                url = nil
            }
        }
        let zip = files.first { $0.url.hasSuffix("-arm64-mac.zip") } ?? files.first { $0.url.hasSuffix("-universal-mac.zip") }
        guard let version, !version.isEmpty, let zip else { throw UpdateError.feed }
        return (version, zip)
    }

    private static func value(_ line: String, _ key: String) -> String {
        String(line.dropFirst(key.count)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }

    /// Whether `a` is a later version than `b`, number by number.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let (x, y) = (a.split(separator: ".").map { Int($0) ?? 0 }, b.split(separator: ".").map { Int($0) ?? 0 })
        for i in 0..<max(x.count, y.count) {
            let (l, r) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if l != r { return l > r }
        }
        return false
    }
}

/// Puts a downloaded release in place of the installed app.
public enum UpdateInstall {
    /// The base64 sha512 of a file, read in chunks.
    public static func sha512(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA512()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return Data(hash.finalize()).base64EncodedString()
    }

    /// Whether the app can replace itself in `dir`: false on a read-only disk image.
    public static func writable(_ dir: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: dir.path)
    }

    /// Verifies `zip`, unpacks it beside `installed` (the same volume, so the move is a rename) and swaps it in.
    /// The old app stays if anything fails; nothing is left behind either way.
    public static func install(zip: URL, sha512 expected: String, installed: URL) throws {
        let parent = installed.deletingLastPathComponent()
        guard writable(parent) else { throw UpdateError.unwritable }
        guard try sha512(of: zip) == expected else { throw UpdateError.checksum }
        let work = parent.appendingPathComponent(".catnotch-update")
        let fm = FileManager.default
        try? fm.removeItem(at: work)
        defer { try? fm.removeItem(at: work) }
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            guard run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) else { throw UpdateError.failed }
        } catch { throw UpdateError.failed }
        try swap(next: work.appendingPathComponent(installed.lastPathComponent), installed: installed)
    }

    /// Puts `next` in place of `installed`, which may be running: macOS lets a bundle be renamed under a live
    /// process. The old app is set aside first and put back if the move fails.
    public static func swap(next: URL, installed: URL) throws {
        let fm = FileManager.default
        let parent = installed.deletingLastPathComponent()
        guard writable(parent) else { throw UpdateError.unwritable }
        guard fm.fileExists(atPath: next.path) else { throw UpdateError.failed }
        let old = parent.appendingPathComponent(".\(installed.lastPathComponent).old")
        // Unsigned build: macOS would block the first launch of a downloaded app.
        guard run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", next.path]) else { throw UpdateError.failed }
        try? fm.removeItem(at: old)
        do {
            try fm.moveItem(at: installed, to: old)
            do { try fm.moveItem(at: next, to: installed) } catch {
                try fm.moveItem(at: old, to: installed)
                throw error
            }
        } catch { throw UpdateError.failed }
        try? fm.removeItem(at: old)
    }

    private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

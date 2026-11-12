import AppKit
import Foundation
import Observation
import CatNotchCore

/// The Update button's state and work. Checking only reports; `install` runs only from the button.
@MainActor @Observable
final class UpdateModel {
    private(set) var state = UpdateState.idle
    private var zip: ReleaseFile?
    private var next = ""

    private static let releases = "https://github.com/thecharydev/catnotch/releases"
    private let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private let installed = Bundle.main.bundleURL

    var version: String { current }
    var busy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    var isInstalled: Bool { if case .installed = state { true } else { false } }

    func check() async {
        guard !busy, !isInstalled else { return }
        state = .checking
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "\(Self.releases)/latest/download/latest-mac.yml")!)
            let release = try UpdateFeed.parse(String(decoding: data, as: UTF8.self))
            guard UpdateFeed.isNewer(release.version, than: current) else { return state = .upToDate }
            (next, zip) = (release.version, release.zip)
            state = .available(version: release.version)
        } catch {
            state = .checkFailed
        }
    }

    /// Download, check and swap in, then wait for `restart()`. Only ever called from the Update button.
    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    func install() async {
        // `failed` may retry: the release it failed on is still the one offered.
        guard state == .failed || { if case .available = state { true } else { false } }(), let zip else { return }
        guard !Self.isDebugBuild else { return } // a debug run is a build product, not an installed app
        // A disk image or read-only folder cannot be replaced: say so before downloading, and point at the Release.
        guard UpdateInstall.writable(installed.deletingLastPathComponent()) else {
            NSWorkspace.shared.open(URL(string: "\(Self.releases)/latest")!)
            return state = .unwritable
        }
        state = .downloading(percent: 0)
        do {
            guard let url = URL(string: "\(Self.releases)/download/\(next)/\(zip.url)") else { throw UpdateError.feed }
            let file = FileManager.default.temporaryDirectory.appending(path: "CatNotch-update-\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: file) }
            try await download(url, to: file)
            state = .installing
            // Hashing and unzipping a large file blocks, so not on the main actor, or "Installing…" never paints.
            let installed = installed
            try await Task.detached { try UpdateInstall.install(zip: file, sha512: zip.sha512, installed: installed) }.value
            state = .installed(version: next) // the user picks when to `restart()`
        } catch {
            state = .failed // the old app is still in place
        }
    }

    private func download(_ url: URL, to file: URL) async throws {
        let progress = DownloadProgress { [weak self] percent in Task { @MainActor in if case .downloading = self?.state { self?.state = .downloading(percent: percent) } } }
        let (temp, response) = try await URLSession.shared.download(from: url, delegate: progress)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.failed }
        try FileManager.default.moveItem(at: temp, to: file)
    }

    /// A detached `open` starts the new app once this process has exited (opening earlier would only focus it).
    func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 $1 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", installed.path, String(ProcessInfo.processInfo.processIdentifier)]
        try? process.run()
        NSApp.terminate(nil)
    }
}

/// Reports whole percents as a download arrives.
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let report: @Sendable (Int) -> Void
    private var shown = -1

    init(report: @escaping @Sendable (Int) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten done: Int64, totalBytesExpectedToWrite total: Int64) {
        guard total > 0, case let percent = Int(done * 100 / total), percent != shown else { return }
        shown = percent
        report(percent)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

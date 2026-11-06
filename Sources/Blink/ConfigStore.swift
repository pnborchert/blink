import BlinkCore
import Foundation

/// Loads and saves the JSON config file. The file is the single source of
/// truth: menu toggles write to it, and hand edits are picked up on reload.
struct ConfigStore {
    let url: URL

    init() {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        url = base.appendingPathComponent("blink/config.json")
    }

    /// Returns the config, creating a default file on first run. A file that
    /// cannot be parsed yields the defaults plus an error to show the user.
    func load() -> (config: BlinkConfig, error: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let config = BlinkConfig.default
            if let error = save(config) { return (config, error) }
            return (config, nil)
        }
        do {
            let data = try Data(contentsOf: url)
            return (try BlinkConfig.decode(from: data), nil)
        } catch let error as DecodingError {
            return (.default, "\(url.path) is not valid: \(Self.describe(error))\n\nUsing default settings until it is fixed.")
        } catch {
            return (.default, "Could not read \(url.path): \(error.localizedDescription)")
        }
    }

    /// Returns an error message on failure.
    @discardableResult
    func save(_ config: BlinkConfig) -> String? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = try config.encoded()
            data.append(0x0A)
            try data.write(to: url, options: .atomic)
            return nil
        } catch {
            return "Could not write \(url.path): \(error.localizedDescription)"
        }
    }

    /// Calls `onChange` (debounced) when the file is saved. Editors usually save
    /// by replacing the file, so this watches the directory, not the file.
    /// Keep the returned source alive for as long as you want updates.
    func watch(onChange: @escaping @MainActor () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        var pending: DispatchWorkItem?
        source.setEventHandler {
            pending?.cancel()
            let work = DispatchWorkItem { MainActor.assumeIsolated { onChange() } }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let p = context.codingPath.map(\.stringValue).joined(separator: ".")
            return p.isEmpty ? "" : " (at '\(p)')"
        }
        switch error {
        case .dataCorrupted(let c):
            return ((c.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String ?? c.debugDescription) + path(c)
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c):
            return c.debugDescription + path(c)
        @unknown default:
            return "\(error)"
        }
    }
}

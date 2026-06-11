import Foundation

/// Injectable seam for reactive file watching (ADR-0006), so the app can depend
/// on the abstraction and tests can substitute a fake.
public protocol FileWatching: Sendable {
    @discardableResult func start() -> Bool
    func stop()
}

/// Watches a file with a `DispatchSource` and fires `onChange` on writes/renames/
/// deletes — lets the app refresh *reactively* (e.g. when Claude Code rewrites the
/// credential file after `claude /login`) instead of only on the poll timer (ADR-0014).
public final class FileWatcher: FileWatching, @unchecked Sendable {
    private let path: String
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    public init(path: String, onChange: @escaping @Sendable () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    /// Begin watching. No-op if the file can't be opened (returns false).
    @discardableResult
    public func start() -> Bool {
        stop()
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return false }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )
        let handler = onChange
        src.setEventHandler { handler() }
        let fd = fileDescriptor
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
        return true
    }

    public func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    deinit { stop() }
}

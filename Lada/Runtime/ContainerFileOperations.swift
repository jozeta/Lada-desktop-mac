import Foundation

/// File operations for the container Files tab, built on `container copy` and direct `exec` argv
/// (never `sh -c`, so file names are never interpreted by a shell inside the container).
///
/// Data moves through `container copy` via a private temporary directory on the host. That keeps
/// file contents out of the process argument list (Linux limits one argument to 128 KiB), keeps
/// binary files byte-exact, and keeps user-chosen host paths (which may contain `:`) away from the
/// CLI's `container:path` syntax.
public struct ContainerFileOperations: Sendable {
    /// Largest file the text editor opens. Larger files can still be downloaded.
    public static let maxEditableBytes: Int64 = 1_048_576

    public enum TextLoadResult: Equatable, Sendable {
        case text(String)
        case tooLarge(bytes: Int64)
        case binary
    }

    public let runtime: ContainerRuntimeService
    public let containerID: String

    public init(runtime: ContainerRuntimeService, containerID: String) {
        self.runtime = runtime
        self.containerID = containerID
    }

    // MARK: - Listing

    public func listDirectory(_ path: String) async throws -> [ContainerFileEntry] {
        let dir = try checkedPath(path)
        let res = try await exec(["ls", "-la", dir])
        guard res.isSuccess else {
            throw failure("Unable to list '\(dir)'.", res)
        }
        return Self.parseLsOutput(res.stdout, basePath: dir)
    }

    // MARK: - Editor

    /// Loads a whole file for editing. Files over `maxEditableBytes` or that are not valid UTF-8
    /// are refused rather than truncated, so saving can never cut a file short.
    public func loadText(_ entry: ContainerFileEntry) async throws -> TextLoadResult {
        if entry.sizeBytes > Self.maxEditableBytes { return .tooLarge(bytes: entry.sizeBytes) }
        let data = try await readData(entry.fullPath)
        if Int64(data.count) > Self.maxEditableBytes { return .tooLarge(bytes: Int64(data.count)) }
        guard let text = String(data: data, encoding: .utf8), !data.contains(0) else { return .binary }
        return .text(text)
    }

    /// Writes text back to an existing (or new) file, restoring the original mode and owner,
    /// because `container copy` always writes the file as root with mode 0644.
    public func saveText(_ text: String, to path: String) async throws {
        let target = try checkedPath(path)
        let original = try await fileMode(target)
        try await withTemporaryDirectory { dir in
            let staged = dir.appendingPathComponent("payload")
            try Data(text.utf8).write(to: staged)
            try await runtime.copyToContainer(id: containerID, fromHostPath: staged.path, containerPath: target)
        }
        if let original {
            let chmod = try await exec(["chmod", original.mode, target])
            guard chmod.isSuccess else { throw failure("Saved, but could not restore permissions \(original.mode).", chmod) }
            let chown = try await exec(["chown", "\(original.uid):\(original.gid)", target])
            guard chown.isSuccess else { throw failure("Saved, but could not restore owner \(original.uid):\(original.gid).", chown) }
        }
    }

    // MARK: - Transfers

    public func readData(_ path: String) async throws -> Data {
        let source = try checkedPath(path)
        return try await withTemporaryDirectory { dir in
            let staged = dir.appendingPathComponent("payload")
            try await runtime.copyFromContainer(id: containerID, containerPath: source, toHostPath: staged.path)
            return try Data(contentsOf: staged)
        }
    }

    /// Copies a container file or folder to `destination` on the Mac, replacing what is there.
    public func download(_ path: String, to destination: URL) async throws {
        let source = try checkedPath(path)
        try await withTemporaryDirectory { dir in
            let staged = dir.appendingPathComponent("payload")
            try await runtime.copyFromContainer(id: containerID, containerPath: source, toHostPath: staged.path)
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: destination)
            }
        }
    }

    /// Uploads a Mac file into `directory`, keeping its file name. Returns the container path.
    @discardableResult
    public func upload(_ hostFile: URL, into directory: String) async throws -> String {
        let dir = try checkedPath(directory)
        let name = hostFile.lastPathComponent
        guard ValidationUtils.isValidFileName(name) else {
            throw invalid("'\(name)' is not a valid file name.")
        }
        let target = Self.join(dir, name)
        try await withTemporaryDirectory { tmp in
            // Stage a copy (an APFS clone, so cheap) under a name without ':'.
            let staged = tmp.appendingPathComponent("payload")
            try FileManager.default.copyItem(at: hostFile, to: staged)
            try await runtime.copyToContainer(id: containerID, fromHostPath: staged.path, containerPath: target)
        }
        return target
    }

    // MARK: - Folders

    @discardableResult
    public func makeDirectory(named name: String, in directory: String) async throws -> String {
        let dir = try checkedPath(directory)
        guard ValidationUtils.isValidFileName(name) else {
            throw invalid("'\(name)' is not a valid folder name (no '/', not '.' or '..').")
        }
        let target = Self.join(dir, name)
        let res = try await exec(["mkdir", "-p", target])
        guard res.isSuccess else { throw failure("Could not create '\(target)'.", res) }
        return target
    }

    public func remove(_ path: String) async throws {
        let target = try checkedPath(path)
        guard target != "/" else { throw invalid("Refusing to delete '/'.") }
        let res = try await exec(["rm", "-rf", target])
        guard res.isSuccess else { throw failure("Could not delete '\(target)'.", res) }
    }

    // MARK: - ls -la parsing

    /// Parses `ls -la` output from BusyBox or GNU coreutils.
    ///
    /// Columns: permissions, links, owner, group, size (or `major, minor` for device files),
    /// three date fields, then the name. The name is the rest of the line, so names with inner or
    /// trailing spaces survive (leading spaces are indistinguishable from column padding).
    public static func parseLsOutput(_ output: String, basePath: String) -> [ContainerFileEntry] {
        var list: [ContainerFileEntry] = []
        for line in output.components(separatedBy: "\n") {
            let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("total ") { continue }

            var scanner = FieldScanner(line)
            guard let perms = scanner.next(), scanner.next() != nil,
                  let owner = scanner.next(), scanner.next() != nil,
                  var sizeField = scanner.next() else { continue }

            let isDevice = perms.hasPrefix("c") || perms.hasPrefix("b")
            if sizeField.hasSuffix(",") {
                // Device file: "10, 235" (major, minor) — consume the minor number too.
                guard let minor = scanner.next() else { continue }
                sizeField += " " + minor
            }
            guard let month = scanner.next(), let day = scanner.next(), let timeOrYear = scanner.next() else { continue }
            var rawName = scanner.remainder()
            guard !rawName.isEmpty else { continue }

            let isDir = perms.hasPrefix("d")
            let isLink = perms.hasPrefix("l")
            var symlinkTarget: String?
            if isLink, let arrowRange = rawName.range(of: " -> ") {
                symlinkTarget = String(rawName[arrowRange.upperBound...])
                rawName = String(rawName[..<arrowRange.lowerBound])
            }
            if rawName == "." || rawName == ".." { continue }

            list.append(
                ContainerFileEntry(
                    name: rawName,
                    fullPath: join(basePath, rawName),
                    permissions: perms,
                    owner: owner,
                    sizeBytes: isDevice ? 0 : (Int64(sizeField) ?? 0),
                    modifiedText: "\(month) \(day) \(timeOrYear)",
                    isDirectory: isDir,
                    isSymlink: isLink,
                    symlinkTarget: symlinkTarget
                )
            )
        }

        return list.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    public static func join(_ directory: String, _ name: String) -> String {
        directory == "/" ? "/\(name)" : "\(directory.hasSuffix("/") ? String(directory.dropLast()) : directory)/\(name)"
    }

    // MARK: - Helpers

    private struct FileMode { let mode: String; let uid: Int; let gid: Int }

    /// Mode and owner of an existing file, or nil if it does not exist yet.
    private func fileMode(_ path: String) async throws -> FileMode? {
        let res = try await exec(["stat", "-c", "%a %u %g", path])
        guard res.isSuccess else { return nil }
        let parts = res.stdout.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 3, parts[0].allSatisfy(\.isNumber), let uid = Int(parts[1]), let gid = Int(parts[2]) else { return nil }
        return FileMode(mode: parts[0], uid: uid, gid: gid)
    }

    private func exec(_ command: [String]) async throws -> CommandExecutionResult {
        try await runtime.execCommand(containerID: containerID, command: command, user: nil, workdir: nil, env: [])
    }

    private func checkedPath(_ path: String) throws -> String {
        guard ValidationUtils.isValidAbsoluteContainerPath(path) else {
            throw invalid("Container path must be absolute: '\(path)'.")
        }
        return path
    }

    private func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lada-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await body(dir)
    }

    private func invalid(_ explanation: String) -> LadaError {
        LadaError(category: .invalidConfiguration, explanation: explanation, suggestedRemediation: "Choose a different name or path.", isRetryable: false)
    }

    private func failure(_ explanation: String, _ res: CommandExecutionResult) -> LadaError {
        LadaError(
            category: .containerLifecycleFailure,
            explanation: explanation,
            exitStatus: res.exitStatus,
            diagnosticOutput: res.combinedOutput,
            suggestedRemediation: "Check that the path exists and that the container user has permission.",
            isRetryable: true
        )
    }
}

/// Splits leading whitespace-separated fields off a line while keeping the rest verbatim.
private struct FieldScanner {
    private let line: Substring
    private var index: Substring.Index

    init(_ line: String) {
        self.line = Substring(line)
        self.index = self.line.startIndex
    }

    mutating func next() -> String? {
        skipSpaces()
        guard index < line.endIndex else { return nil }
        let start = index
        while index < line.endIndex, line[index] != " ", line[index] != "\t" { index = line.index(after: index) }
        return String(line[start..<index])
    }

    /// Everything after the single separator that follows the last field read.
    mutating func remainder() -> String {
        skipSpaces()
        return String(line[index...])
    }

    private mutating func skipSpaces() {
        while index < line.endIndex, line[index] == " " || line[index] == "\t" { index = line.index(after: index) }
    }
}

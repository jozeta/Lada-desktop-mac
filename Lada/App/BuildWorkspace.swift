import Foundation

/// The Builds screen's form and the running build, kept in `AppState` so leaving the screen
/// mid-build loses nothing.
@MainActor
public final class BuildWorkspace: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case building(startedAt: Date)
        case succeeded(image: String, seconds: Int)
        case failed(reason: String)
    }

    @Published public var folder: String = ""
    /// Absolute path of the build file; filled in by detection, can be overridden.
    @Published public var buildFile: String?
    @Published public var imageName: String = ""
    @Published public var request: ImageBuildRequest
    @Published public var additionalTags: String = ""
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var log: String = ""
    @Published public var logSearch = ""
    @Published public var logPaused = false
    @Published public var logAutoScroll = true

    init(cpus: Int, memoryMB: Int) {
        request = ImageBuildRequest(contextDirectory: "", containerfilePath: "", tags: [], cpus: cpus, memoryMB: memoryMB)
    }

    public var isBuilding: Bool {
        if case .building = phase { return true }
        return false
    }

    /// Picks a folder: detects its build file and suggests an image name if none was typed.
    public func choose(folder: String) {
        self.folder = folder
        buildFile = BuildPlanner.detectBuildFile(in: folder)
        if imageName.isEmpty || imageName.hasPrefix("local/") {
            imageName = BuildPlanner.suggestedImageName(for: folder)
        }
    }

    /// What still stops the build, in plain words (nil when ready).
    public var blocker: String? {
        if folder.isEmpty { return "Choose the project folder that contains your Dockerfile." }
        if buildFile == nil { return "No Dockerfile or Containerfile found in this folder. Choose the file below." }
        return BuildPlanner.imageNameProblem(imageName)
    }

    /// The exact request that will run, with the build file resolved inside the folder.
    public var effectiveRequest: ImageBuildRequest {
        var req = request
        req.contextDirectory = folder
        req.containerfilePath = buildFile.map { BuildPlanner.resolvedBuildFile($0, in: folder) } ?? ""
        let extras = additionalTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        req.tags = [imageName.trimmingCharacters(in: .whitespaces)] + extras
        return req
    }

    /// Reuses a past build's folder, file and image name.
    public func reuse(_ record: BuildRecord) {
        folder = record.contextDirectory
        buildFile = record.containerfilePath.isEmpty ? BuildPlanner.detectBuildFile(in: record.contextDirectory) : record.containerfilePath
        imageName = record.tags.first ?? imageName
        log = record.logOutput
        phase = .idle
    }

    public func build(appState: AppState) {
        guard blocker == nil, !isBuilding else { return }
        let req = effectiveRequest
        let started = Date()
        phase = .building(startedAt: started)
        log = ""
        var record = BuildRecord(tags: req.tags, contextDirectory: req.contextDirectory, containerfilePath: req.containerfilePath, status: .running)
        appState.appendBuildRecord(record)

        Task {
            do {
                let result = try await appState.runtimeService.buildImage(request: req) { line in
                    Task { @MainActor in self.log += line + "\n" }
                }
                // Let queued output lines land before summarising.
                await Task.yield()
                let seconds = Int(Date().timeIntervalSince(started).rounded())
                record.finishedAt = Date()
                record.exitCode = result.exitStatus
                record.status = result.isSuccess ? .succeeded : .failed
                record.logOutput = log.isEmpty ? result.combinedOutput : log
                appState.appendBuildRecord(record)
                phase = result.isSuccess
                    ? .succeeded(image: req.tags.first ?? "", seconds: seconds)
                    : .failed(reason: BuildPlanner.failureSummary(in: record.logOutput) ?? "The build exited with code \(result.exitStatus).")
                appState.recordActivity(
                    category: "Builds",
                    title: "Build \(req.tags.first ?? "image")",
                    detail: result.isSuccess ? "Built in \(seconds) s." : "Failed with exit code \(result.exitStatus).",
                    redactedCommand: SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments()),
                    outcome: result.isSuccess ? .success : .failure
                )
                await appState.refreshAll(isUserInitiated: false)
            } catch {
                record.finishedAt = Date()
                record.status = .failed
                let message = (error as? LadaError).map { [$0.explanation, $0.diagnosticOutput ?? ""].joined(separator: "\n") } ?? error.localizedDescription
                record.logOutput = log + "\n" + message
                appState.appendBuildRecord(record)
                phase = .failed(reason: BuildPlanner.failureSummary(in: record.logOutput) ?? (error as? LadaError)?.explanation ?? error.localizedDescription)
            }
        }
    }
}

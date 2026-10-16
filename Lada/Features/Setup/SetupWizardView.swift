import SwiftUI
import AppKit

public struct SetupWizardView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isChecking = false
    @State private var isFetchingRelease = false
    @State private var isDownloadingInstaller = false
    @State private var installerProgressText: String = ""
    @State private var downloadedInstallerURL: URL? = nil
    @State private var installerError: LadaError? = nil

    public init(appState: AppState) {
        self.appState = appState
    }

    private var requiredReadyCount: Int {
        appState.prerequisites.filter { $0.isRequired && $0.status == .ready }.count
    }

    private var requiredTotalCount: Int {
        appState.prerequisites.filter { $0.isRequired }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                LadaIcon(.appIdentity, size: 32, strokeWidth: 1.6)
                    .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Låda System & Runtime Setup")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)
                    Text("Verify macOS hardware, virtualization capabilities, and Apple's official `container` runtime.")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                }

                Spacer()

                NordicStatusBadge(
                    label: "\(requiredReadyCount)/\(requiredTotalCount) Required Ready",
                    tone: requiredReadyCount == requiredTotalCount ? .positive : .warning
                )
            }
            .padding(20)
            .background(NordicTheme.elevatedSurface)
            .overlay(alignment: .bottom) {
                Divider().overlay(NordicTheme.borderSubtle)
            }

            if let installerError {
                NordicErrorBanner(error: installerError) {
                    Task { await fetchReleaseAndDownload() }
                } onDismiss: {
                    self.installerError = nil
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            // Prerequisite Checklist
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NordicSectionHeader(
                        "Prerequisite Checklist",
                        subtitle: "Apple's container runtime requires Apple silicon and macOS 26+.",
                        trailingText: isChecking ? "Checking…" : "Verified \(appState.systemStatus.checkedAt.formatted(date: .omitted, time: .standard))"
                    )

                    VStack(spacing: 1) {
                        ForEach(appState.prerequisites) { item in
                            PrerequisiteRowView(
                                item: item,
                                onAction: { handlePrerequisiteAction(item) }
                            )
                        }
                    }
                    .background(NordicTheme.borderSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(NordicTheme.borderSubtle, lineWidth: 1)
                    )

                    // Official Release & Automated / Manual Installation Box
                    officialInstallerPanel
                }
                .padding(20)
            }
            .background(NordicTheme.contentSurface)

            // Footer
            HStack(spacing: 12) {
                Button {
                    Task {
                        isChecking = true
                        await appState.refreshAll(isUserInitiated: true)
                        isChecking = false
                    }
                } label: {
                    Label("Re-run Checks", systemImage: "arrow.clockwise")
                }
                .disabled(isChecking)

                Button("Open Official Releases") {
                    NSWorkspace.shared.open(RuntimeHealthService.officialReleasesURL)
                }

                Spacer()

                if !appState.installation.isInstalled {
                    Toggle("Enable Demo Sandbox (No CLI)", isOn: $appState.preferences.useSimulationWhenCLIMissing)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                        .foregroundStyle(NordicTheme.secondaryText)
                        .onChange(of: appState.preferences.useSimulationWhenCLIMissing) { _, _ in
                            Task { await appState.refreshAll(isUserInitiated: true) }
                        }
                }

                Button("Continue to Låda") {
                    appState.preferences.hasCompletedFirstLaunchSetup = true
                    appState.showSetupWizard = false
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(NordicTheme.elevatedSurface)
            .overlay(alignment: .top) {
                Divider().overlay(NordicTheme.borderSubtle)
            }
        }
        .frame(minWidth: 740, minHeight: 580)
        .accessibilityIdentifier(AccessibilityID.setupWizardSheet)
        .task {
            if appState.latestReleaseInfo == nil {
                appState.latestReleaseInfo = try? await appState.healthService.fetchLatestOfficialRelease()
            }
        }
    }

    @ViewBuilder
    private var officialInstallerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            NordicSectionHeader(
                "Official Apple Container Installer & Manual Commands",
                subtitle: "Signed packages are fetched directly over HTTPS from github.com/apple/container/releases."
            )

            VStack(alignment: .leading, spacing: 10) {
                if let release = appState.latestReleaseInfo {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("Latest Upstream Release: \(release.tagName)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(NordicTheme.primaryText)
                                NordicStatusBadge(label: "Signed .pkg", tone: .positive, showDot: false)
                            }
                            Text("Publisher: \(release.publisher) • Asset: \(release.assetName) (\(ByteCountFormatter.string(fromByteCount: release.sizeBytes, countStyle: .file)))")
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.secondaryText)
                            if let sha = release.sha256Digest {
                                Text("Digest: \(sha)")
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.secondaryText)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        Button {
                            Task { await fetchReleaseAndDownload() }
                        } label: {
                            if isDownloadingInstaller {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Verifying…")
                                }
                            } else {
                                Label("Download & Verify Signed Installer", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isDownloadingInstaller)
                    }
                } else {
                    HStack {
                        Text("Official release page: https://github.com/apple/container/releases")
                            .font(NordicTheme.monoFontSmall)
                            .foregroundStyle(NordicTheme.secondaryText)
                        Spacer()
                        Button("Check Latest Release") {
                            Task { await fetchReleaseAndDownload() }
                        }
                        .disabled(isFetchingRelease || isDownloadingInstaller)
                    }
                }

                if !installerProgressText.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: downloadedInstallerURL != nil ? "checkmark.seal.fill" : "info.circle")
                            .foregroundStyle(downloadedInstallerURL != nil ? NordicTheme.statusGreen : NordicTheme.accent())
                        Text(installerProgressText)
                            .font(.system(size: 12))
                            .foregroundStyle(NordicTheme.primaryText)
                        Spacer()
                        if let pkgURL = downloadedInstallerURL {
                            Button("Launch macOS Installer…") {
                                appState.healthService.openNativeMacOSInstaller(for: pkgURL)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                    .background(NordicTheme.windowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Divider().overlay(NordicTheme.borderSubtle)

                Text("Guided Terminal Commands (Copyable)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NordicTheme.secondaryText)

                HStack(spacing: 8) {
                    Text("container system start && container system status")
                        .font(NordicTheme.monoFontRegular)
                        .foregroundStyle(NordicTheme.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NordicTheme.codeSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .textSelection(.enabled)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("container system start && container system status", forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }
            .padding(14)
            .background(NordicTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(NordicTheme.borderSubtle, lineWidth: 1)
            )
        }
    }

    private func handlePrerequisiteAction(_ item: PrerequisiteItem) {
        switch item.actionType {
        case .installCLI:
            Task { await fetchReleaseAndDownload() }
        case .startSystemService:
            Task {
                await appState.performOperation(
                    category: "Runtime",
                    title: "Start Container System",
                    redactedCommand: "container system start --enable-kernel-install"
                ) {
                    try await appState.runtimeService.startSystemService(enableKernelInstall: true)
                    return "Container API server started and verified."
                }
            }
        case .installDefaultKernel:
            Task {
                await appState.performOperation(
                    category: "Runtime",
                    title: "Install Recommended Kernel",
                    redactedCommand: "container system kernel set --recommended"
                ) {
                    try await appState.runtimeService.installRecommendedKernel()
                    return "Recommended guest Linux kernel installed."
                }
            }
        case .openReleasePage:
            NSWorkspace.shared.open(RuntimeHealthService.officialReleasesURL)
        case .recheck, .none:
            Task { await appState.refreshAll(isUserInitiated: true) }
        }
    }

    private func fetchReleaseAndDownload() async {
        installerError = nil
        isDownloadingInstaller = true
        defer { isDownloadingInstaller = false }
        do {
            let release: ReleaseAssetInfo
            if let existing = appState.latestReleaseInfo {
                release = existing
            } else {
                installerProgressText = "Querying latest official release from github.com/apple/container…"
                release = try await appState.healthService.fetchLatestOfficialRelease()
                appState.latestReleaseInfo = release
            }
            let pkgURL = try await appState.healthService.downloadAndVerifyInstaller(release: release) { msg in
                Task { @MainActor in
                    self.installerProgressText = msg
                }
            }
            self.downloadedInstallerURL = pkgURL
            appState.healthService.openNativeMacOSInstaller(for: pkgURL)
        } catch let ladaErr as LadaError {
            installerError = ladaErr
        } catch {
            installerError = LadaError(
                category: .networkFailure,
                explanation: error.localizedDescription,
                suggestedRemediation: "Open https://github.com/apple/container/releases to download the signed installer package manually.",
                isRetryable: true
            )
        }
    }
}

public struct PrerequisiteRowView: View {
    public let item: PrerequisiteItem
    public let onAction: () -> Void

    public init(item: PrerequisiteItem, onAction: @escaping () -> Void) {
        self.item = item
        self.onAction = onAction
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NordicTheme.primaryText)

                    Text(item.isRequired ? "Required" : "Optional")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NordicTheme.secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(NordicTheme.windowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Text(item.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)

                if item.status != .ready {
                    Text("Remediation: \(item.recommendedRemediation)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(item.status == .incompatible || item.status == .failed ? NordicTheme.statusRed : NordicTheme.statusAmber)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.detectedStatusText)
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.secondaryText)

                    NordicStatusBadge(prerequisiteStatus: item.status)
                }

                if let actionTitle = item.actionTitle {
                    Button(actionTitle, action: onAction)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NordicTheme.elevatedSurface)
    }
}

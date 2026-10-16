import SwiftUI

public struct RegistriesView: View {
    @ObservedObject var appState: AppState
    @State private var showLoginSheet = false
    @State private var serverInput = "ghcr.io"
    @State private var usernameInput = ""
    @State private var passwordInput = ""
    @State private var schemeInput = "https"

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            securityNoteBanner
            if appState.registries.isEmpty {
                NordicEmptyState(
                    icon: .registries,
                    title: "No Authenticated Registries",
                    description: "Log in to Docker Hub, GitHub Container Registry (ghcr.io), Amazon ECR, or private OCI registries. Credentials are passed via `--password-stdin` and stored in macOS Keychain.",
                    primaryActionTitle: "Log In to Registry",
                    onPrimaryAction: { showLoginSheet = true }
                )
            } else {
                registryTable
            }
        }
        .background(NordicTheme.windowBackground)
        .sheet(isPresented: $showLoginSheet) {
            loginSheet
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Text("OCI Container Registries (\(appState.registries.count))")
                .font(NordicTheme.subtitleFont)
                .foregroundStyle(NordicTheme.primaryText)
            Spacer()
            Button {
                serverInput = "ghcr.io"
                usernameInput = ""
                passwordInput = ""
                schemeInput = "https"
                showLoginSheet = true
            } label: {
                Label("Log In to Registry", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(NordicTheme.elevatedSurface)
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    private var securityNoteBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(NordicTheme.statusGreen)
            Text("Låda never passes registry passwords or tokens as command-line arguments. Authentication uses `container registry login --username <user> --password-stdin <server>` and stores credentials in macOS Keychain.")
                .font(.system(size: 11))
                .foregroundStyle(NordicTheme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(NordicTheme.contentSurface)
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    private var registryTable: some View {
        Table(appState.registries) {
            TableColumn("Registry Hostname") { reg in
                HStack(spacing: 8) {
                    LadaIcon(.registries, size: 15)
                        .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    Text(reg.hostname)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .width(min: 180, ideal: 240)

            TableColumn("Username") { reg in
                Text(reg.username.isEmpty ? "token" : reg.username)
                    .font(NordicTheme.monoFontSmall)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Status") { reg in
                NordicStatusBadge(label: reg.isAuthenticated ? "Authenticated" : "Logged Out", tone: reg.isAuthenticated ? .positive : .neutral)
            }
            .width(min: 100, ideal: 130)

            TableColumn("Modified") { reg in
                Text(reg.modificationDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Actions") { reg in
                Button("Log Out", role: .destructive) {
                    Task {
                        await appState.performOperation(
                            category: "Registries",
                            title: "Logout Registry \(reg.hostname)",
                            redactedCommand: "container registry logout \(reg.hostname)"
                        ) {
                            try await appState.runtimeService.logoutRegistry(server: reg.hostname)
                            return "Logged out of '\(reg.hostname)'."
                        }
                    }
                }
                .controlSize(.small)
            }
            .width(min: 80, ideal: 100)
        }
        .accessibilityIdentifier(AccessibilityID.registryTable)
    }

    private var loginSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authenticate with Container Registry")
                .font(NordicTheme.titleFont)

            Form {
                TextField("Registry Server (e.g. docker.io, ghcr.io, quay.io)", text: $serverInput)
                    .font(NordicTheme.monoFontRegular)
                TextField("Username", text: $usernameInput)
                    .font(NordicTheme.monoFontRegular)
                SecureField("Password or Personal Access Token", text: $passwordInput)
                Picker("Transport Scheme", selection: $schemeInput) {
                    Text("HTTPS").tag("https")
                    Text("HTTP (Local / Insecure)").tag("http")
                }
            }
            .formStyle(.grouped)

            let previewArgs = [
                "registry", "login",
                "--username", usernameInput.isEmpty ? "<username>" : usernameInput,
                "--password-stdin",
                "--scheme", schemeInput,
                serverInput.isEmpty ? "<server>" : serverInput,
            ]
            Text(SecretRedactor.formatCommandPreview(executable: "container", arguments: previewArgs))
                .font(NordicTheme.monoFontSmall)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NordicTheme.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Button("Cancel") { showLoginSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Log In") {
                    let server = serverInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let user = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let pass = passwordInput
                    let scheme = schemeInput
                    showLoginSheet = false
                    Task {
                        await appState.performOperation(
                            category: "Registries",
                            title: "Login Registry \(server)",
                            redactedCommand: "container registry login --username \(user) --password-stdin --scheme \(scheme) \(server)"
                        ) {
                            try await appState.runtimeService.loginRegistry(
                                server: server,
                                username: user,
                                password: pass,
                                scheme: scheme
                            )
                            return "Authenticated with '\(server)' as '\(user)'."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                .disabled(serverInput.isEmpty || usernameInput.isEmpty || passwordInput.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

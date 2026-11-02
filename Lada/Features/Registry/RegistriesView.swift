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
        .nordicBar()
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
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    private var registryTable: some View {
        Table(appState.registries) {
            TableColumn("Registry") { reg in
                HStack(spacing: 8) {
                    LadaIcon(.registries, size: 14)
                        .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    Text(reg.hostname)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .width(min: 180, ideal: 240)

            TableColumn("Username") { reg in
                Text(reg.username.isEmpty ? "token" : reg.username)
                    .font(.system(size: 12).monospacedDigit())
            }
            .width(min: 120, ideal: 160)

            TableColumn("Status") { reg in
                NordicStatusBadge(label: reg.isAuthenticated ? "Authenticated" : "Logged Out", tone: reg.isAuthenticated ? .positive : .neutral)
            }
            .width(min: 100, ideal: 130)

            TableColumn("Modified") { reg in
                Text(reg.modificationDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
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
        .nordicTransparentTable()
        .accessibilityIdentifier(AccessibilityID.registryTable)
    }

    private var loginSheet: some View {
        let server = serverInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewArgs = ["registry", "login", "--username", user.isEmpty ? "<username>" : user,
                           "--password-stdin", "--scheme", schemeInput, server.isEmpty ? "<server>" : server]
        let existing = appState.registries.first { $0.hostname == server }
        return NordicSheet(
            icon: .registries,
            title: "Log In to a Registry",
            subtitle: "Sign in to pull private images and push your own. The password goes to the runtime over stdin and is stored in your Keychain.",
            primaryTitle: existing?.isAuthenticated == true ? "Log In Again" : "Log In",
            problem: loginProblem(server: server, user: user),
            onCancel: { passwordInput = ""; showLoginSheet = false },
            onPrimary: { logIn(server: server, user: user) }
        ) {
            NordicFormSection(title: "Registry") {
                NordicFormField(title: "Server", hint: Self.tokenHint(for: server),
                                info: "The registry's host name (and port, if it isn't the default), without https://.") {
                    TextField("ghcr.io", text: $serverInput)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontRegular)
                        .accessibilityIdentifier("lada.registries.login.server")
                    NordicChoiceChips(options: ["docker.io", "ghcr.io", "quay.io", "registry.gitlab.com", "public.ecr.aws"], selected: server) { serverInput = $0 }
                    if let existing, existing.isAuthenticated {
                        Text("Already signed in as \(existing.username). Logging in again replaces those credentials.")
                            .font(.system(size: 11))
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                }
            }
            NordicFormSection(title: "Credentials") {
                NordicFormField(title: "Username") {
                    TextField("your-user", text: $usernameInput)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontRegular)
                        .accessibilityIdentifier("lada.registries.login.username")
                }
                NordicFormField(title: "Password or access token",
                                hint: "Prefer an access token with only the permissions you need; you can revoke it without changing your password.",
                                info: "Never shown in command previews or logs, and never passed as a command-line argument.") {
                    SecureField("token", text: $passwordInput)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("lada.registries.login.password")
                }
            }
            NordicFormSection(title: "Connection") {
                NordicFormField(title: "Scheme",
                                hint: schemeInput == "http" ? "HTTP sends your credentials unencrypted. Use it only for a registry on this Mac or a trusted local network." : "Encrypted. Use this for every registry on the internet.",
                                info: "How Låda's runtime connects to the registry.") {
                    Picker("Scheme", selection: $schemeInput) {
                        Text("HTTPS").tag("https")
                        Text("HTTP (local, insecure)").tag("http")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            NordicCommandPreview(arguments: previewArgs)
        }
    }

    /// Where to get a token, for the well-known registries.
    static func tokenHint(for server: String) -> String {
        switch server {
        case "docker.io": return "Docker Hub: create a personal access token under Account settings → Personal access tokens."
        case "ghcr.io": return "GitHub: use a personal access token (classic) with read:packages, plus write:packages to push."
        case "quay.io": return "Quay: use a robot account, or an encrypted password from Account settings."
        case "registry.gitlab.com": return "GitLab: use a personal or deploy token with read_registry (and write_registry to push)."
        case "public.ecr.aws": return "Amazon ECR Public: the username is AWS and the password a token from `aws ecr-public get-login-password`."
        default: return "For example docker.io, ghcr.io, or localhost:5000 for a registry on this Mac."
        }
    }

    /// A registry host: name or IP, optional port, no scheme or path.
    static func isValidRegistryHost(_ host: String) -> Bool {
        host.range(of: #"^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$"#, options: .regularExpression) != nil
    }

    private func loginProblem(server: String, user: String) -> String? {
        if server.isEmpty { return "Enter the registry's server." }
        if server.contains("://") { return "Leave out http:// or https://; choose the scheme below." }
        if !Self.isValidRegistryHost(server) { return "That doesn't look like a registry host, e.g. ghcr.io or localhost:5000." }
        if user.isEmpty { return "Enter your username." }
        if passwordInput.isEmpty { return "Enter your password or access token." }
        return nil
    }

    private func logIn(server: String, user: String) {
        let pass = passwordInput
        let scheme = schemeInput
        // Don't keep the secret in view state longer than needed.
        passwordInput = ""
        showLoginSheet = false
        Task {
            await appState.performOperation(
                category: "Registries",
                title: "Login Registry \(server)",
                redactedCommand: "container registry login --username \(user) --password-stdin --scheme \(scheme) \(server)"
            ) {
                try await appState.runtimeService.loginRegistry(server: server, username: user, password: pass, scheme: scheme)
                return "Authenticated with '\(server)' as '\(user)'."
            }
        }
    }
}

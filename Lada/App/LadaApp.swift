import SwiftUI

@main
public struct LadaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup("Låda — Apple Container Studio") {
            MainWindowView(appState: appState)
                .frame(minWidth: 1060, minHeight: 680)
                .onAppear {
                    appDelegate.appState = appState
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Container…") {
                    appState.createContainerInitialRequest = nil
                    appState.showCreateContainerSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Pull Image…") {
                    appState.selectedSection = .images
                    appState.showPullImageSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Refresh Runtime State") {
                    Task { await appState.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandMenu("Navigate") {
                Button("Overview") { appState.selectedSection = .overview }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Containers") { appState.selectedSection = .containers }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Compose Stacks") { appState.selectedSection = .stacks }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Images") { appState.selectedSection = .images }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Image Library (Docker Hub)") { appState.selectedSection = .imageLibrary }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Dockerfile Editor") { appState.selectedSection = .dockerfileEditor }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Builds") { appState.selectedSection = .builds }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Networks") { appState.selectedSection = .networks }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Volumes") { appState.selectedSection = .volumes }
                    .keyboardShortcut("6", modifiers: [.command])
                Button("Machines") { appState.selectedSection = .machines }
                    .keyboardShortcut("7", modifiers: [.command])
                Button("Registries") { appState.selectedSection = .registries }
                    .keyboardShortcut("8", modifiers: [.command])
                Button("Activity") { appState.selectedSection = .activity }
                    .keyboardShortcut("9", modifiers: [.command])
                Button("Settings") { appState.selectedSection = .settings }
                    .keyboardShortcut("0", modifiers: [.command])
                Divider()
                Button("Setup & Runtime Wizard…") {
                    appState.showSetupWizard = true
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appState.selectedSection = .settings
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        MenuBarExtra("Låda", systemImage: "shippingbox.fill") {
            MenuBarPopoverView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

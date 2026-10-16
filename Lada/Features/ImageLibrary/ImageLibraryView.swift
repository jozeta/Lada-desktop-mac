import SwiftUI
import AppKit

public struct ImageLibraryView: View {
    @ObservedObject var appState: AppState

    @State private var searchQuery: String = ""
    @State private var selectedCategory: DockerHubCategory = .all
    @State private var selectedBadgeFilter: DockerHubBadgeFilter = .all
    @State private var selectedSort: DockerHubSortOption = .mostPulls
    @State private var repositories: [DockerHubRepositoryItem] = DockerHubService.curatedCatalog
    @State private var selectedTagBySlug: [String: String] = [:]
    @State private var isSearching: Bool = false
    @State private var pullingSlug: String? = nil
    @State private var pullStatusMessage: String = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredAndSortedRepositories: [DockerHubRepositoryItem] {
        var list = repositories

        if selectedCategory != .all {
            list = list.filter { $0.category == selectedCategory }
        }

        switch selectedBadgeFilter {
        case .all:
            break
        case .officialOnly:
            list = list.filter { $0.isOfficial }
        case .verifiedOnly:
            list = list.filter { $0.isVerifiedPublisher || $0.isOfficial }
        case .arm64Native:
            list = list.filter { $0.architectures.contains("arm64") }
        }

        let globalQ = appState.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !globalQ.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(globalQ) ||
                $0.description.localizedCaseInsensitiveContains(globalQ)
            }
        }

        switch selectedSort {
        case .mostPulls:
            list.sort { $0.pullCount > $1.pullCount }
        case .mostStars:
            list.sort { $0.starCount > $1.starCount }
        case .nameAZ:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recentlyUpdated:
            list.sort { $0.updatedAt > $1.updatedAt }
        }

        return list
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(NordicTheme.borderSubtle)
            filterAndSortStrip
            Divider().overlay(NordicTheme.borderSubtle)

            if let pullingSlug, !pullStatusMessage.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Pulling \(pullingSlug): \(pullStatusMessage)")
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.primaryText)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NordicTheme.elevatedSurface)
                Divider().overlay(NordicTheme.borderSubtle)
            }

            if filteredAndSortedRepositories.isEmpty {
                NordicEmptyState(
                    icon: .images,
                    title: "No Matching Docker Hub Images",
                    description: "Try adjusting your search query, category filter, or badge filter.",
                    primaryActionTitle: "Reset Filters",
                    onPrimaryAction: {
                        searchQuery = ""
                        selectedCategory = .all
                        selectedBadgeFilter = .all
                        Task { await performSearch() }
                    }
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 340, maximum: 500), spacing: 14)
                        ],
                        spacing: 14
                    ) {
                        ForEach(filteredAndSortedRepositories) { item in
                            repositoryCard(for: item)
                        }
                    }
                    .padding(18)
                }
                .background(NordicTheme.windowBackground)
            }
        }
        .task(id: searchQuery) {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Docker Hub Image Library")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)
                    Text("hub.docker.com")
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.06))
                        )
                }
                Text("Search, filter, and deploy official and community OCI images directly into Apple containers.")
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }

            Spacer()

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NordicTheme.secondaryText)
                TextField("Search hub.docker.com (e.g. postgres, redis, nginx, python)…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .frame(width: 280)
                if isSearching {
                    ProgressView().controlSize(.small)
                } else if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(NordicTheme.contentSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(NordicTheme.borderSubtle, lineWidth: 1)
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(NordicTheme.elevatedSurface)
    }

    private var filterAndSortStrip: some View {
        HStack(spacing: 12) {
            // Category pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DockerHubCategory.allCases) { category in
                        let isSelected = selectedCategory == category
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(
                                    isSelected
                                        ? .white
                                        : NordicTheme.primaryText
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(
                                            isSelected
                                                ? NordicTheme.accent(for: appState.preferences.accentThemeChoice)
                                                : Color.primary.opacity(0.06)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            Picker("Filter:", selection: $selectedBadgeFilter) {
                ForEach(DockerHubBadgeFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .frame(width: 195)
            .controlSize(.small)

            Picker("Sort:", selection: $selectedSort) {
                ForEach(DockerHubSortOption.allCases) { sort in
                    Text(sort.rawValue).tag(sort)
                }
            }
            .frame(width: 165)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(NordicTheme.contentSurface)
    }

    private func repositoryCard(for item: DockerHubRepositoryItem) -> some View {
        let selectedTag = selectedTagBySlug[item.slug] ?? item.availableTags.first ?? "latest"
        let fullRef = item.imageReference(forTag: selectedTag)
        let isLocalInstalled = appState.images.contains {
            $0.fullReference.hasSuffix(fullRef) || $0.repository.hasSuffix(item.name) && $0.tag == selectedTag
        }

        return VStack(alignment: .leading, spacing: 10) {
                // Top Row: Title + Badges + Stats
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.slug)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(NordicTheme.primaryText)

                            if item.isOfficial {
                                Text("OFFICIAL")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        Capsule().fill(NordicTheme.accent(for: appState.preferences.accentThemeChoice).opacity(0.14))
                                    )
                            } else if item.isVerifiedPublisher {
                                Text("VERIFIED")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(NordicTheme.statusGreen)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        Capsule().fill(NordicTheme.statusGreen.opacity(0.14))
                                    )
                            }

                            if isLocalInstalled {
                                Text("CACHED")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(NordicTheme.statusGreen)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        Capsule().fill(NordicTheme.statusGreen.opacity(0.12))
                                    )
                            }
                        }

                        Text(item.category.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NordicTheme.secondaryText)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(NordicTheme.statusAmber)
                            Text(item.formattedStarCount)
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(NordicTheme.secondaryText)
                            Text(item.formattedPullCount)
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                    }
                }

                // Description
                Text(item.description)
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(2)
                    .frame(minHeight: 32, alignment: .topLeading)

                // Architectures & Pre-configured defaults summary
                HStack(spacing: 6) {
                    ForEach(item.architectures, id: \.self) { arch in
                        Text(arch)
                            .font(NordicTheme.monoFontSmall)
                            .foregroundStyle(NordicTheme.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    }

                    if !item.recommendedPorts.isEmpty {
                        Text(verbatim: "Ports: " + item.recommendedPorts.map { "\($0.hostPort)→\($0.containerPort)" }.joined(separator: ", "))
                            .font(NordicTheme.monoFontSmall)
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                    Spacer()
                }

                Divider().overlay(NordicTheme.borderSubtle)

                // Bottom Action Row: Tag Picker + Pull + Deploy
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Tag:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NordicTheme.secondaryText)
                            .fixedSize(horizontal: true, vertical: false)
                        Picker("", selection: Binding(
                            get: { selectedTag },
                            set: { selectedTagBySlug[item.slug] = $0 }
                        )) {
                            ForEach(item.availableTags, id: \.self) { tag in
                                Text(tag).tag(tag)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 115)
                        .controlSize(.small)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()

                    Button {
                        pullImageDirectly(item: item, tag: selectedTag)
                    } label: {
                        Text("Pull")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(pullingSlug != nil)

                    Button {
                        deployRepository(item: item, tag: selectedTag)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text("Deploy")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    .controlSize(.small)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NordicTheme.contentSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NordicTheme.borderSubtle, lineWidth: 1)
            )
    }

    // MARK: - Actions

    private func performSearch() async {
        isSearching = true
        let results = await DockerHubService.shared.searchRepositories(query: searchQuery)
        repositories = results
        isSearching = false
    }

    private func deployRepository(item: DockerHubRepositoryItem, tag: String) {
        let req = item.buildDeployRequest(
            selectedTag: tag,
            defaultCPUs: appState.preferences.defaultContainerCPUs,
            defaultMemoryMB: appState.preferences.defaultContainerMemoryMB
        )
        let resolved = appState.resolveCreateRequestConflicts(req)
        appState.presentCreateContainer(with: resolved)
    }

    private func pullImageDirectly(item: DockerHubRepositoryItem, tag: String) {
        let reference = item.imageReference(forTag: tag)
        pullingSlug = reference
        pullStatusMessage = "Starting pull for \(reference)…"
        let pullReq = ImagePullRequest(reference: reference)
        let preview = SecretRedactor.formatCommandPreview(
            executable: appState.installation.executablePath ?? "container",
            arguments: pullReq.buildCLIArguments()
        )
        Task {
            await appState.performOperation(
                category: "Images",
                title: "Pull Docker Hub Image",
                redactedCommand: preview
            ) {
                try await appState.runtimeService.pullImage(request: pullReq) { line in
                    Task { @MainActor in
                        self.pullStatusMessage = line
                    }
                }
                return "Pulled \(reference) from Docker Hub."
            }
            pullingSlug = nil
            pullStatusMessage = ""
        }
    }
}

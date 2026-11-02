import Foundation

/// Autocomplete for image references (`repository[:tag]`) in the Create Container wizard.
///
/// Suggestions come from images already on this Mac and from the curated Docker Hub catalog
/// (whose tags were checked for arm64 builds). Nothing is fetched over the network while typing.
public enum ImageReferenceSuggester {
    public struct Suggestion: Identifiable, Equatable, Sendable {
        public enum Source: String, Sendable { case local = "Local", catalog = "Library" }
        public var id: String { reference }
        public let reference: String
        public let source: Source
        public let detail: String
    }

    /// - Parameters:
    ///   - query: what the user has typed so far.
    ///   - localReferences: full references of local images (e.g. `docker.io/library/nginx:latest`).
    ///   - catalog: curated catalog entries.
    ///   - limit: maximum number of suggestions.
    public static func suggestions(
        for query: String,
        localReferences: [String],
        catalog: [DockerHubRepositoryItem],
        limit: Int = 8
    ) -> [Suggestion] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var results: [Suggestion] = []
        var seen = Set<String>()
        func add(_ s: Suggestion) {
            guard s.reference.lowercased() != q, seen.insert(s.reference.lowercased()).inserted else { return }
            results.append(s)
        }

        // Tag completion once a tag separator is typed: `nginx:1.3` → nginx tags starting with
        // "1.3". A colon followed by "/" is a registry port (`localhost:5000/app`), not a tag.
        if let colon = q.lastIndex(of: ":"), !q[q.index(after: colon)...].contains("/") {
            let repo = shortName(String(q[..<colon]))
            let tagPrefix = String(q[q.index(after: colon)...])
            for ref in localReferences where shortName(ref) == repo && (tag(of: ref) ?? "").hasPrefix(tagPrefix) {
                add(Suggestion(reference: ref, source: .local, detail: "On this Mac"))
            }
            for item in catalog where repoName(item) == repo {
                for t in item.availableTags where t.lowercased().hasPrefix(tagPrefix) {
                    add(Suggestion(reference: item.imageReference(forTag: t), source: .catalog, detail: item.category.rawValue))
                }
            }
            return Array(results.prefix(limit))
        }

        // Repository completion: prefix matches rank above substring matches, local images first.
        let rank: (String) -> Int? = { name in
            if name.hasPrefix(q) { return 0 }
            if name.split(whereSeparator: { $0 == "/" || $0 == "-" }).contains(where: { $0.hasPrefix(q) }) { return 1 }
            if name.contains(q) { return 2 }
            return nil
        }
        var localRanked: [(reference: String, rank: Int)] = []
        for ref in localReferences {
            if let r = rank(shortName(ref)) ?? rank(ref.lowercased()) { localRanked.append((ref, r)) }
        }
        localRanked.sort { a, b in a.rank == b.rank ? a.reference < b.reference : a.rank < b.rank }
        for entry in localRanked {
            add(Suggestion(reference: entry.reference, source: .local, detail: "On this Mac"))
        }

        var catalogRanked: [(item: DockerHubRepositoryItem, rank: Int)] = []
        for item in catalog {
            if let r = rank(repoName(item)) ?? rank(item.name.lowercased()) { catalogRanked.append((item, r)) }
        }
        catalogRanked.sort { a, b in a.rank == b.rank ? a.item.pullCount > b.item.pullCount : a.rank < b.rank }
        for entry in catalogRanked {
            let tag = entry.item.availableTags.first ?? "latest"
            add(Suggestion(reference: entry.item.imageReference(forTag: tag), source: .catalog, detail: entry.item.category.rawValue))
        }
        return Array(results.prefix(limit))
    }

    /// `docker.io/library/nginx:1.31` → `nginx`; `ghcr.io/acme/tool:1` → `acme/tool`.
    static func shortName(_ reference: String) -> String {
        var r = reference.lowercased()
        if let at = r.firstIndex(of: "@") { r = String(r[..<at]) }
        if let colon = r.lastIndex(of: ":"), !r[r.index(after: colon)...].contains("/") { r = String(r[..<colon]) }
        var parts = r.split(separator: "/").map(String.init)
        if parts.count > 1, parts[0].contains(".") || parts[0].contains(":") || parts[0] == "localhost" { parts.removeFirst() }
        if parts.first == "library" { parts.removeFirst() }
        return parts.joined(separator: "/")
    }

    static func tag(of reference: String) -> String? {
        let r = reference.lowercased()
        guard let colon = r.lastIndex(of: ":"), !r[r.index(after: colon)...].contains("/") else { return nil }
        return String(r[r.index(after: colon)...])
    }

    /// The repository as typed in a reference: `nginx` for official images, `grafana/grafana` otherwise.
    static func repoName(_ item: DockerHubRepositoryItem) -> String {
        shortName(item.imageReference(forTag: "x"))
    }
}

import Foundation

/// Multi-selection helpers for the Containers and Images lists.
public enum BulkSelection {
    /// The container IDs a list selection covers, in list order and without duplicates. A stack
    /// row stands for all of its members; a member can also be picked on its own.
    public static func containerIDs(in selection: Set<String>, rows: [ContainerListRow]) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        for row in rows {
            switch row {
            case .container(let container):
                if selection.contains(container.id), seen.insert(container.id).inserted { ids.append(container.id) }
            case .stack(let group):
                let wholeStack = selection.contains(row.id)
                for member in group.members where wholeStack || selection.contains(member.id) {
                    if seen.insert(member.id).inserted { ids.append(member.id) }
                }
            }
        }
        return ids
    }

    /// Keeps only the IDs that still exist (rows and stack members), so a selection never points
    /// at a deleted or filtered-out item.
    public static func pruned(_ selection: Set<String>, rows: [ContainerListRow]) -> Set<String> {
        var valid = Set<String>()
        for row in rows {
            valid.insert(row.id)
            if case .stack(let group) = row { valid.formUnion(group.members.map(\.id)) }
        }
        return selection.intersection(valid)
    }

    /// Applies a selection change to stack groups: selecting a stack row selects its members,
    /// deselecting it deselects them, and deselecting one member drops the stack's own selection
    /// (it's no longer all selected).
    public static func cascade(from old: Set<String>, to new: Set<String>, rows: [ContainerListRow]) -> Set<String> {
        var result = new
        for row in rows {
            guard case .stack(let group) = row else { continue }
            let members = Set(group.members.map(\.id))
            let wasSelected = old.contains(row.id), isSelected = new.contains(row.id)
            if isSelected && !wasSelected {
                result.formUnion(members)
            } else if !isSelected && wasSelected {
                result.subtract(members)
            } else if isSelected && !members.isSubset(of: new) {
                result.remove(row.id)
            }
        }
        return result
    }

    /// The stack row when the selection is exactly one stack and its members, which is still a
    /// single selection (the inspector shows the stack, not bulk actions).
    public static func soleStack(in selection: Set<String>, rows: [ContainerListRow]) -> String? {
        for row in rows {
            guard case .stack(let group) = row, selection.contains(row.id) else { continue }
            return selection == Set(group.members.map(\.id)).union([row.id]) ? row.id : nil
        }
        return nil
    }

    /// Runs `perform` for every item, carrying on after a failure, and reports what happened.
    /// Runs on the caller's actor (`#isolation`), so main-actor callers can pass closures that touch
    /// app state.
    public static func run(_ items: [String], isolation: isolated (any Actor)? = #isolation,
                           perform: (String) async throws -> Void) async -> Outcome {
        var outcome = Outcome()
        for item in items {
            do {
                try await perform(item)
                outcome.succeeded.append(item)
            } catch let error as LadaError {
                outcome.failed.append(Failure(item: item, reason: error.explanation))
            } catch {
                outcome.failed.append(Failure(item: item, reason: error.localizedDescription))
            }
        }
        return outcome
    }

    public struct Failure: Equatable, Sendable {
        public let item: String
        public let reason: String
    }

    public struct Outcome: Equatable, Sendable {
        public var succeeded: [String] = []
        public var failed: [Failure] = []

        /// "Stopped 3 containers." or "Stopped 2 of 3 containers. web: <reason>".
        public func summary(verb: String, noun: String) -> String {
            let total = succeeded.count + failed.count
            let plural = total == 1 ? noun : noun + "s"
            if failed.isEmpty { return "\(verb) \(total) \(plural)." }
            let reasons = failed.map { "\($0.item): \($0.reason)" }.joined(separator: "\n")
            return "\(verb) \(succeeded.count) of \(total) \(plural).\n\(reasons)"
        }
    }
}

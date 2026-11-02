import Foundation

extension IPv4 {
    /// The address range of a CIDR, or nil if it isn't one.
    static func range(of cidr: String) -> ClosedRange<UInt32>? {
        let pieces = cidr.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard pieces.count == 2, let base = value(String(pieces[0])), let bits = UInt32(pieces[1]), (1...32).contains(bits) else { return nil }
        let mask: UInt32 = ~UInt32(0) << (32 - bits)
        let start = base & mask
        return start...(start | ~mask)
    }

    static func overlaps(_ a: String, _ b: String) -> Bool {
        guard let ra = range(of: a), let rb = range(of: b) else { return false }
        return ra.overlaps(rb)
    }
}

public enum SubnetSuggester {
    /// The first /24 in 192.168.70–250.0 that overlaps none of `existing` (subnets in use).
    public static func nextFree(avoiding existing: [String]) -> String? {
        for third in 70...250 {
            let candidate = "192.168.\(third).0/24"
            if !existing.contains(where: { IPv4.overlaps($0, candidate) }) { return candidate }
        }
        return nil
    }
}

public enum ByteSizeSpec {
    /// `512M`, `20G`, `1.5T`, `100MiB` → bytes (binary units, as the runtime reads them).
    public static func bytes(_ spec: String) -> Int64? {
        let s = spec.trimmingCharacters(in: .whitespaces).uppercased()
        guard let match = s.range(of: #"^(\d+(?:\.\d+)?)([KMGTP]?)(I?B?)$"#, options: .regularExpression), match == s.startIndex..<s.endIndex else { return nil }
        let number = s.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(number) else { return nil }
        let unit = s.dropFirst(number.count).first.map(String.init) ?? ""
        let powers = ["": 0, "K": 1, "M": 2, "G": 3, "T": 4, "P": 5]
        guard let power = powers[unit == "B" || unit == "I" ? "" : unit] else { return nil }
        return Int64(value * pow(1024, Double(power)))
    }
}

/// Checks shared by the create sheets.
public enum CreateSheetChecks {
    public static func nameTaken(_ name: String, in existing: [String]) -> Bool {
        existing.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}

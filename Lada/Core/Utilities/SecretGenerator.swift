import Foundation
import Security

/// Random secrets for presets and the "generate" button, so no container starts with a
/// well-known default password.
public enum SecretGenerator {
    /// Letters and digits only, so the value needs no quoting in shells, URLs or connection strings.
    private static let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// A random password from the system CSPRNG (`SecRandomCopyBytes`), ~5.8 bits per character.
    public static func password(length: Int = 24) -> String {
        precondition(length > 0)
        var result = ""
        result.reserveCapacity(length)
        // Rejection sampling avoids modulo bias.
        let limit = UInt8(256 - (256 % alphabet.count))
        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: length * 2)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
            for b in bytes where b < limit && result.count < length {
                result.append(alphabet[Int(b) % alphabet.count])
            }
        }
        return result
    }
}

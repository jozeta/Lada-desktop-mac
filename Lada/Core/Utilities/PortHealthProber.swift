import Foundation
import Darwin

/// Represents the live connectivity status of a published container host port.
public enum PortReadinessState: String, Codable, Sendable, Equatable {
    case unknown
    case healthyHTTP
    case listeningTCP
    case unreachable

    public var displayBadge: String {
        switch self {
        case .unknown: return "Probing"
        case .healthyHTTP: return "HTTP Ready"
        case .listeningTCP: return "TCP Ready"
        case .unreachable: return "Waiting"
        }
    }
}

public struct PortProbeResult: Sendable, Equatable {
    public let hostPort: UInt16
    public let state: PortReadinessState
    public let statusCode: Int?
    public let latencyMs: Int?
    public let checkedAt: Date

    public init(
        hostPort: UInt16,
        state: PortReadinessState,
        statusCode: Int? = nil,
        latencyMs: Int? = nil,
        checkedAt: Date = Date()
    ) {
        self.hostPort = hostPort
        self.state = state
        self.statusCode = statusCode
        self.latencyMs = latencyMs
        self.checkedAt = checkedAt
    }

    public var tooltipDescription: String {
        switch state {
        case .healthyHTTP:
            let codeText = statusCode.map { "HTTP \($0)" } ?? "HTTP OK"
            let latText = latencyMs.map { " (\($0) ms)" } ?? ""
            return "Port \(hostPort) is accepting HTTP requests — \(codeText)\(latText)"
        case .listeningTCP:
            let latText = latencyMs.map { " (\($0) ms)" } ?? ""
            return "Port \(hostPort) is open and accepting TCP connections\(latText)"
        case .unreachable:
            return "Port \(hostPort) is not yet accepting TCP connections on 127.0.0.1"
        case .unknown:
            return "Checking port \(hostPort)…"
        }
    }
}

/// Lightweight non-blocking TCP + HTTP readiness prober for published container ports.
public enum PortHealthProber {
    public static func probe(host: String = "127.0.0.1", port: UInt16) async -> PortProbeResult {
        let effectiveHost = (host == "0.0.0.0" || host == "::" || host.isEmpty) ? "127.0.0.1" : host
        let start = DispatchTime.now()

        let tcpConnected = await Task.detached(priority: .utility) {
            checkTCPConnection(host: effectiveHost, port: port, timeoutMs: 350)
        }.value

        guard tcpConnected else {
            return PortProbeResult(hostPort: port, state: .unreachable)
        }

        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)

        // For common HTTP ports or web services, perform a fast HTTP HEAD/GET check
        if isLikelyHTTPPort(port), let statusCode = await checkHTTPStatus(host: effectiveHost, port: port) {
            let totalMs = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
            return PortProbeResult(
                hostPort: port,
                state: .healthyHTTP,
                statusCode: statusCode,
                latencyMs: max(1, totalMs)
            )
        }

        return PortProbeResult(
            hostPort: port,
            state: .listeningTCP,
            statusCode: nil,
            latencyMs: max(1, elapsedMs)
        )
    }

    private static func isLikelyHTTPPort(_ port: UInt16) -> Bool {
        let nonHTTPPorts: Set<UInt16> = [5432, 3306, 6379, 27017, 22, 53]
        if nonHTTPPorts.contains(port) { return false }
        return true
    }

    private static func checkHTTPStatus(host: String, port: UInt16) async -> Int? {
        guard let url = URL(string: "http://\(host):\(port)/") else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.6
        config.timeoutIntervalForResource = 0.6
        let session = URLSession(configuration: config)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func checkTCPConnection(host: String, port: UInt16, timeoutMs: Int32) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            return true
        }
        guard errno == EINPROGRESS else {
            return false
        }

        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollRes = poll(&pfd, 1, timeoutMs)
        guard pollRes > 0 else { return false }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &soError, &len)
        return soError == 0
    }
}

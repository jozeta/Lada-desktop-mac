import Foundation

/// Parses machine-readable (JSON / TOML) and human-readable outputs emitted by Apple's `container` CLI.
public enum ContainerOutputParser {

    // MARK: - Flexible Date Decoding

    private static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                let isoFractional = ISO8601DateFormatter()
                isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoFractional.date(from: str) {
                    return date
                }
                let isoStandard = ISO8601DateFormatter()
                isoStandard.formatOptions = [.withInternetDateTime]
                if let date = isoStandard.date(from: str) {
                    return date
                }
                let fallback = DateFormatter()
                fallback.locale = Locale(identifier: "en_US_POSIX")
                fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
                if let date = fallback.date(from: str) {
                    return date
                }
            }
            if let timestamp = try? container.decode(Double.self) {
                // Distinguish Apple reference date (2001) vs Unix epoch (1970)
                if timestamp < 1_000_000_000 {
                    return Date(timeIntervalSinceReferenceDate: timestamp)
                }
                return Date(timeIntervalSince1970: timestamp)
            }
            return Date(timeIntervalSince1970: 0)
        }
        return decoder
    }

    // MARK: - 1. System Version (`container system version --format json` or `container --version`)

    public static func parseSystemVersions(jsonString: String) throws -> [RuntimeComponentVersion] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        struct RawVersionEntry: Decodable {
            let appName: String
            let version: String
            let buildType: String?
            let build: String?
            let commit: String?
        }
        let entries = try makeJSONDecoder().decode([RawVersionEntry].self, from: data)
        return entries.map {
            RuntimeComponentVersion(
                appName: $0.appName,
                version: $0.version,
                buildType: $0.buildType ?? $0.build ?? "release",
                commit: $0.commit ?? "unspecified"
            )
        }
    }

    // MARK: - 2. System Status (`container system status --format json`)

    public static func parseSystemStatus(jsonString: String) throws -> RuntimeSystemStatus {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw parserError("Empty JSON output from `container system status`.")
        }
        struct RawStatusPayload: Decodable {
            struct RawComponent: Decodable {
                let version: String
                let build: String?
                let commit: String?
                let appName: String?
            }
            struct RawPaths: Decodable {
                let appRoot: String?
                let installRoot: String?
                let logRoot: String?
            }
            struct RawResources: Decodable {
                let containersTotal: Int?
                let containersRunning: Int?
                let images: Int?
            }
            let status: String
            let client: RawComponent?
            let server: RawComponent?
            let paths: RawPaths?
            let resources: RawResources?
        }

        let payload = try makeJSONDecoder().decode(RawStatusPayload.self, from: data)
        let state = RuntimeServiceState(rawValue: payload.status.lowercased()) ?? (payload.status.lowercased() == "running" ? .running : .stopped)
        let clientVer = payload.client.map {
            RuntimeComponentVersion(
                appName: $0.appName ?? "container",
                version: $0.version,
                buildType: $0.build ?? "release",
                commit: $0.commit ?? "unspecified"
            )
        }
        let serverVer = payload.server.map {
            RuntimeComponentVersion(
                appName: $0.appName ?? "container-apiserver",
                version: $0.version,
                buildType: $0.build ?? "release",
                commit: $0.commit ?? "unspecified"
            )
        }

        return RuntimeSystemStatus(
            state: state,
            clientVersion: clientVer,
            serverVersion: serverVer,
            appRoot: payload.paths?.appRoot,
            installRoot: payload.paths?.installRoot,
            logRoot: payload.paths?.logRoot,
            containersTotal: payload.resources?.containersTotal ?? 0,
            containersRunning: payload.resources?.containersRunning ?? 0,
            imagesTotal: payload.resources?.images,
            statusMessage: payload.status
        )
    }

    // MARK: - 3. Containers (`container list --all --format json` & `container inspect`)

    public static func parseContainers(jsonString: String) throws -> [ContainerModel] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" { return [] }
        guard let data = trimmed.data(using: .utf8) else { return [] }

        guard let topArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw parserError("Expected JSON array of containers.")
        }

        return topArray.compactMap { parseSingleContainerDict($0) }
    }

    private static func parseSingleContainerDict(_ dict: [String: Any]) -> ContainerModel? {
        let configDict = dict["configuration"] as? [String: Any] ?? dict
        guard let id = (configDict["id"] as? String) ?? (dict["id"] as? String) else {
            return nil
        }

        // Image
        var imageRef = "unknown"
        var imageDigest: String? = nil
        if let imageObj = configDict["image"] as? [String: Any] {
            imageRef = (imageObj["reference"] as? String) ?? (imageObj["name"] as? String) ?? "unknown"
            if let desc = imageObj["descriptor"] as? [String: Any] {
                imageDigest = desc["digest"] as? String
            }
        } else if let imageStr = configDict["image"] as? String {
            imageRef = imageStr
        }

        // Status & networks
        var rawState = "stopped"
        var startedDate: Date? = nil
        var networkAttachments: [ContainerNetworkAttachment] = []

        if let statusObj = dict["status"] as? [String: Any] {
            rawState = (statusObj["state"] as? String) ?? "stopped"
            if let startedStr = statusObj["startedDate"] as? String {
                startedDate = parseDateValue(startedStr)
            } else if let startedNum = statusObj["startedDate"] as? Double {
                startedDate = parseDateValue(startedNum)
            }
            if let nets = statusObj["networks"] as? [[String: Any]] {
                networkAttachments = nets.map { parseNetworkAttachment($0) }
            }
        } else if let statusStr = dict["status"] as? String {
            rawState = statusStr
            if let nets = dict["networks"] as? [[String: Any]] {
                networkAttachments = nets.map { parseNetworkAttachment($0) }
            }
        }

        let creationDate = parseDateValue(configDict["creationDate"]) ?? Date()

        // Process configuration
        let procDict = configDict["initProcess"] as? [String: Any] ?? [:]
        let executable = (procDict["executable"] as? String) ?? "/bin/sh"
        let arguments = (procDict["arguments"] as? [String]) ?? []
        let environment = (procDict["environment"] as? [String]) ?? []
        let workingDir = (procDict["workingDirectory"] as? String) ?? "/"
        let terminal = (procDict["terminal"] as? Bool) ?? false

        var userString = "0:0"
        if let userObj = procDict["user"] as? [String: Any] {
            if let idObj = userObj["id"] as? [String: Any] {
                let uid = (idObj["uid"] as? Int) ?? 0
                let gid = (idObj["gid"] as? Int) ?? 0
                userString = "\(uid):\(gid)"
            } else if let rawObj = userObj["raw"] as? [String: Any], let s = rawObj["userString"] as? String {
                userString = s
            }
        } else if let uStr = procDict["user"] as? String {
            userString = uStr
        }

        // Resources
        let resDict = configDict["resources"] as? [String: Any] ?? [:]
        let cpus = (resDict["cpus"] as? Int) ?? 4
        let memoryInBytes: UInt64
        if let memNum = resDict["memoryInBytes"] as? UInt64 {
            memoryInBytes = memNum
        } else if let memInt = resDict["memoryInBytes"] as? Int {
            memoryInBytes = UInt64(max(0, memInt))
        } else {
            memoryInBytes = 1_073_741_824
        }

        // Platform
        let platDict = configDict["platform"] as? [String: Any] ?? [:]
        let os = (platDict["os"] as? String) ?? "linux"
        let arch = (platDict["architecture"] as? String) ?? "arm64"

        // Mounts
        var mounts: [MountAttachment] = []
        if let mountsArr = configDict["mounts"] as? [[String: Any]] {
            for m in mountsArr {
                let source = (m["source"] as? String) ?? ""
                let destination = (m["destination"] as? String) ?? ""
                let options = (m["options"] as? [String]) ?? []
                let readOnly = options.contains("ro") || options.contains("readonly")
                var kind: MountKind = .bind
                var volName: String? = nil
                if let typeObj = m["type"] as? [String: Any] {
                    if typeObj["tmpfs"] != nil {
                        kind = .tmpfs
                    } else if let volObj = typeObj["volume"] as? [String: Any] {
                        kind = .volume
                        volName = volObj["name"] as? String
                    } else if typeObj["block"] != nil {
                        kind = .block
                    } else {
                        kind = .bind
                    }
                } else if let typeStr = m["type"] as? String {
                    kind = MountKind(rawValue: typeStr) ?? .bind
                }
                mounts.append(MountAttachment(
                    kind: kind,
                    source: source,
                    destination: destination,
                    readOnly: readOnly,
                    options: options,
                    volumeName: volName
                ))
            }
        }

        // Published ports
        var ports: [PortMapping] = []
        if let portsArr = configDict["publishedPorts"] as? [[String: Any]] {
            for p in portsArr {
                let hostAddress = (p["hostAddress"] as? String) ?? "127.0.0.1"
                let hostPort = UInt16((p["hostPort"] as? Int) ?? 0)
                let containerPort = UInt16((p["containerPort"] as? Int) ?? 0)
                let proto = (p["proto"] as? String) ?? "tcp"
                let count = UInt16((p["count"] as? Int) ?? 1)
                if hostPort > 0 && containerPort > 0 {
                    ports.append(PortMapping(hostAddress: hostAddress, hostPort: hostPort, containerPort: containerPort, proto: proto, count: count))
                }
            }
        }

        // Published sockets
        var sockets: [SocketMapping] = []
        if let socksArr = configDict["publishedSockets"] as? [[String: Any]] {
            for s in socksArr {
                if let hp = s["hostPath"] as? String, let cp = s["containerPath"] as? String {
                    sockets.append(SocketMapping(hostPath: hp, containerPath: cp))
                }
            }
        }

        // DNS
        let dnsDict = configDict["dns"] as? [String: Any] ?? [:]
        let nameservers = (dnsDict["nameservers"] as? [String]) ?? ["1.1.1.1"]
        let dnsDomain = dnsDict["domain"] as? String
        let dnsSearch = (dnsDict["searchDomains"] as? [String]) ?? []
        let dnsOpts = (dnsDict["options"] as? [String]) ?? []

        // Configured networks
        var configuredNets: [String] = []
        if let cfgNets = configDict["networks"] as? [[String: Any]] {
            configuredNets = cfgNets.compactMap { $0["network"] as? String }
        }
        if configuredNets.isEmpty {
            configuredNets = networkAttachments.map(\.network)
        }
        if configuredNets.isEmpty {
            configuredNets = ["default"]
        }

        let labels = (configDict["labels"] as? [String: String]) ?? [:]
        let sysctls = (configDict["sysctls"] as? [String: String]) ?? [:]
        let rosetta = (configDict["rosetta"] as? Bool) ?? false
        let virtualization = (configDict["virtualization"] as? Bool) ?? false
        let ssh = (configDict["ssh"] as? Bool) ?? false
        let readOnly = (configDict["readOnly"] as? Bool) ?? false
        let useInit = (configDict["useInit"] as? Bool) ?? false
        let runtimeHandler = (configDict["runtimeHandler"] as? String) ?? "container-runtime-linux"
        let capAdd = (configDict["capAdd"] as? [String]) ?? []
        let capDrop = (configDict["capDrop"] as? [String]) ?? []
        let maskedPaths = configDict["maskedPaths"] as? [String]
        let readonlyPaths = configDict["readonlyPaths"] as? [String]
        let shmSize = (configDict["shmSize"] as? Int).map { UInt64(max(0, $0)) }

        let prettyJSON: String?
        if let rawData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            prettyJSON = String(data: rawData, encoding: .utf8)
        } else {
            prettyJSON = nil
        }

        let cfgModel = ContainerConfigurationModel(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDir,
            terminal: terminal,
            user: userString,
            cpus: cpus,
            memoryInBytes: memoryInBytes,
            shmSizeInBytes: shmSize,
            os: os,
            arch: arch,
            readOnlyRootfs: readOnly,
            useInit: useInit,
            rosetta: rosetta,
            virtualization: virtualization,
            sshForwarding: ssh,
            runtimeHandler: runtimeHandler,
            capAdd: capAdd,
            capDrop: capDrop,
            maskedPaths: maskedPaths,
            readonlyPaths: readonlyPaths,
            dnsNameservers: nameservers,
            dnsDomain: dnsDomain,
            dnsSearchDomains: dnsSearch,
            dnsOptions: dnsOpts,
            labels: labels,
            sysctls: sysctls,
            mounts: mounts,
            publishedPorts: ports,
            publishedSockets: sockets,
            configuredNetworks: configuredNets
        )

        return ContainerModel(
            id: id,
            imageReference: imageRef,
            imageDigest: imageDigest,
            state: ContainerState(rawRuntimeState: rawState),
            rawState: rawState,
            creationDate: creationDate,
            startedDate: startedDate,
            configuration: cfgModel,
            networks: networkAttachments,
            rawInspectJSON: prettyJSON
        )
    }

    private static func parseNetworkAttachment(_ dict: [String: Any]) -> ContainerNetworkAttachment {
        let network = (dict["network"] as? String) ?? "default"
        let hostname = (dict["hostname"] as? String) ?? ""
        let ipv4 = (dict["ipv4Address"] as? String) ?? (dict["address"] as? String) ?? ""
        let gw = (dict["ipv4Gateway"] as? String) ?? (dict["gateway"] as? String) ?? ""
        let ipv6 = dict["ipv6Address"] as? String
        let mac = dict["macAddress"] as? String
        let mtu = (dict["mtu"] as? Int).map { UInt32($0) }
        return ContainerNetworkAttachment(
            network: network,
            hostname: hostname,
            ipv4Address: ipv4,
            ipv4Gateway: gw,
            ipv6Address: ipv6,
            macAddress: mac,
            mtu: mtu
        )
    }

    // MARK: - 4. Container Stats (`container stats --format json --no-stream`)

    public static func parseContainerStats(jsonString: String) throws -> [ContainerStatsModel] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" { return [] }
        guard let data = trimmed.data(using: .utf8) else { return [] }
        return try makeJSONDecoder().decode([ContainerStatsModel].self, from: data)
    }

    // MARK: - 5. Images (`container image list --format json` & `container image inspect`)

    public static func parseImages(jsonString: String) throws -> [ImageModel] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" { return [] }
        guard let data = trimmed.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw parserError("Expected JSON array of images.")
        }

        return array.compactMap { dict in
            let configDict = dict["configuration"] as? [String: Any] ?? dict
            guard let name = (configDict["name"] as? String) ?? (dict["name"] as? String) else {
                return nil
            }
            let descDict = configDict["descriptor"] as? [String: Any] ?? [:]
            let digest = (descDict["digest"] as? String) ?? (dict["id"] as? String) ?? "sha256:unknown"
            let mediaType = (descDict["mediaType"] as? String) ?? "application/vnd.oci.image.index.v1+json"
            let annotations = (descDict["annotations"] as? [String: String]) ?? [:]
            let creationDate = parseDateValue(configDict["creationDate"]) ?? Date()

            var variants: [ImageVariantModel] = []
            if let variantsArr = dict["variants"] as? [[String: Any]] {
                for v in variantsArr {
                    let plat = v["platform"] as? [String: Any] ?? [:]
                    let os = (plat["os"] as? String) ?? "linux"
                    let arch = (plat["architecture"] as? String) ?? "arm64"
                    let variantName = plat["variant"] as? String
                    let vDigest = (v["digest"] as? String) ?? digest
                    let size = Int64((v["size"] as? Int) ?? 0)

                    let ociConfigWrapper = v["config"] as? [String: Any] ?? [:]
                    let createdStr = ociConfigWrapper["created"] as? String
                    let innerCfg = ociConfigWrapper["config"] as? [String: Any] ?? ociConfigWrapper
                    let entrypoint = innerCfg["Entrypoint"] as? [String] ?? innerCfg["entrypoint"] as? [String]
                    let cmd = innerCfg["Cmd"] as? [String] ?? innerCfg["cmd"] as? [String]
                    let env = innerCfg["Env"] as? [String] ?? innerCfg["env"] as? [String]
                    let workingDir = innerCfg["WorkingDir"] as? String ?? innerCfg["workingDir"] as? String
                    let user = innerCfg["User"] as? String ?? innerCfg["user"] as? String
                    let labels = (innerCfg["Labels"] as? [String: String]) ?? (innerCfg["labels"] as? [String: String]) ?? [:]
                    var exposedPorts: [String] = []
                    if let expMap = innerCfg["ExposedPorts"] as? [String: Any] {
                        exposedPorts = Array(expMap.keys).sorted()
                    }

                    var diffIDs: [String] = []
                    if let rootfs = ociConfigWrapper["rootfs"] as? [String: Any],
                       let ids = rootfs["diff_ids"] as? [String] {
                        diffIDs = ids
                    }

                    var historyLayers: [ImageHistoryLayer] = []
                    if let histArr = ociConfigWrapper["history"] as? [[String: Any]] {
                        historyLayers = histArr.map { h in
                            ImageHistoryLayer(
                                created: h["created"] as? String,
                                createdBy: h["created_by"] as? String ?? h["createdBy"] as? String,
                                comment: h["comment"] as? String,
                                emptyLayer: (h["empty_layer"] as? Bool) ?? false
                            )
                        }
                    }

                    variants.append(ImageVariantModel(
                        os: os,
                        architecture: arch,
                        variant: variantName,
                        digest: vDigest,
                        sizeBytes: size,
                        created: createdStr,
                        entrypoint: entrypoint,
                        cmd: cmd,
                        env: env,
                        workingDir: workingDir,
                        user: user,
                        exposedPorts: exposedPorts,
                        labels: labels,
                        layerDiffIDs: diffIDs,
                        history: historyLayers
                    ))
                }
            }

            let prettyJSON: String?
            if let rawData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                prettyJSON = String(data: rawData, encoding: .utf8)
            } else {
                prettyJSON = nil
            }

            return ImageModel(
                fullReference: name,
                digest: digest,
                mediaType: mediaType,
                creationDate: creationDate,
                variants: variants,
                annotations: annotations,
                rawInspectJSON: prettyJSON
            )
        }
    }

    // MARK: - 6. Networks (`container network list --format json` & `container network inspect`)

    public static func parseNetworks(jsonString: String) throws -> [NetworkModel] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" { return [] }
        guard let data = trimmed.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw parserError("Expected JSON array of networks.")
        }

        return array.compactMap { dict in
            let configDict = dict["configuration"] as? [String: Any] ?? dict
            let statusDict = dict["status"] as? [String: Any] ?? [:]
            guard let id = (configDict["name"] as? String) ?? (configDict["id"] as? String) ?? (dict["id"] as? String) else {
                return nil
            }
            let mode = (configDict["mode"] as? String) ?? "nat"
            let plugin = (configDict["plugin"] as? String) ?? "container-network-vmnet"
            let ipv4Subnet = (statusDict["ipv4Subnet"] as? String)
                ?? (configDict["ipv4Subnet"] as? String)
                ?? (configDict["subnet"] as? String)
                ?? "192.168.64.0/24"
            let ipv4Gateway = (statusDict["ipv4Gateway"] as? String) ?? ""
            let ipv6Subnet = (statusDict["ipv6Subnet"] as? String) ?? (configDict["ipv6Subnet"] as? String)
            let creationDate = parseDateValue(configDict["creationDate"]) ?? Date()
            let labels = (configDict["labels"] as? [String: String]) ?? [:]
            let options = (configDict["options"] as? [String: String]) ?? [:]

            let prettyJSON: String?
            if let rawData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                prettyJSON = String(data: rawData, encoding: .utf8)
            } else {
                prettyJSON = nil
            }

            return NetworkModel(
                id: id,
                mode: mode,
                plugin: plugin,
                ipv4Subnet: ipv4Subnet,
                ipv4Gateway: ipv4Gateway,
                ipv6Subnet: ipv6Subnet,
                creationDate: creationDate,
                labels: labels,
                options: options,
                rawInspectJSON: prettyJSON
            )
        }
    }

    // MARK: - 7. Volumes (`container volume list --format json` & `container volume inspect`)

    public static func parseVolumes(jsonString: String) throws -> [VolumeModel] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" { return [] }
        guard let data = trimmed.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw parserError("Expected JSON array of volumes.")
        }

        return array.compactMap { dict in
            let configDict = dict["configuration"] as? [String: Any] ?? dict
            guard let name = (configDict["name"] as? String) ?? (dict["id"] as? String) else {
                return nil
            }
            let driver = (configDict["driver"] as? String) ?? "local"
            let format = (configDict["format"] as? String) ?? "ext4"
            let source = (configDict["source"] as? String) ?? ""
            let creationDate = parseDateValue(configDict["creationDate"] ?? configDict["createdAt"]) ?? Date()
            let labels = (configDict["labels"] as? [String: String]) ?? [:]
            let options = (configDict["options"] as? [String: String]) ?? [:]
            let sizeInBytes: UInt64?
            if let s = configDict["sizeInBytes"] as? UInt64 {
                sizeInBytes = s
            } else if let sInt = configDict["sizeInBytes"] as? Int {
                sizeInBytes = UInt64(max(0, sInt))
            } else {
                sizeInBytes = nil
            }

            let prettyJSON: String?
            if let rawData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                prettyJSON = String(data: rawData, encoding: .utf8)
            } else {
                prettyJSON = nil
            }

            return VolumeModel(
                id: name,
                driver: driver,
                format: format,
                sourcePath: source,
                creationDate: creationDate,
                sizeInBytes: sizeInBytes,
                labels: labels,
                options: options,
                rawInspectJSON: prettyJSON
            )
        }
    }

    // MARK: - 8. Machines (`container machine list --format json` & `container machine inspect`)

    public static func parseMachines(jsonString: String) throws -> [MachineModel] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" { return [] }
        guard let data = trimmed.data(using: .utf8) else { return [] }

        let jsonObj = try JSONSerialization.jsonObject(with: data)
        let dicts: [[String: Any]]
        if let arr = jsonObj as? [[String: Any]] {
            dicts = arr
        } else if let single = jsonObj as? [String: Any] {
            dicts = [single]
        } else {
            throw parserError("Expected JSON object or array for container machines.")
        }

        return dicts.compactMap { dict in
            let configDict = dict["configuration"] as? [String: Any] ?? [:]
            let bootConfig = dict["bootConfig"] as? [String: Any] ?? [:]

            guard let id = (dict["id"] as? String) ?? (configDict["id"] as? String) else {
                return nil
            }
            let statusStr = (dict["status"] as? String) ?? "stopped"
            let isDefault = (dict["default"] as? Bool) ?? false
            let ipAddress = dict["ipAddress"] as? String
            let cpus = (dict["cpus"] as? Int) ?? (bootConfig["cpus"] as? Int) ?? 4

            var memoryBytes: UInt64 = 8_589_934_592
            if let m = dict["memory"] as? UInt64 {
                memoryBytes = m
            } else if let mInt = dict["memory"] as? Int {
                memoryBytes = UInt64(max(0, mInt))
            }

            var diskSizeBytes: UInt64? = nil
            if let d = dict["diskSize"] as? UInt64 {
                diskSizeBytes = d
            } else if let dInt = dict["diskSize"] as? Int {
                diskSizeBytes = UInt64(max(0, dInt))
            }

            let createdDate = parseDateValue(dict["createdDate"])
            let startedDate = parseDateValue(dict["startedDate"])

            var imageRef: String? = nil
            if let imgObj = configDict["image"] as? [String: Any] {
                imageRef = imgObj["reference"] as? String
            }
            let homeMountRaw = (bootConfig["homeMount"] as? String) ?? "rw"
            let homeMount = HomeMountMode(rawValue: homeMountRaw) ?? .rw
            let virt = (bootConfig["virtualization"] as? Bool) ?? false
            let kernelPath = bootConfig["kernelPath"] as? String
            let username = (configDict["userSetup"] as? [String: Any])?["username"] as? String

            let prettyJSON: String?
            if let rawData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                prettyJSON = String(data: rawData, encoding: .utf8)
            } else {
                prettyJSON = nil
            }

            return MachineModel(
                id: id,
                status: ContainerState(rawRuntimeState: statusStr),
                isDefault: isDefault,
                ipAddress: ipAddress,
                cpus: cpus,
                memoryBytes: memoryBytes,
                diskSizeBytes: diskSizeBytes,
                createdDate: createdDate,
                startedDate: startedDate,
                imageReference: imageRef,
                homeMount: homeMount,
                virtualizationEnabled: virt,
                kernelPath: kernelPath,
                username: username,
                rawInspectJSON: prettyJSON
            )
        }
    }

    // MARK: - 9. Registries (`container registry list --format json`)

    public static func parseRegistries(jsonString: String) throws -> [RegistryModel] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" { return [] }
        guard let data = trimmed.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw parserError("Expected JSON array of registries.")
        }

        return array.compactMap { dict in
            guard let hostname = (dict["name"] as? String) ?? (dict["id"] as? String) ?? (dict["hostname"] as? String) else {
                return nil
            }
            let username = (dict["username"] as? String) ?? ""
            let creationDate = parseDateValue(dict["creationDate"]) ?? Date()
            let modificationDate = parseDateValue(dict["modificationDate"]) ?? creationDate
            return RegistryModel(
                hostname: hostname,
                username: username,
                isAuthenticated: true,
                creationDate: creationDate,
                modificationDate: modificationDate
            )
        }
    }

    // MARK: - 10. Disk Usage (`container system df --format json`)

    public static func parseDiskUsage(jsonString: String) throws -> DiskUsageSummary {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return DiskUsageSummary()
        }
        return try makeJSONDecoder().decode(DiskUsageSummary.self, from: data)
    }

    // MARK: - 11. System Properties (`container system property list --format json`)

    public static func parseSystemProperties(jsonString: String) throws -> SystemProperties {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SystemProperties()
        }

        let buildDict = dict["build"] as? [String: Any] ?? [:]
        let containerDict = dict["container"] as? [String: Any] ?? [:]
        let dnsDict = dict["dns"] as? [String: Any] ?? [:]
        let kernelDict = dict["kernel"] as? [String: Any] ?? [:]
        let networkDict = dict["network"] as? [String: Any] ?? [:]
        let registryDict = dict["registry"] as? [String: Any] ?? [:]
        let vminitDict = dict["vminit"] as? [String: Any] ?? [:]

        return SystemProperties(
            build: .init(
                cpus: (buildDict["cpus"] as? Int) ?? 2,
                memory: (buildDict["memory"] as? String) ?? "2048mb",
                rosetta: (buildDict["rosetta"] as? Bool) ?? true,
                image: (buildDict["image"] as? String) ?? "ghcr.io/apple/container-builder-shim/builder:0.13.1"
            ),
            container: .init(
                cpus: (containerDict["cpus"] as? Int) ?? 4,
                memory: (containerDict["memory"] as? String) ?? "1gb"
            ),
            dns: .init(domain: dnsDict["domain"] as? String),
            kernel: .init(
                binaryPath: kernelDict["binaryPath"] as? String,
                url: kernelDict["url"] as? String,
                digest: kernelDict["digest"] as? String
            ),
            network: .init(
                subnet: networkDict["subnet"] as? String,
                subnetv6: networkDict["subnetv6"] as? String
            ),
            registry: .init(domain: (registryDict["domain"] as? String) ?? "docker.io"),
            vminit: .init(image: (vminitDict["image"] as? String) ?? "ghcr.io/apple/containerization/vminit:0.34.0")
        )
    }

    // MARK: - 12. Builder Status (`container builder status --format json`)

    public static func parseBuilderStatus(jsonString: String) throws -> BuilderStatusModel {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" || trimmed.lowercased().contains("builder is not running") {
            return BuilderStatusModel(isRunning: false)
        }
        let containers = try parseContainers(jsonString: trimmed)
        guard let builder = containers.first else {
            return BuilderStatusModel(isRunning: false)
        }
        return BuilderStatusModel(
            isRunning: builder.state == .running,
            id: builder.id,
            imageReference: builder.imageReference,
            state: builder.rawState,
            ipAddress: builder.primaryIPv4,
            cpus: builder.configuration.cpus,
            memoryBytes: builder.configuration.memoryInBytes
        )
    }

    // MARK: - Helpers

    private static func parseDateValue(_ anyVal: Any?) -> Date? {
        if let str = anyVal as? String {
            let isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = isoFractional.date(from: str) { return d }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: str) { return d }
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let d = df.date(from: str) { return d }
        } else if let num = anyVal as? Double {
            if num < 1_000_000_000 {
                return Date(timeIntervalSinceReferenceDate: num)
            }
            return Date(timeIntervalSince1970: num)
        }
        return nil
    }

    private static func parserError(_ msg: String) -> LadaError {
        LadaError(
            category: .internalError,
            explanation: msg,
            suggestedRemediation: "Ensure the installed `container` CLI version is compatible with Låda.",
            isRetryable: false
        )
    }
}

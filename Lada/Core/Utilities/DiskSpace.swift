import Foundation

/// Capacity of the drive that holds the container runtime's data.
public struct DiskSpaceSnapshot: Equatable, Sendable {
    public let totalBytes: Int64
    public let availableBytes: Int64

    public init(totalBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }

    /// Reads the volume containing `path` (or its nearest existing parent). "Available" is the
    /// space for important data, which includes purgeable space, as Finder reports it.
    public static func read(path: String) -> DiskSpaceSnapshot? {
        var url = URL(fileURLWithPath: path)
        while !FileManager.default.fileExists(atPath: url.path), url.path != "/" { url.deleteLastPathComponent() }
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        return DiskSpaceSnapshot(totalBytes: Int64(total), availableBytes: max(0, available))
    }
}

/// The drive split into what the runtime uses (images, containers, volumes), everything else, and
/// free space, for the dashboard's donut chart.
public enum DiskBreakdown {
    public struct Segment: Identifiable, Equatable, Sendable {
        public enum Kind: String, Sendable { case images, containers, volumes, other, free }
        public var id: Kind { kind }
        public let kind: Kind
        public let label: String
        public let bytes: Int64
    }

    public static func segments(runtime: DiskUsageSummary, disk: DiskSpaceSnapshot) -> [Segment] {
        let images = Int64(clamping: runtime.images.sizeInBytes)
        let containers = Int64(clamping: runtime.containers.sizeInBytes)
        let volumes = Int64(clamping: runtime.volumes.sizeInBytes)
        let used = max(0, disk.totalBytes - disk.availableBytes)
        // Sparse volumes can report more than they occupy; never let "other" go negative.
        let other = max(0, used - images - containers - volumes)
        return [
            Segment(kind: .images, label: "Images", bytes: images),
            Segment(kind: .containers, label: "Containers", bytes: containers),
            Segment(kind: .volumes, label: "Volumes", bytes: volumes),
            Segment(kind: .other, label: "Other files", bytes: other),
            Segment(kind: .free, label: "Free", bytes: disk.availableBytes)
        ]
    }
}

/// A container's own disk: its root filesystem is a sparse `rootfs.ext4` image (512 GiB logical
/// size on `container` 1.6) in the runtime's data folder. "Used" is what the image really occupies
/// on the Mac; "free" is what it can still grow into, which is the smaller of the image's remaining
/// capacity and the Mac's free space.
public struct ContainerDiskSnapshot: Equatable, Sendable {
    public let usedBytes: Int64
    public let capacityBytes: Int64
    public let freeBytes: Int64
    /// True when the Mac's free space, not the image size, is what limits growth.
    public let limitedByHostDisk: Bool

    public static func make(allocatedBytes: Int64, logicalSizeBytes: Int64, hostAvailableBytes: Int64) -> ContainerDiskSnapshot {
        let used = max(0, allocatedBytes)
        let capacity = max(used, logicalSizeBytes)
        let imageRoom = capacity - used
        let host = max(0, hostAvailableBytes)
        return ContainerDiskSnapshot(
            usedBytes: used,
            capacityBytes: capacity,
            freeBytes: min(imageRoom, host),
            limitedByHostDisk: host < imageRoom
        )
    }

    /// `<data root>/containers/<id>/rootfs.ext4`.
    public static func rootfsPath(dataRoot: String, containerID: String) -> String {
        ((dataRoot as NSString).appendingPathComponent("containers") as NSString)
            .appendingPathComponent(containerID)
            .appending("/rootfs.ext4")
    }

    /// Nil when the image doesn't exist (simulation mode, or a container being created).
    public static func read(rootfsPath: String, hostAvailableBytes: Int64) -> ContainerDiskSnapshot? {
        let url = URL(fileURLWithPath: rootfsPath)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]),
              let logical = values.fileSize, let allocated = values.totalFileAllocatedSize else { return nil }
        return make(allocatedBytes: Int64(allocated), logicalSizeBytes: Int64(logical), hostAvailableBytes: hostAvailableBytes)
    }
}

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(Darwin)
import Darwin
#endif

/// Empirical decoding and touch-model constants.
///
/// One value is shared through ``KeyboardTuningConfig/current``. `SpatialTouchModel`,
/// `GlideDecoderActor`, and the keyboard controller read that instance so a
/// device experiment changes one place.
///
/// Beam score fusion, applied to each surviving path:
///
/// `finalScore = (spatialWeight * normalizedSpatial) + (frequencyWeight * logFrequency)`
///
/// `normalizedSpatial` is the path's cumulative spatial log-probability divided
/// by its length. `logFrequency` is `-log(rank + 10)` from the lexicon rank, so
/// a more common word contributes a larger (less negative) term.
/// `spatialWeight` (0.65) favors the finger path; `frequencyWeight` (0.35)
/// favors common words. The two weights are complementary and sum to 1.
public struct KeyboardTuningConfig: Sendable, Equatable {
    /// Weight of the length-normalized spatial log-probability in the beam score.
    public var spatialWeight: Float
    /// Weight of `-log(rank + 10)` in the beam score.
    public var frequencyWeight: Float
    /// Gaussian σ, in points, for keys that are not on an outer column.
    public var baseSigma: Float
    /// Multiplier applied to `baseSigma` for the first and last letter of each
    /// row. On the English layout those columns are Q/A/Z and P/L/M. A value
    /// above 1 widens the Gaussian so a touch that lands just outside the
    /// keyboard still reaches the edge key.
    public var edgeKeySigmaMultiplier: Float
    /// Number of beam paths kept after each frame. Clamped to 4...64.
    public var beamWidth: Int
    /// Minimum interval between decoded touch frames, in milliseconds.
    /// 8 ms matches a 120 Hz ProMotion frame.
    public var frameThrottleIntervalMs: Double
    /// Minimum finger travel, in points, before a touch stops being a tap and
    /// becomes a glide. Layout pitch may raise the effective distance, but it
    /// never drops below this floor.
    public var glideActivationThresholdPoints: CGFloat
    /// When true, debug builds record `phys_footprint` and the average frame
    /// decode time. Release builds compile the sampler out, so this flag cannot
    /// enable it there.
    public var diagnosticsEnabled: Bool

    public static let current = KeyboardTuningConfig()

    public init(
        spatialWeight: Float = 0.65,
        frequencyWeight: Float = 0.35,
        baseSigma: Float = 34.0,
        edgeKeySigmaMultiplier: Float = 1.25,
        beamWidth: Int = 16,
        frameThrottleIntervalMs: Double = 8,
        glideActivationThresholdPoints: CGFloat = 12,
        diagnosticsEnabled: Bool = KeyboardTuningConfig.defaultDiagnosticsEnabled
    ) {
        self.spatialWeight = spatialWeight.isFinite ? spatialWeight : 0.65
        self.frequencyWeight = frequencyWeight.isFinite ? frequencyWeight : 0.35
        self.baseSigma = max(1, baseSigma.isFinite ? baseSigma : 34)
        self.edgeKeySigmaMultiplier = max(1, edgeKeySigmaMultiplier.isFinite ? edgeKeySigmaMultiplier : 1)
        self.beamWidth = min(64, max(4, beamWidth))
        let interval = frameThrottleIntervalMs.isFinite ? frameThrottleIntervalMs : 8
        self.frameThrottleIntervalMs = min(50, max(1, interval))
        let travel = glideActivationThresholdPoints.isFinite ? glideActivationThresholdPoints : 12
        self.glideActivationThresholdPoints = min(48, max(7, travel))
        self.diagnosticsEnabled = diagnosticsEnabled
    }

    /// Frame throttle expressed in seconds for the decoder's timestamp check.
    public var frameThrottleInterval: TimeInterval { frameThrottleIntervalMs / 1_000 }

    /// Letters that sit on the outer column of any installed layout.
    public static let edgeColumnKeys: Set<String> = {
        var keys: Set<String> = []
        for language in KeyboardLanguage.allCases {
            for row in language.rows {
                if let first = row.first { keys.insert(first) }
                if let last = row.last { keys.insert(last) }
            }
        }
        return keys
    }()

    public func isEdgeColumn(_ key: String) -> Bool {
        Self.edgeColumnKeys.contains(key.lowercased())
    }

    /// σ used for `key`. Outer-column keys use `baseSigma * edgeKeySigmaMultiplier`.
    public func sigma(for key: String, base: Float? = nil) -> Float {
        let resolved = max(1, (base ?? baseSigma).isFinite ? (base ?? baseSigma) : baseSigma)
        return isEdgeColumn(key) ? resolved * edgeKeySigmaMultiplier : resolved
    }

    private static var defaultDiagnosticsEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

/// Debug-only sample of the keyboard process footprint and frame decode time.
///
/// Release builds keep the type so call sites compile, but `record` is a no-op
/// and `physicalFootprintBytes` stays nil. The footprint reading uses
/// `task_info(..., TASK_VM_INFO)` and `phys_footprint`, which is the ledger
/// Jetsam consults.
public final class KeyboardFrameDiagnostics: @unchecked Sendable {
    public static let shared = KeyboardFrameDiagnostics()

    public struct Snapshot: Sendable, Equatable {
        public var physicalFootprintBytes: UInt64?
        public var averageMilliseconds: Double
        public var sampleCount: Int
    }

    private let lock = NSLock()
    private var ring = [Double](repeating: 0, count: 32)
    private var count = 0
    private var cursor = 0

    public func record(nanoseconds: UInt64) {
        #if DEBUG
        let milliseconds = Double(nanoseconds) / 1_000_000
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        lock.lock()
        ring[cursor] = milliseconds
        cursor = (cursor + 1) % ring.count
        if count < ring.count { count += 1 }
        let shouldLog = cursor == 0 && count == ring.count
        let snapshot = lockedSnapshot()
        lock.unlock()
        if shouldLog {
            let footprint = snapshot.physicalFootprintBytes.map { String(format: "%.2f MB", Double($0) / 1_048_576) } ?? "unavailable"
            print(String(format: "GlassType diagnostics: phys_footprint %@, average frame decode %.3f ms (%d samples)", footprint, snapshot.averageMilliseconds, snapshot.sampleCount))
        }
        #else
        _ = nanoseconds
        #endif
    }

    public func snapshot() -> Snapshot {
        #if DEBUG
        lock.lock()
        let value = lockedSnapshot()
        lock.unlock()
        return value
        #else
        return Snapshot(physicalFootprintBytes: nil, averageMilliseconds: 0, sampleCount: 0)
        #endif
    }

    public func reset() {
        lock.lock()
        count = 0
        cursor = 0
        lock.unlock()
    }

    private func lockedSnapshot() -> Snapshot {
        let samples = count
        var total = 0.0
        if samples > 0 {
            for index in 0..<samples { total += ring[index] }
        }
        return Snapshot(
            physicalFootprintBytes: Self.physicalFootprintBytes(),
            averageMilliseconds: samples > 0 ? total / Double(samples) : 0,
            sampleCount: samples
        )
    }

    /// Resident physical footprint in bytes, or nil where `task_vm_info` is unavailable.
    public static func physicalFootprintBytes() -> UInt64? {
        #if DEBUG && canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
        #else
        return nil
        #endif
    }
}

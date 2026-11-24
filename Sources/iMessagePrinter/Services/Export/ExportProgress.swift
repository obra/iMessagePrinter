import Foundation

struct ExportProgress {
    enum Phase {
        case preparing
        case rendering
        case images
        case compressing
        case finishing
    }

    var phase: Phase
    var fraction: Double
    var processedMessages: Int
    var totalMessages: Int
    var processedImages: Int
    var totalImages: Int
    var estimatedRemaining: TimeInterval?
}

struct ExportProgressEstimator {
    private let totalMessages: Int
    private let totalImages: Int
    private let totalUnits: Double
    private let now: () -> TimeInterval
    private let startedAt: TimeInterval
    private let startSample: (time: TimeInterval, units: Double)
    private var phase: ExportProgress.Phase = .preparing
    private var processedMessages = 0
    private var processedImages = 0
    private var fractionRange: ClosedRange<Double> = 0...1
    private var recentSamples: [(time: TimeInterval, units: Double)] = []

    init(
        totalMessages: Int,
        totalImages: Int,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        let messages = max(0, totalMessages)
        let images = max(0, totalImages)
        self.totalMessages = messages
        self.totalImages = images
        self.totalUnits = Double(messages) + 3.0 * Double(images)
        self.now = now
        let start = now()
        self.startedAt = start
        self.startSample = (start, 0)
    }

    mutating func setPhase(_ phase: ExportProgress.Phase) {
        self.phase = phase
    }

    /// Map this estimator's local 0...1 progress into a slice of the whole
    /// export so separate planning and rendering runs never move backward.
    mutating func setFractionRange(_ range: ClosedRange<Double>) {
        fractionRange = max(0, range.lowerBound)...min(1, max(range.lowerBound, range.upperBound))
    }

    mutating func messageCompleted() {
        processedMessages += 1
        recordSample()
    }

    mutating func imageCompleted() {
        processedImages += 1
        recordSample()
    }

    private var completedUnits: Double {
        Double(processedMessages) + 3.0 * Double(processedImages)
    }

    private mutating func recordSample() {
        recentSamples.append((now(), completedUnits))
        if recentSamples.count > 20 {
            recentSamples.removeFirst(recentSamples.count - 20)
        }
    }

    var snapshot: ExportProgress {
        let localFraction: Double
        if totalUnits > 0 {
            localFraction = min(max(completedUnits / totalUnits, 0), 1)
        } else {
            localFraction = (processedMessages + processedImages) > 0 ? 1 : 0
        }
        let fraction = fractionRange.lowerBound
            + localFraction * (fractionRange.upperBound - fractionRange.lowerBound)

        var rate: Double = 0
        if let last = recentSamples.last {
            let baseline = recentSamples.first(where: { $0.time < last.time }) ?? startSample
            if last.time > baseline.time {
                rate = (last.units - baseline.units) / (last.time - baseline.time)
            }
        }

        let remaining: TimeInterval?
        if localFraction >= 0.1, localFraction < 1, rate > 0 {
            remaining = (totalUnits - completedUnits) / rate
        } else {
            remaining = nil
        }

        return ExportProgress(
            phase: phase,
            fraction: fraction,
            processedMessages: processedMessages,
            totalMessages: totalMessages,
            processedImages: processedImages,
            totalImages: totalImages,
            estimatedRemaining: remaining
        )
    }
}

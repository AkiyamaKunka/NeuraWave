import Foundation

/// Wall-clock bookkeeping for a session that can be paused: how long it has
/// actually played and, when it has an end (sleep timer, focus program), how
/// long is left. Paused time never counts, so a paused session can't expire
/// underneath you. A pure value type: every query takes `now`, which keeps
/// it deterministic in tests.
public struct SessionClock: Equatable {
    private let startedAt: Date
    private var pausedTotal: TimeInterval = 0
    private var pausedAt: Date?
    /// Total playing time the session lasts; nil = open-ended.
    public private(set) var duration: TimeInterval?

    public init(startedAt: Date, duration: TimeInterval?) {
        self.startedAt = startedAt
        self.duration = duration
    }

    public var isPaused: Bool { pausedAt != nil }

    /// Time actually played: wall time since start minus every pause,
    /// including one in progress.
    public func elapsed(at now: Date) -> TimeInterval {
        let currentPause = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - pausedTotal - currentPause)
    }

    /// Playing time left before the session ends; nil when open-ended.
    public func remaining(at now: Date) -> TimeInterval? {
        duration.map { max(0, $0 - elapsed(at: now)) }
    }

    public func isFinished(at now: Date) -> Bool {
        remaining(at: now).map { $0 <= 0 } ?? false
    }

    public mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        pausedAt = now
    }

    public mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        pausedTotal += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    /// Restart the countdown: `seconds` more playing time from `now` (nil =
    /// no end). Time already played is kept for progress displays, so Now
    /// Playing shows e.g. 20:00 of 50:00 after picking 30 min twenty minutes in.
    public mutating func setRemaining(_ seconds: TimeInterval?, at now: Date) {
        duration = seconds.map { elapsed(at: now) + $0 }
    }
}

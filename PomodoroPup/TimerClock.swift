import Foundation

/// Wall time assigns calendar days; monotonic time measures a running phase.
protocol TimerClock {
    var now: Date { get }
    var uptime: TimeInterval { get }
}

struct SystemTimerClock: TimerClock {
    var now: Date { Date() }
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

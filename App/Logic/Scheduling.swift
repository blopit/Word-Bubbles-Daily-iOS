import Foundation

/// A handle on delayed work.
@MainActor
final class ScheduledWork {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

/// Delayed work on the main actor. Everything timed in the game goes through this, so tests can run on a virtual clock.
@MainActor
protocol Scheduling: AnyObject {
    @discardableResult
    func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) -> ScheduledWork
}

@MainActor
final class MainScheduler: Scheduling {
    @discardableResult
    func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        let handle = ScheduledWork()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated {
                if !handle.isCancelled { work() }
            }
        }
        return handle
    }
}

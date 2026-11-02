/// A finger on the board, ported from the web game's pointer handlers. The UI hit-tests each touch with
/// `BoardLayout.hitTest` and passes the bubble id, or nil when the touch is on no bubble.
public struct SwipeTracker {
    private struct Gesture {
        var added: [String]
        var last: String
    }

    private var gesture: Gesture?

    public init() {}

    public var isActive: Bool { gesture != nil }

    /// A tap on a picked bubble puts it back. Otherwise it is picked and a swipe begins, unless that pick ended a word.
    @discardableResult
    public mutating func pointerDown(hit id: String?, session: inout GameSession) -> [GameEvent] {
        guard let id, !session.progress.done, !session.progress.consumed.contains(id) else { return [] }
        if session.chain.contains(id) {
            let events = session.removeFromChain(id)
            gesture = nil
            return events
        }
        let events = session.addToChain(id)
        if events.isEmpty || events.contains(where: \.endsGesture) { return events }
        gesture = Gesture(added: [id], last: id)
        return events
    }

    /// Sliding back onto the previous bubble undoes the last one. Re-entering older ones is ignored.
    @discardableResult
    public mutating func pointerMove(hit id: String?, session: inout GameSession) -> [GameEvent] {
        guard var current = gesture, let id, id != current.last, !session.progress.consumed.contains(id) else { return [] }
        if let index = current.added.firstIndex(of: id) {
            guard index == current.added.count - 2 else { return [] }
            let undone = current.added.removeLast()
            current.last = id
            gesture = current
            let events = session.removeFromChain(undone)
            if events.contains(where: \.endsGesture) { gesture = nil }
            return events
        }
        if session.chain.contains(id) { return [] }
        let events = session.addToChain(id)
        guard !events.isEmpty else { return [] }
        current.added.append(id)
        current.last = id
        gesture = events.contains(where: \.endsGesture) ? nil : current
        return events
    }

    public mutating func pointerUp(session: GameSession) {
        gesture = nil
        session.saveNow()
    }
}

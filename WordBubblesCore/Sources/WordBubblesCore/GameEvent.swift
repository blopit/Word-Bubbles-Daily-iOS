public enum FlashTone: String, Equatable, Sendable {
    case good, hint, bad, secret
}

/// A short message over the board. In the web game it clears after 1.9 seconds.
public struct Flash: Equatable, Sendable {
    public let text: String
    public let tone: FlashTone

    public init(text: String, tone: FlashTone) {
        self.text = text
        self.tone = tone
    }
}

/// What a mutator did, for the UI to turn into animation, sound and haptics. State has already changed.
/// Events come in the order the web game shows their flashes, so when several flash, the last one should stay up.
public enum GameEvent: Equatable, Sendable {
    /// `chainLength` and `combo` pick the sound's pitch.
    case picked(id: String, chainLength: Int, combo: Int)
    /// Plays the put-back sound. Only sent when the put-back didn't complete anything.
    case unpicked(ids: [String])
    case wordLocked(wordIndex: Int, word: String, ids: [String], gained: Int, combo: Int, isTutorial: Bool, completesBoard: Bool)
    case bonusCollected(word: String, isSecret: Bool, points: Int, ids: [String])
    /// A bonus banked on the way to a hidden word. The tiles stay, so the player can keep spelling.
    case bonusInline(word: String, isSecret: Bool, points: Int)
    case bonusAlreadyFound(word: String)
    /// The picked bubbles are a word's pieces in the wrong order.
    case nearMiss(isTutorial: Bool)
    case tooManyLetters
    /// `wasCombo` is true when a run of 2 or more ended, which plays the crack sound.
    case comboBroken(wasCombo: Bool)
    case starEarned(stars: Int)
    /// A hint showed the word's first `chunks`.
    case hintRevealed(wordIndex: Int, chunks: [String], firstHint: Bool)
    /// A hint showed the last piece, so the word locked on its own.
    case wordRevealed(wordIndex: Int, word: String, ids: [String], points: Int, firstHint: Bool)
    case shuffled
    case finished

    private static func noMedal(_ firstHint: Bool) -> String {
        firstHint ? " · no medal" : ""
    }

    /// The message this event shows, as the web game builds it. Bonus flashes leave out the word: on iOS found bonus
    /// words stay private until the score screen.
    public var flash: Flash? {
        switch self {
        case .picked, .unpicked, .comboBroken, .shuffled, .finished:
            return nil
        case let .wordLocked(_, word, _, gained, combo, isTutorial, completesBoard):
            if completesBoard { return nil }
            if isTutorial { return Flash(text: word + " ✓", tone: .good) }
            let suffix = combo >= 2 ? " · combo ×\(Scoring.multiplier(combo))!" : ""
            return Flash(text: "\(word) +\(gained)\(suffix)", tone: .good)
        case let .bonusCollected(_, isSecret, points, _), let .bonusInline(_, isSecret, points):
            return isSecret
                ? Flash(text: "◆ Secret +\(points)", tone: .secret)
                : Flash(text: "✦ Bonus +\(points)", tone: .hint)
        case .bonusAlreadyFound:
            return Flash(text: "Bonus already found", tone: .hint)
        case let .nearMiss(isTutorial):
            let text = isTutorial
                ? "Right bubbles. Now tap them in order: RA → IN → BOW"
                : "Right bubbles, wrong order. Tap a tile to put it back"
            return Flash(text: text, tone: .hint)
        case .tooManyLetters:
            return Flash(text: "Too many letters", tone: .bad)
        case let .starEarned(stars):
            return Flash(text: stars == 1 ? "You earned a star!" : "\(stars) stars!", tone: .good)
        case let .hintRevealed(_, chunks, firstHint):
            return Flash(text: "Starts with " + chunks.joined(separator: " · ") + " …" + Self.noMedal(firstHint), tone: .hint)
        case let .wordRevealed(_, word, _, points, firstHint):
            return Flash(text: "Revealed: \(word) +\(points)" + Self.noMedal(firstHint), tone: .hint)
        }
    }

    /// True when this ends a swipe in progress.
    var endsGesture: Bool {
        switch self {
        case .wordLocked, .bonusCollected: return true
        default: return false
        }
    }
}

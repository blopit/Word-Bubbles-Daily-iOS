import Foundation
import WordBubblesCore

enum LockTone: Equatable, Sendable {
    case accent, gold, secret
}

/// The state change that lands once a word's animation has played out.
enum Commit: Equatable, Sendable {
    case word(index: Int, word: String, ids: [String], combo: Int)
    case bonus(word: String, tone: LockTone, ids: [String])
    case reveal(index: Int, ids: [String])
}

/// One thing that happens on the timeline after a batch of events.
enum Cue: Equatable, Sendable {
    case sound(SoundEffect)
    case haptic(Haptic)
    case flash(Flash)
    case shakeTray
    case bumpScore
    /// Hides the letter count and Clear before a bonus word fuses.
    case freezeTray
    case fuseTray(LockTone, ids: [String])
    case popBubbles([String])
    case commit(Commit)
    case landSlot(Int)
    /// A bonus word has reached the score, which is where it stays until the result.
    case landScore
    case celebrate
    case showResult
    case releaseInput
}

struct TimedCue: Equatable, Sendable {
    let at: Double
    let cue: Cue
}

/// Turns the core's events into the website's timeline. Pure, so the sequencing can be tested without any views.
///
/// A word: tiles fuse at 200ms, at 620ms the tray empties and the fused word flies to its slot, and its flash and any
/// finish wait for it to land. A bonus word takes a further 200ms. A reveal pops its bubbles for 420ms.
enum Choreography {
    static let fuseDelay = 0.2
    static let lockCommit = 0.62
    static let bonusFreeze = 0.2
    static let bonusFuse = 0.4
    static let bonusCommit = 0.82
    static let revealCommit = 0.42
    /// One frame or so for a slot to lay out before a flight reads where it is.
    static let frameLead = 0.02

    /// `flight` is the length of a flight; 0 with Reduce Motion, when nothing flies.
    static func timeline(for events: [GameEvent], flight: Double) -> [TimedCue] {
        var cues: [TimedCue] = []
        func add(_ at: Double, _ cue: Cue) { cues.append(TimedCue(at: at, cue: cue)) }

        let finishes = events.contains(.finished)
        let travel = flight > 0 ? frameLead + flight : 0

        func starCues(_ at: Double, _ event: GameEvent) {
            add(at, .sound(.earn))
            add(at, .bumpScore)
            if let flash = event.flash { add(at, .flash(flash)) }
        }

        func finishCues(_ at: Double) {
            add(at, .sound(.win))
            add(at, .haptic(.finish))
            add(at, .celebrate)
            add(at, .showResult)
            add(at, .releaseInput)
        }

        let deferredStars = events.contains {
            switch $0 {
            case .wordLocked, .bonusCollected: return true
            default: return false
            }
        }
        let stars = events.filter {
            if case .starEarned = $0 { return true }
            return false
        }

        for event in events {
            switch event {
            case let .picked(_, chainLength, combo):
                add(0, .sound(.pick(index: chainLength - 1, lift: combo)))
                add(0, .haptic(.pick))
            case .unpicked:
                add(0, .sound(.unpick))
            case let .wordLocked(index, word, ids, _, combo, _, _):
                add(fuseDelay, .fuseTray(.accent, ids: ids))
                add(lockCommit, .sound(.lock(combo: combo)))
                add(lockCommit, .haptic(.lock))
                add(lockCommit, .commit(.word(index: index, word: word, ids: ids, combo: combo)))
                stars.forEach { starCues(lockCommit, $0) }
                let land = lockCommit + travel
                add(land, .landSlot(index))
                if let flash = event.flash { add(land, .flash(flash)) }
                if finishes { finishCues(land) } else { add(lockCommit, .releaseInput) }
            case let .bonusCollected(word, isSecret, _, ids):
                let tone: LockTone = isSecret ? .secret : .gold
                add(bonusFreeze, .freezeTray)
                add(bonusFuse, .fuseTray(tone, ids: ids))
                add(bonusCommit, .commit(.bonus(word: word, tone: tone, ids: ids)))
                add(bonusCommit, .sound(.bonus))
                stars.forEach { starCues(bonusCommit, $0) }
                add(bonusCommit, .releaseInput)
                let land = bonusCommit + travel
                add(land, .landScore)
                if let flash = event.flash { add(land, .flash(flash)) }
            case .bonusInline:
                add(0, .sound(.bonus))
                add(0, .haptic(.lock))
                add(0, .bumpScore)
                if let flash = event.flash { add(0, .flash(flash)) }
            case .bonusAlreadyFound:
                if let flash = event.flash { add(0, .flash(flash)) }
            case .nearMiss:
                add(0, .sound(.near))
                add(0, .shakeTray)
                if let flash = event.flash { add(0, .flash(flash)) }
            case .tooManyLetters:
                add(0, .sound(.wrong))
                add(0, .shakeTray)
                if let flash = event.flash { add(0, .flash(flash)) }
            case let .comboBroken(wasCombo):
                if wasCombo { add(0, .sound(.crack)) }
            case .starEarned:
                if !deferredStars { starCues(0, event) }
            case .hintRevealed:
                add(0, .sound(.hint))
                if let flash = event.flash { add(0, .flash(flash)) }
            case let .wordRevealed(index, _, ids, _, _):
                add(0, .sound(.hint))
                add(0, .popBubbles(ids))
                if let flash = event.flash { add(0, .flash(flash)) }
                add(revealCommit, .commit(.reveal(index: index, ids: ids)))
                if finishes { finishCues(revealCommit) } else { add(revealCommit, .releaseInput) }
            case .shuffled:
                add(0, .sound(.shuffle))
            case .finished:
                break
            }
        }

        // A stable sort: within one moment, cues keep the order above.
        return cues.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    /// How long the board ignores input after these events.
    static func blockDuration(for events: [GameEvent], flight: Double) -> Double {
        timeline(for: events, flight: flight).last { $0.cue == .releaseInput }?.at ?? 0
    }
}

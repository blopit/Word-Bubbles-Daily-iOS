/// One letter chunk on the board. `id` is "wordIndex-chunkIndex", the same form the website stores.
public struct Bubble: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let text: String
    public let wordIndex: Int
    public let chunkIndex: Int
    public var nudge: Int

    public init(id: String, text: String, wordIndex: Int, chunkIndex: Int, nudge: Int) {
        self.id = id
        self.text = text
        self.wordIndex = wordIndex
        self.chunkIndex = chunkIndex
        self.nudge = nudge
    }
}

/// A theme and its hidden words, before they are cut into bubbles.
public struct PuzzleData: Codable, Hashable, Sendable {
    public let theme: String
    public let words: [String]

    public init(theme: String, words: [String]) {
        self.theme = theme
        self.words = words
    }

    enum CodingKeys: String, CodingKey {
        case theme = "t"
        case words = "w"
    }
}

/// A finished board. `bubbles` is in its final shuffled order.
public struct Puzzle: Codable, Hashable, Sendable {
    public let level: Level
    public let theme: String
    public let words: [String]
    public let chunksByWord: [[String]]
    public let bubbles: [Bubble]
    /// Every hidden word can be spelled from the pool in exactly one way.
    public let unique: Bool
    /// No bubble directly follows the next bubble of its word in `bubbles`.
    public let strict: Bool
    /// How many seeds were tried. `nil` for the tutorial, which is hand-built.
    public let attempts: Int?

    public init(
        level: Level, theme: String, words: [String], chunksByWord: [[String]], bubbles: [Bubble],
        unique: Bool, strict: Bool, attempts: Int?
    ) {
        self.level = level
        self.theme = theme
        self.words = words
        self.chunksByWord = chunksByWord
        self.bubbles = bubbles
        self.unique = unique
        self.strict = strict
        self.attempts = attempts
    }
}

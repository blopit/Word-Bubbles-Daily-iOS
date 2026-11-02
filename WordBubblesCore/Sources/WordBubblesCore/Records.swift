import Foundation

public enum RecordTier: String, Hashable, Sendable {
    case world, country, local
}

public struct RecordKey: Equatable, Hashable, Sendable {
    public let tier: RecordTier
    public let id: String
}

/// A posted finish. Times are whole milliseconds.
public struct RecordEntry: Equatable, Hashable, Sendable {
    public let ms: Int
    public let pts: Int

    public init(ms: Int, pts: Int) {
        self.ms = ms
        self.pts = pts
    }
}

/// The record rules. Faster wins, compared to the second; a tie on time goes to the higher score.
public enum Records {
    private static func seconds(_ ms: Int) -> Int { ms / 1000 }

    public static func beats(_ a: RecordEntry, _ b: RecordEntry?) -> Bool {
        guard let b else { return true }
        return seconds(a.ms) < seconds(b.ms) || (seconds(a.ms) == seconds(b.ms) && a.pts > b.pts)
    }

    public static func holds(_ a: RecordEntry, _ b: RecordEntry?) -> Bool {
        guard let b else { return false }
        return seconds(a.ms) < seconds(b.ms) || (seconds(a.ms) == seconds(b.ms) && a.pts >= b.pts)
    }

    /// Times under 0.4s a bubble are impossible, so they are ignored.
    public static func plausible(ms: Double, bubbleCount: Int) -> Bool {
        ms >= Double(bubbleCount * 400)
    }
}

/// A finish to post to the records server.
public struct FinishedBoard: Equatable, Sendable {
    public let day: Int
    public let level: Level
    public let progress: LevelProgress
    public let bubbleCount: Int

    public init(day: Int, level: Level, progress: LevelProgress, bubbleCount: Int) {
        self.day = day
        self.level = level
        self.progress = progress
        self.bubbleCount = bubbleCount
    }
}

/// Which tiers a finish took.
public struct RecordWins: Equatable, Sendable {
    public var world: Bool
    public var country: Bool
    public var local: Bool

    public init(world: Bool = false, country: Bool = false, local: Bool = false) {
        self.world = world
        self.country = country
        self.local = local
    }

    public var any: Bool { world || country || local }
}

/// What a read of one record came back with.
public enum RecordFetch: Equatable, Sendable {
    /// The server answered. Nil means no one has set this record.
    case found(RecordEntry?)
    case failed
}

/// How requests reach the server. Tests supply a fake.
public protocol RecordsTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

public struct URLSessionRecordsTransport: RecordsTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// The shared best times, kept by records.php. Nothing here throws: without a network every call just comes back
/// empty and the game plays on.
public actor RecordsClient {
    public static let defaultURL = URL(string: "https://shrenp.com/word-bubbles/records.php")!

    private static let timeout: TimeInterval = 10
    private static let maxMs = 86_400_000
    private static let minMs = 1000
    private static let maxPoints = 100_000
    /// `encodeURIComponent`'s unreserved characters.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )

    private struct Envelope: Decodable {
        struct Raw: Decodable {
            let ms: Double
            let pts: Lossy<Double>?
        }

        let record: Lossy<Raw>?
        let won: Bool?

        var entry: RecordEntry? {
            guard let raw = record?.value, let ms = Int(exactly: JSMath.round(raw.ms)) else { return nil }
            return RecordEntry(ms: ms, pts: Int(exactly: JSMath.round(raw.pts?.value ?? 0)) ?? 0)
        }
    }

    /// Every record seen so far, by record id.
    public private(set) var records: [String: RecordEntry] = [:]
    /// True once the server has answered. Until then the end card shows no record pills.
    public private(set) var isAvailable = false

    private let transport: any RecordsTransport
    private let baseURL: URL

    public init(transport: any RecordsTransport = URLSessionRecordsTransport(), baseURL: URL = RecordsClient.defaultURL) {
        self.transport = transport
        self.baseURL = baseURL
    }

    /// `records`, or nil while the server has not answered.
    public var snapshot: [String: RecordEntry]? { isAvailable ? records : nil }

    public func fetch(id: String) async -> RecordFetch {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? id
        guard let url = URL(string: baseURL.absoluteString + "?id=" + encoded) else { return .failed }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        guard let envelope = await exchange(request) else { return .failed }
        isAvailable = true
        return .found(envelope.entry)
    }

    /// Reads every tier of a board. Implausible times are ignored. A failed read keeps what was known.
    /// The web game polls this every 30 seconds while a board is open.
    @discardableResult
    public func refresh(day: Int, level: Level, bubbleCount: Int, place: Place) async -> [String: RecordEntry] {
        for key in place.recordKeys(day: day, level: level) {
            guard case let .found(entry) = await fetch(id: key.id) else { continue }
            if let entry, Records.plausible(ms: Double(entry.ms), bubbleCount: bubbleCount) {
                records[key.id] = entry
            } else {
                records[key.id] = nil
            }
        }
        return records
    }

    /// Submits a finish to every tier. Boards that used a hint are never submitted.
    public func submitFinish(_ board: FinishedBoard, place: Place) async -> RecordWins {
        var wins = RecordWins()
        let progress = board.progress
        guard !progress.forfeitedMedal, progress.elapsed != 0 else { return wins }
        let mine = RecordEntry(ms: Int(JSMath.round(progress.elapsed)), pts: progress.points)
        guard
            mine.ms <= Self.maxMs, mine.ms >= Self.minMs, mine.pts <= Self.maxPoints,
            Records.plausible(ms: progress.elapsed, bubbleCount: board.bubbleCount)
        else { return wins }
        for key in place.recordKeys(day: board.day, level: board.level) {
            let won = await submit(mine, id: key.id)
            switch key.tier {
            case .world: wins.world = won
            case .country: wins.country = won
            case .local: wins.local = won
            }
        }
        return wins
    }

    /// The server compares and writes in one step, so this only saves a POST it would refuse.
    private func submit(_ mine: RecordEntry, id: String) async -> Bool {
        guard case let .found(current) = await fetch(id: id), Records.beats(mine, current) else { return false }
        var request = URLRequest(url: baseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["id": id, "ms": mine.ms, "pts": mine.pts]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let envelope = await exchange(request) else { return false }
        if let entry = envelope.entry { records[id] = entry }
        return envelope.won == true
    }

    private func exchange(_ request: URLRequest) async -> Envelope? {
        guard
            let reply = try? await transport.send(request),
            (200..<300).contains(reply.status)
        else { return nil }
        return try? JSONDecoder().decode(Envelope.self, from: reply.data)
    }
}

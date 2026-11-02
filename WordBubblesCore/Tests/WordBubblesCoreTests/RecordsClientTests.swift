import XCTest
@testable import WordBubblesCore

/// Answers each request from a script and remembers what it was asked.
final class FakeTransport: RecordsTransport, @unchecked Sendable {
    enum Reply {
        case ok(String)
        case status(Int, String)
        case offline
    }

    private let lock = NSLock()
    private var script: (URLRequest) -> Reply
    private var seen: [URLRequest] = []

    init(_ script: @escaping (URLRequest) -> Reply) {
        self.script = script
    }

    var requests: [URLRequest] { lock.withLock { seen } }
    var gets: [URLRequest] { requests.filter { $0.httpMethod == "GET" } }
    var posts: [URLRequest] { requests.filter { $0.httpMethod == "POST" } }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let reply = lock.withLock { () -> Reply in
            seen.append(request)
            return script(request)
        }
        switch reply {
        case let .ok(body): return (Data(body.utf8), 200)
        case let .status(code, body): return (Data(body.utf8), code)
        case .offline: throw URLError(.notConnectedToInternet)
        }
    }

    static func body(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    static func postedID(_ request: URLRequest) -> String? { body(request)["id"] as? String }
}

final class RecordsClientTests: XCTestCase {
    let toronto = Place.detect(timeZoneID: "America/Toronto")
    let world = "d7-easy"
    let country = "d7-easy-c-CA"
    let local = "d7-easy-z-America~Toronto"

    func board(ms: Double = 20_000, pts: Int = 300, bubbles: Int = 10) -> FinishedBoard {
        var p = LevelProgress()
        p.done = true
        p.elapsed = ms
        p.points = pts
        return FinishedBoard(day: 7, level: .easy, progress: p, bubbleCount: bubbles)
    }

    func client(_ transport: FakeTransport) -> RecordsClient {
        RecordsClient(transport: transport)
    }

    func emptyServer() -> FakeTransport {
        FakeTransport { request in
            request.httpMethod == "GET"
                ? .ok(#"{"record":null}"#)
                : .ok(#"{"record":{"ms":20000,"pts":300},"won":true}"#)
        }
    }

    // MARK: Reading

    func testDefaultURLIsTheWebsite() {
        XCTAssertEqual(RecordsClient.defaultURL.absoluteString, "https://shrenp.com/word-bubbles/records.php")
    }

    func testGetBuildsThePercentEncodedURL() async {
        let t = FakeTransport { _ in .ok(#"{"record":null}"#) }
        _ = await client(t).fetch(id: "d7-easy-z-America~Toronto")
        XCTAssertEqual(t.gets.first?.url?.absoluteString, "https://shrenp.com/word-bubbles/records.php?id=d7-easy-z-America~Toronto")
        _ = await client(t).fetch(id: "d7-easy-z-Etc~GMT+5")
        XCTAssertEqual(t.gets.last?.url?.absoluteString, "https://shrenp.com/word-bubbles/records.php?id=d7-easy-z-Etc~GMT%2B5")
    }

    func testFetchParsesAnEntry() async {
        let t = FakeTransport { _ in .ok(#"{"record":{"ms":41200,"pts":120}}"#) }
        let reply = await client(t).fetch(id: world)
        XCTAssertEqual(reply, .found(RecordEntry(ms: 41200, pts: 120)))
    }

    func testFetchShapes() async {
        let cases: [(String, RecordFetch)] = [
            (#"{"record":null}"#, .found(nil)),
            (#"{"other":1}"#, .found(nil)),
            (#"{"record":{"ms":5000}}"#, .found(RecordEntry(ms: 5000, pts: 0))),
            (#"{"record":{"ms":5000,"pts":"x"}}"#, .found(RecordEntry(ms: 5000, pts: 0))),
            (#"{"record":{"ms":"soon"}}"#, .found(nil)),
            (#"{"record":{"ms":true}}"#, .found(nil)),
            (#"{"record":7}"#, .found(nil)),
            (#"{"record":{"ms":1e300,"pts":1}}"#, .found(nil)),
            (#"{"record":{"ms":5000,"pts":1e300}}"#, .found(RecordEntry(ms: 5000, pts: 0))),
            ("not json", .failed),
            ("", .failed),
            ("[]", .failed),
        ]
        for (body, expected) in cases {
            let t = FakeTransport { _ in .ok(body) }
            let reply = await client(t).fetch(id: world)
            XCTAssertEqual(reply, expected, body)
        }
    }

    func testFetchFailures() async {
        for reply in [FakeTransport.Reply.status(500, #"{"error":"server error"}"#), .status(404, ""), .offline] {
            let result = await client(FakeTransport { _ in reply }).fetch(id: world)
            XCTAssertEqual(result, .failed)
        }
    }

    func testRefreshReadsEveryTier() async {
        let t = FakeTransport { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("-c-CA") { return .ok(#"{"record":{"ms":6000,"pts":1}}"#) }
            if url.hasSuffix("Toronto") { return .ok(#"{"record":null}"#) }
            return .ok(#"{"record":{"ms":5000,"pts":2}}"#)
        }
        let c = client(t)
        let records = await c.refresh(day: 7, level: .easy, bubbleCount: 10, place: toronto)
        XCTAssertEqual(records, [world: RecordEntry(ms: 5000, pts: 2), country: RecordEntry(ms: 6000, pts: 1)])
        XCTAssertEqual(t.gets.count, 3)
        let available = await c.isAvailable
        XCTAssertTrue(available)
    }

    func testRefreshDropsImplausibleRecords() async {
        let c = client(FakeTransport { _ in .ok(#"{"record":{"ms":3999,"pts":2}}"#) })
        let records = await c.refresh(day: 7, level: .easy, bubbleCount: 10, place: .nowhere)
        XCTAssertEqual(records, [:])
    }

    func testRefreshForgetsARemovedRecordButKeepsItWhenOffline() async {
        final class Box: @unchecked Sendable { var reply = FakeTransport.Reply.ok(#"{"record":{"ms":5000,"pts":2}}"#) }
        let box = Box()
        let c = client(FakeTransport { _ in box.reply })
        _ = await c.refresh(day: 7, level: .easy, bubbleCount: 10, place: .nowhere)
        box.reply = .offline
        let offline = await c.refresh(day: 7, level: .easy, bubbleCount: 10, place: .nowhere)
        XCTAssertEqual(offline, [world: RecordEntry(ms: 5000, pts: 2)])
        box.reply = .ok(#"{"record":null}"#)
        let gone = await c.refresh(day: 7, level: .easy, bubbleCount: 10, place: .nowhere)
        XCTAssertEqual(gone, [:])
    }

    func testOfflineMeansNoSnapshot() async {
        let c = client(FakeTransport { _ in .offline })
        _ = await c.refresh(day: 7, level: .easy, bubbleCount: 10, place: toronto)
        let snapshot = await c.snapshot
        XCTAssertNil(snapshot, "with no server the end card shows no record pills")
    }

    func testSnapshotOnceTheServerAnswers() async {
        let c = client(FakeTransport { _ in .ok(#"{"record":null}"#) })
        _ = await c.refresh(day: 7, level: .easy, bubbleCount: 10, place: .nowhere)
        let snapshot = await c.snapshot
        XCTAssertEqual(snapshot, [:])
    }

    // MARK: Submitting

    func testPostShape() async {
        let t = emptyServer()
        let wins = await client(t).submitFinish(board(ms: 20_000.5, pts: 300), place: .nowhere)
        XCTAssertTrue(wins.world)
        let post = t.posts[0]
        XCTAssertEqual(post.url?.absoluteString, "https://shrenp.com/word-bubbles/records.php")
        XCTAssertEqual(post.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let text = String(decoding: post.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(text.contains("20001"), text)
        XCTAssertFalse(text.contains("."), "ms is an integer, and no id here has a dot: " + text)
        let body = FakeTransport.body(post)
        XCTAssertEqual(body["id"] as? String, world)
        XCTAssertEqual(body["ms"] as? Int, 20001)
        XCTAssertEqual(body["pts"] as? Int, 300)
        XCTAssertEqual(body.count, 3)
    }

    func testEachTierIsSubmittedInOrder() async {
        let t = emptyServer()
        let wins = await client(t).submitFinish(board(), place: toronto)
        XCTAssertEqual(wins, RecordWins(world: true, country: true, local: true))
        XCTAssertEqual(t.posts.compactMap(FakeTransport.postedID), [world, country, local])
        XCTAssertEqual(t.gets.count, 3)
    }

    func testAFreshGetThatWeDontBeatSkipsThePost() async {
        let t = FakeTransport { _ in .ok(#"{"record":{"ms":5000,"pts":999}}"#) }
        let wins = await client(t).submitFinish(board(), place: .nowhere)
        XCTAssertEqual(wins, RecordWins())
        XCTAssertEqual(t.posts.count, 0)
    }

    func testTieOnTimeGoesToHigherScore() async {
        let t = FakeTransport { request in
            request.httpMethod == "GET"
                ? .ok(#"{"record":{"ms":20900,"pts":100}}"#)
                : .ok(#"{"record":{"ms":20000,"pts":300},"won":true}"#)
        }
        let wins = await client(t).submitFinish(board(), place: .nowhere)
        XCTAssertTrue(wins.world)
    }

    func testWinningOnlySomeTiers() async {
        let t = FakeTransport { request in
            if request.httpMethod == "POST" { return .ok(#"{"record":{"ms":20000,"pts":300},"won":true}"#) }
            let url = request.url?.absoluteString ?? ""
            return url.hasSuffix("easy") ? .ok(#"{"record":{"ms":5000,"pts":9}}"#) : .ok(#"{"record":null}"#)
        }
        let wins = await client(t).submitFinish(board(), place: toronto)
        XCTAssertEqual(wins, RecordWins(world: false, country: true, local: true))
    }

    func testServerSaysNoEvenThoughGetLookedGood() async {
        let t = FakeTransport { request in
            request.httpMethod == "GET"
                ? .ok(#"{"record":null}"#)
                : .ok(#"{"record":{"ms":9000,"pts":1},"won":false}"#)
        }
        let c = client(t)
        let wins = await c.submitFinish(board(), place: .nowhere)
        XCTAssertFalse(wins.world)
        let records = await c.records
        XCTAssertEqual(records[world], RecordEntry(ms: 9000, pts: 1), "the server's answer is the record now")
    }

    func testAWinIsCached() async {
        let c = client(emptyServer())
        _ = await c.submitFinish(board(), place: .nowhere)
        let records = await c.records
        XCTAssertEqual(records[world], RecordEntry(ms: 20_000, pts: 300))
    }

    func testPostFailuresAreSilentLosses() async {
        let replies: [FakeTransport.Reply] = [.status(500, "oops"), .offline, .ok("garbage"), .ok(#"{"record":null}"#), .status(400, #"{"error":"bad ms"}"#)]
        for reply in replies {
            let t = FakeTransport { request in request.httpMethod == "GET" ? .ok(#"{"record":null}"#) : reply }
            let wins = await client(t).submitFinish(board(), place: toronto)
            XCTAssertEqual(wins, RecordWins())
        }
    }

    func testFailedGetSkipsThePost() async {
        for reply in [FakeTransport.Reply.offline, .status(500, ""), .ok("<html>")] {
            let t = FakeTransport { _ in reply }
            let wins = await client(t).submitFinish(board(), place: toronto)
            XCTAssertEqual(wins, RecordWins())
            XCTAssertEqual(t.posts.count, 0)
        }
    }

    func testImplausibleTimesGoNowhere() async {
        let t = emptyServer()
        let c = client(t)
        var wins = await c.submitFinish(board(ms: 3_999), place: toronto)
        XCTAssertEqual(wins, RecordWins())
        wins = await c.submitFinish(board(ms: 0), place: toronto)
        XCTAssertEqual(wins, RecordWins())
        wins = await c.submitFinish(board(ms: 3_999.6), place: toronto)
        XCTAssertEqual(wins, RecordWins(), "judged before rounding, as in the JS")
        XCTAssertEqual(t.requests.count, 0)
    }

    func testServerLimitsAreRespected() async {
        let t = emptyServer()
        let c = client(t)
        var wins = await c.submitFinish(board(ms: 900, bubbles: 1), place: .nowhere)
        XCTAssertEqual(wins, RecordWins(), "records.php wants ms >= 1000")
        wins = await c.submitFinish(board(pts: 100_001), place: .nowhere)
        XCTAssertEqual(wins, RecordWins(), "records.php wants pts <= 100000")
        wins = await c.submitFinish(board(ms: 86_400_001), place: .nowhere)
        XCTAssertEqual(wins, RecordWins(), "records.php wants ms <= a day")
        XCTAssertEqual(t.requests.count, 0)
        wins = await c.submitFinish(board(ms: 1000, pts: 100_000, bubbles: 1), place: .nowhere)
        XCTAssertTrue(wins.world)
    }

    func testAForfeitedBoardSubmitsNothing() async {
        var finished = board()
        var p = finished.progress
        p.usedHint = true
        finished = FinishedBoard(day: 7, level: .easy, progress: p, bubbleCount: 10)
        let t = emptyServer()
        let wins = await client(t).submitFinish(finished, place: toronto)
        XCTAssertEqual(wins, RecordWins())
        XCTAssertEqual(t.requests.count, 0)
    }

    // MARK: Into the save file

    func applied(_ wins: RecordWins) -> (changed: Bool, record: LevelProgress) {
        let store = ProgressStore(url: tempStoreURL(), today: 7)
        store.setRecord(board().progress, day: 7, level: .easy)
        let changed = store.applyRecordWins(wins, day: 7, level: .easy)
        return (changed, store.record(day: 7, level: .easy))
    }

    func testWorldWinSetsNewRecord() {
        let result = applied(RecordWins(world: true, country: true, local: true))
        XCTAssertTrue(result.changed)
        XCTAssertTrue(result.record.newRecord)
        XCTAssertNil(result.record.newRegional)
    }

    func testCountryThenLocalSetNewRegional() {
        XCTAssertEqual(applied(RecordWins(world: false, country: true, local: true)).record.newRegional, .country)
        XCTAssertEqual(applied(RecordWins(world: false, country: false, local: true)).record.newRegional, .local)
    }

    func testNoWinsChangesNothing() {
        let result = applied(RecordWins())
        XCTAssertFalse(result.changed)
        XCTAssertFalse(result.record.newRecord)
        XCTAssertNil(result.record.newRegional)
    }

    func testRecordWinsPersist() {
        let url = tempStoreURL()
        let store = ProgressStore(url: url, today: 7)
        store.setRecord(board().progress, day: 7, level: .easy)
        store.applyRecordWins(RecordWins(world: true), day: 7, level: .easy)
        XCTAssertTrue(ProgressStore(url: url, today: 7).record(day: 7, level: .easy).newRecord)
    }

    func testAFullGameOfflineStaysPlayable() async {
        let clock = FakeClock()
        var s = realSession(day: 7, clock: clock)
        clock.advance(ms: 20_000)
        s.solveAll()
        let finished = s.finishedBoard
        XCTAssertNotNil(finished)
        let c = client(FakeTransport { _ in .offline })
        let wins = await c.submitFinish(finished!, place: toronto)
        XCTAssertEqual(wins, RecordWins())
        XCTAssertTrue(s.progress.done)
    }
}

import StoreKitTest
import XCTest
@testable import WordBubbles

/// Buys, restores and refunds Word Bubbles+ against the local StoreKit configuration.
@MainActor
final class PlusStoreTests: XCTestCase {
    var session: SKTestSession!
    var defaults: UserDefaults!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "WordBubbles")
        session.disableDialogs = true
        session.clearTransactions()
        defaults = UserDefaults(suiteName: "wb-plus-store-\(UUID().uuidString)")
    }

    func testLoadsTheProductAndItsPrice() async {
        let plus = PlusStore(defaults: defaults)
        await plus.loadProduct()
        XCTAssertEqual(plus.product?.id, PlusStore.productID)
        XCTAssertNotNil(plus.price)
    }

    func testBuyingUnlocksAndIsRemembered() async {
        let plus = PlusStore(defaults: defaults)
        XCTAssertFalse(plus.isUnlocked)
        await plus.purchase()
        XCTAssertTrue(plus.isUnlocked)
        XCTAssertEqual(plus.status, .idle)
        XCTAssertTrue(PlusStore(defaults: defaults).isUnlocked)
    }

    func testRefreshFindsAPurchaseMadeElsewhere() async throws {
        try await session.buyProduct(identifier: PlusStore.productID)
        let plus = PlusStore(defaults: defaults)
        await plus.refresh()
        XCTAssertTrue(plus.isUnlocked)
    }

    func testRefundTakesItBack() async throws {
        let plus = PlusStore(defaults: defaults)
        await plus.purchase()
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: UInt(transaction.identifier))
        await plus.refresh()
        XCTAssertFalse(plus.isUnlocked)
    }
}

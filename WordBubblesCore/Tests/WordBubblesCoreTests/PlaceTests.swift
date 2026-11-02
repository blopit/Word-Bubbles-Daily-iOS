import XCTest
@testable import WordBubblesCore

final class PlaceTests: XCTestCase {
    func testTorontoFromNorthAmerica() {
        let p = Place.detect(timeZoneID: "America/Toronto")
        XCTAssertEqual(p.continent, PlaceContinent(code: "NA", name: "North America"))
        XCTAssertEqual(p.country, PlaceCountry(code: "CA", name: "Canada", flag: "🇨🇦"))
        XCTAssertEqual(p.local, PlaceLocal(code: "America~Toronto", name: "ON & QC"))
    }

    func testAliasZoneSharesItsLocalCode() {
        XCTAssertEqual(Place.detect(timeZoneID: "America/Thunder_Bay").local?.code, "America~Toronto")
    }

    func testAliasInSpaceSeparatedCountryList() {
        // Africa/Timbuktu is the second zone listed for ML
        XCTAssertEqual(Place.detect(timeZoneID: "Africa/Timbuktu").country?.code, "ML")
    }

    func testOneZoneCountryHasNoLocal() {
        let p = Place.detect(timeZoneID: "Asia/Tokyo")
        XCTAssertEqual(p.country?.name, "Japan")
        XCTAssertEqual(p.country?.flag, "🇯🇵")
        XCTAssertNil(p.local)
        XCTAssertEqual(p.continent?.code, "AS")
    }

    func testContinents() {
        let expected = [
            "America/New_York": "NA", "America/Sao_Paulo": "SA", "America/Argentina/Buenos_Aires": "SA",
            "America/Bogota": "SA", "Europe/Paris": "EU", "Atlantic/Canary": "EU", "Africa/Cairo": "AF",
            "Asia/Tokyo": "AS", "Indian/Maldives": "AS", "Australia/Sydney": "OC", "Pacific/Auckland": "OC",
        ]
        for (zone, code) in expected {
            XCTAssertEqual(Place.detect(timeZoneID: zone).continent?.code, code, zone)
        }
    }

    func testPrefixRegexQuirkIsPorted() {
        // /^America\/(…Bahia…)/ has no end anchor, so Mexico's Bahia_Banderas lands in South America
        XCTAssertEqual(Place.detect(timeZoneID: "America/Bahia_Banderas").continent?.code, "SA")
    }

    func testUnknownZones() {
        for zone in ["", "UTC", "Mars/Olympus"] {
            let p = Place.detect(timeZoneID: zone)
            XCTAssertNil(p.continent, zone)
            XCTAssertNil(p.country, zone)
            XCTAssertNil(p.local, zone)
            XCTAssertEqual(p.recordKeys(day: 7, level: .easy).map(\.id), ["d7-easy"])
        }
    }

    func testLocalAreaNamedLikeItsCountryIsRenamed() {
        XCTAssertEqual(Place.detect(timeZoneID: "America/Sao_Paulo").local, PlaceLocal(code: "America~Sao_Paulo", name: "Sao Paulo area"))
        XCTAssertEqual(Place.detect(timeZoneID: "Europe/Lisbon").local?.name, "Lisbon area")
        XCTAssertEqual(Place.detect(timeZoneID: "Asia/Kuala_Lumpur").local?.name, "Kuala Lumpur area")
    }

    func testRecordKeysMatchTheWebsiteIDs() {
        let keys = Place.detect(timeZoneID: "America/Toronto").recordKeys(day: 51, level: .hard)
        XCTAssertEqual(keys, [
            RecordKey(tier: .world, id: "d51-hard"),
            RecordKey(tier: .country, id: "d51-hard-c-CA"),
            RecordKey(tier: .local, id: "d51-hard-z-America~Toronto"),
        ])
    }

    func testEveryZoneProducesIDsTheServerAccepts() throws {
        let regex = try NSRegularExpression(pattern: "^d\\d{1,5}-(easy|medium|hard)(-[cz]-[A-Za-z0-9~_.+-]{1,60})?$")
        XCTAssertGreaterThan(Place.knownTimeZoneIDs.count, 300)
        for zone in Place.knownTimeZoneIDs {
            let place = Place.detect(timeZoneID: zone)
            XCTAssertNotNil(place.country, zone)
            for key in place.recordKeys(day: 99999, level: .medium) {
                let range = NSRange(key.id.startIndex..., in: key.id)
                XCTAssertNotNil(regex.firstMatch(in: key.id, range: range), key.id)
            }
        }
    }
}

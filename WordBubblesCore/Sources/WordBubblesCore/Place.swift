import Foundation

public struct PlaceContinent: Equatable, Sendable {
    public let code: String
    public let name: String
}

public struct PlaceCountry: Equatable, Sendable {
    public let code: String
    public let name: String
    public let flag: String
}

public struct PlaceLocal: Equatable, Sendable {
    public let code: String
    public let name: String
}

/// Where the player is, from the device's time zone only. The game never sees a location.
public struct Place: Equatable, Sendable {
    public let continent: PlaceContinent?
    public let country: PlaceCountry?
    /// The part of the country this zone covers, such as "ON & QC". Nil for one-zone countries.
    public let local: PlaceLocal?

    public init(continent: PlaceContinent? = nil, country: PlaceCountry? = nil, local: PlaceLocal? = nil) {
        self.continent = continent
        self.country = country
        self.local = local
    }

    /// No place known: only world records apply.
    public static let nowhere = Place()

    private struct Zones: Decodable {
        let country: [String: String]
        let local: [String: [String]]
    }

    private static let zones: Zones = {
        guard
            let url = Bundle.module.url(forResource: "timezones", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let value = try? JSONDecoder().decode(Zones.self, from: data)
        else { preconditionFailure("Bundled timezones.json is missing or malformed") }
        return value
    }()

    private static let countryByZone: [String: String] = {
        var map: [String: String] = [:]
        for (code, list) in zones.country {
            for zone in list.split(separator: " ") { map[String(zone)] = code }
        }
        return map
    }()

    /// Every zone with a known country.
    static var knownTimeZoneIDs: [String] { Array(countryByZone.keys) }

    private static let southAmerica = [
        "Argentina", "Sao_Paulo", "Buenos_Aires", "Lima", "Bogota", "Santiago", "Caracas", "La_Paz", "Montevideo",
        "Asuncion", "Guayaquil", "Cayenne", "Paramaribo", "Guyana", "Fortaleza", "Recife", "Manaus", "Belem", "Bahia",
        "Maceio", "Araguaina", "Cuiaba", "Campo_Grande", "Porto_Velho", "Boa_Vista", "Rio_Branco", "Eirunepe",
        "Santarem", "Noronha", "Punta_Arenas",
    ]

    private static func continent(zone: String, area: String) -> PlaceContinent? {
        switch area {
        case "America":
            let south = southAmerica.contains { zone.hasPrefix("America/" + $0) }
            return south
                ? PlaceContinent(code: "SA", name: "South America")
                : PlaceContinent(code: "NA", name: "North America")
        case "Europe", "Atlantic": return PlaceContinent(code: "EU", name: "Europe")
        case "Africa": return PlaceContinent(code: "AF", name: "Africa")
        case "Asia", "Indian": return PlaceContinent(code: "AS", name: "Asia")
        case "Australia", "Pacific": return PlaceContinent(code: "OC", name: "Oceania")
        default: return nil
        }
    }

    private static func flag(_ code: String) -> String {
        var view = String.UnicodeScalarView()
        for scalar in code.unicodeScalars {
            if let flagScalar = Unicode.Scalar(0x1F1E6 + scalar.value - 65) { view.append(flagScalar) }
        }
        return String(view)
    }

    public static func detect(timeZoneID zone: String = TimeZone.current.identifier) -> Place {
        let parts = zone.components(separatedBy: "/")
        let place = continent(zone: zone, area: parts[0])
        guard let code = countryByZone[zone] else { return Place(continent: place) }
        let name = Locale(identifier: "en").localizedString(forRegionCode: code) ?? code
        let country = PlaceCountry(code: code, name: name, flag: flag(code))
        var local: PlaceLocal?
        if let entry = zones.local[zone], entry.count == 2 {
            var area = entry[1]
            if area.lowercased() == name.lowercased() {
                area = (parts.last ?? zone).replacingOccurrences(of: "_", with: " ") + " area"
            }
            local = PlaceLocal(code: entry[0], name: area)
        }
        return Place(continent: place, country: country, local: local)
    }

    /// The record ids for a board. They are shared with the website, so their form must not change.
    public func recordKeys(day: Int, level: Level) -> [RecordKey] {
        let board = "d\(day)-\(level.rawValue)"
        var keys = [RecordKey(tier: .world, id: board)]
        if let country { keys.append(RecordKey(tier: .country, id: board + "-c-" + country.code)) }
        if let local { keys.append(RecordKey(tier: .local, id: board + "-z-" + local.code)) }
        return keys
    }
}

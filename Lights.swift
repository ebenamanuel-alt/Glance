//  Glance: works with Look and Nod's bulb bridge.
//  When you leave your desk, your lights switch off. When you come back, they switch back on.
//  Only after dark (sunset to sunrise, or hours you choose).

import Foundation

// MARK: - Sunrise and sunset

enum Sun {
    /// Sunrise or sunset for a day, in UTC hours (for example 6.42 means 06:25 UTC). nil in polar day or night.
    static func utcHours(on date: Date, lat: Double, lon: Double, rising: Bool) -> Double? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let n = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let rad = Double.pi / 180
        let lngHour = lon / 15
        let t = n + ((rising ? 6 : 18) - lngHour) / 24
        let m = 0.9856 * t - 3.289
        var l = m + 1.916 * sin(m * rad) + 0.020 * sin(2 * m * rad) + 282.634
        l = l.truncatingRemainder(dividingBy: 360); if l < 0 { l += 360 }
        var ra = atan(0.91764 * tan(l * rad)) / rad
        ra = ra.truncatingRemainder(dividingBy: 360); if ra < 0 { ra += 360 }
        ra = (ra + (floor(l / 90) * 90 - floor(ra / 90) * 90)) / 15
        let sinDec = 0.39782 * sin(l * rad)
        let cosDec = cos(asin(sinDec))
        let cosH = (cos(90.833 * rad) - sinDec * sin(lat * rad)) / (cosDec * cos(lat * rad))
        guard cosH >= -1, cosH <= 1 else { return nil }
        let h = (rising ? 360 - acos(cosH) / rad : acos(cosH) / rad) / 15
        let tt = h + ra - 0.06571 * t - 6.622
        var ut = (tt - lngHour).truncatingRemainder(dividingBy: 24); if ut < 0 { ut += 24 }
        return ut
    }

    /// Today's sunrise and sunset as real times.
    static func today(lat: Double, lon: Double, now: Date = Date()) -> (rise: Date, set: Date)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let midnight = cal.startOfDay(for: now)
        guard let r = utcHours(on: now, lat: lat, lon: lon, rising: true),
              let s = utcHours(on: now, lat: lat, lon: lon, rising: false) else { return nil }
        return (midnight.addingTimeInterval(r * 3600), midnight.addingTimeInterval(s * 3600))
    }
}

// MARK: - Talking to the bridge

struct BridgeLight: Decodable, Identifiable, Equatable {
    let name: String
    let label: String
    var id: String { name }
}

private struct BridgeDevices: Decodable { let devices: [BridgeLight] }
private struct BridgeStatus: Decodable { let on: Bool? }

enum Bridge {
    static let base = URL(string: "http://127.0.0.1:8765")!

    static func devices() async -> [BridgeLight]? {
        guard let result = try? await URLSession.shared.data(from: base.appendingPathComponent("devices")) else { return nil }
        let data = result.0
        return (try? JSONDecoder().decode(BridgeDevices.self, from: data))?.devices
    }

    /// true or false, or nil if the bridge is too old to say.
    static func isOn(_ name: String) async -> Bool?? {
        let url = base.appendingPathComponent(name).appendingPathComponent("status")
        guard let result = try? await URLSession.shared.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return .none }
        let on: Bool? = (try? JSONDecoder().decode(BridgeStatus.self, from: result.0))?.on
        return .some(on)
    }

    @discardableResult
    static func send(_ name: String, _ action: String) async -> Bool {
        let url = base.appendingPathComponent(name).appendingPathComponent(action)
        guard let result = try? await URLSession.shared.data(from: url) else { return false }
        return (result.1 as? HTTPURLResponse)?.statusCode == 200
    }
}

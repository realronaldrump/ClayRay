import Foundation
import CoreGraphics

/// Computes the sun's position (subsolar point) for a given date, and generates
/// a day/night overlay texture for the globe.
enum SunPosition {

    /// Returns the subsolar point (latitude, longitude) where the sun is directly overhead.
    static func subsolarPoint(at date: Date = Date()) -> (lat: Double, lon: Double) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let year = Double(components.year ?? 2024)
        let month = Double(components.month ?? 1)
        let day = Double(components.day ?? 1)
        let hour = Double(components.hour ?? 12)
        let minute = Double(components.minute ?? 0)
        let second = Double(components.second ?? 0)

        // Julian date
        let a = floor((14 - month) / 12)
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        let jdn = day + floor((153 * m + 2) / 5) + 365 * y + floor(y / 4) - floor(y / 100) + floor(y / 400) - 32045
        let jd = jdn + (hour - 12) / 24 + minute / 1440 + second / 86400

        // Days since J2000.0
        let n = jd - 2451545.0

        // Mean longitude and anomaly of the sun
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = ((357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360)) * .pi / 180

        // Ecliptic longitude
        let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)).truncatingRemainder(dividingBy: 360) * .pi / 180

        // Obliquity of the ecliptic
        let epsilon = (23.439 - 0.0000004 * n) * .pi / 180

        // Sun declination (subsolar latitude)
        let declination = asin(sin(epsilon) * sin(lambda)) * 180 / .pi

        // Greenwich Mean Sidereal Time
        let gmst = (280.46061837 + 360.98564736629 * n).truncatingRemainder(dividingBy: 360)

        // Right ascension
        let ra = atan2(cos(epsilon) * sin(lambda), cos(lambda)) * 180 / .pi

        // Subsolar longitude
        var subLon = (ra - gmst).truncatingRemainder(dividingBy: 360)
        if subLon > 180 { subLon -= 360 }
        if subLon < -180 { subLon += 360 }

        return (lat: declination, lon: subLon)
    }

    /// Generate a day/night overlay texture. Dark side is a semi-transparent dark tint.
    /// The terminator line includes a smooth twilight gradient.
    static func generateDayNightOverlay(width: Int = 4096, height: Int = 2048, date: Date = Date()) -> CGImage? {
        let subsolar = subsolarPoint(at: date)
        let subLatRad = subsolar.lat * .pi / 180
        let subLonDeg = subsolar.lon

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Start fully transparent
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // Direct pixel buffer access for performance
        guard let data = ctx.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        for py in 0..<height {
            let v = Double(py) / Double(height)
            let lat = (0.5 - v) * .pi  // -pi/2 to pi/2

            for px in 0..<width {
                let u = Double(px) / Double(width)
                let lon = (u - 0.5) * 2 * .pi  // -pi to pi
                let lonDiff = lon - subLonDeg * .pi / 180

                // Solar elevation angle approximation
                let cosZenith = sin(lat) * sin(subLatRad) + cos(lat) * cos(subLatRad) * cos(lonDiff)

                // cosZenith > 0 = day, < 0 = night
                // Smooth twilight band: civil twilight at ~6° below horizon
                let twilightWidth = 0.12  // ~7° smooth transition
                let darkness: Double
                if cosZenith > twilightWidth {
                    darkness = 0  // Full day
                } else if cosZenith < -twilightWidth {
                    darkness = 1  // Full night
                } else {
                    // Smooth transition through twilight
                    darkness = (1 - (cosZenith + twilightWidth) / (2 * twilightWidth))
                }

                if darkness > 0.01 {
                    let offset = (py * width + px) * 4
                    let alpha = UInt8(min(darkness * 0.55, 0.55) * 255)  // Max 55% opacity for night
                    // Dark blue-black tint
                    buffer[offset + 0] = UInt8(min(darkness * 8, 15))     // R
                    buffer[offset + 1] = UInt8(min(darkness * 12, 20))    // G
                    buffer[offset + 2] = UInt8(min(darkness * 30, 45))    // B
                    buffer[offset + 3] = alpha                             // A
                }
            }
        }

        // Draw terminator line — a subtle glowing edge at the sunset/sunrise boundary
        for py in 0..<height {
            let v = Double(py) / Double(height)
            let lat = (0.5 - v) * .pi

            for px in 0..<width {
                let u = Double(px) / Double(width)
                let lon = (u - 0.5) * 2 * .pi
                let lonDiff = lon - subLonDeg * .pi / 180
                let cosZenith = sin(lat) * sin(subLatRad) + cos(lat) * cos(subLatRad) * cos(lonDiff)

                // Terminator glow band
                let terminatorDist = abs(cosZenith)
                if terminatorDist < 0.04 {
                    let glow = 1.0 - (terminatorDist / 0.04)
                    let offset = (py * width + px) * 4
                    let existing = Double(buffer[offset + 3]) / 255.0
                    // Warm golden terminator glow
                    let glowAlpha = glow * 0.35
                    if glowAlpha > existing {
                        buffer[offset + 0] = UInt8(min(255, Int(Double(buffer[offset + 0]) + glow * 200)))
                        buffer[offset + 1] = UInt8(min(255, Int(Double(buffer[offset + 1]) + glow * 140)))
                        buffer[offset + 2] = UInt8(min(255, Int(Double(buffer[offset + 2]) + glow * 40)))
                        buffer[offset + 3] = UInt8(min(255, Int(glowAlpha * 255)))
                    }
                }
            }
        }

        return ctx.makeImage()
    }
}

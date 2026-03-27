import AppKit
import CoreGraphics
import Foundation

/// Generates procedural textures for the clay globe using direct CGContext rendering.
enum GlobeTextureGenerator {

    // MARK: - Base Clay Texture (Continents + Oceans)

    static func generateBaseTexture(width: Int = 2048, height: Int = 1024, isDark: Bool = false) -> CGImage? {
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

        // Fill ocean base
        let oceanR: CGFloat = isDark ? 0.18 : 0.16
        let oceanG: CGFloat = isDark ? 0.28 : 0.38
        let oceanB: CGFloat = isDark ? 0.32 : 0.44
        ctx.setFillColor(CGColor(red: oceanR, green: oceanG, blue: oceanB, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Add ocean depth variation with large soft splotches
        addOceanVariation(to: ctx, width: width, height: height, isDark: isDark)

        // Draw continents with multiple fill passes for clay depth
        let landR: CGFloat = isDark ? 0.52 : 0.76
        let landG: CGFloat = isDark ? 0.48 : 0.42
        let landB: CGFloat = isDark ? 0.44 : 0.30
        let landColor = CGColor(red: landR, green: landG, blue: landB, alpha: 1)

        for continent in WorldMapData.continents {
            let path = continentPath(continent, width: width, height: height)

            // Base land fill
            ctx.setFillColor(landColor)
            ctx.addPath(path)
            ctx.fillPath()

            // Slightly darker interior for depth
            let innerColor = CGColor(red: landR * 0.88, green: landG * 0.85, blue: landB * 0.82, alpha: 0.5)
            ctx.setFillColor(innerColor)
            ctx.addPath(path)
            ctx.fillPath()

            // Continent edge highlight (rim of raised clay)
            let edgeColor = CGColor(red: min(landR * 1.15, 1), green: min(landG * 1.12, 1), blue: min(landB * 1.1, 1), alpha: 0.7)
            ctx.setStrokeColor(edgeColor)
            ctx.setLineWidth(3.5)
            ctx.addPath(path)
            ctx.strokePath()

            // Outer shadow edge for embossed feel
            let shadowColor = CGColor(red: landR * 0.55, green: landG * 0.5, blue: landB * 0.45, alpha: 0.4)
            ctx.setStrokeColor(shadowColor)
            ctx.setLineWidth(2.0)
            ctx.addPath(path)
            // Offset slightly for shadow effect
            ctx.translateBy(x: 1.5, y: -1.5)
            ctx.strokePath()
            ctx.translateBy(x: -1.5, y: 1.5)
        }

        // Add clay surface noise — thumbprints and imperfections
        addClayNoise(to: ctx, width: width, height: height, isDark: isDark)
        addThumbprints(to: ctx, width: width, height: height, isDark: isDark)

        return ctx.makeImage()
    }

    // MARK: - Normal Map (Clay Imperfections)

    static func generateNormalMap(width: Int = 2048, height: Int = 1024) -> CGImage? {
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

        // Default flat normal = (0.5, 0.5, 1.0) in tangent space
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 1.0, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Random subtle bumps — clay imperfections
        var gen = SystemRandomNumberGenerator()
        for _ in 0..<1200 {
            let cx = CGFloat.random(in: 0...CGFloat(width), using: &gen)
            let cy = CGFloat.random(in: 0...CGFloat(height), using: &gen)
            let radius = CGFloat.random(in: 6...35, using: &gen)
            let intensity = CGFloat.random(in: 0.03...0.12, using: &gen)

            let nx = 0.5 + intensity * CGFloat.random(in: -1...1, using: &gen)
            let ny = 0.5 + intensity * CGFloat.random(in: -1...1, using: &gen)

            let bumpColor = CGColor(red: nx, green: ny, blue: 0.92, alpha: 0.4)
            ctx.setFillColor(bumpColor)
            ctx.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
        }

        // Continent edge bumps (raised ridges)
        for continent in WorldMapData.continents {
            let path = continentPath(continent, width: width, height: height)

            // Outward-pointing normal at edges = raised
            ctx.setStrokeColor(CGColor(red: 0.58, green: 0.58, blue: 0.85, alpha: 0.7))
            ctx.setLineWidth(5)
            ctx.addPath(path)
            ctx.strokePath()

            // Inner normal for depth
            ctx.setStrokeColor(CGColor(red: 0.42, green: 0.42, blue: 0.92, alpha: 0.4))
            ctx.setLineWidth(2)
            ctx.addPath(path)
            ctx.strokePath()
        }

        // Thumbprint ring patterns in normal space
        for _ in 0..<60 {
            let cx = CGFloat.random(in: 0...CGFloat(width), using: &gen)
            let cy = CGFloat.random(in: 0...CGFloat(height), using: &gen)
            let radius = CGFloat.random(in: 20...80, using: &gen)

            for ring in stride(from: radius * 0.3, through: radius, by: 4) {
                let intensity = CGFloat.random(in: 0.01...0.04, using: &gen)
                let color = CGColor(red: 0.5 + intensity, green: 0.5 - intensity, blue: 0.95, alpha: 0.15)
                ctx.setStrokeColor(color)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: CGRect(x: cx - ring, y: cy - ring, width: ring * 2, height: ring * 2))
            }
        }

        return ctx.makeImage()
    }

    // MARK: - UV Overlay Texture

    static func generateUVOverlay(
        width: Int = 4096,
        height: Int = 2048,
        uvPoints: [(lat: Double, lon: Double, uvi: Double)] = [],
        userLat: Double? = nil,
        userLon: Double? = nil,
        userUVI: Double? = nil
    ) -> CGImage? {
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

        var allPoints = uvPoints
        if let lat = userLat, let lon = userLon, let uvi = userUVI, uvi > 0 {
            allPoints.append((lat: lat, lon: lon, uvi: uvi))
        }

        // Determine if we have a user location to highlight
        let isUserPoint: (Double, Double) -> Bool = { lat, lon in
            guard let uLat = userLat, let uLon = userLon else { return false }
            return abs(lat - uLat) < 1 && abs(lon - uLon) < 1
        }

        for point in allPoints {
            guard point.uvi > 0.1 else { continue }

            let uv = WorldMapData.latLonToUV(lat: point.lat, lon: point.lon)
            let x = CGFloat(uv.u * Double(width))
            let y = CGFloat((1 - uv.v) * Double(height))
            let uvi = point.uvi
            let isUser = isUserPoint(point.lat, point.lon)

            let (r, g, b) = uvGlowRGB(for: uvi)

            // Tighter radii for denser grid — sharper detail per data point
            let radius = CGFloat(45 + uvi * 15)
            let alpha = CGFloat(min(0.10 + uvi * 0.03, 0.55))

            // Soft radial glow — wide falloff for seamless blending
            let colors: [CGColor] = [
                CGColor(red: r, green: g, blue: b, alpha: alpha),
                CGColor(red: r, green: g, blue: b, alpha: alpha * 0.4),
                CGColor(red: r, green: g, blue: b, alpha: alpha * 0.08),
                CGColor(red: r, green: g, blue: b, alpha: 0)
            ]
            let locations: [CGFloat] = [0, 0.25, 0.6, 1.0]

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) {
                ctx.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: x, y: y), startRadius: 0,
                    endCenter: CGPoint(x: x, y: y), endRadius: radius,
                    options: []
                )
            }

            // Hot center spot only for user's location or extreme UV
            if isUser && uvi >= 3 {
                let hotAlpha = CGFloat(min((uvi - 2) * 0.08, 0.4))
                let hotRadius = radius * 0.2
                let hotColors: [CGColor] = [
                    CGColor(red: 1, green: 1, blue: min(r + 0.5, 1), alpha: hotAlpha),
                    CGColor(red: r, green: g, blue: b, alpha: hotAlpha * 0.2),
                    CGColor(red: r, green: g, blue: b, alpha: 0)
                ]
                let hotLocs: [CGFloat] = [0, 0.4, 1.0]
                if let hotGrad = CGGradient(colorsSpace: colorSpace, colors: hotColors as CFArray, locations: hotLocs) {
                    ctx.drawRadialGradient(
                        hotGrad,
                        startCenter: CGPoint(x: x, y: y), startRadius: 0,
                        endCenter: CGPoint(x: x, y: y), endRadius: hotRadius,
                        options: []
                    )
                }

                // Cracks only at user location for extreme UV
                if uvi >= 8 {
                    drawCracks(in: ctx, at: CGPoint(x: x, y: y), uvi: uvi, r: r, g: g, b: b)
                }
            }
        }

        return ctx.makeImage()
    }

    // MARK: - Displacement / Height Map

    /// Generate a heightmap for topographic depth: land is light (raised), ocean is dark (depressed).
    /// Mountain ranges get brighter spots for extra relief.
    static func generateHeightMap(width: Int = 2048, height: Int = 1024) -> CGImage? {
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

        // Ocean baseline — mid-gray (no displacement)
        ctx.setFillColor(CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Ocean depth variation — subtle darker patches
        var gen = SystemRandomNumberGenerator()
        for _ in 0..<80 {
            let cx = CGFloat.random(in: 0...CGFloat(width), using: &gen)
            let cy = CGFloat.random(in: 0...CGFloat(height), using: &gen)
            let radius = CGFloat.random(in: 40...150, using: &gen)
            ctx.setFillColor(CGColor(red: 0.28, green: 0.28, blue: 0.28, alpha: 0.3))
            ctx.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
        }

        // Continents raised — lighter gray
        for continent in WorldMapData.continents {
            let path = continentPath(continent, width: width, height: height)

            // Base land height
            ctx.setFillColor(CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1))
            ctx.addPath(path)
            ctx.fillPath()

            // Continental shelf gradient (slightly raised at edges)
            ctx.setStrokeColor(CGColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 0.7))
            ctx.setLineWidth(8)
            ctx.addPath(path)
            ctx.strokePath()
        }

        // Mountain ridges — bright spots at key mountain range areas
        let mountainRanges: [(lat: Double, lon: Double, radius: CGFloat, height: CGFloat)] = [
            (35, -106, 60, 0.82),   // Rockies
            (46, 8, 40, 0.78),      // Alps
            (28, 85, 50, 0.90),     // Himalayas
            (-15, -70, 55, 0.80),   // Andes
            (62, 60, 45, 0.72),     // Urals
            (-5, 37, 30, 0.70),     // East African Rift
            (36, 52, 35, 0.72),     // Iranian Plateau
            (-42, 170, 25, 0.68),   // Southern Alps NZ
        ]

        for mtn in mountainRanges {
            let uv = WorldMapData.latLonToUV(lat: mtn.lat, lon: mtn.lon)
            let x = CGFloat(uv.u * Double(width))
            let y = CGFloat((1 - uv.v) * Double(height))
            let colors: [CGColor] = [
                CGColor(red: mtn.height, green: mtn.height, blue: mtn.height, alpha: 0.8),
                CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0)
            ]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: x, y: y), startRadius: 0,
                    endCenter: CGPoint(x: x, y: y), endRadius: mtn.radius,
                    options: []
                )
            }
        }

        return ctx.makeImage()
    }

    // MARK: - Private Helpers

    private static func continentPath(_ continent: WorldMapData.ContinentPath, width: Int, height: Int) -> CGPath {
        let path = CGMutablePath()
        for (i, point) in continent.points.enumerated() {
            let uv = WorldMapData.latLonToUV(lat: point.lat, lon: point.lon)
            let x = CGFloat(uv.u * Double(width))
            let y = CGFloat((1 - uv.v) * Double(height))
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }

    private static func addOceanVariation(to ctx: CGContext, width: Int, height: Int, isDark: Bool) {
        var gen = SystemRandomNumberGenerator()
        let baseR: CGFloat = isDark ? 0.18 : 0.16
        let baseG: CGFloat = isDark ? 0.28 : 0.38
        let baseB: CGFloat = isDark ? 0.32 : 0.44

        for _ in 0..<150 {
            let cx = CGFloat.random(in: 0...CGFloat(width), using: &gen)
            let cy = CGFloat.random(in: 0...CGFloat(height), using: &gen)
            let radius = CGFloat.random(in: 30...120, using: &gen)
            let variation = CGFloat.random(in: -0.04...0.04, using: &gen)

            let color = CGColor(red: baseR + variation, green: baseG + variation * 0.5, blue: baseB + variation, alpha: 0.3)
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
        }
    }

    private static func addClayNoise(to ctx: CGContext, width: Int, height: Int, isDark: Bool) {
        var gen = SystemRandomNumberGenerator()
        // Fine grain speckle
        for _ in 0..<6000 {
            let x = CGFloat.random(in: 0...CGFloat(width), using: &gen)
            let y = CGFloat.random(in: 0...CGFloat(height), using: &gen)
            let size = CGFloat.random(in: 1...3, using: &gen)
            let brightness = CGFloat.random(in: 0.2...0.8, using: &gen)
            let alpha = CGFloat.random(in: 0.03...0.10, using: &gen)
            ctx.setFillColor(CGColor(red: brightness, green: brightness * 0.9, blue: brightness * 0.8, alpha: alpha))
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }

        // Larger splotches for clay mottling
        for _ in 0..<200 {
            let x = CGFloat.random(in: 0...CGFloat(width), using: &gen)
            let y = CGFloat.random(in: 0...CGFloat(height), using: &gen)
            let size = CGFloat.random(in: 8...25, using: &gen)
            let brightness = CGFloat.random(in: 0.3...0.7, using: &gen)
            ctx.setFillColor(CGColor(red: brightness, green: brightness * 0.85, blue: brightness * 0.7, alpha: 0.06))
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size * CGFloat.random(in: 0.7...1.3, using: &gen)))
        }
    }

    private static func addThumbprints(to ctx: CGContext, width: Int, height: Int, isDark: Bool) {
        var gen = SystemRandomNumberGenerator()
        let baseL: CGFloat = isDark ? 0.45 : 0.65

        // Large thumbprint-like oval impressions
        for _ in 0..<40 {
            let cx = CGFloat.random(in: 0...CGFloat(width), using: &gen)
            let cy = CGFloat.random(in: 0...CGFloat(height), using: &gen)
            let radiusX = CGFloat.random(in: 25...80, using: &gen)
            let radiusY = CGFloat.random(in: 20...60, using: &gen)
            let angle = CGFloat.random(in: 0...CGFloat.pi, using: &gen)

            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: angle)

            // Concentric rings for fingerprint texture
            let ringCount = Int.random(in: 3...8, using: &gen)
            for r in 0..<ringCount {
                let ringRadius = CGFloat(r) / CGFloat(ringCount)
                let rx = radiusX * ringRadius
                let ry = radiusY * ringRadius
                let brightness = baseL + CGFloat.random(in: -0.05...0.05, using: &gen)
                ctx.setStrokeColor(CGColor(red: brightness, green: brightness * 0.88, blue: brightness * 0.75, alpha: 0.06))
                ctx.setLineWidth(CGFloat.random(in: 1...2.5, using: &gen))
                ctx.strokeEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            }

            ctx.restoreGState()
        }
    }

    private static func uvGlowRGB(for uvi: Double) -> (CGFloat, CGFloat, CGFloat) {
        // Smooth interpolation between UV color stops for accurate per-index coloring
        let stops: [(uvi: Double, r: CGFloat, g: CGFloat, b: CGFloat)] = [
            (0,  0.40, 0.45, 0.75),  // Deep cool blue-lavender
            (1,  0.50, 0.55, 0.85),  // Cool lavender
            (2,  0.55, 0.65, 0.80),  // Blue-teal transition
            (3,  0.70, 0.80, 0.35),  // Yellow-green
            (4,  0.90, 0.82, 0.30),  // Golden yellow
            (5,  0.95, 0.75, 0.25),  // Warm amber
            (6,  0.95, 0.55, 0.18),  // Orange
            (7,  0.95, 0.40, 0.15),  // Dark orange
            (8,  0.95, 0.28, 0.10),  // Red-orange
            (9,  0.95, 0.18, 0.08),  // Deep red
            (10, 0.92, 0.10, 0.10),  // Intense red
            (11, 0.90, 0.05, 0.15),  // Crimson
            (12, 1.00, 0.05, 0.20),  // Extreme magenta-red
            (14, 1.00, 0.10, 0.40),  // Ultra-extreme violet-red
        ]
        let clamped = max(0, min(uvi, 14))
        // Find surrounding color stops and interpolate
        var lo = stops[0]
        var hi = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) {
            if clamped >= stops[i].uvi && clamped <= stops[i + 1].uvi {
                lo = stops[i]
                hi = stops[i + 1]
                break
            }
        }
        let range = hi.uvi - lo.uvi
        let t = range > 0 ? CGFloat((clamped - lo.uvi) / range) : 0
        let r = lo.r + (hi.r - lo.r) * t
        let g = lo.g + (hi.g - lo.g) * t
        let b = lo.b + (hi.b - lo.b) * t
        return (r, g, b)
    }

    private static func drawCracks(in ctx: CGContext, at center: CGPoint, uvi: Double, r: CGFloat, g: CGFloat, b: CGFloat) {
        var gen = SystemRandomNumberGenerator()
        let crackCount = Int(uvi - 3)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)

        for _ in 0..<crackCount {
            let angle = CGFloat.random(in: 0...(2 * .pi), using: &gen)
            let length = CGFloat.random(in: 12...40, using: &gen)

            // Jagged crack with midpoint offset
            let mid = CGFloat.random(in: 0.3...0.7, using: &gen)
            let midX = center.x + CGFloat(cos(angle)) * length * mid + CGFloat.random(in: -5...5, using: &gen)
            let midY = center.y + CGFloat(sin(angle)) * length * mid + CGFloat.random(in: -5...5, using: &gen)
            let endX = center.x + CGFloat(cos(angle)) * length
            let endY = center.y + CGFloat(sin(angle)) * length

            ctx.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 0.7))
            ctx.move(to: center)
            ctx.addLine(to: CGPoint(x: midX, y: midY))
            ctx.addLine(to: CGPoint(x: endX, y: endY))
            ctx.strokePath()

            // Glow around crack
            ctx.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 0.2))
            ctx.setLineWidth(4)
            ctx.move(to: center)
            ctx.addLine(to: CGPoint(x: endX, y: endY))
            ctx.strokePath()
            ctx.setLineWidth(1.5)
        }
    }

    private static func drawSparks(in ctx: CGContext, at center: CGPoint, r: CGFloat, g: CGFloat, b: CGFloat) {
        var gen = SystemRandomNumberGenerator()
        for _ in 0..<8 {
            let angle = CGFloat.random(in: 0...(2 * .pi), using: &gen)
            let dist = CGFloat.random(in: 15...50, using: &gen)
            let sx = center.x + CGFloat(cos(angle)) * dist
            let sy = center.y + CGFloat(sin(angle)) * dist
            let sparkSize = CGFloat.random(in: 2...5, using: &gen)

            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0.8, alpha: 0.8))
            ctx.fillEllipse(in: CGRect(x: sx - sparkSize, y: sy - sparkSize, width: sparkSize * 2, height: sparkSize * 2))

            // Glow around spark
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 0.25))
            let glowSize = sparkSize * 3
            ctx.fillEllipse(in: CGRect(x: sx - glowSize, y: sy - glowSize, width: glowSize * 2, height: glowSize * 2))
        }
    }
}

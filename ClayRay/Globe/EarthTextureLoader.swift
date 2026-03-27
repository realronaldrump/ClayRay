import AppKit
import CoreGraphics
import Foundation

/// Downloads a real equirectangular Earth texture from NASA (public domain),
/// applies clay color grading, and caches the result locally.
actor EarthTextureLoader {
    static let shared = EarthTextureLoader()

    // NASA Blue Marble (public domain, stable URLs)
    private let textureURLs = [
        "https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57752/land_ocean_ice_2048.jpg",
        "https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73909/world.topo.bathy.200412.3x5400x2700.jpg"
    ]

    private var cachedTexture: CGImage?

    /// Load the earth texture, downloading if needed. Returns a clay-processed CGImage.
    func loadClayTexture(isDark: Bool) async -> CGImage? {
        // Check in-memory cache
        if let cached = cachedTexture {
            return applyClayGrading(to: cached, isDark: isDark)
        }

        // Check disk cache
        if let diskCached = loadFromDisk() {
            cachedTexture = diskCached
            return applyClayGrading(to: diskCached, isDark: isDark)
        }

        // Download from NASA
        for urlString in textureURLs {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                guard let nsImage = NSImage(data: data),
                      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }

                // Cache to disk
                saveToDisk(data: data)
                cachedTexture = cgImage
                return applyClayGrading(to: cgImage, isDark: isDark)
            } catch {
                continue
            }
        }

        return nil
    }

    // MARK: - Clay Color Grading

    /// Transform a photorealistic earth texture into a clay-colored version.
    /// Land becomes warm terracotta/stone, ocean becomes deep teal/slate.
    private func applyClayGrading(to source: CGImage, isDark: Bool) -> CGImage? {
        let width = min(source.width, 2048)
        let height = min(source.height, 1024)

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

        // Draw the source image scaled to our target size
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Get pixel data for processing
        guard let pixelData = ctx.data else { return nil }
        let data = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Clay color palette
        let landR: Float = isDark ? 0.56 : 0.78
        let landG: Float = isDark ? 0.50 : 0.48
        let landB: Float = isDark ? 0.44 : 0.32

        let oceanR: Float = isDark ? 0.14 : 0.14
        let oceanG: Float = isDark ? 0.24 : 0.34
        let oceanB: Float = isDark ? 0.30 : 0.42

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = Float(data[offset]) / 255.0
                let g = Float(data[offset + 1]) / 255.0
                let b = Float(data[offset + 2]) / 255.0

                // Luminance to determine land vs ocean
                let lum = r * 0.299 + g * 0.587 + b * 0.114

                // Blue channel weight helps distinguish ocean from land
                let blueRatio = b / max(r + g + b, 0.01)
                let greenness = g / max(r + b, 0.01)

                // Classify: ocean is dark-blue/blue-green, land is brighter/warmer
                let isOcean = (blueRatio > 0.38 && lum < 0.55) || (lum < 0.15)
                let isIceOrCloud = lum > 0.75

                let outR: Float
                let outG: Float
                let outB: Float

                if isOcean {
                    // Map ocean depth: darker source = deeper ocean
                    let depth = 1.0 - (lum * 1.2)
                    outR = oceanR * (0.8 + depth * 0.25)
                    outG = oceanG * (0.8 + depth * 0.3)
                    outB = oceanB * (0.85 + depth * 0.2)
                } else if isIceOrCloud {
                    // Ice caps / bright areas: lighter clay
                    outR = min(landR * 1.2, 1.0)
                    outG = min(landG * 1.15, 1.0)
                    outB = min(landB * 1.1, 1.0)
                } else {
                    // Land: use luminance to add terrain variation
                    let terrain = lum
                    // Forests (green) → slightly darker clay
                    let greenFactor: Float = greenness > 0.4 ? 0.88 : 1.0
                    outR = landR * (0.7 + terrain * 0.5) * greenFactor
                    outG = landG * (0.7 + terrain * 0.45) * greenFactor
                    outB = landB * (0.65 + terrain * 0.4)
                }

                data[offset] = UInt8(max(0, min(255, outR * 255)))
                data[offset + 1] = UInt8(max(0, min(255, outG * 255)))
                data[offset + 2] = UInt8(max(0, min(255, outB * 255)))
                data[offset + 3] = 255
            }
        }

        return ctx.makeImage()
    }

    // MARK: - Disk Cache

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ClayRay")
            .appendingPathComponent("earth_texture.jpg")
    }

    private func loadFromDisk() -> CGImage? {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return cgImage
    }

    private func saveToDisk(data: Data) {
        guard let url = cacheURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }
}

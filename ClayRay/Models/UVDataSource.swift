import Foundation

/// Available UV data API sources. Each case knows its own endpoint and parsing logic.
enum UVDataSource: String, CaseIterable, Identifiable, Codable {
    case currentUVIndex = "currentuvindex.com"
    case openMeteo = "Open-Meteo"
    case uvIndexAPI = "uvindexapi.com"
    case openUV = "OpenUV.io"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var requiresAPIKey: Bool {
        self == .openUV
    }

    var attribution: String {
        switch self {
        case .currentUVIndex: return "Data from currentuvindex.com (CC BY 4.0)"
        case .openMeteo: return "Data from Open-Meteo.com"
        case .uvIndexAPI: return "Data from uvindexapi.com (NOAA-sourced)"
        case .openUV: return "Data from OpenUV.io"
        }
    }

    var rateLimitNote: String {
        switch self {
        case .currentUVIndex: return "500 requests/day per IP"
        case .openMeteo: return "No rate limit"
        case .uvIndexAPI: return "Free, no key required"
        case .openUV: return "50 requests/day (free tier)"
        }
    }
}

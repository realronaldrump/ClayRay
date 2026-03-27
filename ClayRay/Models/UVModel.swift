import Foundation

// MARK: - Unified UV Data Model

/// Standardized UV data regardless of which API source provided it.
struct UVData: Equatable {
    let currentUVI: Double
    let locationName: String?
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let hourlyForecast: [HourlyUV]
    let dailyPeaks: [DailyPeak]

    var uvLevel: UVLevel { UVLevel(uvi: currentUVI) }

    /// Trend based on next hour vs current
    var trend: UVTrend {
        guard let nextHour = hourlyForecast.first(where: { $0.time > timestamp }) else { return .stable }
        let diff = nextHour.uvi - currentUVI
        if diff > 0.5 { return .rising }
        if diff < -0.5 { return .falling }
        return .stable
    }

    /// Peak UVI time today
    var peakTimeToday: Date? {
        let calendar = Calendar.current
        let todayForecasts = hourlyForecast.filter { calendar.isDateInToday($0.time) }
        return todayForecasts.max(by: { $0.uvi < $1.uvi })?.time
    }

    static let empty = UVData(
        currentUVI: 0,
        locationName: nil,
        latitude: 0,
        longitude: 0,
        timestamp: .now,
        hourlyForecast: [],
        dailyPeaks: []
    )
}

struct HourlyUV: Equatable, Identifiable {
    let time: Date
    let uvi: Double
    var id: Date { time }
}

struct DailyPeak: Equatable, Identifiable {
    let date: Date
    let maxUVI: Double
    var id: Date { date }

    var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - UV Level Classification

enum UVLevel: String {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case veryHigh = "Very High"
    case extreme = "Extreme"

    init(uvi: Double) {
        switch uvi {
        case ..<3: self = .low
        case 3..<6: self = .moderate
        case 6..<8: self = .high
        case 8..<11: self = .veryHigh
        default: self = .extreme
        }
    }

}

enum UVTrend {
    case rising
    case falling
    case stable

    var symbol: String {
        switch self {
        case .rising: return "arrow.up.forward"
        case .falling: return "arrow.down.forward"
        case .stable: return "arrow.forward"
        }
    }

    var label: String {
        switch self {
        case .rising: return "Rising"
        case .falling: return "Falling"
        case .stable: return "Steady"
        }
    }
}

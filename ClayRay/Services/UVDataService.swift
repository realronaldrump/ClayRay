import Foundation

/// Fetches UV data from the selected API source and returns a unified `UVData` struct.
@MainActor
final class UVDataService: ObservableObject {
    @Published var currentData: UVData = .empty
    @Published var globalGridPoints: [(lat: Double, lon: Double, uvi: Double)] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var refreshTimer: Timer?
    private var cachedData: [String: UVData] = [:]
    private let session = URLSession.shared

    func fetch(
        latitude: Double,
        longitude: Double,
        source: UVDataSource,
        apiKey: String? = nil
    ) async {
        let cacheKey = "\(String(format: "%.2f", latitude)),\(String(format: "%.2f", longitude))"
        isLoading = true
        errorMessage = nil

        do {
            let data: UVData
            switch source {
            case .currentUVIndex:
                data = try await fetchCurrentUVIndex(lat: latitude, lon: longitude)
            case .openMeteo:
                data = try await fetchOpenMeteo(lat: latitude, lon: longitude)
            case .uvIndexAPI:
                data = try await fetchUVIndexAPI(lat: latitude, lon: longitude)
            case .openUV:
                guard let key = apiKey, !key.isEmpty else {
                    throw UVError.apiKeyRequired
                }
                data = try await fetchOpenUV(lat: latitude, lon: longitude, apiKey: key)
            }
            cachedData[cacheKey] = data
            currentData = data
        } catch {
            if let cached = cachedData[cacheKey] {
                currentData = cached
                errorMessage = "Using cached data — \(error.localizedDescription)"
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    /// Fetch UV data for a grid of points across the globe to paint the full overlay.
    /// Uses Open-Meteo (free, no key, no rate limit) regardless of user's selected source.
    func fetchGlobalGrid() async {
        // Dense grid: every 12° — ~330 points for smooth UV heatmap
        var points: [(lat: Double, lon: Double, uvi: Double)] = []

        // Build grid coordinates
        var coords: [(Double, Double)] = []
        for lat in stride(from: -60.0, through: 72.0, by: 12.0) {
            for lon in stride(from: -180.0, through: 168.0, by: 12.0) {
                coords.append((lat, lon))
            }
        }

        // Fetch in batches of ~10 concurrent requests
        await withTaskGroup(of: (Double, Double, Double)?.self) { group in
            for (lat, lon) in coords {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.fetchSingleUVI(lat: lat, lon: lon)
                }
            }
            for await result in group {
                if let r = result {
                    points.append(r)
                }
            }
        }

        globalGridPoints = points
    }

    private func fetchSingleUVI(lat: Double, lon: Double) async -> (Double, Double, Double)? {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=uv_index&timezone=auto"
        guard let url = URL(string: urlStr) else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let current = json["current"] as? [String: Any],
               let uvi = current["uv_index"] as? Double {
                // Enforce nighttime = 0: API may return small residual values
                return (lat, lon, max(uvi, 0))
            }
        } catch { }
        return nil
    }

    func startAutoRefresh(latitude: Double, longitude: Double, source: UVDataSource, apiKey: String?, interval: TimeInterval = 300) {
        stopAutoRefresh()
        Task {
            await fetch(latitude: latitude, longitude: longitude, source: source, apiKey: apiKey)
            await fetchGlobalGrid()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetch(latitude: latitude, longitude: longitude, source: source, apiKey: apiKey)
                await self?.fetchGlobalGrid()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - currentuvindex.com

    private func fetchCurrentUVIndex(lat: Double, lon: Double) async throws -> UVData {
        let url = URL(string: "https://currentuvindex.com/api/v1/uvi?latitude=\(lat)&longitude=\(lon)")!
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let now = json["now"] as? [String: Any]
        let currentUVI = now?["uvi"] as? Double ?? 0

        var hourly: [HourlyUV] = []
        if let forecast = json["forecast"] as? [[String: Any]] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallback = ISO8601DateFormatter()
            for entry in forecast {
                let uvi = entry["uvi"] as? Double ?? 0
                let timeStr = entry["time"] as? String ?? ""
                let time = formatter.date(from: timeStr) ?? fallback.date(from: timeStr) ?? Date()
                hourly.append(HourlyUV(time: time, uvi: uvi))
            }
        }

        return UVData(
            currentUVI: currentUVI, locationName: nil,
            latitude: lat, longitude: lon, timestamp: Date(),
            hourlyForecast: hourly, dailyPeaks: extractDailyPeaks(from: hourly)
        )
    }

    // MARK: - Open-Meteo

    private func fetchOpenMeteo(lat: Double, lon: Double) async throws -> UVData {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=uv_index&hourly=uv_index&daily=uv_index_max&timezone=auto&forecast_days=5"
        let url = URL(string: urlStr)!
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // Current
        let current = json["current"] as? [String: Any]
        let currentUVI = current?["uv_index"] as? Double ?? 0

        // Determine timezone from response for correct date parsing
        let tzAbbr = json["timezone_abbreviation"] as? String
        let tzName = json["timezone"] as? String

        // Open-Meteo returns times like "2024-03-27T10:00" (no timezone offset, local time)
        let hourlyFormatter = DateFormatter()
        hourlyFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        hourlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        // Set timezone from response so times parse correctly
        if let tzName, let tz = TimeZone(identifier: tzName) {
            hourlyFormatter.timeZone = tz
        } else if let tzAbbr, let tz = TimeZone(abbreviation: tzAbbr) {
            hourlyFormatter.timeZone = tz
        }

        // Hourly
        var hourly: [HourlyUV] = []
        if let hourlyData = json["hourly"] as? [String: Any],
           let times = hourlyData["time"] as? [String],
           let uvis = hourlyData["uv_index"] as? [Any] {
            for (i, timeStr) in times.enumerated() where i < uvis.count {
                guard let time = hourlyFormatter.date(from: timeStr) else { continue }
                // Handle null values (nighttime)
                let uvi: Double
                if let val = uvis[i] as? Double {
                    uvi = val
                } else if let val = uvis[i] as? Int {
                    uvi = Double(val)
                } else {
                    uvi = 0
                }
                hourly.append(HourlyUV(time: time, uvi: uvi))
            }
        }

        // Daily peaks
        var dailyPeaks: [DailyPeak] = []
        if let dailyData = json["daily"] as? [String: Any],
           let days = dailyData["time"] as? [String],
           let maxUvis = dailyData["uv_index_max"] as? [Any] {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            dayFormatter.locale = Locale(identifier: "en_US_POSIX")
            if let tzName, let tz = TimeZone(identifier: tzName) {
                dayFormatter.timeZone = tz
            }
            for (i, dayStr) in days.enumerated() where i < maxUvis.count {
                guard let date = dayFormatter.date(from: dayStr) else { continue }
                let maxUvi: Double
                if let val = maxUvis[i] as? Double {
                    maxUvi = val
                } else if let val = maxUvis[i] as? Int {
                    maxUvi = Double(val)
                } else {
                    continue
                }
                dailyPeaks.append(DailyPeak(date: date, maxUVI: maxUvi))
            }
        }

        return UVData(
            currentUVI: currentUVI, locationName: nil,
            latitude: lat, longitude: lon, timestamp: Date(),
            hourlyForecast: hourly, dailyPeaks: dailyPeaks
        )
    }

    // MARK: - uvindexapi.com

    private func fetchUVIndexAPI(lat: Double, lon: Double) async throws -> UVData {
        let urlStr = "https://uvindexapi.com/api/v1/forecast?latitude=\(lat)&longitude=\(lon)&timezone=Auto"
        let url = URL(string: urlStr)!
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        var hourly: [HourlyUV] = []
        if let forecast = json["forecast"] as? [[String: Any]] {
            let formatter = ISO8601DateFormatter()
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            for entry in forecast {
                let uvi = entry["uvi"] as? Double ?? entry["uv"] as? Double ?? 0
                let timeStr = entry["time"] as? String ?? entry["datetime"] as? String ?? ""
                let time = formatter.date(from: timeStr) ?? fallback.date(from: timeStr) ?? Date()
                hourly.append(HourlyUV(time: time, uvi: uvi))
            }
        }

        let now = Date()
        let currentUVI = hourly.min(by: { abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now)) })?.uvi ?? 0

        return UVData(
            currentUVI: currentUVI, locationName: nil,
            latitude: lat, longitude: lon, timestamp: Date(),
            hourlyForecast: hourly, dailyPeaks: extractDailyPeaks(from: hourly)
        )
    }

    // MARK: - OpenUV.io

    private func fetchOpenUV(lat: Double, lon: Double, apiKey: String) async throws -> UVData {
        let urlStr = "https://api.openuv.io/api/v1/uv?lat=\(lat)&lng=\(lon)"
        var request = URLRequest(url: URL(string: urlStr)!)
        request.setValue(apiKey, forHTTPHeaderField: "x-access-token")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let result = json["result"] as? [String: Any] ?? [:]
        let currentUVI = result["uv"] as? Double ?? 0

        var hourly: [HourlyUV] = []
        if let forecast = result["forecast"] as? [[String: Any]] {
            let formatter = ISO8601DateFormatter()
            for entry in forecast {
                let uvi = entry["uv"] as? Double ?? 0
                let timeStr = entry["time"] as? String ?? ""
                if let time = formatter.date(from: timeStr) {
                    hourly.append(HourlyUV(time: time, uvi: uvi))
                }
            }
        }

        return UVData(
            currentUVI: currentUVI, locationName: nil,
            latitude: lat, longitude: lon, timestamp: Date(),
            hourlyForecast: hourly, dailyPeaks: extractDailyPeaks(from: hourly)
        )
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw UVError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw UVError.httpError(http.statusCode)
        }
    }

    private func extractDailyPeaks(from hourly: [HourlyUV]) -> [DailyPeak] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: hourly) { calendar.startOfDay(for: $0.time) }
        return grouped.compactMap { (day, entries) -> DailyPeak? in
            guard let maxUVI = entries.map(\.uvi).max() else { return nil }
            return DailyPeak(date: day, maxUVI: maxUVI)
        }.sorted(by: { $0.date < $1.date })
         .prefix(5)
         .map { $0 }
    }
}

enum UVError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiKeyRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let code): return "Server error (HTTP \(code))"
        case .apiKeyRequired: return "API key required for OpenUV.io — add it in Settings"
        }
    }
}

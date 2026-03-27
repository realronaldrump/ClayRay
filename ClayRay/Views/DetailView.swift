import SwiftUI

/// Detail view shown after dive-in: forecast panels on the right side.
struct DetailView: View {
    let uvData: UVData
    let locationName: String
    let isLoading: Bool
    let onBack: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back to Globe")
                            .font(ClayFonts.rounded(13, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Text("ClayRay — \(locationName)")
                    .font(ClayFonts.rounded(14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 20)
                    }

                    currentUVCard
                    hourlyForecastCard
                    dailyPeaksCard

                    Text("Last updated \(uvData.timestamp.shortTimeString)")
                        .font(ClayFonts.rounded(11))
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
            }
        }
        .background(colorScheme == .dark ? ClayColors.panelBackgroundDark : ClayColors.panelBackground)
    }

    // MARK: - Current UV Card

    private var currentUVCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(uvData.currentUVI.uvFormatted)
                    .font(ClayFonts.rounded(56, weight: .bold))
                    .foregroundColor(ClayColors.uvColor(for: uvData.currentUVI))

                Text(uvData.uvLevel.rawValue)
                    .font(ClayFonts.rounded(22, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: uvData.trend.symbol)
                        .font(.system(size: 12, weight: .semibold))
                    Text(uvData.trend.label)
                        .font(ClayFonts.rounded(13, weight: .medium))
                }
                .foregroundColor(ClayColors.uvColor(for: uvData.currentUVI))

                if let peakTime = uvData.peakTimeToday {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 3) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("Peak at \(peakTime.shortTimeString)")
                            .font(ClayFonts.rounded(13))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Hourly Forecast (fixed baseline bar chart)

    private var hourlyForecastCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOURLY FORECAST")
                .font(ClayFonts.rounded(11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1)

            let upcoming = Array(
                uvData.hourlyForecast
                    .filter { $0.time > Date().addingTimeInterval(-3600) }
                    .prefix(24)
            )
            let display = upcoming.isEmpty ? Array(uvData.hourlyForecast.prefix(12)) : Array(upcoming.prefix(12))

            if display.isEmpty {
                Text("No hourly data available")
                    .font(ClayFonts.rounded(13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                let maxUVI = max(display.map(\.uvi).max() ?? 1, 1)
                let barAreaHeight: CGFloat = 64

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(display) { hour in
                            HourlyBarView(hour: hour, maxUVI: maxUVI, barAreaHeight: barAreaHeight)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Daily Peaks

    private var dailyPeaksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("5-DAY PEAKS")
                .font(ClayFonts.rounded(11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1)

            if uvData.dailyPeaks.isEmpty {
                Text("No daily data available")
                    .font(ClayFonts.rounded(13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                HStack(spacing: 16) {
                    ForEach(uvData.dailyPeaks.prefix(5)) { day in
                        daySunDisc(day: day)
                    }
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func daySunDisc(day: DailyPeak) -> some View {
        SunDiscView(day: day)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.7))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

// MARK: - Hover-animated hourly bar

private struct HourlyBarView: View {
    let hour: HourlyUV
    let maxUVI: Double
    let barAreaHeight: CGFloat
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Text(hour.uvi.uvFormatted)
                .font(ClayFonts.rounded(10, weight: .semibold))
                .foregroundColor(ClayColors.uvColor(for: hour.uvi))
                .frame(height: 14)
                .padding(.bottom, 2)

            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(width: 26, height: barAreaHeight)

                RoundedRectangle(cornerRadius: 4)
                    .fill(ClayColors.uvColor(for: hour.uvi).opacity(isHovered ? 1.0 : 0.85))
                    .frame(
                        width: 26,
                        height: max(4, CGFloat(hour.uvi / maxUVI) * barAreaHeight)
                    )
                    .shadow(color: isHovered ? ClayColors.uvColor(for: hour.uvi).opacity(0.5) : .clear, radius: 6)
            }

            Text(hour.time.hourString)
                .font(ClayFonts.rounded(9))
                .foregroundStyle(.secondary)
                .frame(height: 14)
                .padding(.top, 4)
        }
        .frame(width: 34)
        .scaleEffect(isHovered ? 1.12 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Hover-animated sun disc

private struct SunDiscView: View {
    let day: DailyPeak
    @State private var isHovered = false

    var body: some View {
        let size = max(30, min(54, CGFloat(day.maxUVI) * 5))
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(ClayColors.uvColor(for: day.maxUVI).opacity(isHovered ? 0.4 : 0.25))
                    .frame(width: size + 10, height: size + 10)

                Circle()
                    .fill(ClayColors.uvColor(for: day.maxUVI))
                    .frame(width: size, height: size)
                    .shadow(color: ClayColors.uvColor(for: day.maxUVI).opacity(isHovered ? 0.7 : 0.4), radius: isHovered ? 10 : 5)

                Text(day.maxUVI.uvFormatted)
                    .font(ClayFonts.rounded(12, weight: .bold))
                    .foregroundColor(.white)
            }

            Text(day.dayName)
                .font(ClayFonts.rounded(11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }
}

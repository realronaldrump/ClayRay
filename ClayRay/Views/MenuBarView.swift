import SwiftUI

/// Menu bar dropdown content.
struct MenuBarView: View {
    let uvData: UVData
    let locationName: String
    let onOpenWindow: () -> Void
    let onDiveToLocation: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationName)
                        .font(ClayFonts.rounded(13, weight: .semibold))

                    HStack(spacing: 4) {
                        Text("UV \(uvData.currentUVI.uvFormatted)")
                            .font(ClayFonts.rounded(18, weight: .bold))
                            .foregroundColor(ClayColors.uvColor(for: uvData.currentUVI))

                        Text(uvData.uvLevel.rawValue)
                            .font(ClayFonts.rounded(12, weight: .medium))
                            .foregroundStyle(.secondary)

                        Image(systemName: uvData.trend.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ClayColors.uvColor(for: uvData.currentUVI))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)

            Divider()

            Button("Open ClayRay", action: onOpenWindow)
                .font(ClayFonts.rounded(13))
            Button("Dive to My Location", action: onDiveToLocation)
                .font(ClayFonts.rounded(13))

            Divider()

            Text("Updated \(uvData.timestamp.shortTimeString)")
                .font(ClayFonts.rounded(10))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 240)
    }
}

import SwiftUI

/// Bottom HUD overlay showing current location UV info.
struct HUDView: View {
    let uvData: UVData
    let locationName: String
    let onMyLocation: () -> Void
    let onResetOrbit: () -> Void
    let onExportPNG: () -> Void
    let onSettings: () -> Void
    @State private var isHovered = false

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            // Location + UV strip
            HStack(spacing: 8) {
                Text(locationName)
                    .font(ClayFonts.rounded(14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("·")
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("UV \(uvData.currentUVI.uvFormatted)")
                        .font(ClayFonts.rounded(14, weight: .bold))
                        .foregroundColor(ClayColors.uvColor(for: uvData.currentUVI))

                    Text(uvData.uvLevel.rawValue)
                        .font(ClayFonts.rounded(13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Image(systemName: uvData.trend.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ClayColors.uvColor(for: uvData.currentUVI))
                }

                Spacer()

                Text("Updated \(uvData.timestamp.shortTimeString)")
                    .font(ClayFonts.rounded(11))
                    .foregroundStyle(.tertiary)
            }

            // Action buttons
            HStack(spacing: 16) {
                hudButton(label: "My Location", systemImage: "location.fill", shortcut: "⌘K") {
                    onMyLocation()
                }
                hudButton(label: "Reset View", systemImage: "arrow.counterclockwise", shortcut: nil) {
                    onResetOrbit()
                }
                hudButton(label: "Export", systemImage: "square.and.arrow.up", shortcut: nil) {
                    onExportPNG()
                }
                Spacer()
                hudButton(label: "Settings", systemImage: "gearshape.fill", shortcut: nil) {
                    onSettings()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .opacity(isHovered ? 1.0 : 0.7)
        .animation(.easeInOut(duration: 0.3), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private func hudButton(label: String, systemImage: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(ClayFonts.rounded(12, weight: .medium))
                if let shortcut {
                    Text(shortcut)
                        .font(ClayFonts.rounded(10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

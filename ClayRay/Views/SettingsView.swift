import SwiftUI

/// Settings panel: switch UV data source, enter API key, view attribution.
struct SettingsView: View {
    @Binding var selectedSource: UVDataSource
    @Binding var apiKey: String
    @AppStorage("lockVerticalAxis") var lockVerticalAxis = false
    @AppStorage("invertControls") var invertControls = false
    @AppStorage("autoSpin") var autoSpin = true
    @AppStorage("showSunlight") var showSunlight = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(ClayFonts.rounded(18, weight: .bold))
                Spacer()
                Button("Done") { dismiss() }
                    .font(ClayFonts.rounded(14, weight: .medium))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Data source picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UV DATA SOURCE")
                            .font(ClayFonts.rounded(11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1)

                        ForEach(UVDataSource.allCases) { source in
                            sourceRow(source)
                        }
                    }

                    // API key field (only for OpenUV)
                    if selectedSource.requiresAPIKey {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API KEY")
                                .font(ClayFonts.rounded(11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(1)

                            TextField("Enter your OpenUV.io API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(ClayFonts.rounded(13))

                            Text("Get a free key at openuv.io (50 requests/day)")
                                .font(ClayFonts.rounded(11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Divider()

                    // Globe controls
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GLOBE")
                            .font(ClayFonts.rounded(11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1)

                        Toggle(isOn: $lockVerticalAxis) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lock vertical axis")
                                    .font(ClayFonts.rounded(14, weight: .medium))
                                Text("Only allow horizontal rotation — prevents the globe from tipping")
                                    .font(ClayFonts.rounded(11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.switch)

                        Toggle(isOn: $invertControls) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Invert controls")
                                    .font(ClayFonts.rounded(14, weight: .medium))
                                Text("Reverse drag, scroll, and arrow key directions")
                                    .font(ClayFonts.rounded(11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.switch)

                        Toggle(isOn: $autoSpin) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-spin")
                                    .font(ClayFonts.rounded(14, weight: .medium))
                                Text("Slowly rotate the globe when idle")
                                    .font(ClayFonts.rounded(11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.switch)

                        Toggle(isOn: $showSunlight) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show sunlight")
                                    .font(ClayFonts.rounded(14, weight: .medium))
                                Text("Visualize day/night and sun position on the globe")
                                    .font(ClayFonts.rounded(11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.switch)
                    }

                    Divider()

                    // Attribution
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ATTRIBUTION")
                            .font(ClayFonts.rounded(11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1)

                        Text(selectedSource.attribution)
                            .font(ClayFonts.rounded(12))
                            .foregroundStyle(.secondary)

                        Text(selectedSource.rateLimitNote)
                            .font(ClayFonts.rounded(11))
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    // About
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ClayRay v1.0")
                            .font(ClayFonts.rounded(13, weight: .semibold))
                        Text("A squeezable clay globe for live UV levels.")
                            .font(ClayFonts.rounded(12))
                            .foregroundStyle(.secondary)
                        Text("Built as a fun desk toy.")
                            .font(ClayFonts.rounded(11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 400, height: 620)
        .background(colorScheme == .dark ? ClayColors.panelBackgroundDark : ClayColors.panelBackground)
    }

    private func sourceRow(_ source: UVDataSource) -> some View {
        Button {
            selectedSource = source
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.displayName)
                        .font(ClayFonts.rounded(14, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(source.rateLimitNote)
                        .font(ClayFonts.rounded(11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if source == selectedSource {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 18))
                }

                if source.requiresAPIKey {
                    Text("Key needed")
                        .font(ClayFonts.rounded(10))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange.opacity(0.1))
                        )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(source == selectedSource
                        ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.accentColor.opacity(0.08))
                        : Color.clear
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(source == selectedSource ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

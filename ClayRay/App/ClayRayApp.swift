import SwiftUI

@main
struct ClayRayApp: App {
    @StateObject private var uvService = UVDataService()
    @StateObject private var locationManager = LocationManager()
    @AppStorage("selectedSource") private var selectedSource: UVDataSource = .openMeteo
    @AppStorage("apiKey") private var apiKey: String = ""

    var body: some Scene {
        // Main window — shares uvService and locationManager with ContentView
        WindowGroup {
            ContentView()
                .environmentObject(uvService)
                .environmentObject(locationManager)
                .frame(
                    minWidth: 600, idealWidth: AppConstants.defaultWindowWidth,
                    minHeight: 400, idealHeight: AppConstants.defaultWindowHeight
                )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: AppConstants.defaultWindowWidth, height: AppConstants.defaultWindowHeight)

        // Menu bar extra
        MenuBarExtra {
            MenuBarView(
                uvData: uvService.currentData,
                locationName: locationManager.locationName,
                onOpenWindow: {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.isVisible || $0.isMiniaturized }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                },
                onDiveToLocation: {
                    NSApp.activate(ignoringOtherApps: true)
                    // The ContentView handles dive via its own location manager
                }
            )
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let uvi = uvService.currentData.currentUVI
        HStack(spacing: 3) {
            Image(systemName: "sun.max.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    Color(nsColor: ClayColors.uvNSColor(for: uvi)),
                    .primary
                )
                .font(.system(size: 12))

            Text(uvi > 0 ? uvi.uvFormatted : "--")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    init() {
        // Start background data refresh for menu bar
        let service = UVDataService()
        let location = LocationManager()

        _uvService = StateObject(wrappedValue: service)
        _locationManager = StateObject(wrappedValue: location)

        // Request location on launch
        Task { @MainActor in
            location.requestPermission()
            // Small delay for location to arrive
            try? await Task.sleep(for: .seconds(1))
            service.startAutoRefresh(
                latitude: location.latitude,
                longitude: location.longitude,
                source: UVDataSource(rawValue: UserDefaults.standard.string(forKey: "selectedSource") ?? "Open-Meteo") ?? .openMeteo,
                apiKey: UserDefaults.standard.string(forKey: "apiKey")
            )
        }
    }
}

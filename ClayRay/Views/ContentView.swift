import SwiftUI
import SceneKit

/// Main container view: globe + HUD overlay, transitions to detail view.
struct ContentView: View {
    @StateObject private var globeScene = GlobeScene()
    @StateObject private var cameraController = CameraController()
    @StateObject private var uvService = UVDataService()
    @StateObject private var locationManager = LocationManager()

    @AppStorage("selectedSource") private var selectedSource: UVDataSource = .openMeteo
    @AppStorage("apiKey") private var apiKey: String = ""

    @State private var showDetail = false
    @State private var showSettings = false
    @State private var detailLocationName: String = ""
    @State private var clickedLat: Double = 0
    @State private var clickedLon: Double = 0

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background desk gradient
            deskBackground

            if showDetail {
                detailLayout
            } else {
                globeLayout
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            locationManager.requestPermission()
            globeScene.startIdleRotation()
            startDataFetching()
        }
        .onChange(of: locationManager.latitude) { _, _ in
            startDataFetching()
        }
        .onChange(of: selectedSource) { _, _ in
            startDataFetching()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(selectedSource: $selectedSource, apiKey: $apiKey)
        }
        // Keyboard shortcuts
        .keyboardShortcut(KeyEquivalent("k"), modifiers: .command, action: diveToMyLocation)
        .onKeyPress(.escape) {
            if showDetail {
                goBackToGlobe()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Layouts

    private var globeLayout: some View {
        ZStack(alignment: .bottom) {
            GlobeView(
                globeScene: globeScene,
                cameraController: cameraController,
                onLocationClicked: { lat, lon in
                    handleGlobeClick(lat: lat, lon: lon)
                }
            )

            HUDView(
                uvData: uvService.currentData,
                locationName: locationManager.locationName,
                onMyLocation: diveToMyLocation,
                onResetOrbit: { cameraController.resetOrbit() },
                onSettings: { showSettings = true }
            )
        }
    }

    private var detailLayout: some View {
        HStack(spacing: 0) {
            // Left: zoomed globe (60%)
            GlobeView(
                globeScene: globeScene,
                cameraController: cameraController,
                onLocationClicked: nil
            )
            .frame(maxWidth: .infinity)

            // Right: detail panel (40%)
            DetailView(
                uvData: uvService.currentData,
                locationName: detailLocationName.isEmpty ? locationManager.locationName : detailLocationName,
                onBack: goBackToGlobe
            )
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .trailing))
        }
    }

    private var deskBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [ClayColors.deskDark, ClayColors.deskDark.opacity(0.95)]
                : [ClayColors.deskLight, ClayColors.deskLight.opacity(0.9)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Actions

    private func startDataFetching() {
        uvService.startAutoRefresh(
            latitude: locationManager.latitude,
            longitude: locationManager.longitude,
            source: selectedSource,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            interval: AppConstants.refreshInterval
        )

        // Update globe overlay when data arrives
        Task {
            // Small delay to let first fetch complete
            try? await Task.sleep(for: .seconds(2))
            updateGlobeOverlay()
        }
    }

    private func updateGlobeOverlay() {
        globeScene.updateUVOverlay(
            userLat: locationManager.latitude,
            userLon: locationManager.longitude,
            userUVI: uvService.currentData.currentUVI
        )
    }

    private func handleGlobeClick(lat: Double, lon: Double) {
        clickedLat = lat
        clickedLon = lon

        // Fetch UV for clicked location
        Task {
            await uvService.fetch(latitude: lat, longitude: lon, source: selectedSource, apiKey: apiKey.isEmpty ? nil : apiKey)
            if let name = await locationManager.reverseGeocode(latitude: lat, longitude: lon) {
                detailLocationName = name
            } else {
                detailLocationName = String(format: "%.1f°, %.1f°", lat, lon)
            }
        }

        // Animate dive-in
        cameraController.diveToLocation(lat: lat, lon: lon) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showDetail = true
            }
        }
    }

    private func diveToMyLocation() {
        clickedLat = locationManager.latitude
        clickedLon = locationManager.longitude
        detailLocationName = locationManager.locationName

        // Refetch for user's location
        Task {
            await uvService.fetch(
                latitude: locationManager.latitude,
                longitude: locationManager.longitude,
                source: selectedSource,
                apiKey: apiKey.isEmpty ? nil : apiKey
            )
        }

        cameraController.diveToLocation(lat: locationManager.latitude, lon: locationManager.longitude) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showDetail = true
            }
        }
    }

    private func goBackToGlobe() {
        cameraController.diveOut {
            withAnimation(.easeInOut(duration: 0.3)) {
                showDetail = false
            }
            // Refetch user location data and update overlay
            startDataFetching()
        }
    }
}

// MARK: - Keyboard Shortcut Extension

private extension View {
    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        self.background(
            Button("") { action() }
                .keyboardShortcut(key, modifiers: modifiers)
                .frame(width: 0, height: 0)
                .opacity(0)
        )
    }
}

// MARK: - AppStorage Conformance for UVDataSource

extension UVDataSource: @retroactive RawRepresentable {
    // Already RawRepresentable via String enum, AppStorage works natively
}

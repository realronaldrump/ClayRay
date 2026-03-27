import SwiftUI
import SceneKit

/// Main container view: globe + HUD, transitions to detail view on click.
struct ContentView: View {
    @StateObject private var globeScene = GlobeScene()
    @StateObject private var cameraController = CameraController()
    @EnvironmentObject var uvService: UVDataService
    @EnvironmentObject var locationManager: LocationManager

    @AppStorage("selectedSource") private var selectedSource: UVDataSource = .openMeteo
    @AppStorage("apiKey") private var apiKey: String = ""
    @AppStorage("lockVerticalAxis") private var lockVerticalAxis = false
    @AppStorage("invertControls") private var invertControls = false
    @AppStorage("autoSpin") private var autoSpin = true
    @AppStorage("showSunlight") private var showSunlight = false

    @State private var showDetail = false
    @State private var showSettings = false
    @State private var detailLocationName: String = ""
    @State private var scnViewRef: SCNView?

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
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
            if autoSpin {
                globeScene.startIdleRotation()
            }
            startDataFetching()
            cameraController.lockVerticalAxis = lockVerticalAxis
            cameraController.invertControls = invertControls
            cameraController.autoSpin = autoSpin
            if showSunlight {
                globeScene.updateSunlight(enabled: true)
            }
        }
        .onChange(of: lockVerticalAxis) { _, newValue in
            cameraController.lockVerticalAxis = newValue
        }
        .onChange(of: invertControls) { _, newValue in
            cameraController.invertControls = newValue
        }
        .onChange(of: autoSpin) { _, newValue in
            cameraController.autoSpin = newValue
            if newValue && !cameraController.isDetailView {
                globeScene.startIdleRotation()
            } else if !newValue {
                globeScene.stopIdleRotation()
            }
        }
        .onChange(of: showSunlight) { _, newValue in
            globeScene.updateSunlight(enabled: newValue)
        }
        .onChange(of: locationManager.latitude) { _, _ in
            startDataFetching()
        }
        .onChange(of: selectedSource) { _, _ in
            startDataFetching()
        }
        // Update globe overlay whenever UV data changes
        .onChange(of: uvService.currentData) { _, newData in
            updateGlobeOverlay(data: newData)
        }
        // Update globe overlay when global grid data arrives
        .onChange(of: uvService.globalGridPoints.count) { _, _ in
            updateGlobeOverlayWithGrid()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(selectedSource: $selectedSource, apiKey: $apiKey)
        }
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
                },
                onViewReady: { view in scnViewRef = view }
            )

            HUDView(
                uvData: uvService.currentData,
                locationName: locationManager.locationName,
                onMyLocation: diveToMyLocation,
                onResetOrbit: { cameraController.resetOrbit() },
                onExportPNG: { if let view = scnViewRef { globeScene.exportPNG(from: view) } },
                onSettings: { showSettings = true }
            )
        }
    }

    private var detailLayout: some View {
        HStack(spacing: 0) {
            // Left: globe zoomed in close
            GlobeView(
                globeScene: globeScene,
                cameraController: cameraController,
                onLocationClicked: { _, _ in goBackToGlobe() }
            )
            .frame(maxWidth: .infinity)

            // Right: detail panel
            DetailView(
                uvData: uvService.currentData,
                locationName: detailLocationName.isEmpty ? locationManager.locationName : detailLocationName,
                isLoading: uvService.isLoading,
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

    // MARK: - Data

    private func startDataFetching() {
        uvService.startAutoRefresh(
            latitude: locationManager.latitude,
            longitude: locationManager.longitude,
            source: selectedSource,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            interval: AppConstants.refreshInterval
        )
    }

    private func updateGlobeOverlay(data: UVData) {
        if uvService.globalGridPoints.isEmpty {
            // Just user location until grid arrives
            globeScene.updateUVOverlay(
                userLat: data.latitude,
                userLon: data.longitude,
                userUVI: data.currentUVI
            )
        } else {
            updateGlobeOverlayWithGrid()
        }
    }

    private func updateGlobeOverlayWithGrid() {
        let data = uvService.currentData
        globeScene.updateUVOverlayWithGrid(
            uvService.globalGridPoints,
            userLat: data.latitude,
            userLon: data.longitude,
            userUVI: data.currentUVI
        )
    }

    // MARK: - Actions

    private func handleGlobeClick(lat: Double, lon: Double) {
        guard !cameraController.isDiving else { return }

        // Fetch UV for clicked location
        Task {
            await uvService.fetch(latitude: lat, longitude: lon, source: selectedSource, apiKey: apiKey.isEmpty ? nil : apiKey)
            if let name = await locationManager.reverseGeocode(latitude: lat, longitude: lon) {
                detailLocationName = name
            } else {
                detailLocationName = String(format: "%.1f°, %.1f°", lat, lon)
            }
        }

        // Stop idle rotation and animate dive
        globeScene.stopIdleRotation()
        cameraController.diveToLocation(lat: lat, lon: lon) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showDetail = true
            }
        }
    }

    private func diveToMyLocation() {
        guard !cameraController.isDiving else { return }
        detailLocationName = locationManager.locationName

        Task {
            await uvService.fetch(
                latitude: locationManager.latitude,
                longitude: locationManager.longitude,
                source: selectedSource,
                apiKey: apiKey.isEmpty ? nil : apiKey
            )
        }

        globeScene.stopIdleRotation()
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
            if autoSpin {
                globeScene.startIdleRotation()
            }
            // Refetch for user's location
            Task {
                await uvService.fetch(
                    latitude: locationManager.latitude,
                    longitude: locationManager.longitude,
                    source: selectedSource,
                    apiKey: apiKey.isEmpty ? nil : apiKey
                )
            }
        }
    }
}

// Hidden button trick for ⌘K shortcut
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

extension UVDataSource: RawRepresentable {}

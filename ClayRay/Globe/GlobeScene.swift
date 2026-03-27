import SceneKit
import AppKit
import UniformTypeIdentifiers

/// Manages the SceneKit globe: geometry, materials, lighting, and UV overlay.
@MainActor
final class GlobeScene: ObservableObject {
    let scene: SCNScene
    let globeNode: SCNNode
    let cameraNode: SCNNode

    @Published var isDarkMode = false {
        didSet { refreshTexture() }
    }

    /// Current UV overlay CGImage to composite as emission.
    private var currentUVOverlay: CGImage?
    /// Current day/night overlay CGImage for the sunlight visualization.
    private var currentDayNightOverlay: CGImage?
    private var showSunlight = false
    private var sunNode: SCNNode?
    private var sunGlowNode: SCNNode?
    private var sunTimer: Timer?
    /// Cached textures to avoid regenerating when only UV overlay changes.
    private var cachedBaseTexture: CGImage?
    private var cachedNormalMap: CGImage?
    private var cachedHeightMap: CGImage?

    init() {
        scene = SCNScene()
        scene.background.contents = NSColor.clear

        // Globe sphere
        let sphere = SCNSphere(radius: AppConstants.globeRadius)
        sphere.segmentCount = 96
        globeNode = SCNNode(geometry: sphere)
        globeNode.name = "globe"
        // Shift globe up slightly so HUD doesn't clip the bottom
        globeNode.position = SCNVector3(0, 0.15, 0)

        // Camera
        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 40
        camera.zNear = 0.1
        camera.zFar = 100
        cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, AppConstants.cameraDistance)
        cameraNode.look(at: SCNVector3(0, 0.15, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))

        // Lighting — warm, soft, clay-friendly
        let ambientNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 500
        ambient.color = NSColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1)
        ambientNode.light = ambient

        let keyNode = SCNNode()
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.color = NSColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1)
        key.castsShadow = true
        key.shadowRadius = 12
        key.shadowSampleCount = 8
        key.shadowColor = NSColor(white: 0, alpha: 0.25)
        keyNode.light = key
        keyNode.position = SCNVector3(3, 5, 4)
        keyNode.look(at: SCNVector3Zero)

        let rimNode = SCNNode()
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 350
        rim.color = NSColor(red: 1.0, green: 0.92, blue: 0.85, alpha: 1)
        rimNode.light = rim
        rimNode.position = SCNVector3(-3, 1, -3)
        rimNode.look(at: SCNVector3Zero)

        let fillNode = SCNNode()
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 200
        fill.color = NSColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 1)
        fillNode.light = fill
        fillNode.position = SCNVector3(-2, -3, 2)
        fillNode.look(at: SCNVector3Zero)

        // Assemble
        scene.rootNode.addChildNode(globeNode)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(ambientNode)
        scene.rootNode.addChildNode(keyNode)
        scene.rootNode.addChildNode(rimNode)
        scene.rootNode.addChildNode(fillNode)

        // Apply initial procedural texture while real one downloads
        applyProceduralMaterial(isDark: false)

        // Start downloading real NASA texture
        Task {
            await loadRealTexture(isDark: false)
        }
    }

    // MARK: - Texture Loading

    /// Download real earth texture and apply clay grading.
    private func loadRealTexture(isDark: Bool) async {
        if let clayTexture = await EarthTextureLoader.shared.loadClayTexture(isDark: isDark) {
            applyMaterial(baseTexture: clayTexture)
        }
    }

    private func refreshTexture() {
        Task {
            if let clayTexture = await EarthTextureLoader.shared.loadClayTexture(isDark: isDarkMode) {
                applyMaterial(baseTexture: clayTexture)
            } else {
                applyProceduralMaterial(isDark: isDarkMode)
            }
        }
    }

    // MARK: - Materials

    private func applyMaterial(baseTexture: CGImage) {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased

        material.diffuse.contents = baseTexture
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat

        // Normal map for clay surface imperfections (cached)
        if let normalMap = cachedNormalMap ?? GlobeTextureGenerator.generateNormalMap() {
            cachedNormalMap = normalMap
            material.normal.contents = normalMap
            material.normal.intensity = 0.5
        }

        // UV overlay as emission (self-illuminated glow on top of clay)
        if let uvOverlay = currentUVOverlay {
            material.emission.contents = uvOverlay
            material.emission.intensity = 0.8
        }

        // Day/night overlay as transparency mask
        if showSunlight, let dayNight = currentDayNightOverlay {
            material.transparent.contents = dayNight
            material.transparent.intensity = 1.0
            material.transparencyMode = .default
        }

        // Clay PBR
        material.roughness.contents = 0.88
        material.metalness.contents = 0.01

        // Topographic displacement — land raised, oceans depressed
        if let heightMap = cachedHeightMap ?? GlobeTextureGenerator.generateHeightMap() {
            cachedHeightMap = heightMap
            material.displacement.contents = heightMap
            material.displacement.intensity = 0.04
        }

        // Stronger SSS approximation — warm clay glow at edges
        applySSSShader(to: material)

        material.isDoubleSided = false
        globeNode.geometry?.materials = [material]
    }

    func applyProceduralMaterial(isDark: Bool) {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased

        if let baseTexture = GlobeTextureGenerator.generateBaseTexture(isDark: isDark) {
            material.diffuse.contents = baseTexture
        } else {
            material.diffuse.contents = isDark
                ? NSColor(red: 0.52, green: 0.48, blue: 0.44, alpha: 1)
                : NSColor(red: 0.76, green: 0.42, blue: 0.30, alpha: 1)
        }

        if let normalMap = cachedNormalMap ?? GlobeTextureGenerator.generateNormalMap() {
            cachedNormalMap = normalMap
            material.normal.contents = normalMap
            material.normal.intensity = 0.5
        }

        if let uvOverlay = currentUVOverlay {
            material.emission.contents = uvOverlay
            material.emission.intensity = 1.2
        }

        // Day/night overlay as transparency mask
        if showSunlight, let dayNight = currentDayNightOverlay {
            material.transparent.contents = dayNight
            material.transparent.intensity = 1.0
            material.transparencyMode = .default
        }

        material.roughness.contents = 0.88
        material.metalness.contents = 0.01

        // Topographic displacement
        if let heightMap = cachedHeightMap ?? GlobeTextureGenerator.generateHeightMap() {
            cachedHeightMap = heightMap
            material.displacement.contents = heightMap
            material.displacement.intensity = 0.04
        }

        applySSSShader(to: material)
        material.isDoubleSided = false
        globeNode.geometry?.materials = [material]
    }

    /// Shared SSS shader — warm fresnel glow at grazing angles
    private func applySSSShader(to material: SCNMaterial) {
        material.shaderModifiers = [
            .fragment: """
            float3 viewDir = normalize(_surface.view);
            float3 norm = normalize(_surface.normal);
            float fresnel = pow(1.0 - max(dot(viewDir, norm), 0.0), 2.5);
            float3 sssWarm = float3(0.92, 0.58, 0.38) * fresnel * 0.25;
            float3 sssCool = float3(0.45, 0.55, 0.70) * fresnel * 0.08;
            _output.color.rgb += sssWarm + sssCool;
            """
        ]
    }

    // MARK: - UV Overlay (emission on main material)

    func updateUVOverlay(userLat: Double, userLon: Double, userUVI: Double) {
        currentUVOverlay = GlobeTextureGenerator.generateUVOverlay(
            userLat: userLat, userLon: userLon, userUVI: userUVI
        )
        applyUVEmission()
    }

    func updateUVOverlayWithGrid(_ points: [(lat: Double, lon: Double, uvi: Double)],
                                  userLat: Double? = nil, userLon: Double? = nil, userUVI: Double? = nil) {
        currentUVOverlay = GlobeTextureGenerator.generateUVOverlay(
            uvPoints: points, userLat: userLat, userLon: userLon, userUVI: userUVI
        )
        applyUVEmission()
    }

    /// Apply the current UV overlay to the emission channel without rebuilding the full material.
    /// If sunlight is enabled, also apply the day/night overlay as a transparency mask.
    /// Fixed intensity — no animation, so it looks consistent regardless of zoom/angle.
    private func applyUVEmission() {
        guard let material = globeNode.geometry?.firstMaterial else { return }
        material.emission.contents = currentUVOverlay
        material.emission.intensity = 0.8

        if showSunlight, let dayNight = currentDayNightOverlay {
            material.transparent.contents = dayNight
            material.transparent.intensity = 1.0
            material.transparencyMode = .default
        } else {
            material.transparent.contents = nil
        }
    }

    // MARK: - Sunlight Overlay

    func updateSunlight(enabled: Bool) {
        showSunlight = enabled
        if enabled {
            refreshSunlight()
            // Update every 60 seconds
            sunTimer?.invalidate()
            sunTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshSunlight()
                }
            }
        } else {
            sunTimer?.invalidate()
            sunTimer = nil
            currentDayNightOverlay = nil
            sunNode?.removeFromParentNode()
            sunNode = nil
            sunGlowNode?.removeFromParentNode()
            sunGlowNode = nil
            // Re-apply material without day/night overlay
            applyUVEmission()
        }
    }

    private func refreshSunlight() {
        let now = Date()
        currentDayNightOverlay = SunPosition.generateDayNightOverlay(date: now)
        applyUVEmission()
        updateSunNode(date: now)
    }

    private func updateSunNode(date: Date) {
        let subsolar = SunPosition.subsolarPoint(at: date)
        let sunDistance: CGFloat = 6.0
        let latRad = subsolar.lat * .pi / 180
        let lonRad = subsolar.lon * .pi / 180
        let x = sunDistance * CGFloat(cos(latRad) * sin(lonRad))
        let y = sunDistance * CGFloat(sin(latRad)) + 0.15  // Match globe center offset
        let z = sunDistance * CGFloat(cos(latRad) * cos(lonRad))

        if sunNode == nil {
            // Sun sphere — bright emissive yellow-white
            let sunSphere = SCNSphere(radius: 0.12)
            let sunMaterial = SCNMaterial()
            sunMaterial.diffuse.contents = NSColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1)
            sunMaterial.emission.contents = NSColor(red: 1.0, green: 0.92, blue: 0.6, alpha: 1)
            sunMaterial.emission.intensity = 2.0
            sunMaterial.lightingModel = .constant
            sunSphere.materials = [sunMaterial]

            let node = SCNNode(geometry: sunSphere)
            node.name = "sun"
            scene.rootNode.addChildNode(node)
            sunNode = node

            // Glow halo around sun
            let glowSphere = SCNSphere(radius: 0.35)
            let glowMat = SCNMaterial()
            glowMat.diffuse.contents = NSColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 0.15)
            glowMat.emission.contents = NSColor(red: 1.0, green: 0.90, blue: 0.5, alpha: 0.3)
            glowMat.emission.intensity = 1.5
            glowMat.lightingModel = .constant
            glowMat.isDoubleSided = true
            glowMat.blendMode = .add
            glowMat.writesToDepthBuffer = false
            glowSphere.materials = [glowMat]

            let glowNode = SCNNode(geometry: glowSphere)
            glowNode.name = "sunGlow"
            scene.rootNode.addChildNode(glowNode)
            sunGlowNode = glowNode
        }

        sunNode?.position = SCNVector3(x, y, z)
        sunGlowNode?.position = SCNVector3(x, y, z)
    }

    // MARK: - Rotation

    func startIdleRotation() {
        globeNode.removeAction(forKey: "idleRotation")
        let rotation = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 120)
        globeNode.runAction(SCNAction.repeatForever(rotation), forKey: "idleRotation")
    }

    func stopIdleRotation() {
        globeNode.removeAction(forKey: "idleRotation")
    }

    var isIdleRotating: Bool {
        globeNode.action(forKey: "idleRotation") != nil
    }

    // MARK: - Squish Animation

    /// Fun clay squish: scale down then bounce back — like squeezing the globe.
    func squish() {
        globeNode.removeAction(forKey: "squish")
        let squishDown = SCNAction.scale(to: 0.88, duration: 0.1)
        squishDown.timingMode = .easeIn
        let bounceUp = SCNAction.scale(to: 1.05, duration: 0.15)
        bounceUp.timingMode = .easeOut
        let settle = SCNAction.scale(to: 1.0, duration: 0.2)
        settle.timingMode = .easeInEaseOut
        globeNode.runAction(SCNAction.sequence([squishDown, bounceUp, settle]), forKey: "squish")
    }

    // MARK: - Export

    /// Capture the current globe view as a PNG and save via NSSavePanel.
    func exportPNG(from view: SCNView) {
        let snapshot = view.snapshot()
        guard let tiffData = snapshot.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "ClayRay-\(formatter.string(from: Date())).png"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? pngData.write(to: url)
            }
        }
    }

    // MARK: - Hit Testing

    func hitTestGlobe(at point: CGPoint, in view: SCNView) -> (lat: Double, lon: Double)? {
        let hits = view.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .ignoreHiddenNodes: true
        ])
        guard let hit = hits.first(where: { $0.node == globeNode }) else { return nil }

        let local = hit.localCoordinates
        let r = Double(AppConstants.globeRadius)
        let lat = asin(Double(local.y) / r) * 180 / .pi
        let lon = atan2(Double(local.x), Double(local.z)) * 180 / .pi
        return (lat: lat, lon: lon)
    }
}

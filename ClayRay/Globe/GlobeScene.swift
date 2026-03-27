import SceneKit
import AppKit

/// Manages the SceneKit globe: geometry, materials, lighting, and UV overlay.
@MainActor
final class GlobeScene: ObservableObject {
    let scene: SCNScene
    let globeNode: SCNNode
    let uvOverlayNode: SCNNode
    let cameraNode: SCNNode
    let ambientLightNode: SCNNode
    let keyLightNode: SCNNode
    let rimLightNode: SCNNode
    let fillLightNode: SCNNode

    @Published var isDarkMode = false {
        didSet { updateAppearance() }
    }

    init() {
        scene = SCNScene()
        scene.background.contents = NSColor.clear

        // Globe sphere — moderate segment count for smooth-enough clay
        let sphere = SCNSphere(radius: AppConstants.globeRadius)
        sphere.segmentCount = 72
        globeNode = SCNNode(geometry: sphere)
        globeNode.name = "globe"

        // UV overlay sphere — slightly larger, additive blended
        let overlaySphere = SCNSphere(radius: AppConstants.globeRadius * 1.003)
        overlaySphere.segmentCount = 72
        uvOverlayNode = SCNNode(geometry: overlaySphere)
        uvOverlayNode.name = "uvOverlay"

        // Camera
        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 40
        camera.zNear = 0.1
        camera.zFar = 100
        cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, AppConstants.cameraDistance)
        cameraNode.look(at: SCNVector3Zero)

        // Lighting — warm, soft, clay-friendly
        ambientLightNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 500
        ambient.color = NSColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1) // warm
        ambientLightNode.light = ambient

        keyLightNode = SCNNode()
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.color = NSColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1)
        key.castsShadow = true
        key.shadowRadius = 12
        key.shadowSampleCount = 8
        key.shadowColor = NSColor(white: 0, alpha: 0.25)
        keyLightNode.light = key
        keyLightNode.position = SCNVector3(3, 5, 4)
        keyLightNode.look(at: SCNVector3Zero)

        rimLightNode = SCNNode()
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 350
        rim.color = NSColor(red: 1.0, green: 0.92, blue: 0.85, alpha: 1)
        rimLightNode.light = rim
        rimLightNode.position = SCNVector3(-3, 1, -3)
        rimLightNode.look(at: SCNVector3Zero)

        fillLightNode = SCNNode()
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 200
        fill.color = NSColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 1) // cool fill
        fillLightNode.light = fill
        fillLightNode.position = SCNVector3(-2, -3, 2)
        fillLightNode.look(at: SCNVector3Zero)

        // Assemble scene
        scene.rootNode.addChildNode(globeNode)
        scene.rootNode.addChildNode(uvOverlayNode)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(ambientLightNode)
        scene.rootNode.addChildNode(keyLightNode)
        scene.rootNode.addChildNode(rimLightNode)
        scene.rootNode.addChildNode(fillLightNode)

        // Shadow-receiving floor plane
        let shadowPlane = SCNPlane(width: 6, height: 6)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.diffuse.contents = NSColor.clear
        shadowMaterial.colorBufferWriteMask = []
        shadowMaterial.writesToDepthBuffer = true
        shadowPlane.materials = [shadowMaterial]
        let shadowNode = SCNNode(geometry: shadowPlane)
        shadowNode.position = SCNVector3(0, -1.5, 0)
        shadowNode.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(shadowNode)

        // Apply materials
        applyClayMaterial(isDark: false)
        applyUVOverlayMaterial()
    }

    // MARK: - Clay Material

    func applyClayMaterial(isDark: Bool) {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased

        // Base color from procedural texture generator
        if let baseTexture = GlobeTextureGenerator.generateBaseTexture(isDark: isDark) {
            material.diffuse.contents = baseTexture
        } else {
            // Fallback solid color
            material.diffuse.contents = isDark
                ? NSColor(red: 0.52, green: 0.48, blue: 0.44, alpha: 1)
                : NSColor(red: 0.76, green: 0.42, blue: 0.30, alpha: 1)
        }
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat

        // Normal map for clay imperfections (thumbprints, bumps)
        if let normalMap = GlobeTextureGenerator.generateNormalMap() {
            material.normal.contents = normalMap
            material.normal.intensity = 0.7
        }

        // Clay PBR: very rough, non-metallic
        material.roughness.contents = 0.88
        material.metalness.contents = 0.01

        // Shader modifier for subsurface scattering approximation
        // Adds warm translucent glow at grazing angles
        material.shaderModifiers = [
            .fragment: """
            // Clay SSS approximation: warm glow at edges
            float3 viewDir = normalize(_surface.view);
            float3 norm = normalize(_surface.normal);
            float fresnel = pow(1.0 - max(dot(viewDir, norm), 0.0), 3.0);
            float3 sssColor = float3(0.85, 0.55, 0.35) * fresnel * 0.15;
            _output.color.rgb += sssColor;
            """
        ]

        material.isDoubleSided = false
        globeNode.geometry?.materials = [material]
    }

    // MARK: - UV Overlay Material

    func applyUVOverlayMaterial() {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.clear
        material.emission.contents = NSColor.clear
        material.transparent.contents = NSColor.white
        material.transparency = 1.0
        material.isDoubleSided = false
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        uvOverlayNode.geometry?.materials = [material]
    }

    /// Update UV overlay with user location data.
    func updateUVOverlay(userLat: Double, userLon: Double, userUVI: Double) {
        guard let overlay = GlobeTextureGenerator.generateUVOverlay(
            userLat: userLat, userLon: userLon, userUVI: userUVI
        ) else { return }

        if let material = uvOverlayNode.geometry?.firstMaterial {
            material.emission.contents = overlay
            material.transparent.contents = overlay
            material.transparency = 0.0
        }
    }

    /// Batch update with multiple global UV grid points.
    func updateUVOverlayWithGrid(_ points: [(lat: Double, lon: Double, uvi: Double)],
                                  userLat: Double? = nil, userLon: Double? = nil, userUVI: Double? = nil) {
        guard let overlay = GlobeTextureGenerator.generateUVOverlay(
            uvPoints: points, userLat: userLat, userLon: userLon, userUVI: userUVI
        ) else { return }

        if let material = uvOverlayNode.geometry?.firstMaterial {
            material.emission.contents = overlay
            material.transparent.contents = overlay
            material.transparency = 0.0
        }
    }

    // MARK: - Appearance

    func updateAppearance() {
        applyClayMaterial(isDark: isDarkMode)
    }

    // MARK: - Auto-Rotation

    func startIdleRotation() {
        globeNode.removeAction(forKey: "idleRotation")
        let rotation = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 120)
        let forever = SCNAction.repeatForever(rotation)
        forever.timingMode = .linear
        globeNode.runAction(forever, forKey: "idleRotation")
    }

    func stopIdleRotation() {
        globeNode.removeAction(forKey: "idleRotation")
    }

    var isIdleRotating: Bool {
        globeNode.action(forKey: "idleRotation") != nil
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

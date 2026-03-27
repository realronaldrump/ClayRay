import SceneKit
import Foundation

/// Controls the camera orbit, zoom, and GTA-style two-phase dive-in animation.
@MainActor
final class CameraController: ObservableObject {
    @Published var isDiving = false
    @Published var isDetailView = false

    private weak var cameraNode: SCNNode?
    private weak var globeNode: SCNNode?
    private weak var scnView: SCNView?

    // Orbit state
    private var orbitAngleX: CGFloat = 0
    private var orbitAngleY: CGFloat = 0.3
    private var zoomDistance: CGFloat = AppConstants.cameraDistance

    // Saved state for returning from detail view
    private var savedOrbitX: CGFloat = 0
    private var savedOrbitY: CGFloat = 0.3
    private var savedZoom: CGFloat = AppConstants.cameraDistance

    func configure(cameraNode: SCNNode, globeNode: SCNNode, scnView: SCNView) {
        self.cameraNode = cameraNode
        self.globeNode = globeNode
        self.scnView = scnView
        updateCameraPosition()
    }

    // MARK: - Orbit Controls

    func handleDrag(delta: CGSize) {
        guard !isDiving && !isDetailView else { return }
        let sensitivity: CGFloat = 0.005
        orbitAngleX += delta.width * sensitivity
        orbitAngleY -= delta.height * sensitivity
        orbitAngleY = max(-.pi / 2 + 0.1, min(.pi / 2 - 0.1, orbitAngleY))
        updateCameraPosition()
    }

    func handleZoom(delta: CGFloat) {
        guard !isDiving && !isDetailView else { return }
        zoomDistance -= delta * 0.05
        zoomDistance = max(2.0, min(8.0, zoomDistance))
        updateCameraPosition()
    }

    func resetOrbit() {
        orbitAngleX = 0
        orbitAngleY = 0.3
        zoomDistance = AppConstants.cameraDistance
        animateCameraTo(
            position: computeCameraPosition(),
            lookAt: SCNVector3Zero,
            duration: 0.6
        )
    }

    // MARK: - GTA-Style Two-Phase Dive Animation

    /// Phase 1 (0.4s): Arc upward + rotate globe so target faces camera
    /// Phase 2 (0.8s): Zoom in close with ease-in-out
    func diveToLocation(lat: Double, lon: Double, completion: @escaping () -> Void) {
        guard !isDiving else { return }
        isDiving = true

        savedOrbitX = orbitAngleX
        savedOrbitY = orbitAngleY
        savedZoom = zoomDistance

        let targetOnSurface = latLonToPosition(lat: lat, lon: lon, radius: AppConstants.globeRadius)
        let r = AppConstants.globeRadius

        // Normalize to get direction
        let nx = targetOnSurface.x / r
        let ny = targetOnSurface.y / r
        let nz = targetOnSurface.z / r

        // Phase 1 destination: pull back + arc upward
        let arcDistance: CGFloat = zoomDistance * 1.15  // Pull back slightly
        let arcHeight: CGFloat = 0.4  // Arc up
        let arcPosition = SCNVector3(
            nx * arcDistance * 0.5,
            ny * arcDistance * 0.5 + arcHeight,
            nz * arcDistance * 0.5 + arcDistance * 0.7
        )

        // Phase 2 destination: close to surface, hovering over target
        let hoverDistance: CGFloat = 1.75
        let finalPosition = SCNVector3(
            nx * hoverDistance,
            ny * hoverDistance,
            nz * hoverDistance
        )

        // Phase 1: Arc up and rotate (0.4s)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeIn)

        cameraNode?.position = arcPosition
        cameraNode?.look(at: SCNVector3Zero)

        SCNTransaction.completionBlock = { [weak self] in
            // Phase 2: Zoom in to surface (0.8s)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.8
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)

            self?.cameraNode?.position = finalPosition
            self?.cameraNode?.look(at: SCNVector3Zero)

            SCNTransaction.completionBlock = {
                Task { @MainActor in
                    self?.isDiving = false
                    self?.isDetailView = true
                    completion()
                }
            }

            SCNTransaction.commit()
        }

        SCNTransaction.commit()
    }

    /// Reverse: smooth zoom-out back to full globe.
    func diveOut(completion: @escaping () -> Void) {
        guard isDetailView else { return }
        isDiving = true

        orbitAngleX = savedOrbitX
        orbitAngleY = savedOrbitY
        zoomDistance = savedZoom

        let destination = computeCameraPosition()

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        cameraNode?.position = destination
        cameraNode?.look(at: SCNVector3Zero)

        SCNTransaction.completionBlock = { [weak self] in
            Task { @MainActor in
                self?.isDiving = false
                self?.isDetailView = false
                completion()
            }
        }

        SCNTransaction.commit()
    }

    // MARK: - Helpers

    private func updateCameraPosition() {
        cameraNode?.position = computeCameraPosition()
        cameraNode?.look(at: SCNVector3Zero)
    }

    private func computeCameraPosition() -> SCNVector3 {
        let x = zoomDistance * cos(orbitAngleY) * sin(orbitAngleX)
        let y = zoomDistance * sin(orbitAngleY)
        let z = zoomDistance * cos(orbitAngleY) * cos(orbitAngleX)
        return SCNVector3(x, y, z)
    }

    private func animateCameraTo(position: SCNVector3, lookAt: SCNVector3, duration: TimeInterval) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode?.position = position
        cameraNode?.look(at: lookAt)
        SCNTransaction.commit()
    }

    private func latLonToPosition(lat: Double, lon: Double, radius: CGFloat) -> SCNVector3 {
        let latRad = lat * .pi / 180
        let lonRad = lon * .pi / 180
        let x = radius * CGFloat(cos(latRad) * sin(lonRad))
        let y = radius * CGFloat(sin(latRad))
        let z = radius * CGFloat(cos(latRad) * cos(lonRad))
        return SCNVector3(x, y, z)
    }
}

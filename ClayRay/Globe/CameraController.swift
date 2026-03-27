import SceneKit
import Foundation

/// Controls the camera orbit, zoom, and GTA-style dive-in animation.
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

    // MARK: - GTA-Style Dive-In Animation

    func diveToLocation(lat: Double, lon: Double, completion: @escaping () -> Void) {
        guard !isDiving else { return }
        isDiving = true

        savedOrbitX = orbitAngleX
        savedOrbitY = orbitAngleY
        savedZoom = zoomDistance

        let targetPos = latLonToPosition(lat: lat, lon: lon, radius: AppConstants.globeRadius)
        let r = AppConstants.globeRadius

        let cameraOffset: CGFloat = 1.8
        let normalizedTarget = SCNVector3(
            targetPos.x / r,
            targetPos.y / r,
            targetPos.z / r
        )
        let cameraDestination = SCNVector3(
            normalizedTarget.x * cameraOffset,
            normalizedTarget.y * cameraOffset,
            normalizedTarget.z * cameraOffset
        )

        globeNode?.removeAction(forKey: "idleRotation")

        SCNTransaction.begin()
        SCNTransaction.animationDuration = AppConstants.diveAnimationDuration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        cameraNode?.position = cameraDestination
        cameraNode?.look(at: SCNVector3Zero)

        SCNTransaction.completionBlock = { [weak self] in
            Task { @MainActor in
                self?.isDiving = false
                self?.isDetailView = true
                completion()
            }
        }

        SCNTransaction.commit()
    }

    func diveOut(completion: @escaping () -> Void) {
        guard isDetailView else { return }
        isDiving = true

        orbitAngleX = savedOrbitX
        orbitAngleY = savedOrbitY
        zoomDistance = savedZoom

        let destination = computeCameraPosition()

        SCNTransaction.begin()
        SCNTransaction.animationDuration = AppConstants.diveAnimationDuration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        cameraNode?.position = destination
        cameraNode?.look(at: SCNVector3Zero)

        SCNTransaction.completionBlock = { [weak self] in
            Task { @MainActor in
                self?.isDiving = false
                self?.isDetailView = false
                self?.globeNode?.runAction(
                    SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 120)),
                    forKey: "idleRotation"
                )
                completion()
            }
        }

        SCNTransaction.commit()
    }

    func diveToCurrentLocation(lat: Double, lon: Double, completion: @escaping () -> Void) {
        diveToLocation(lat: lat, lon: lon, completion: completion)
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

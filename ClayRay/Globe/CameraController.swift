import SceneKit
import Foundation

/// Controls the camera orbit, zoom, and cinematic dive-in animation.
@MainActor
final class CameraController: ObservableObject {
    @Published var isDiving = false
    @Published var isDetailView = false
    @Published var invertControls = false
    @Published var autoSpin = true
    @Published var lockVerticalAxis = false {
        didSet {
            if lockVerticalAxis {
                // Clamp to the tighter range when lock is enabled
                orbitAngleY = max(-0.35, min(0.35, orbitAngleY))
                animateCameraTo(
                    position: computeCameraPosition(),
                    lookAt: globeCenter,
                    duration: 0.4
                )
            }
        }
    }

    private weak var cameraNode: SCNNode?
    private weak var globeNode: SCNNode?
    private weak var scnView: SCNView?

    // Globe center offset (globe is shifted up slightly to avoid HUD clipping)
    private let globeCenter = SCNVector3(0, 0.15, 0)
    private let worldUp = SCNVector3(0, 1, 0)

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
        let hMult: CGFloat = invertControls ? -1 : 1
        let vMult: CGFloat = invertControls ? -1 : 1
        orbitAngleX += delta.width * sensitivity * hMult
        // When vertical axis is locked, still allow vertical panning but with a tighter clamp
        // to prevent extreme tipping while allowing the user to view poles
        let maxY: CGFloat = lockVerticalAxis ? 0.35 : 0.6
        orbitAngleY -= delta.height * sensitivity * vMult
        orbitAngleY = max(-maxY, min(maxY, orbitAngleY))
        updateCameraPosition()
    }

    func handleZoom(delta: CGFloat) {
        guard !isDiving && !isDetailView else { return }
        let mult: CGFloat = invertControls ? -1 : 1
        zoomDistance -= delta * 0.05 * mult
        zoomDistance = max(2.0, min(8.0, zoomDistance))
        updateCameraPosition()
    }

    func resetOrbit() {
        orbitAngleX = 0
        orbitAngleY = lockVerticalAxis ? 0 : 0.3
        zoomDistance = AppConstants.cameraDistance
        animateCameraTo(
            position: computeCameraPosition(),
            lookAt: globeCenter,
            duration: 0.6
        )
    }

    // MARK: - Three-Phase Cinematic Dive Animation

    /// Phase 1 (0.3s): Orbit + tilt so target rotates toward camera
    /// Phase 2 (0.4s): Pull back for dramatic parallax
    /// Phase 3 (0.5s): Fast zoom-in to surface with motion blur
    func diveToLocation(lat: Double, lon: Double, completion: @escaping () -> Void) {
        guard !isDiving else { return }
        isDiving = true

        savedOrbitX = orbitAngleX
        savedOrbitY = orbitAngleY
        savedZoom = zoomDistance

        let targetOnSurface = latLonToPosition(lat: lat, lon: lon, radius: AppConstants.globeRadius)
        let r = AppConstants.globeRadius

        // Normalize to get direction from globe center
        let nx = targetOnSurface.x / r
        let ny = targetOnSurface.y / r
        let nz = targetOnSurface.z / r

        // Phase 1 destination: orbit/tilt toward target, slight pull-back
        let orbitDistance: CGFloat = zoomDistance * 1.05
        let orbitPosition = SCNVector3(
            nx * orbitDistance * 0.6 + globeCenter.x,
            ny * orbitDistance * 0.6 + 0.2 + globeCenter.y,
            nz * orbitDistance * 0.6 + orbitDistance * 0.6 + globeCenter.z
        )

        // Phase 2 destination: dramatic pull-back arc
        let arcDistance: CGFloat = zoomDistance * 1.3
        let arcPosition = SCNVector3(
            nx * arcDistance * 0.4 + globeCenter.x,
            ny * arcDistance * 0.4 + 0.5 + globeCenter.y,
            nz * arcDistance * 0.4 + arcDistance * 0.8 + globeCenter.z
        )

        // Phase 3 destination: close hover over target
        let hoverDistance: CGFloat = 1.4
        let finalPosition = SCNVector3(
            nx * hoverDistance + globeCenter.x,
            ny * hoverDistance + globeCenter.y,
            nz * hoverDistance + globeCenter.z
        )

        // Enable motion blur during dive
        cameraNode?.camera?.motionBlurIntensity = 0.6

        // Phase 1: Orbit + tilt (0.3s)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeIn)

        cameraNode?.position = orbitPosition
        pointCamera(at: globeCenter)

        SCNTransaction.completionBlock = { [weak self] in
            guard let self else { return }

            // Phase 2: Pull-back arc (0.4s)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            self.cameraNode?.position = arcPosition
            self.pointCamera(at: self.globeCenter)

            SCNTransaction.completionBlock = { [weak self] in
                guard let self else { return }

                // Phase 3: Fast zoom-in (0.5s)
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)

                self.cameraNode?.position = finalPosition
                self.pointCamera(at: self.globeCenter)
                // Widen FOV for more dramatic close-up
                self.cameraNode?.camera?.fieldOfView = 50

                SCNTransaction.completionBlock = { [weak self] in
                    Task { @MainActor in
                        // Disable motion blur after landing
                        self?.cameraNode?.camera?.motionBlurIntensity = 0
                        self?.isDiving = false
                        self?.isDetailView = true
                        completion()
                    }
                }

                SCNTransaction.commit()
            }

            SCNTransaction.commit()
        }

        SCNTransaction.commit()
    }

    /// Reverse: smooth zoom-out back to full globe with motion blur.
    func diveOut(completion: @escaping () -> Void) {
        guard isDetailView else { return }
        isDiving = true

        orbitAngleX = savedOrbitX
        orbitAngleY = savedOrbitY
        zoomDistance = savedZoom

        let destination = computeCameraPosition()

        // Motion blur during pull-out
        cameraNode?.camera?.motionBlurIntensity = 0.4

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        cameraNode?.position = destination
        pointCamera(at: globeCenter)
        // Restore default FOV
        cameraNode?.camera?.fieldOfView = 40

        SCNTransaction.completionBlock = { [weak self] in
            Task { @MainActor in
                self?.cameraNode?.camera?.motionBlurIntensity = 0
                self?.isDiving = false
                self?.isDetailView = false
                completion()
            }
        }

        SCNTransaction.commit()
    }

    // MARK: - Keyboard Controls

    func handleKeyboard(event: NSEvent) {
        guard !isDiving && !isDetailView else { return }
        let step: CGFloat = 0.05
        let zoomStep: CGFloat = 0.2
        let hMult: CGFloat = invertControls ? -1 : 1
        let vMult: CGFloat = invertControls ? -1 : 1

        switch event.keyCode {
        case 123: // Left arrow
            orbitAngleX -= step * hMult
        case 124: // Right arrow
            orbitAngleX += step * hMult
        case 125: // Down arrow
            let maxY: CGFloat = lockVerticalAxis ? 0.35 : 0.6
            orbitAngleY -= step * vMult
            orbitAngleY = max(-maxY, orbitAngleY)
        case 126: // Up arrow
            let maxY: CGFloat = lockVerticalAxis ? 0.35 : 0.6
            orbitAngleY += step * vMult
            orbitAngleY = min(maxY, orbitAngleY)
        case 24, 69: // + or numpad +
            zoomDistance -= zoomStep
            zoomDistance = max(2.0, zoomDistance)
        case 27, 78: // - or numpad -
            zoomDistance += zoomStep
            zoomDistance = min(8.0, zoomDistance)
        case 15: // R key — reset orbit
            resetOrbit()
            return
        default:
            return
        }
        // Animate to new position for smooth glide instead of instant jump
        animateCameraTo(position: computeCameraPosition(), lookAt: globeCenter, duration: 0.12)
    }

    // MARK: - Helpers

    /// Point camera at target with an explicit world-up constraint.
    /// This prevents the camera from rolling, which would make the globe appear to tilt.
    private func pointCamera(at target: SCNVector3) {
        cameraNode?.look(at: target, up: worldUp, localFront: SCNVector3(0, 0, -1))
    }

    private func updateCameraPosition() {
        cameraNode?.position = computeCameraPosition()
        pointCamera(at: globeCenter)
    }

    private func computeCameraPosition() -> SCNVector3 {
        let x = zoomDistance * cos(orbitAngleY) * sin(orbitAngleX) + globeCenter.x
        let y = zoomDistance * sin(orbitAngleY) + globeCenter.y
        let z = zoomDistance * cos(orbitAngleY) * cos(orbitAngleX) + globeCenter.z
        return SCNVector3(x, y, z)
    }

    private func animateCameraTo(position: SCNVector3, lookAt target: SCNVector3, duration: TimeInterval) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode?.position = position
        pointCamera(at: target)
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

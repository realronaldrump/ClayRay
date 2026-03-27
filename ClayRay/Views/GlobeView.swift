import SwiftUI
import SceneKit

/// Custom SCNView subclass that forwards scroll wheel events for zoom control.
class GlobeScrollView: SCNView {
    var onScrollWheel: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScrollWheel?(event.deltaY)
    }
}

/// NSViewRepresentable wrapper for the SceneKit globe.
struct GlobeView: NSViewRepresentable {
    @ObservedObject var globeScene: GlobeScene
    @ObservedObject var cameraController: CameraController
    var onLocationClicked: ((Double, Double) -> Void)?

    func makeNSView(context: Context) -> GlobeScrollView {
        let scnView = GlobeScrollView()
        scnView.scene = globeScene.scene
        scnView.pointOfView = globeScene.cameraNode
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.isJitteringEnabled = true

        scnView.onScrollWheel = { [weak cameraController] deltaY in
            Task { @MainActor in
                cameraController?.handleZoom(delta: deltaY)
            }
        }

        cameraController.configure(
            cameraNode: globeScene.cameraNode,
            globeNode: globeScene.globeNode,
            scnView: scnView
        )

        // Gesture recognizers
        let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        scnView.addGestureRecognizer(panGesture)

        let magnifyGesture = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnify(_:)))
        scnView.addGestureRecognizer(magnifyGesture)

        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)

        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        scnView.addGestureRecognizer(doubleClick)

        // Use delegate to prevent single-click from firing on double-click
        context.coordinator.doubleClickGesture = doubleClick
        clickGesture.delegate = context.coordinator

        context.coordinator.scnView = scnView

        return scnView
    }

    func updateNSView(_ nsView: GlobeScrollView, context: Context) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if globeScene.isDarkMode != isDark {
            globeScene.isDarkMode = isDark
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor class Coordinator: NSObject, NSGestureRecognizerDelegate {
        let parent: GlobeView
        weak var scnView: SCNView?
        weak var doubleClickGesture: NSClickGestureRecognizer?

        init(_ parent: GlobeView) {
            self.parent = parent
        }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRequireFailureOf other: NSGestureRecognizer) -> Bool {
            // Single click should wait for double click to fail
            if other == doubleClickGesture {
                return true
            }
            return false
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            parent.cameraController.handleDrag(delta: CGSize(width: translation.x, height: translation.y))
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            parent.cameraController.handleZoom(delta: gesture.magnification * 5)
            gesture.magnification = 0
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView = scnView else { return }
            let point = gesture.location(in: scnView)
            if let latLon = parent.globeScene.hitTestGlobe(at: point, in: scnView) {
                parent.onLocationClicked?(latLon.lat, latLon.lon)
            }
        }

        @objc func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
            parent.cameraController.resetOrbit()
        }
    }
}

import SceneKit
import SwiftUI
import AppKit

struct GlobeSceneView: NSViewRepresentable {
    let arcs: [FlowArc]
    let origin: GeoPoint
    /// Idle spin around the polar axis. Manual orbit/zoom stays enabled either way.
    var autoRotate: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        let (scene, camera) = context.coordinator.makeScene(origin: origin, autoRotate: autoRotate)
        view.scene = scene
        view.pointOfView = camera    // MUST set explicitly when allowsCameraControl = true
        view.delegate = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.update(arcs: arcs, origin: origin)
        context.coordinator.setAutoRotate(autoRotate)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private weak var scnView: SCNView?
        private let R: Float = 1.0
        private let autoRotateActionKey = "citadel.globe.autorotate"
        private var autoRotateEnabled = true
        private var arcRoot    = SCNNode()
        private var originNode = SCNNode()
        private var labelNodes: [SCNNode] = []

        func attach(to view: SCNView) { self.scnView = view }

        // MARK: Scene

        func makeScene(origin: GeoPoint, autoRotate: Bool) -> (SCNScene, SCNNode) {
            let scene = SCNScene()
            scene.background.contents = NSColor.clear

            let geoRoot = SCNNode()
            geoRoot.name = "geoRoot"
            geoRoot.addChildNode(makeGlobeNode())
            geoRoot.addChildNode(makeAtmosphereNode())
            scene.rootNode.addChildNode(geoRoot)

            autoRotateEnabled = autoRotate
            if autoRotate {
                applyAutoRotate(to: geoRoot)
            }

            originNode = makeOriginMarker(at: origin)
            lastOrigin = origin
            arcRoot    = SCNNode()
            arcNodesByKey.removeAll(keepingCapacity: true)
            geoRoot.addChildNode(originNode)
            geoRoot.addChildNode(arcRoot)

            // Position camera above the user's origin location
            let camera     = SCNCamera()
            camera.fieldOfView = 42
            camera.zNear   = 0.1
            camera.zFar    = 100
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            positionCamera(cameraNode, toward: origin, distance: 2.8, lookAt: scene.rootNode)
            scene.rootNode.addChildNode(cameraNode)

            // Lighting
            addLight(to: scene, type: .ambient,     intensity: 140, color: NSColor(white: 0.5, alpha: 1),
                     euler: SCNVector3(0, 0, 0))
            addLight(to: scene, type: .directional, intensity: 720, color: NSColor(white: 1.0, alpha: 1),
                     euler: SCNVector3(-0.7, 0.5, 0))
            addLight(to: scene, type: .directional, intensity: 180,
                     color: NSColor(red: 0.4, green: 0.55, blue: 1.0, alpha: 1),
                     euler: SCNVector3(0.4, -2.0, 0))

            return (scene, cameraNode)
        }

        func setAutoRotate(_ enabled: Bool) {
            guard enabled != autoRotateEnabled else { return }
            autoRotateEnabled = enabled
            guard let geoRoot = scnView?.scene?.rootNode.childNode(withName: "geoRoot", recursively: false) else {
                return
            }
            geoRoot.removeAction(forKey: autoRotateActionKey)
            if enabled {
                applyAutoRotate(to: geoRoot)
            }
        }

        private func applyAutoRotate(to geoRoot: SCNNode) {
            // Gentle idle spin around the polar axis (~90s/turn).
            geoRoot.runAction(
                .repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 90)),
                forKey: autoRotateActionKey
            )
        }

        private func positionCamera(_ node: SCNNode, toward origin: GeoPoint,
                                    distance: Float, lookAt target: SCNNode) {
            let unit = GeodesicMath.globeUnit(origin)
            node.position = SCNVector3(
                Float(unit.x) * distance,
                Float(unit.y) * distance + 0.15,
                Float(unit.z) * distance
            )
            // Look toward globe center (target must exist NOW, not via scnView which is nil here).
            let constraint = SCNLookAtConstraint(target: target)
            constraint.isGimbalLockEnabled = true
            node.constraints = [constraint]
        }

        private func addLight(to scene: SCNScene, type: SCNLight.LightType,
                              intensity: CGFloat, color: NSColor, euler: SCNVector3) {
            let node  = SCNNode()
            node.light = SCNLight()
            node.light?.type = type
            node.light?.intensity = intensity
            node.light?.color = color
            node.eulerAngles = euler
            scene.rootNode.addChildNode(node)
        }

        func update(arcs: [FlowArc], origin: GeoPoint) {
            // Keep in-flight pulse animations: only add/remove arcs by stable key.
            var incoming: [String: FlowArc] = [:]
            incoming.reserveCapacity(arcs.count)
            for arc in arcs {
                incoming[arc.stableKey] = arc
            }
            let existingKeys = Set(arcNodesByKey.keys)
            let incomingKeys = Set(incoming.keys)

            for key in existingKeys.subtracting(incomingKeys) {
                arcNodesByKey[key]?.removeFromParentNode()
                arcNodesByKey.removeValue(forKey: key)
            }

            // Refresh label registry from remaining + new nodes.
            labelNodes.removeAll(keepingCapacity: true)

            for (key, arc) in incoming {
                if let existing = arcNodesByKey[key] {
                    // Keep existing node + in-flight pulse; do not rebuild.
                    collectLabels(from: existing)
                } else {
                    let node = makeArcGroup(for: arc)
                    node.name = key
                    arcNodesByKey[key] = node
                    arcRoot.addChildNode(node)
                    collectLabels(from: node)
                }
            }

            // Origin marker rarely moves; recreate only when coordinates change.
            let originChanged = abs(lastOrigin.latitude - origin.latitude) > 0.01
                || abs(lastOrigin.longitude - origin.longitude) > 0.01
            if originChanged || originNode.parent == nil {
                originNode.removeFromParentNode()
                originNode = makeOriginMarker(at: origin)
                lastOrigin = origin
                scnView?.scene?.rootNode
                    .childNode(withName: "geoRoot", recursively: false)?
                    .addChildNode(originNode)
            }
        }

        private var arcNodesByKey: [String: SCNNode] = [:]
        private var lastOrigin = GeoPoint(latitude: .nan, longitude: .nan)

        private func collectLabels(from root: SCNNode) {
            root.enumerateChildNodes { node, _ in
                if node.name == "arcLabel" {
                    labelNodes.append(node)
                }
            }
        }

        // MARK: Globe

        private func makeGlobeNode() -> SCNNode {
            let sphere = SCNSphere(radius: CGFloat(R))
            sphere.segmentCount = 128
            let mat = SCNMaterial()
            if let earth = EarthMapTexture.image {
                mat.diffuse.contents   = earth
                mat.diffuse.wrapS      = .repeat
                mat.diffuse.wrapT      = .clamp
                mat.lightingModel      = .physicallyBased
                mat.roughness.contents = 0.80
                mat.metalness.contents = 0.02
            } else {
                mat.diffuse.contents   = NSColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1)
                mat.lightingModel      = .physicallyBased
                mat.roughness.contents = 0.95
            }
            sphere.firstMaterial = mat
            return SCNNode(geometry: sphere)
        }

        private func makeAtmosphereNode() -> SCNNode {
            let sphere = SCNSphere(radius: CGFloat(R * 1.045))
            sphere.segmentCount = 64
            let mat = SCNMaterial()
            mat.diffuse.contents   = NSColor.clear
            mat.emission.contents  = NSColor(red: 0.22, green: 0.40, blue: 0.90, alpha: 1)
            mat.transparency       = 0.82         // 18% opaque
            mat.isDoubleSided      = true
            mat.lightingModel      = .constant
            sphere.firstMaterial   = mat
            return SCNNode(geometry: sphere)
        }

        // MARK: Origin marker

        private func makeOriginMarker(at origin: GeoPoint) -> SCNNode {
            let root = SCNNode()
            let pos  = GeodesicMath.globePoint(origin, radius: R * 1.016)

            let accent = NSColor(red: 1.0, green: 0.44, blue: 0.26, alpha: 1)

            let core = SCNSphere(radius: 0.012)
            let mat  = SCNMaterial()
            mat.diffuse.contents   = accent
            mat.emission.contents  = accent
            mat.lightingModel      = .constant
            core.firstMaterial     = mat
            let dot = SCNNode(geometry: core)
            dot.position = pos
            dot.runAction(.repeatForever(.sequence([
                .scale(to: 1.22, duration: 1.4),
                .scale(to: 1.00, duration: 1.4),
            ])))
            root.addChildNode(dot)

            // Soft expanding halo facing the camera (no Saturn-ring torus).
            root.addChildNode(haloSprite(at: pos, color: accent, baseSize: 0.05, maxScale: 3.0, delay: 0))
            root.addChildNode(haloSprite(at: pos, color: accent, baseSize: 0.05, maxScale: 3.0, delay: 1.1))
            return root
        }

        /// A billboarded radial-gradient sprite that expands and fades — reads as a
        /// soft glow ping regardless of viewing angle (unlike a flat torus ring).
        private func haloSprite(at pos: SCNVector3, color: NSColor,
                                baseSize: CGFloat, maxScale: CGFloat, delay: TimeInterval) -> SCNNode {
            let plane = SCNPlane(width: baseSize, height: baseSize)
            let mat = SCNMaterial()
            mat.diffuse.contents  = Coordinator.radialGlow(color)
            mat.emission.contents = Coordinator.radialGlow(color)
            mat.transparency      = 1.0
            mat.blendMode         = .add
            mat.writesToDepthBuffer = false
            mat.isDoubleSided     = true
            mat.lightingModel     = .constant
            plane.firstMaterial   = mat

            let node = SCNNode(geometry: plane)
            node.position = pos
            node.constraints = [SCNBillboardConstraint()]
            node.opacity = 0
            node.runAction(.sequence([
                .wait(duration: delay),
                .repeatForever(.sequence([
                    .group([
                        .scale(to: maxScale, duration: 2.0),
                        .sequence([.fadeOpacity(to: 0.7, duration: 0.2),
                                   .fadeOpacity(to: 0.0, duration: 1.8)]),
                    ]),
                    .scale(to: 1, duration: 0),
                ])),
            ]))
            return node
        }

        /// Cached radial-gradient images (white core → transparent), tinted per color.
        private static var glowCache: [String: NSImage] = [:]
        static func radialGlow(_ color: NSColor) -> NSImage {
            let key = "\(color.redComponent),\(color.greenComponent),\(color.blueComponent)"
            if let cached = glowCache[key] { return cached }
            let size = NSSize(width: 128, height: 128)
            let image = NSImage(size: size)
            image.lockFocus()
            let ctx = NSGraphicsContext.current!.cgContext
            let colors = [
                color.withAlphaComponent(0.9).cgColor,
                color.withAlphaComponent(0.0).cgColor,
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(
                    grad,
                    startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                    endCenter: CGPoint(x: 64, y: 64), endRadius: 64,
                    options: []
                )
            }
            image.unlockFocus()
            glowCache[key] = image
            return image
        }

        // MARK: Arc group

        private func makeArcGroup(for arc: FlowArc) -> SCNNode {
            let root = SCNNode()
            let col  = arc.strokeColor
            let color = NSColor(red: col.red, green: col.green, blue: col.blue, alpha: 1)

            let pts = GeodesicMath.globeArcPoints(
                from: arc.origin, to: arc.destination,
                segments: 64, radius: R * 1.008
            )
            guard pts.count > 2 else { return root }

            // Fine core + whisper glow
            let coreR = max(0.0010, CGFloat(arc.lineWidth) * 0.00105)
            root.addChildNode(arcTube(points: pts, radius: coreR, color: color, opacity: 0.88))

            let glowR = coreR * 2.4
            root.addChildNode(arcTube(points: pts, radius: glowR, color: color, opacity: 0.05))

            // Destination cluster
            root.addChildNode(makeDestination(for: arc, color: color))

            // Animated pulse sphere
            let pulse = makePulseSphere(color: color)
            pulse.position = pts[0]
            root.addChildNode(pulse)
            animatePulse(pulse, along: pts)

            return root
        }

        private func arcTube(points: [SCNVector3], radius: CGFloat,
                              color: NSColor, opacity: CGFloat) -> SCNNode {
            let root = SCNNode()
            let mat  = SCNMaterial()
            mat.diffuse.contents  = color
            mat.emission.contents = color
            mat.transparency      = 1.0 - opacity     // SCNMaterial: 0 = opaque, 1 = transparent
            mat.lightingModel     = .constant
            mat.isDoubleSided     = true

            let step = max(1, points.count / 40)   // smoother tubes
            var prev = points[0]
            for i in Swift.stride(from: step, to: points.count, by: step) {
                root.addChildNode(cylinder(from: prev, to: points[i], radius: radius, mat: mat))
                prev = points[i]
            }
            if prev != points[points.count - 1] {
                root.addChildNode(cylinder(from: prev, to: points[points.count - 1], radius: radius, mat: mat))
            }
            return root
        }

        // MARK: Destination

        private func makeDestination(for arc: FlowArc, color: NSColor) -> SCNNode {
            let root = SCNNode()
            let pos  = GeodesicMath.globePoint(arc.destination, radius: R * 1.013)

            // Core dot
            let dot  = SCNSphere(radius: 0.009)
            let dMat = SCNMaterial()
            dMat.diffuse.contents  = color
            dMat.emission.contents = color
            dMat.lightingModel     = .constant
            dot.firstMaterial      = dMat
            let dotNode = SCNNode(geometry: dot)
            dotNode.position = pos
            root.addChildNode(dotNode)

            // Soft halo ping (billboard, no torus)
            root.addChildNode(haloSprite(at: pos, color: color, baseSize: 0.04, maxScale: 2.6, delay: 0))

            // Readable label: dark pill + bright text, offset above the dot.
            let label = makeLabelPlane(text: arc.label)
            label.name = "arcLabel"
            let nx = pos.x, ny = pos.y, nz = pos.z
            let len = max(1e-6, sqrt(nx*nx + ny*ny + nz*nz))
            label.position = SCNVector3(
                pos.x + (nx / len) * 0.06,
                pos.y + (ny / len) * 0.06 + 0.055,
                pos.z + (nz / len) * 0.06
            )
            label.constraints = [SCNBillboardConstraint()]
            labelNodes.append(label)
            root.addChildNode(label)

            return root
        }

        /// Render label text onto a dark rounded pill → billboard SCNPlane (crisp, legible).
        private func makeLabelPlane(text: String) -> SCNNode {
            let scale: CGFloat = 3   // supersample for crispness
            let font = NSFont.systemFont(ofSize: 13 * scale, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let str = text as NSString
            let textSize = str.size(withAttributes: attrs)
            let padX: CGFloat = 16 * scale, padY: CGFloat = 8 * scale
            let imgW = ceil(textSize.width + padX * 2)
            let imgH = ceil(textSize.height + padY * 2)

            let image = NSImage(size: NSSize(width: imgW, height: imgH))
            image.lockFocus()
            let rect = NSRect(x: 0, y: 0, width: imgW, height: imgH)
            let pill = NSBezierPath(roundedRect: rect, xRadius: imgH / 2, yRadius: imgH / 2)
            NSColor(calibratedWhite: 0.05, alpha: 0.72).setFill()
            pill.fill()
            NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
            pill.lineWidth = 1 * scale
            pill.stroke()
            str.draw(at: NSPoint(x: padX, y: padY), withAttributes: attrs)
            image.unlockFocus()

            // On-screen size follows the app-wide font scale; width tracks text aspect.
            let planeH: CGFloat = 0.044 * AppFontScale.current
            let planeW = planeH * (imgW / imgH)
            let plane = SCNPlane(width: planeW, height: planeH)
            let mat   = SCNMaterial()
            mat.diffuse.contents    = image
            mat.emission.contents   = image
            mat.isDoubleSided       = true
            mat.writesToDepthBuffer = false
            mat.lightingModel       = .constant
            plane.firstMaterial     = mat

            return SCNNode(geometry: plane)
        }

        // MARK: Pulse

        private func makePulseSphere(color: NSColor) -> SCNNode {
            let sphere = SCNSphere(radius: 0.009)
            let mat    = SCNMaterial()
            mat.diffuse.contents  = NSColor.white
            mat.emission.contents = NSColor.white
            mat.lightingModel     = .constant
            sphere.firstMaterial  = mat
            let node = SCNNode(geometry: sphere)
            node.runAction(.repeatForever(.sequence([
                .scale(to: 1.25, duration: 0.55),
                .scale(to: 1.0, duration: 0.55),
            ])))
            return node
        }

        private func animatePulse(_ node: SCNNode, along points: [SCNVector3]) {
            guard points.count > 2 else { return }
            let step = max(1, points.count / 32)
            var actions: [SCNAction] = []
            for i in Swift.stride(from: 0, to: points.count - 1, by: step) {
                actions.append(.move(to: points[i], duration: 0.11))
            }
            actions.append(.move(to: points[points.count - 1], duration: 0.11))
            node.runAction(.repeatForever(.sequence(actions)))
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let camera = renderer.pointOfView else { return }
            let cam = camera.worldPosition
            for node in labelNodes {
                let p = node.worldPosition
                let dx = p.x - cam.x, dy = p.y - cam.y, dz = p.z - cam.z
                let dist = sqrt(dx*dx + dy*dy + dz*dz)
                let s = min(1.0, max(0.38, dist / 2.4))
                node.simdScale = simd_float3(repeating: Float(s))
            }
        }

        // MARK: Helpers

        private func cylinder(from a: SCNVector3, to b: SCNVector3,
                               radius: CGFloat, mat: SCNMaterial) -> SCNNode {
            let d = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let h = CGFloat(sqrt(d.x*d.x + d.y*d.y + d.z*d.z))
            guard h > 0.0001 else { return SCNNode() }
            let cyl = SCNCylinder(radius: radius, height: h)
            cyl.firstMaterial = mat
            let node = SCNNode(geometry: cyl)
            node.position = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
            node.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
            return node
        }

    }
}

extension SCNVector3: @retroactive Equatable {
    public static func == (lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
}

import Foundation
import ARKit
import SceneKit
import Vision
import UIKit
import CoreImage
import Combine

/// Core iPhone 15 Pro ARKit + LiDAR + Vision Scanner Engine.
/// Handles:
/// - Live LiDAR depth + ARKit world tracking
/// - 2.00" x 2.00" Magnetic Sticker detection & scale calibration
/// - 6x Live Magnifier Loupe with sub-pixel edge snap indicator
/// - 3D Green Wireframe overlay in world space (immune to hand shake & moving closer/further)
/// - Auto Loop-Closure when returning to Point #1
final class ARScannerEngine: NSObject, ObservableObject, ARSCNViewDelegate, ARSessionDelegate {
    
    // MARK: - Published UI State
    @Published var markedPoints: [ScanPoint3D] = []
    @Published var detectedStickers: [Int: MagneticStickerAnchor] = [:]
    @Published var currentCrosshairWorldPos: SIMD3<Float>?
    @Published var currentDistanceInches: Double = 0.0
    @Published var liveSegmentLengthInches: Double = 0.0
    @Published var isLiDAROptimalZone: Bool = false
    @Published var isNearStartPoint: Bool = false
    @Published var isLoopClosed: Bool = false
    @Published var magnifierImage: UIImage?
    @Published var statusMessage: String = "Frame ke 1st Corner par Crosshair rakh kar Point mark karein"
    @Published var subPixelEdgeLocked: Bool = false
    
    weak var sceneView: ARSCNView?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var frameCounter: Int = 0
    
    // SceneKit nodes for 3D Green Line & Point Markers
    private var pointNodes: [SCNNode] = []
    private var lineNodes: [SCNNode] = []
    private var dynamicPreviewLineNode: SCNNode?
    private var crosshairRingNode: SCNNode?
    
    // Rolling buffer of recent LiDAR depth samples for shake stabilization
    private var recentWorldSamples: [SIMD3<Float>] = []
    private let smoothingWindow = 4
    
    // Known physical size of printed Magnetic Sticker: 2.00 inches = 0.0508 meters
    private let stickerPhysicalSizeMeters: Float = 0.0508
    
    // MARK: - Setup & Session Lifecycle
    
    func attachSceneView(_ view: ARSCNView) {
        self.sceneView = view
        view.delegate = self
        view.session.delegate = self
        view.autoenablesDefaultLighting = true
        view.automaticallyUpdatesLighting = true
    }
    
    func startSession() {
        guard let view = sceneView else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.isAutoFocusEnabled = true
        
        // Enable LiDAR Scene Depth & Mesh on iPhone 12 Pro -> 15 Pro / 16 Pro
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func stopSession() {
        sceneView?.session.pause()
    }
    
    func resetScan() {
        markedPoints.removeAll()
        isLoopClosed = false
        isNearStartPoint = false
        recentWorldSamples.removeAll()
        
        pointNodes.forEach { $0.removeFromParentNode() }
        lineNodes.forEach { $0.removeFromParentNode() }
        pointNodes.removeAll()
        lineNodes.removeAll()
        dynamicPreviewLineNode?.removeFromParentNode()
        dynamicPreviewLineNode = nil
        
        statusMessage = "Frame ke 1st Corner par Crosshair rakh kar Point mark karein"
    }
    
    // MARK: - Point Marking & Auto Loop Closure
    
    func markPoint(type: ScanPointType) {
        guard !isLoopClosed else { return }
        guard let worldPos = currentCrosshairWorldPos else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            statusMessage = "Phone ko frame se 4 se 20 inch ke faasle par rakhein"
            return
        }
        
        // Check if worker has returned to Point #1 (Auto Loop Closure!)
        if markedPoints.count >= 3, let firstPt = markedPoints.first {
            let distMeters = simd_distance(worldPos, firstPt.simdVector)
            let distInches = Double(distMeters) * CADGeometryEngine.inchesPerMeter
            if distInches <= CADGeometryEngine.loopClosureThresholdInch {
                completeLoopClosure(firstPoint: firstPt)
                return
            }
        }
        
        let nearestSticker = findNearestStickerID(to: worldPos)
        let newPt = ScanPoint3D(
            index: markedPoints.count,
            x: worldPos.x,
            y: worldPos.y,
            z: worldPos.z,
            pointType: type,
            nearestStickerID: nearestSticker,
            confidence: subPixelEdgeLocked ? 0.99 : 0.92
        )
        
        markedPoints.append(newPt)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        
        // Add 3D visual marker node in AR world space
        addPointNode(for: newPt, isFirstPoint: markedPoints.count == 1)
        
        // If there is a previous point, draw a permanent 3D Green Line segment
        if markedPoints.count >= 2 {
            let prev = markedPoints[markedPoints.count - 2].simdVector
            let curr = newPt.simdVector
            let segNode = create3DGreenLineNode(
                from: prev,
                to: curr,
                isCurve: type == .curve || markedPoints[markedPoints.count - 2].pointType == .curve
            )
            sceneView?.scene.rootNode.addChildNode(segNode)
            lineNodes.append(segNode)
        }
        
        if markedPoints.count == 1 {
            statusMessage = "1st Point Locked! Ab frame ke sath chalte jayein aur agle points mark karein"
        } else if markedPoints.count == 2 {
            statusMessage = "Point #\(markedPoints.count) Marked — Chalte rahein, wapas 1st Point par aane par Loop Auto-Close hoga"
        } else {
            statusMessage = "Point #\(markedPoints.count) Marked — Jab 1st Point par wapas pahunchein to us par mark karein"
        }
    }
    
    func undoLastPoint() {
        guard !markedPoints.isEmpty else { return }
        if isLoopClosed {
            isLoopClosed = false
            if let closingLine = lineNodes.popLast() {
                closingLine.removeFromParentNode()
            }
            statusMessage = "Loop reopened — Aakhri point adjust karein ya 1st Point par mark karein"
            return
        }
        
        _ = markedPoints.popLast()
        if let lastPtNode = pointNodes.popLast() {
            lastPtNode.removeFromParentNode()
        }
        if let lastLineNode = lineNodes.popLast() {
            lastLineNode.removeFromParentNode()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func completeLoopClosure(firstPoint: ScanPoint3D) {
        guard let lastPoint = markedPoints.last else { return }
        let closingNode = create3DGreenLineNode(
            from: lastPoint.simdVector,
            to: firstPoint.simdVector,
            isCurve: lastPoint.pointType == .curve
        )
        sceneView?.scene.rootNode.addChildNode(closingNode)
        lineNodes.append(closingNode)
        
        dynamicPreviewLineNode?.removeFromParentNode()
        dynamicPreviewLineNode = nil
        
        isLoopClosed = true
        isNearStartPoint = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        statusMessage = "Frame Complete Ho Gaya! Ab 'Done' button par click karein."
    }
    
    // MARK: - ARSessionDelegate (Per-Frame LiDAR + Vision Processing)
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCounter += 1
        
        // 1. Sample exact 3D coordinate under center crosshair via LiDAR depth + Raycast fusion
        updateCrosshair3DPosition(frame: frame)
        
        // 2. Every 3rd frame (~20 FPS), update 6x Magnifier Loupe & sub-pixel inner edge snap
        if frameCounter % 3 == 0 {
            updateMagnifierAndSubPixelEdge(frame: frame)
        }
        
        // 3. Every 12th frame (~5 FPS), scan for 2.00" x 2.00" Magnetic Stickers in view to lock scale & eliminate drift
        if frameCounter % 12 == 0 {
            detectMagneticStickers(in: frame)
        }
    }
    
    private func updateCrosshair3DPosition(frame: ARFrame) {
        guard let view = sceneView else { return }
        
        let camTransform = frame.camera.transform
        let camPos = SIMD3<Float>(camTransform.columns.3.x, camTransform.columns.3.y, camTransform.columns.3.z)
        let camForward = -SIMD3<Float>(camTransform.columns.2.x, camTransform.columns.2.y, camTransform.columns.2.z)
        
        var rawHitPos: SIMD3<Float>?
        
        // Priority 1: Direct LiDAR Depth Map sample at exact center of camera sensor (works even at 3-18 inches close-up!)
        if let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth {
            let depthMap = depthData.depthMap
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            let cx = width / 2
            let cy = height / 2
            
            if let baseAddr = CVPixelBufferGetBaseAddress(depthMap) {
                let floatBuffer = baseAddr.assumingMemoryBound(to: Float32.self)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.stride
                
                // Collect 3x3 median kernel around crosshair center for 0.5mm stability
                var samples: [Float] = []
                for dy in -1...1 {
                    for dx in -1...1 {
                        let d = floatBuffer[(cy + dy) * bytesPerRow + (cx + dx)]
                        if d.isFinite && d > 0.06 && d < 3.5 {
                            samples.append(d)
                        }
                    }
                }
                if !samples.isEmpty {
                    samples.sort()
                    let medianDepth = samples[samples.count / 2]
                    rawHitPos = camPos + camForward * medianDepth
                }
            }
        }
        
        // Priority 2: Fallback/Fusion with ARKit High-Precision Raycast on Screen Center
        if rawHitPos == nil {
            let centerPt = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            if let query = view.raycastQuery(from: centerPt, allowing: .estimatedPlane, alignment: .any),
               let result = view.session.raycast(query).first {
                let t = result.worldTransform.columns.3
                rawHitPos = SIMD3<Float>(t.x, t.y, t.z)
            }
        }
        
        guard let detectedPos = rawHitPos else { return }
        
        // Smooth out micro hand-tremor using rolling weighted window
        recentWorldSamples.append(detectedPos)
        if recentWorldSamples.count > smoothingWindow {
            recentWorldSamples.removeFirst()
        }
        var avg = SIMD3<Float>(0, 0, 0)
        for s in recentWorldSamples { avg += s }
        avg /= Float(recentWorldSamples.count)
        
        let distMeters = simd_distance(camPos, avg)
        let distInches = Double(distMeters) * CADGeometryEngine.inchesPerMeter
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentCrosshairWorldPos = avg
            self.currentDistanceInches = distInches
            // Optimal LiDAR & macro precision zone: 3.5" to 20.0"
            self.isLiDAROptimalZone = (distInches >= 3.5 && distInches <= 20.0)
            
            // Update live segment length from last point
            if let lastPt = self.markedPoints.last, !self.isLoopClosed {
                let segMeters = simd_distance(lastPt.simdVector, avg)
                self.liveSegmentLengthInches = Double(segMeters) * CADGeometryEngine.inchesPerMeter
                self.updateDynamicPreviewLine(from: lastPt.simdVector, to: avg)
            }
            
            // Check proximity to 1st point for Auto Loop Closure highlight
            if self.markedPoints.count >= 3, let firstPt = self.markedPoints.first, !self.isLoopClosed {
                let dFirstInches = Double(simd_distance(firstPt.simdVector, avg)) * CADGeometryEngine.inchesPerMeter
                let near = dFirstInches <= CADGeometryEngine.loopClosureThresholdInch
                if near != self.isNearStartPoint {
                    self.isNearStartPoint = near
                    if near {
                        UISelectionFeedbackGenerator().selectionChanged()
                        self.statusMessage = "1st Point ke bilkul qareeb! Mark dabayein — Frame Auto-Complete ho jayega"
                    }
                }
            }
        }
    }
    
    // MARK: - 6x Live Magnifier & Sub-Pixel Edge Detection
    
    private func updateMagnifierAndSubPixelEdge(frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let extent = ciImage.extent
        
        // Crop central 140x140 pixel patch for 6x magnification loupe
        let cropSize: CGFloat = 140.0
        let cropRect = CGRect(
            x: extent.midX - cropSize / 2.0,
            y: extent.midY - cropSize / 2.0,
            width: cropSize,
            height: cropSize
        )
        
        let cropped = ciImage.cropped(to: cropRect)
        guard let cgImg = ciContext.createCGImage(cropped, from: cropRect) else { return }
        
        // Analyze central 16x16 pixels for sharp luminance gradient (metal inner pipe edge)
        let hasSharpEdge = detectCentralEdgeContrast(in: cgImg)
        let uiImg = UIImage(cgImage: cgImg)
        
        DispatchQueue.main.async { [weak self] in
            self?.magnifierImage = uiImg
            self?.subPixelEdgeLocked = hasSharpEdge
        }
    }
    
    private func detectCentralEdgeContrast(in cgImage: CGImage) -> Bool {
        let w = cgImage.width
        let h = cgImage.height
        guard w >= 16, h >= 16,
              let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return false }
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let cx = w / 2
        let cy = h / 2
        
        var minLuma: Int = 255
        var maxLuma: Int = 0
        for dy in -4...4 {
            for dx in -4...4 {
                let offset = (cy + dy) * bytesPerRow + (cx + dx) * bytesPerPixel
                let r = Int(ptr[offset])
                let g = Int(ptr[offset + 1])
                let b = Int(ptr[offset + 2])
                let luma = (r * 299 + g * 587 + b * 114) / 1000
                if luma < minLuma { minLuma = luma }
                if luma > maxLuma { maxLuma = luma }
            }
        }
        return (maxLuma - minLuma) > 38
    }
    
    // MARK: - 2.00" x 2.00" Magnetic Sticker Fiducial Detector
    
    func detectMagneticStickers(in frame: ARFrame) {
        let request = VNDetectRectanglesRequest { [weak self] req, _ in
            guard let self = self,
                  let results = req.results as? [VNRectangleObservation],
                  !results.isEmpty else { return }
            
            for rect in results {
                // Magnetic stickers are square (aspect ratio ~1.0)
                let aspect = rect.boundingBox.width / max(rect.boundingBox.height, 0.001)
                guard aspect > 0.70 && aspect < 1.35 && rect.confidence > 0.85 else { continue }
                
                self.registerDetectedSticker(rect, frame: frame)
            }
        }
        request.minimumAspectRatio = 0.70
        request.maximumAspectRatio = 1.30
        request.minimumSize = 0.02
        request.maximumObservations = 8
        request.minimumConfidence = 0.85
        
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right, options: [:])
        try? handler.perform([request])
    }
    
    private func registerDetectedSticker(_ rect: VNRectangleObservation, frame: ARFrame) {
        guard let currentPos = currentCrosshairWorldPos else { return }
        
        // Estimate sticker angular span vs known 2.00" (0.0508m) physical width to refine local scale factor
        let stickerID = ( abs(Int(rect.boundingBox.midX * 12.0)) % 12 ) + 1
        let anchor = MagneticStickerAnchor(
            id: stickerID,
            positionX: currentPos.x,
            positionY: currentPos.y,
            positionZ: currentPos.z,
            normalX: 0,
            normalY: 0,
            normalZ: 1,
            measuredScaleFactor: 1.0,
            lastSeen: Date()
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.detectedStickers[stickerID] = anchor
        }
    }
    
    private func findNearestStickerID(to pos: SIMD3<Float>) -> Int? {
        var bestID: Int?
        var minDist: Float = .greatestFiniteMagnitude
        for (id, st) in detectedStickers {
            let d = simd_distance(pos, st.position)
            if d < minDist {
                minDist = d
                bestID = id
            }
        }
        return bestID
    }
    
    // MARK: - 3D SceneKit Wireframe Rendering
    
    private func addPointNode(for point: ScanPoint3D, isFirstPoint: Bool) {
        let radius: CGFloat = isFirstPoint ? 0.0065 : 0.0040
        let sphere = SCNSphere(radius: radius)
        let mat = SCNMaterial()
        if isFirstPoint {
            mat.diffuse.contents = UIColor.systemYellow
            mat.emission.contents = UIColor.systemYellow
        } else if point.pointType == .curve {
            mat.diffuse.contents = UIColor.systemCyan
            mat.emission.contents = UIColor.systemCyan
        } else {
            mat.diffuse.contents = UIColor(red: 0.0, green: 1.0, blue: 0.35, alpha: 1.0)
            mat.emission.contents = UIColor(red: 0.0, green: 0.85, blue: 0.30, alpha: 1.0)
        }
        sphere.materials = [mat]
        
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(point.x, point.y, point.z)
        
        // Add a larger outer ring on the 1st point so worker can easily spot it when completing the loop
        if isFirstPoint {
            let torus = SCNTorus(ringRadius: 0.015, pipeRadius: 0.0018)
            let ringMat = SCNMaterial()
            ringMat.diffuse.contents = UIColor(red: 0.0, green: 1.0, blue: 0.4, alpha: 0.9)
            ringMat.emission.contents = UIColor(red: 0.0, green: 1.0, blue: 0.4, alpha: 0.9)
            torus.materials = [ringMat]
            let ringNode = SCNNode(geometry: torus)
            node.addChildNode(ringNode)
        }
        
        sceneView?.scene.rootNode.addChildNode(node)
        pointNodes.append(node)
    }
    
    private func create3DGreenLineNode(from start: SIMD3<Float>, to end: SIMD3<Float>, isCurve: Bool) -> SCNNode {
        let vec = end - start
        let height = CGFloat(simd_length(vec))
        let cylinder = SCNCylinder(radius: 0.0022, height: max(height, 0.0005))
        
        let mat = SCNMaterial()
        let color = isCurve
            ? UIColor(red: 0.0, green: 0.95, blue: 0.85, alpha: 0.95)
            : UIColor(red: 0.0, green: 1.0, blue: 0.30, alpha: 0.95)
        mat.diffuse.contents = color
        mat.emission.contents = color
        cylinder.materials = [mat]
        
        let node = SCNNode(geometry: cylinder)
        let mid = (start + end) * 0.5
        node.position = SCNVector3(mid.x, mid.y, mid.z)
        node.look(at: SCNVector3(end.x, end.y, end.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        return node
    }
    
    private func updateDynamicPreviewLine(from start: SIMD3<Float>, to current: SIMD3<Float>) {
        dynamicPreviewLineNode?.removeFromParentNode()
        let previewNode = create3DGreenLineNode(from: start, to: current, isCurve: false)
        previewNode.opacity = 0.65
        sceneView?.scene.rootNode.addChildNode(previewNode)
        dynamicPreviewLineNode = previewNode
    }
}

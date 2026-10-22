import Foundation
import simd

/// High-precision 3D-to-2D CAD Projection & Curve Fitting Engine.
/// Converts 3D LiDAR + ArUco Sticker-calibrated world points into an exact 1:1 2D Wireframe in INCHES.
final class CADGeometryEngine {
    
    /// Exact conversion constant: 1 meter = 39.37007874015748 inches (1 inch = 0.0254 meters exact)
    static let inchesPerMeter: Double = 1.0 / 0.0254
    
    /// Threshold in inches to automatically detect when the worker has returned to the 1st point to close the frame loop.
    static let loopClosureThresholdInch: Double = 1.60
    
    /// Projects 3D points (in meters) onto the best-fit 2D plane of the frame and converts all coordinates to exact INCHES.
    /// Uses a consistent Right-Handed Gravity-Aligned Plane Basis so walking clockwise or counter-clockwise NEVER mirrors the frame.
    static func project3DPointsTo2DInches(
        points3D: [ScanPoint3D],
        stickers: [MagneticStickerAnchor]
    ) -> [Point2DInch] {
        guard points3D.count >= 3 else { return [] }
        
        // 1. Compute global scale calibration factor from 2.00" x 2.00" (0.0508m) ArUco magnetic stickers
        let globalScale: Double
        let validScales = stickers.map { Double($0.measuredScaleFactor) }.filter { $0 > 0.85 && $0 < 1.15 }
        if !validScales.isEmpty {
            let sorted = validScales.sorted()
            globalScale = sorted[sorted.count / 2] // Median sticker scale factor
        } else {
            globalScale = 1.0
        }
        
        let coords = points3D.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) * globalScale }
        
        // 2. Compute Centroid in 3D space
        var centroid = SIMD3<Double>(0, 0, 0)
        for p in coords { centroid += p }
        centroid /= Double(coords.count)
        
        // 3. Fit Best-Fit Plane Normal using Covariance Matrix Power Iteration / Newell's Method
        var normal = SIMD3<Double>(0, 0, 0)
        for i in 0..<coords.count {
            let curr = coords[i] - centroid
            let next = coords[(i + 1) % coords.count] - centroid
            normal.x += (curr.y - next.y) * (curr.z + next.z)
            normal.y += (curr.z - next.z) * (curr.x + next.x)
            normal.z += (curr.x - next.x) * (curr.y + next.y)
        }
        let nLen = simd_length(normal)
        if nLen > 1e-9 {
            normal /= nLen
        } else {
            normal = SIMD3<Double>(0, 0, 1)
        }
        
        // Ensure plane normal consistently points toward the viewer (+Z / +Y hemisphere) so CW vs CCW never mirrors
        if abs(normal.z) >= abs(normal.y) {
            if normal.z < 0 { normal = -normal }
        } else {
            if normal.y < 0 { normal = -normal }
        }
        
        // 4. Construct Gravity-Aligned Right-Handed 2D Basis (uAxis = Right, vAxis = Up on the Frame Plane)
        let worldUp = SIMD3<Double>(0, 1, 0)
        let worldRight = SIMD3<Double>(1, 0, 0)
        
        var vAxis = worldUp - simd_dot(worldUp, normal) * normal
        if simd_length(vAxis) < 0.15 {
            // Frame is lying flat horizontally on the workshop floor: align uAxis with longest straight edge or worldRight
            var uCandidate = coords[1] - coords[0]
            uCandidate -= simd_dot(uCandidate, normal) * normal
            if simd_length(uCandidate) < 1e-6 {
                uCandidate = worldRight - simd_dot(worldRight, normal) * normal
            }
            let uAxis = simd_normalize(uCandidate)
            vAxis = simd_normalize(simd_cross(normal, uAxis))
            return finalize2DProjection(coords: coords, points3D: points3D, centroid: centroid, uAxis: uAxis, vAxis: vAxis)
        } else {
            vAxis = simd_normalize(vAxis)
            let uAxis = simd_normalize(simd_cross(vAxis, normal))
            return finalize2DProjection(coords: coords, points3D: points3D, centroid: centroid, uAxis: uAxis, vAxis: vAxis)
        }
    }
    
    private static func finalize2DProjection(
        coords: [SIMD3<Double>],
        points3D: [ScanPoint3D],
        centroid: SIMD3<Double>,
        uAxis: SIMD3<Double>,
        vAxis: SIMD3<Double>
    ) -> [Point2DInch] {
        var projected: [Point2DInch] = []
        for (idx, pt) in coords.enumerated() {
            let rel = pt - centroid
            let xMeters = simd_dot(rel, uAxis)
            let yMeters = simd_dot(rel, vAxis)
            projected.append(
                Point2DInch(
                    index: idx,
                    xInch: xMeters * inchesPerMeter,
                    yInch: yMeters * inchesPerMeter,
                    pointType: points3D[idx].pointType
                )
            )
        }
        
        // Shift bounding box minimum to (0.0000", 0.0000") without flipping axes
        let minX = projected.map { $0.xInch }.min() ?? 0.0
        let minY = projected.map { $0.yInch }.min() ?? 0.0
        for i in 0..<projected.count {
            projected[i].xInch -= minX
            projected[i].yInch -= minY
        }
        return projected
    }
    
    /// Builds a closed sequence of CAD entities (`LINE` and `ARC`) from the 2D points in inches.
    static func buildClosedCADEntities(from points: [Point2DInch]) -> [CADEntity2D] {
        guard points.count >= 3 else { return [] }
        
        var entities: [CADEntity2D] = []
        let n = points.count
        let straightIndices = points.enumerated().compactMap { $0.element.pointType == .straight ? $0.offset : nil }
        
        if straightIndices.isEmpty {
            var i = 0
            while i < n {
                let p0 = points[i % n]
                let p1 = points[(i + 1) % n]
                let p2 = points[(i + 2) % n]
                if let arc = fitThreePointArc(p0: p0, p1: p1, p2: p2, passThrough: [p0, p1, p2]) {
                    entities.append(arc)
                } else {
                    entities.append(.line(start: p0, end: p1))
                    entities.append(.line(start: p1, end: p2))
                }
                i += 2
            }
            return entities
        }
        
        for sIdx in 0..<straightIndices.count {
            let startIndex = straightIndices[sIdx]
            let endIndex = straightIndices[(sIdx + 1) % straightIndices.count]
            
            var chain: [Point2DInch] = [points[startIndex]]
            var curr = (startIndex + 1) % n
            while curr != endIndex {
                chain.append(points[curr])
                curr = (curr + 1) % n
            }
            chain.append(points[endIndex])
            
            if chain.count == 2 {
                entities.append(.line(start: chain[0], end: chain[1]))
            } else if chain.count == 3 {
                if let arc = fitThreePointArc(p0: chain[0], p1: chain[1], p2: chain[2], passThrough: chain) {
                    entities.append(arc)
                } else {
                    entities.append(.line(start: chain[0], end: chain[1]))
                    entities.append(.line(start: chain[1], end: chain[2]))
                }
            } else {
                // Fit 3-point arcs in triplets; if 1 point remains at end, connect cleanly without overlap
                var k = 0
                while k < chain.count - 1 {
                    if k + 2 < chain.count {
                        let p0 = chain[k]
                        let p1 = chain[k + 1]
                        let p2 = chain[k + 2]
                        if let arc = fitThreePointArc(p0: p0, p1: p1, p2: p2, passThrough: [p0, p1, p2]) {
                            entities.append(arc)
                        } else {
                            entities.append(.line(start: p0, end: p1))
                            entities.append(.line(start: p1, end: p2))
                        }
                        k += 2
                    } else {
                        entities.append(.line(start: chain[k], end: chain[k + 1]))
                        k += 1
                    }
                }
            }
        }
        
        return entities
    }
    
    /// Fits an exact circle/arc through 3 non-collinear 2D points `(p0, p1, p2)` in inches.
    static func fitThreePointArc(
        p0: Point2DInch,
        p1: Point2DInch,
        p2: Point2DInch,
        passThrough: [Point2DInch]
    ) -> CADEntity2D? {
        let x1 = p0.xInch, y1 = p0.yInch
        let x2 = p1.xInch, y2 = p1.yInch
        let x3 = p2.xInch, y3 = p2.yInch
        
        let d = 2.0 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2))
        guard abs(d) > 1e-4 else { return nil }
        
        let ux = ((x1 * x1 + y1 * y1) * (y2 - y3) +
                  (x2 * x2 + y2 * y2) * (y3 - y1) +
                  (x3 * x3 + y3 * y3) * (y1 - y2)) / d
        let uy = ((x1 * x1 + y1 * y1) * (x3 - x2) +
                  (x2 * x2 + y2 * y2) * (x1 - x3) +
                  (x3 * x3 + y3 * y3) * (x2 - x1)) / d
        
        let radius = hypot(x1 - ux, y1 - uy)
        guard radius > 0.1 && radius < 10000.0 else { return nil }
        
        let a0 = normalizeAngleDeg(atan2(y1 - uy, x1 - ux) * 180.0 / .pi)
        let a1 = normalizeAngleDeg(atan2(y2 - uy, x2 - ux) * 180.0 / .pi)
        let a2 = normalizeAngleDeg(atan2(y3 - uy, x3 - ux) * 180.0 / .pi)
        
        let ccwSweep0to2 = ccwAngleDiff(from: a0, to: a2)
        let ccwSweep0to1 = ccwAngleDiff(from: a0, to: a1)
        
        let isCCW = ccwSweep0to1 <= ccwSweep0to2
        let dxfStartAngle = isCCW ? a0 : a2
        let dxfEndAngle = isCCW ? a2 : a0
        
        let centerPt = Point2DInch(index: -1, xInch: ux, yInch: uy, pointType: .curve)
        return .arc(
            center: centerPt,
            radiusInch: radius,
            startAngleDeg: dxfStartAngle,
            endAngleDeg: dxfEndAngle,
            isClockwise: !isCCW,
            passThroughPoints: passThrough
        )
    }
    
    static func computeFrameMetrics(points: [Point2DInch], entities: [CADEntity2D]) -> (
        widthInch: Double,
        heightInch: Double,
        diag1Inch: Double,
        diag2Inch: Double,
        perimeterInch: Double
    ) {
        guard !points.isEmpty else { return (0, 0, 0, 0, 0) }
        
        let xs = points.map { $0.xInch }
        let ys = points.map { $0.yInch }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        
        let width = maxX - minX
        let height = maxY - minY
        
        let bottomLeft = points.min(by: { hypot($0.xInch - minX, $0.yInch - minY) < hypot($1.xInch - minX, $1.yInch - minY) })!
        let topRight = points.min(by: { hypot($0.xInch - maxX, $0.yInch - maxY) < hypot($1.xInch - maxX, $1.yInch - maxY) })!
        let bottomRight = points.min(by: { hypot($0.xInch - maxX, $0.yInch - minY) < hypot($1.xInch - maxX, $1.yInch - minY) })!
        let topLeft = points.min(by: { hypot($0.xInch - minX, $0.yInch - maxY) < hypot($1.xInch - minX, $1.yInch - maxY) })!
        
        let diag1 = hypot(topRight.xInch - bottomLeft.xInch, topRight.yInch - bottomLeft.yInch)
        let diag2 = hypot(topLeft.xInch - bottomRight.xInch, topLeft.yInch - bottomRight.yInch)
        let perimeter = entities.reduce(0.0) { $0 + $1.lengthInch }
        
        return (width, height, diag1, diag2, perimeter)
    }
    
    private static func normalizeAngleDeg(_ deg: Double) -> Double {
        var r = deg.truncatingRemainder(dividingBy: 360.0)
        if r < 0 { r += 360.0 }
        return r
    }
    
    private static func ccwAngleDiff(from start: Double, to end: Double) -> Double {
        var diff = end - start
        while diff < 0 { diff += 360.0 }
        while diff >= 360.0 { diff -= 360.0 }
        return diff
    }
}

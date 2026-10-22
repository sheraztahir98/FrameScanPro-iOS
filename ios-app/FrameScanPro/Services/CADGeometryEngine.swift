import Foundation
import simd

/// High-precision 3D-to-2D CAD Projection & Curve Fitting Engine.
/// Converts 3D LiDAR + Sticker-calibrated world points into an exact 1:1 2D Wireframe in INCHES.
final class CADGeometryEngine {
    
    /// Exact conversion constant: 1 meter = 39.37007874015748 inches (1 inch = 0.0254 meters exact)
    static let inchesPerMeter: Double = 1.0 / 0.0254
    
    /// Threshold in inches to automatically detect when the worker has returned to the 1st point to close the frame loop.
    static let loopClosureThresholdInch: Double = 1.60 // ~40mm proximity triggers auto-snap to Point #1
    
    /// Projects 3D points (in meters) onto the best-fit 2D plane of the frame and converts all coordinates to exact INCHES.
    static func project3DPointsTo2DInches(
        points3D: [ScanPoint3D],
        stickers: [MagneticStickerAnchor]
    ) -> [Point2DInch] {
        guard points3D.count >= 3 else { return [] }
        
        // 1. Compute global scale calibration factor from 2.00" x 2.00" magnetic stickers (if detected)
        let globalScale: Double
        if !stickers.isEmpty {
            let validScales = stickers.map { Double($0.measuredScaleFactor) }.filter { $0 > 0.90 && $0 < 1.10 }
            if !validScales.isEmpty {
                globalScale = validScales.reduce(0.0, +) / Double(validScales.count)
            } else {
                globalScale = 1.0
            }
        } else {
            globalScale = 1.0
        }
        
        let coords = points3D.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) * globalScale }
        
        // 2. Compute Centroid in 3D space
        var centroid = SIMD3<Double>(0, 0, 0)
        for p in coords { centroid += p }
        centroid /= Double(coords.count)
        
        // 3. Build 2D Basis Axes (U, V) on the Best-Fit Plane
        // We determine the plane normal via Newell's method on the closed polygon loop (robust for any non-self-intersecting frame shape)
        var normal = SIMD3<Double>(0, 0, 0)
        for i in 0..<coords.count {
            let curr = coords[i] - centroid
            let next = coords[(i + 1) % coords.count] - centroid
            normal.x += (curr.y - next.y) * (curr.z + next.z)
            normal.y += (curr.z - next.z) * (curr.x + next.x)
            normal.z += (curr.x - next.x) * (curr.y + next.y)
        }
        
        let normalLen = simd_length(normal)
        if normalLen > 1e-9 {
            normal /= normalLen
        } else {
            normal = SIMD3<Double>(0, 0, 1)
        }
        
        // Use the vector from Point #1 to Point #2 projected onto the plane as initial U-axis
        var uAxis = coords[1] - coords[0]
        uAxis -= simd_dot(uAxis, normal) * normal
        let uLen = simd_length(uAxis)
        if uLen > 1e-9 {
            uAxis /= uLen
        } else {
            uAxis = SIMD3<Double>(1, 0, 0)
        }
        
        let vAxis = simd_normalize(simd_cross(normal, uAxis))
        
        // 4. Project all 3D points onto (uAxis, vAxis) and convert meters -> exact INCHES
        var projected: [Point2DInch] = []
        for (idx, pt) in coords.enumerated() {
            let rel = pt - coords[0]
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
        
        // 5. Normalize orientation so the polygon interior lies in positive Y and shift min (X, Y) to (0.000", 0.000")
        let signedArea = computeSignedArea(projected)
        if signedArea < 0 {
            for i in 0..<projected.count {
                projected[i].yInch = -projected[i].yInch
            }
        }
        
        let minX = projected.map { $0.xInch }.min() ?? 0.0
        let minY = projected.map { $0.yInch }.min() ?? 0.0
        
        for i in 0..<projected.count {
            projected[i].xInch -= minX
            projected[i].yInch -= minY
        }
        
        return projected
    }
    
    /// Builds a closed sequence of CAD entities (`LINE` and `ARC`) from the 2D points in inches.
    /// - Straight points connect with exact `LINE` segments.
    /// - Curve points between straight anchors are fitted with smooth circular `ARC` segments.
    static func buildClosedCADEntities(from points: [Point2DInch]) -> [CADEntity2D] {
        guard points.count >= 3 else { return [] }
        
        var entities: [CADEntity2D] = []
        let n = points.count
        
        // Find indices of all straight anchor points
        let straightIndices = points.enumerated().compactMap { $0.element.pointType == .straight ? $0.offset : nil }
        
        // If all points were marked as curve (e.g. a full circular round window frame), fit arcs in triplets around the loop
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
        
        // Traverse from each straight vertex to the next straight vertex around the closed loop
        for sIdx in 0..<straightIndices.count {
            let startIndex = straightIndices[sIdx]
            let endIndex = straightIndices[(sIdx + 1) % straightIndices.count]
            
            // Collect intermediate curve points between startIndex and endIndex
            var chain: [Point2DInch] = [points[startIndex]]
            var curr = (startIndex + 1) % n
            while curr != endIndex {
                chain.append(points[curr])
                curr = (curr + 1) % n
            }
            chain.append(points[endIndex])
            
            if chain.count == 2 {
                // Direct straight line segment
                entities.append(.line(start: chain[0], end: chain[1]))
            } else if chain.count == 3 {
                // Single curve midpoint between two straight corners -> Exact 3-point CAD Arc
                if let arc = fitThreePointArc(p0: chain[0], p1: chain[1], p2: chain[2], passThrough: chain) {
                    entities.append(arc)
                } else {
                    entities.append(.line(start: chain[0], end: chain[1]))
                    entities.append(.line(start: chain[1], end: chain[2]))
                }
            } else {
                // Multiple curve points along a complex arch -> Fit piecewise 3-point arcs or smooth arc segments
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
                        // One remaining point at the end of an even-count chain: fit arc using previous point, current, and end
                        let p0 = chain[k - 1]
                        let p1 = chain[k]
                        let p2 = chain[k + 1]
                        // Replace last entity's end or add final arc/line
                        if let arc = fitThreePointArc(p0: p0, p1: p1, p2: p2, passThrough: [p1, p2]) {
                            // Use line for final short connection if arc already covered p0->p1
                            _ = arc
                            entities.append(.line(start: p1, end: p2))
                        } else {
                            entities.append(.line(start: p1, end: p2))
                        }
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
        // If points are nearly collinear, return nil so caller falls back to straight lines
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
        
        // Determine whether counter-clockwise sweep from a0 to a2 passes through a1
        let ccwSweep0to2 = ccwAngleDiff(from: a0, to: a2)
        let ccwSweep0to1 = ccwAngleDiff(from: a0, to: a1)
        
        let isCCW = ccwSweep0to1 <= ccwSweep0to2
        // DXF ARC angles are always counter-clockwise from startAngle to endAngle!
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
    
    /// Calculates overall bounding box, diagonals, and total perimeter in INCHES.
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
        
        // Find the 4 points closest to the bounding box corners to compute real physical diagonals
        let bottomLeft = points.min(by: { hypot($0.xInch - minX, $0.yInch - minY) < hypot($1.xInch - minX, $1.yInch - minY) })!
        let topRight = points.min(by: { hypot($0.xInch - maxX, $0.yInch - maxY) < hypot($1.xInch - maxX, $1.yInch - maxY) })!
        let bottomRight = points.min(by: { hypot($0.xInch - maxX, $0.yInch - minY) < hypot($1.xInch - maxX, $1.yInch - minY) })!
        let topLeft = points.min(by: { hypot($0.xInch - minX, $0.yInch - maxY) < hypot($1.xInch - minX, $1.yInch - maxY) })!
        
        let diag1 = hypot(topRight.xInch - bottomLeft.xInch, topRight.yInch - bottomLeft.yInch)
        let diag2 = hypot(topLeft.xInch - bottomRight.xInch, topLeft.yInch - bottomRight.yInch)
        let perimeter = entities.reduce(0.0) { $0 + $1.lengthInch }
        
        return (width, height, diag1, diag2, perimeter)
    }
    
    private static func computeSignedArea(_ pts: [Point2DInch]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var area = 0.0
        for i in 0..<pts.count {
            let p1 = pts[i]
            let p2 = pts[(i + 1) % pts.count]
            area += (p1.xInch * p2.yInch - p2.xInch * p1.yInch)
        }
        return area * 0.5
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

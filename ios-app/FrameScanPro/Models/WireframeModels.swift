import Foundation
import simd

/// Represents whether a marked point on the frame is a sharp corner/straight vertex or part of a smooth curve/arch.
enum ScanPointType: String, Codable {
    case straight = "STRAIGHT"
    case curve = "CURVE"
}

/// A 3D point captured in world space via LiDAR + Camera Vision, along with reference sticker lock metadata.
struct ScanPoint3D: Identifiable, Codable {
    var id: UUID = UUID()
    var index: Int
    var x: Float // in meters (ARKit native), converted to exact inches during 2D projection
    var y: Float
    var z: Float
    var pointType: ScanPointType
    var nearestStickerID: Int?
    var confidence: Float // 0.0 to 1.0
    var timestamp: Date = Date()
    
    var simdVector: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

/// A flattened 2D point on the best-fit frame plane, stored in exact INCHES.
struct Point2DInch: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var index: Int
    var xInch: Double
    var yInch: Double
    var pointType: ScanPointType
}

/// Represents a 2D geometric entity for rendering and DXF export (either a straight LINE or a circular ARC).
enum CADEntity2D: Identifiable, Codable {
    case line(id: UUID = UUID(), start: Point2DInch, end: Point2DInch)
    case arc(
        id: UUID = UUID(),
        center: Point2DInch,
        radiusInch: Double,
        startAngleDeg: Double,
        endAngleDeg: Double,
        isClockwise: Bool,
        passThroughPoints: [Point2DInch]
    )
    
    var id: UUID {
        switch self {
        case .line(let id, _, _): return id
        case .arc(let id, _, _, _, _, _, _): return id
        }
    }
    
    var lengthInch: Double {
        switch self {
        case .line(_, let s, let e):
            return hypot(e.xInch - s.xInch, e.yInch - s.yInch)
        case .arc(_, _, let r, let startDeg, let endDeg, _, _):
            var sweep = endDeg - startDeg
            while sweep < 0 { sweep += 360.0 }
            while sweep > 360.0 { sweep -= 360.0 }
            return r * (sweep * .pi / 180.0)
        }
    }
}

/// Detected 2.00" x 2.00" Magnetic Fiducial Sticker in 3D space.
struct MagneticStickerAnchor: Identifiable, Codable {
    var id: Int // Sticker ID (1 to 12)
    var positionX: Float
    var positionY: Float
    var positionZ: Float
    var normalX: Float
    var normalY: Float
    var normalZ: Float
    var measuredScaleFactor: Float // Compares physical 2.00" (0.0508m) to ARKit distance for 0.5mm local calibration
    var lastSeen: Date
    
    var position: SIMD3<Float> {
        SIMD3<Float>(positionX, positionY, positionZ)
    }
    var normal: SIMD3<Float> {
        SIMD3<Float>(normalX, normalY, normalZ)
    }
}

/// Complete saved wireframe record persisted in local storage and shown on the Home Screen.
struct SavedWireframe: Identifiable, Codable {
    var id: UUID = UUID()
    var customerName: String
    var createdAt: Date = Date()
    var points2D: [Point2DInch]
    var cadEntities: [CADEntity2D]
    var boundingWidthInch: Double
    var boundingHeightInch: Double
    var diagonal1Inch: Double
    var diagonal2Inch: Double
    var perimeterInch: Double
    var detectedStickerCount: Int
    var overviewPhotoFilename: String?
    var dxfFilename: String {
        let safe = customerName
            .replacingOccurrences(of: " ", with: "_")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).inverted)
            .joined()
        return (safe.isEmpty ? "FrameScan" : safe) + ".dxf"
    }
}

import Foundation

/// Generates industry-standard AutoCAD / CypCut / CorelDraw compatible `.DXF` files in exact INCHES (`$INSUNITS = 1`).
/// Produces a clean, single-line 2D wireframe (`LINE` and `ARC` entities) with 0.0001" numeric precision.
final class DXFGenerator {
    
    /// Generates ASCII DXF content in INCHES for the given `SavedWireframe`.
    static func generateDXFString(for wireframe: SavedWireframe) -> String {
        var lines: [String] = []
        
        func add(_ code: Int, _ value: String) {
            lines.append(String(format: "%3d", code))
            lines.append(value)
        }
        
        func fmt(_ val: Double) -> String {
            String(format: "%.4f", val)
        }
        
        // 1. HEADER SECTION (Explicitly set $INSUNITS = 1 -> Inches, $MEASUREMENT = 0 -> English/Inches)
        add(0, "SECTION")
        add(2, "HEADER")
        add(9, "$ACADVER")
        add(1, "AC1009") // AutoCAD R12/LT2 universal compatibility (supported by 100% of CNC/Laser controllers including CypCut)
        add(9, "$INSUNITS")
        add(70, "1")     // 1 = Inches
        add(9, "$MEASUREMENT")
        add(70, "0")     // 0 = Inches (Imperial/Decimal Inches)
        add(9, "$EXTMIN")
        add(10, "0.0000")
        add(20, "0.0000")
        add(30, "0.0000")
        add(9, "$EXTMAX")
        add(10, fmt(wireframe.boundingWidthInch))
        add(20, fmt(wireframe.boundingHeightInch))
        add(30, "0.0000")
        add(0, "ENDSEC")
        
        // 2. TABLES SECTION (Define clean single-line cutting layer `0`)
        add(0, "SECTION")
        add(2, "TABLES")
        add(0, "TABLE")
        add(2, "LTYPE")
        add(70, "1")
        add(0, "LTYPE")
        add(2, "CONTINUOUS")
        add(70, "0")
        add(3, "Solid line")
        add(72, "65")
        add(73, "0")
        add(40, "0.0000")
        add(0, "ENDTAB")
        
        add(0, "TABLE")
        add(2, "LAYER")
        add(70, "1")
        add(0, "LAYER")
        add(2, "0")
        add(70, "0")
        add(62, "3") // Color 3 = Green (matches live wireframe)
        add(6, "CONTINUOUS")
        add(0, "ENDTAB")
        add(0, "ENDSEC")
        
        // 3. ENTITIES SECTION (Single-line closed wireframe in exact INCHES)
        add(0, "SECTION")
        add(2, "ENTITIES")
        
        for entity in wireframe.cadEntities {
            switch entity {
            case .line(_, let start, let end):
                add(0, "LINE")
                add(8, "0")
                add(10, fmt(start.xInch))
                add(20, fmt(start.yInch))
                add(30, "0.0000")
                add(11, fmt(end.xInch))
                add(21, fmt(end.yInch))
                add(31, "0.0000")
                
            case .arc(_, let center, let radiusInch, let startAngleDeg, let endAngleDeg, _, _):
                add(0, "ARC")
                add(8, "0")
                add(10, fmt(center.xInch))
                add(20, fmt(center.yInch))
                add(30, "0.0000")
                add(40, fmt(radiusInch))
                add(50, fmt(startAngleDeg))
                add(51, fmt(endAngleDeg))
            }
        }
        
        add(0, "ENDSEC")
        add(0, "EOF")
        
        return lines.joined(separator: "\r\n") + "\r\n"
    }
    
    /// Writes the `.dxf` file to the app's Documents/Exports directory and returns its `URL` for saving or sharing via WhatsApp.
    static func exportDXFFile(for wireframe: SavedWireframe) throws -> URL {
        let dxfContent = generateDXFString(for: wireframe)
        let fileManager = FileManager.default
        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportDir = docsURL.appendingPathComponent("DXF_Exports", isDirectory: true)
        
        if !fileManager.fileExists(atPath: exportDir.path) {
            try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
        }
        
        let fileURL = exportDir.appendingPathComponent(wireframe.dxfFilename)
        try dxfContent.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}

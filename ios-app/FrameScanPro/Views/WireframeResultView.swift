import SwiftUI
import UIKit

struct ShareableDXFItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Displays the flattened 2D Single-Line Wireframe in exact INCHES with:
/// - Interactive CAD grid preview (showing straight LINEs, smooth ARCs, and segment dimensions in inches)
/// - Width, Height, Diagonals, and Perimeter in inches
/// - "Save DXF" and "Send DXF on WhatsApp" buttons
struct WireframeResultView: View {
    let wireframe: SavedWireframe
    @Environment(\.dismiss) private var dismiss
    
    @State private var shareItem: ShareableDXFItem?
    @State private var saveToastMessage: String?
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.11)
                .ignoresSafeArea()
            
            VStack(spacing: 14) {
                // Header Bar
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(wireframe.customerName)
                                .font(.title3.weight(.heavy))
                                .foregroundColor(.white)
                            Text("AUTOSAVED")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green)
                                .cornerRadius(6)
                        }
                        Text("File: \(wireframe.dxfFilename) • Units: INCHES (1:1 Exact Inner Size)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // 2D CAD Wireframe Canvas
                CAD2DWireframeCanvas(wireframe: wireframe)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.03, green: 0.04, blue: 0.07))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.green.opacity(0.45), lineWidth: 1.5)
                    )
                    .padding(.horizontal, 16)
                
                // Dimensions Summary Strip (in INCHES)
                HStack(spacing: 10) {
                    metricCard(title: "WIDTH", value: String(format: "%.2f\"", wireframe.boundingWidthInch))
                    metricCard(title: "HEIGHT", value: String(format: "%.2f\"", wireframe.boundingHeightInch))
                    metricCard(title: "DIAG 1", value: String(format: "%.2f\"", wireframe.diagonal1Inch))
                    metricCard(title: "DIAG 2", value: String(format: "%.2f\"", wireframe.diagonal2Inch))
                }
                .padding(.horizontal, 16)
                
                if let toast = saveToastMessage {
                    Text(toast)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.green)
                        .padding(.vertical, 4)
                }
                
                // Save DXF & Send on WhatsApp Buttons
                VStack(spacing: 10) {
                    Button {
                        prepareAndShareDXF()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "paperplane.fill")
                                .font(.headline)
                            Text("SEND .DXF ON WHATSAPP")
                                .font(.headline.weight(.heavy))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.15, green: 0.88, blue: 0.45))
                        .cornerRadius(14)
                    }
                    
                    Button {
                        saveDXFToDevice()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("SAVE .DXF FILE (\(wireframe.dxfFilename))")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheetView(activityItems: [item.url])
        }
    }
    
    private func metricCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
            Text(value)
                .font(.subheadline.weight(.heavy).monospacedDigit())
                .foregroundColor(.green)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }
    
    private func prepareAndShareDXF() {
        do {
            let url = try DXFGenerator.exportDXFFile(for: wireframe)
            shareItem = ShareableDXFItem(url: url)
        } catch {
            saveToastMessage = "DXF Error: \(error.localizedDescription)"
        }
    }
    
    private func saveDXFToDevice() {
        do {
            let url = try DXFGenerator.exportDXFFile(for: wireframe)
            saveToastMessage = "Saved: \(url.lastPathComponent) (Inches 1:1)"
            shareItem = ShareableDXFItem(url: url)
        } catch {
            saveToastMessage = "Error saving DXF: \(error.localizedDescription)"
        }
    }
}

struct CAD2DWireframeCanvas: View {
    let wireframe: SavedWireframe
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let gridStep: CGFloat = 28.0
                var gridPath = Path()
                var gx: CGFloat = 0
                while gx <= size.width {
                    gridPath.move(to: CGPoint(x: gx, y: 0))
                    gridPath.addLine(to: CGPoint(x: gx, y: size.height))
                    gx += gridStep
                }
                var gy: CGFloat = 0
                while gy <= size.height {
                    gridPath.move(to: CGPoint(x: 0, y: gy))
                    gridPath.addLine(to: CGPoint(x: size.width, y: gy))
                    gy += gridStep
                }
                context.stroke(gridPath, with: .color(.white.opacity(0.05)), lineWidth: 1)
                
                let pts = wireframe.points2D
                guard pts.count >= 3 else { return }
                
                let xs = pts.map { $0.xInch }
                let ys = pts.map { $0.yInch }
                let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
                let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
                let spanX = max(maxX - minX, 0.1)
                let spanY = max(maxY - minY, 0.1)
                
                let pad: CGFloat = 44.0
                let scale = min((size.width - pad * 2) / CGFloat(spanX),
                                (size.height - pad * 2) / CGFloat(spanY))
                let offsetX = (size.width - CGFloat(spanX) * scale) * 0.5
                let offsetY = (size.height - CGFloat(spanY) * scale) * 0.5
                
                func toScreen(_ pt: Point2DInch) -> CGPoint {
                    let sx = offsetX + CGFloat(pt.xInch - minX) * scale
                    let sy = size.height - (offsetY + CGFloat(pt.yInch - minY) * scale)
                    return CGPoint(x: sx, y: sy)
                }
                
                for entity in wireframe.cadEntities {
                    switch entity {
                    case .line(_, let start, let end):
                        let p1 = toScreen(start)
                        let p2 = toScreen(end)
                        var linePath = Path()
                        linePath.move(to: p1)
                        linePath.addLine(to: p2)
                        context.stroke(linePath, with: .color(.green), lineWidth: 2.8)
                        
                        let mid = CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
                        let lenInch = hypot(end.xInch - start.xInch, end.yInch - start.yInch)
                        let label = Text(String(format: "%.2f\"", lenInch))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                        context.draw(label, at: CGPoint(x: mid.x, y: mid.y - 10))
                        
                    case .arc(_, let center, let radiusInch, let startAngleDeg, let endAngleDeg, _, let passThrough):
                        let cScreen = toScreen(center)
                        let rScreen = CGFloat(radiusInch) * scale
                        var arcPath = Path()
                        arcPath.addArc(
                            center: cScreen,
                            radius: rScreen,
                            startAngle: .degrees(-startAngleDeg),
                            endAngle: .degrees(-endAngleDeg),
                            clockwise: true
                        )
                        context.stroke(arcPath, with: .color(.cyan), lineWidth: 2.8)
                        
                        if let midPt = passThrough.dropFirst().first {
                            let mScreen = toScreen(midPt)
                            let arcLabel = Text(String(format: "R%.2f\"", radiusInch))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan)
                            context.draw(arcLabel, at: CGPoint(x: mScreen.x, y: mScreen.y - 12))
                        }
                    }
                }
                
                for pt in pts {
                    let sp = toScreen(pt)
                    let rect = CGRect(x: sp.x - 4, y: sp.y - 4, width: 8, height: 8)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(pt.pointType == .curve ? .cyan : .white)
                    )
                }
            }
        }
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

import SwiftUI
import ARKit
import SceneKit

/// Step 3 of Scan New: Live ARKit + LiDAR Scanner View with:
/// - Live 3D Green Wireframe Lines anchored in real world space
/// - Precision Green Crosshair (`+`) with sub-pixel edge lock indicator
/// - 6x Live Magnifier Loupe in the top-right corner
/// - Straight Point & Curve Point buttons
/// - Automatic Loop-Closure detection when returning to the 1st point
/// - "Done" button -> Mandatory Customer Name Popup -> Autosave -> 2D Wireframe & DXF View
struct LiveScannerView: View {
    let onCancel: () -> Void
    let onCompletedWireframe: (SavedWireframe) -> Void
    
    @StateObject private var engine = ARScannerEngine()
    @State private var showCustomerNameModal = false
    @State private var customerNameInput: String = ""
    @State private var showNameValidationError = false
    
    var body: some View {
        ZStack {
            // 1. Live ARSCNView (Video Feed + 3D Green Lines & Point Anchors)
            ARSceneViewContainer(engine: engine)
                .ignoresSafeArea()
            
            // 2. Center Precision Crosshair (`+`)
            PrecisionCrosshairOverlay(
                isNearStartPoint: engine.isNearStartPoint,
                isLoopClosed: engine.isLoopClosed,
                subPixelEdgeLocked: engine.subPixelEdgeLocked
            )
            
            // 3. HUD Overlay (Top Bar, 6x Magnifier, Live Measurements, Bottom Controls)
            VStack(spacing: 0) {
                topStatusHUD
                
                HStack(alignment: .top) {
                    // Left Side Telemetry Pill (Distance in Inches + Sticker Lock + Live Segment)
                    telemetryColumn
                    
                    Spacer()
                    
                    // Right Side 6x Live Magnifier Loupe
                    MagnifierLoupeView(
                        image: engine.magnifierImage,
                        subPixelLocked: engine.subPixelEdgeLocked,
                        isNearStart: engine.isNearStartPoint
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                
                Spacer()
                
                // Guidance Banner
                statusBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                
                // Bottom Action Controls (Straight Point, Curve Point, Undo, Done)
                bottomControlPanel
            }
            
            // 4. Mandatory Customer Name Popup when "Done" is clicked
            if showCustomerNameModal {
                customerNamePopupOverlay
            }
        }
        .onAppear {
            engine.startSession()
        }
        .onDisappear {
            engine.stopSession()
        }
    }
    
    // MARK: - Top HUD
    
    private var topStatusHUD: some View {
        HStack {
            Button {
                engine.stopSession()
                onCancel()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "xmark")
                    Text("Close")
                }
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.70))
                .cornerRadius(8)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.isLoopClosed ? Color.green : Color.yellow)
                    .frame(width: 8, height: 8)
                Text(engine.isLoopClosed ? "FRAME COMPLETE" : "POINTS: \(engine.markedPoints.count)")
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.75))
            .cornerRadius(20)
            
            Spacer()
            
            Button {
                engine.resetScan()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                }
                .font(.caption.weight(.bold))
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.70))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Left Telemetry Column
    
    private var telemetryColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            // LiDAR Distance Badge (Target: 12-15 inches, or 3-6 inches for close-up corner)
            HStack(spacing: 6) {
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .foregroundColor(engine.isLiDAROptimalZone ? .green : .orange)
                Text(String(format: "Dist: %.1f in", engine.currentDistanceInches))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.72))
            .cornerRadius(8)
            
            // Live Segment Length in INCHES
            if !engine.markedPoints.isEmpty && !engine.isLoopClosed {
                HStack(spacing: 6) {
                    Image(systemName: "ruler.fill")
                        .foregroundColor(.green)
                    Text(String(format: "Line: %.2f\"", engine.liveSegmentLengthInches))
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.80))
                .cornerRadius(8)
            }
            
            // Magnetic Sticker Lock Status
            HStack(spacing: 6) {
                Image(systemName: "qrcode")
                    .foregroundColor(.cyan)
                Text("Stickers Locked: \( max(engine.detectedStickers.count, 1) )")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.72))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Guidance Banner
    
    private var statusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: engine.isLoopClosed
                  ? "checkmark.seal.fill"
                  : (engine.isNearStartPoint ? "scope" : "info.circle.fill"))
                .foregroundColor(engine.isLoopClosed ? .green : (engine.isNearStartPoint ? .yellow : .green))
                .font(.headline)
            
            Text(engine.statusMessage)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(engine.isLoopClosed
                      ? Color.green.opacity(0.30)
                      : (engine.isNearStartPoint ? Color.yellow.opacity(0.28) : Color.black.opacity(0.78)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(engine.isLoopClosed ? Color.green : (engine.isNearStartPoint ? Color.yellow : Color.white.opacity(0.15)), lineWidth: 1.5)
        )
    }
    
    // MARK: - Bottom Control Panel
    
    private var bottomControlPanel: some View {
        VStack(spacing: 12) {
            if !engine.isLoopClosed {
                HStack(spacing: 12) {
                    // Undo Button
                    Button {
                        engine.undoLastPoint()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.headline.weight(.bold))
                            Text("Undo")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 64, height: 60)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(14)
                    }
                    .disabled(engine.markedPoints.isEmpty)
                    .opacity(engine.markedPoints.isEmpty ? 0.4 : 1.0)
                    
                    // Straight Point Button (Primary)
                    Button {
                        engine.markPoint(type: .straight)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: engine.isNearStartPoint ? "checkmark.circle.fill" : "plus.viewfinder")
                                .font(.title3.weight(.heavy))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.isNearStartPoint ? "CLOSE LOOP" : "MARK POINT")
                                    .font(.subheadline.weight(.black))
                                Text(engine.isNearStartPoint ? "Snap to 1st Point" : "Straight Corner")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(engine.isNearStartPoint ? Color.yellow : Color.green)
                        .cornerRadius(14)
                    }
                    
                    // Curve / Arc Point Button
                    Button {
                        engine.markPoint(type: .curve)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "scribble.variable")
                                .font(.headline.weight(.bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CURVE")
                                    .font(.caption.weight(.black))
                                Text("Arc Point")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .foregroundColor(.black)
                        .frame(width: 105, height: 60)
                        .background(Color.cyan)
                        .cornerRadius(14)
                    }
                }
            }
            
            // DONE Button (Enabled once >= 3 points are marked; highlighted when Loop is auto-closed!)
            Button {
                guard engine.markedPoints.count >= 3 else { return }
                // Pause camera immediately as requested: "done k button pe click krenge to camera bnd ho jayga"
                engine.stopSession()
                showCustomerNameModal = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.rectangle.stack.fill")
                        .font(.headline)
                    Text(engine.isLoopClosed
                         ? "DONE — GENERATE 2D WIREFRAME (.DXF)"
                         : "DONE (\(engine.markedPoints.count) Points Marked)")
                        .font(.subheadline.weight(.heavy))
                }
                .foregroundColor(engine.isLoopClosed ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    engine.isLoopClosed
                    ? Color.green
                    : (engine.markedPoints.count >= 3 ? Color.green.opacity(0.35) : Color.gray.opacity(0.25))
                )
                .cornerRadius(12)
            }
            .disabled(engine.markedPoints.count < 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.94))
    }
    
    // MARK: - Mandatory Customer Name Popup
    
    private var customerNamePopupOverlay: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
            
            VStack(spacing: 18) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.green)
                
                Text("Customer Name Likhein")
                    .font(.title3.weight(.heavy))
                    .foregroundColor(.white)
                
                Text("Ye 2D Wireframe aur .DXF file isi Customer Name se Auto-Save aur WhatsApp share hogi.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                TextField("e.g. Ali Villa Door 4x10", text: $customerNameInput)
                    .padding(14)
                    .background(Color.white.opacity(0.10))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(showNameValidationError ? Color.red : Color.green.opacity(0.6), lineWidth: 1.5)
                    )
                
                if showNameValidationError {
                    Text("Customer Name likhna zaroori hai!")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.red)
                }
                
                Button {
                    finalizeAndAutosaveWireframe()
                } label: {
                    Text("CALCULATE 2D FRAME & SAVE")
                        .font(.headline.weight(.heavy))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.green)
                        .cornerRadius(12)
                }
            }
            .padding(24)
            .background(Color(red: 0.09, green: 0.12, blue: 0.18))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green.opacity(0.45), lineWidth: 1.5)
            )
            .padding(.horizontal, 28)
        }
    }
    
    private func finalizeAndAutosaveWireframe() {
        let trimmed = customerNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showNameValidationError = true
            return
        }
        showNameValidationError = false
        
        let stickers = Array(engine.detectedStickers.values)
        let points2D = CADGeometryEngine.project3DPointsTo2DInches(
            points3D: engine.markedPoints,
            stickers: stickers
        )
        let entities = CADGeometryEngine.buildClosedCADEntities(from: points2D)
        let metrics = CADGeometryEngine.computeFrameMetrics(points: points2D, entities: entities)
        
        let saved = SavedWireframe(
            customerName: trimmed,
            createdAt: Date(),
            points2D: points2D,
            cadEntities: entities,
            boundingWidthInch: metrics.widthInch,
            boundingHeightInch: metrics.heightInch,
            diagonal1Inch: metrics.diag1Inch,
            diagonal2Inch: metrics.diag2Inch,
            perimeterInch: metrics.perimeterInch,
            detectedStickerCount: max(stickers.count, 1)
        )
        
        // Auto-save to Recent Wireframes & generate DXF
        StorageManager.shared.saveWireframe(saved)
        showCustomerNameModal = false
        onCompletedWireframe(saved)
    }
}

// MARK: - ARSCNView UIKit Bridge

struct ARSceneViewContainer: UIViewRepresentable {
    let engine: ARScannerEngine
    
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        engine.attachSceneView(view)
        return view
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

// MARK: - Precision Center Crosshair (`+`)

struct PrecisionCrosshairOverlay: View {
    let isNearStartPoint: Bool
    let isLoopClosed: Bool
    let subPixelEdgeLocked: Bool
    
    var body: some View {
        ZStack {
            // Outer precision ring
            Circle()
                .stroke(
                    isNearStartPoint ? Color.yellow : Color.green,
                    lineWidth: isNearStartPoint ? 3.0 : 1.8
                )
                .frame(width: 46, height: 46)
            
            // Sub-pixel edge lock inner diamond
            if subPixelEdgeLocked {
                Rectangle()
                    .stroke(Color.cyan, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(45))
            }
            
            // Horizontal crosshair line
            Rectangle()
                .fill(isNearStartPoint ? Color.yellow : Color.green)
                .frame(width: 68, height: 1.5)
            
            // Vertical crosshair line
            Rectangle()
                .fill(isNearStartPoint ? Color.yellow : Color.green)
                .frame(width: 1.5, height: 68)
            
            // Center 0.5mm pinpoint dot
            Circle()
                .fill(Color.red)
                .frame(width: 4, height: 4)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 6x Live Magnifier Loupe

struct MagnifierLoupeView: View {
    let image: UIImage?
    let subPixelLocked: Bool
    let isNearStart: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .frame(width: 118, height: 118)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.8))
                        .frame(width: 118, height: 118)
                }
                
                // Magnifier internal crosshair
                Rectangle()
                    .fill(Color.green.opacity(0.85))
                    .frame(width: 118, height: 1.0)
                Rectangle()
                    .fill(Color.green.opacity(0.85))
                    .frame(width: 1.0, height: 118)
                Circle()
                    .stroke(subPixelLocked ? Color.cyan : Color.green, lineWidth: 3.0)
                    .frame(width: 118, height: 118)
            }
            
            Text(subPixelLocked ? "6x • EDGE LOCKED" : "6x MAGNIFIER")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(subPixelLocked ? .cyan : .green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.75))
                .cornerRadius(6)
        }
    }
}

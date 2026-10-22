import SwiftUI

enum ScanWorkflowStep: Identifiable {
    case stickerGuide
    case overviewPhoto
    case livePrecisionScan(overviewImage: UIImage?)
    
    var id: String {
        switch self {
        case .stickerGuide: return "stickerGuide"
        case .overviewPhoto: return "overviewPhoto"
        case .livePrecisionScan: return "livePrecisionScan"
        }
    }
}

struct HomeView: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var activeStep: ScanWorkflowStep?
    @State private var selectedWireframe: SavedWireframe?
    @State private var shareItem: ShareableDXFItem?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.10)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Banner
                    headerSection
                    
                    // Recent Wireframes List
                    if storage.wireframes.isEmpty {
                        emptyStateView
                    } else {
                        List {
                            Section(header: Text("RECENT WIREFRAMES (INCHES • .DXF)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.green)) {
                                ForEach(storage.wireframes) { item in
                                    Button {
                                        selectedWireframe = item
                                    } label: {
                                        WireframeRowCard(wireframe: item) {
                                            shareWireframeOnWhatsApp(item)
                                        }
                                    }
                                    .listRowBackground(Color(red: 0.09, green: 0.12, blue: 0.17))
                                    .listRowSeparatorTint(Color.white.opacity(0.08))
                                }
                                .onDelete(perform: storage.deleteWireframe)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                    
                    // Bottom Scan New Button
                    bottomActionBar
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $activeStep) { step in
                switch step {
                case .stickerGuide:
                    StickerGuideView(
                        onCancel: { activeStep = nil },
                        onDoneStickers: { activeStep = .overviewPhoto }
                    )
                case .overviewPhoto:
                    OverviewCaptureView(
                        onBack: { activeStep = .stickerGuide },
                        onPhotoCaptured: { img in
                            activeStep = .livePrecisionScan(overviewImage: img)
                        }
                    )
                case .livePrecisionScan:
                    LiveScannerView(
                        onCancel: { activeStep = nil },
                        onCompletedWireframe: { saved in
                            activeStep = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                selectedWireframe = saved
                            }
                        }
                    )
                }
            }
            .sheet(item: $selectedWireframe) { wf in
                WireframeResultView(wireframe: wf)
            }
            .sheet(item: $shareItem) { item in
                ShareSheetView(activityItems: [item.url])
            }
        }
    }
    
    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.green, Color(red: 0.0, green: 0.65, blue: 0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                Image(systemName: "viewfinder.rectangular")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("FrameScan Pro LiDAR")
                    .font(.title3.weight(.heavy))
                    .foregroundColor(.white)
                Text("iPhone 15 Pro • Inner Frame 2D DXF Scanner (Inches)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(red: 0.07, green: 0.09, blue: 0.14))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "square.dashed.inset.filled")
                    .font(.system(size: 42))
                    .foregroundColor(.green)
            }
            Text("Abhi Koi Wireframe Scan Nahi Hua")
                .font(.headline)
                .foregroundColor(.white)
            Text("Neeche 'Scan New Frame' button dabayein, frame pe magnetic stickers lagayein, aur inner size ka exact 2D DXF banayein.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
    }
    
    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            Button {
                activeStep = .stickerGuide
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3.weight(.bold))
                    Text("SCAN NEW FRAME")
                        .font(.headline.weight(.heavy))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.1, green: 0.95, blue: 0.45), Color.green],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: Color.green.opacity(0.35), radius: 10, y: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(red: 0.07, green: 0.09, blue: 0.14))
    }
    
    private func shareWireframeOnWhatsApp(_ item: SavedWireframe) {
        if let url = try? DXFGenerator.exportDXFFile(for: item) {
            shareItem = ShareableDXFItem(url: url)
        }
    }
}

struct WireframeRowCard: View {
    let wireframe: SavedWireframe
    let onQuickShare: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Mini 2D Wireframe Thumbnail
            MiniWireframeThumbnail(points: wireframe.points2D)
                .frame(width: 58, height: 58)
                .background(Color.black.opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.green.opacity(0.45), lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 5) {
                Text(wireframe.customerName)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                
                Text(String(format: "Size: %.2f\" × %.2f\"  (%d pts)",
                            wireframe.boundingWidthInch,
                            wireframe.boundingHeightInch,
                            wireframe.points2D.count))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.green)
                
                Text(wireframe.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button {
                onQuickShare()
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .bold))
                    Text("DXF")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.green)
                .padding(10)
                .background(Color.green.opacity(0.14))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}

struct MiniWireframeThumbnail: View {
    let points: [Point2DInch]
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard points.count >= 3 else { return }
                let xs = points.map { $0.xInch }
                let ys = points.map { $0.yInch }
                let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
                let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
                let spanX = max(maxX - minX, 0.1)
                let spanY = max(maxY - minY, 0.1)
                let pad: CGFloat = 8.0
                let scale = min((size.width - pad * 2) / CGFloat(spanX),
                                (size.height - pad * 2) / CGFloat(spanY))
                
                var path = Path()
                for (i, pt) in points.enumerated() {
                    let px = pad + CGFloat(pt.xInch - minX) * scale
                    let py = size.height - (pad + CGFloat(pt.yInch - minY) * scale)
                    if i == 0 {
                        path.move(to: CGPoint(x: px, y: py))
                    } else {
                        path.addLine(to: CGPoint(x: px, y: py))
                    }
                }
                path.closeSubpath()
                context.stroke(path, with: .color(.green), lineWidth: 1.8)
            }
        }
    }
}

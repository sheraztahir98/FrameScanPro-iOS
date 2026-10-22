import SwiftUI
import AVFoundation
import Vision

/// Step 2 of Scan New: Opens the camera and instructs the worker to capture 1 full overview picture of the entire frame
/// so the app can lock the global sticker layout before close-up point marking begins.
struct OverviewCaptureView: View {
    let onBack: () -> Void
    let onPhotoCaptured: (UIImage?) -> Void
    
    @StateObject private var cameraModel = OverviewCameraController()
    
    var body: some View {
        ZStack {
            // Live Camera Preview
            OverviewCameraPreviewRepresentable(session: cameraModel.session)
                .ignoresSafeArea()
            
            // Darkened Frame Alignment Overlay
            VStack {
                // Top Bar
                HStack {
                    Button(action: {
                        cameraModel.stop()
                        onBack()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    Text("STEP 2 OF 3 • FULL FRAME PIC")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                // Instruction Banner
                VStack(spacing: 6) {
                    Text("Poore Frame Ki 1 Pic Capture Karlo")
                        .font(.headline.weight(.heavy))
                        .foregroundColor(.white)
                    Text("Thoda peeche khade ho kar poore frame aur stickers ko box ke andar laa kar Capture dabayein")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .background(Color.black.opacity(0.75))
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                Spacer()
                
                // Guide Frame Box
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, dash: [12, 8]))
                        .padding(.horizontal, 28)
                        .frame(height: 340)
                    
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "viewfinder")
                                .foregroundColor(.green)
                            Text("Global Sticker Map Lock Active")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(20)
                        .padding(.bottom, 12)
                    }
                    .frame(height: 340)
                }
                
                Spacer()
                
                // Capture Button
                VStack(spacing: 10) {
                    Button {
                        cameraModel.captureOverviewPhoto { image in
                            cameraModel.stop()
                            onPhotoCaptured(image)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.green, lineWidth: 4)
                                .frame(width: 78, height: 78)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 64, height: 64)
                            Image(systemName: "camera.fill")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.black)
                        }
                    }
                    
                    Text("CAPTURE FULL FRAME")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 26)
            }
        }
        .onAppear {
            cameraModel.start()
        }
        .onDisappear {
            cameraModel.stop()
        }
    }
}

final class OverviewCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var completionHandler: ((UIImage?) -> Void)?
    private var isConfigured = false
    
    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if self?.session.isRunning == true {
                self?.session.stopRunning()
            }
        }
    }
    
    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
        session.commitConfiguration()
        isConfigured = true
    }
    
    func captureOverviewPhoto(completion: @escaping (UIImage?) -> Void) {
        self.completionHandler = completion
        let settings = AVCapturePhotoSettings()
        if session.isRunning {
            photoOutput.capturePhoto(with: settings, delegate: self)
        } else {
            completion(nil)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let img: UIImage?
        if let data = photo.fileDataRepresentation() {
            img = UIImage(data: data)
        } else {
            img = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.completionHandler?(img)
            self?.completionHandler = nil
        }
    }
}

struct OverviewCameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
    
    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

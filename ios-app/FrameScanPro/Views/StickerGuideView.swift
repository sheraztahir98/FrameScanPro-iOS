import SwiftUI

/// Step 1 of Scan New: Instructs the worker to place the 2.00" x 2.00" Magnetic Stickers around the frame before opening the camera.
struct StickerGuideView: View {
    let onCancel: () -> Void
    let onDoneStickers: () -> Void
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.11)
                .ignoresSafeArea()
            
            VStack(spacing: 22) {
                // Top Bar
                HStack {
                    Button(action: onCancel) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                            Text("Cancel")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                    }
                    Spacer()
                    Text("STEP 1 OF 3")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                Spacer()
                
                // Visual Frame + Sticker Diagram
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.45), lineWidth: 16)
                        .frame(width: 240, height: 180)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                        .frame(width: 210, height: 150)
                    
                    // Simulated Magnetic Stickers around the pipe frame
                    stickerBadge(id: "#1", x: -105, y: -75)
                    stickerBadge(id: "#2", x: 0, y: -75)
                    stickerBadge(id: "#3", x: 105, y: -75)
                    stickerBadge(id: "#4", x: 105, y: 0)
                    stickerBadge(id: "#5", x: 105, y: 75)
                    stickerBadge(id: "#6", x: 0, y: 75)
                    stickerBadge(id: "#7", x: -105, y: 75)
                    stickerBadge(id: "#8", x: -105, y: 0)
                    
                    VStack(spacing: 4) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 34))
                            .foregroundColor(.green)
                        Text("3–5 Feet Distance")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.vertical, 10)
                
                // Clear Instructions in Roman Urdu
                VStack(spacing: 14) {
                    Text("Poore Frame Pe Magnetic Stickers Lagayein")
                        .font(.title3.weight(.heavy))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        instructionRow(
                            num: "1",
                            text: "Apne 2\"×2\" Magnetic Stickers frame ke pipe ke upar har 3 se 5 feet ke faasle par chipka dein."
                        )
                        instructionRow(
                            num: "2",
                            text: "Kono (Corners) aur Curve ke qareeb stickers zaroor lagayein taake 0.5mm scale lock rahe."
                        )
                        instructionRow(
                            num: "3",
                            text: "Stickers lagane ke baad neeche 'Done' par click karein taake camera open ho."
                        )
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(14)
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Done Button
                Button(action: onDoneStickers) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                        Text("DONE — STICKERS LAGA DIYE")
                            .font(.headline.weight(.heavy))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.green)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    private func stickerBadge(id: String, x: CGFloat, y: CGFloat) -> some View {
        Text(id)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundColor(.black)
            .frame(width: 24, height: 24)
            .background(Color.white)
            .border(Color.black, width: 2)
            .offset(x: x, y: y)
    }
    
    private func instructionRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(num)
                .font(.caption.weight(.black))
                .foregroundColor(.black)
                .frame(width: 22, height: 22)
                .background(Color.green)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

# FrameScan Pro (iPhone 15 Pro LiDAR -> 2D DXF in Inches)

## 📁 Project Files Overview

1. **Native iOS App (`ios-app/FrameScanPro`)**:
   - [FrameScanProApp.swift](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/ios-app/FrameScanPro/FrameScanProApp.swift) — Main iOS app entry point.
   - [HomeView.swift](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/ios-app/FrameScanPro/Views/HomeView.swift) — Recent Wireframes list + **Scan New Frame** button.
   - [StickerGuideView.swift](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/ios-app/FrameScanPro/Views/StickerGuideView.swift) — **Step 1:** Instructs worker to place `2.00" × 2.00"` Magnetic Stickers around the frame.
   - [OverviewCaptureView.swift](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/ios-app/FrameScanPro/Views/OverviewCaptureView.swift) — **Step 2:** Captures 1 full overview picture of the entire frame to lock the global sticker map.
   - [LiveScannerView.swift](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/ios-app/FrameScanPro/Views/LiveScannerView.swift) — **Step 3:** Live video feed + **3D Green Line** + **Precision Crosshair (`+`)** + **6x Magnifier** + **Straight Point** & **Curve Point** buttons + **Auto Loop-Closure** when returning to the 1st point + **Mandatory Customer Name Popup**.
   - [WireframeResultView.swift](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/ios-app/FrameScanPro/Views/WireframeResultView.swift) — **Step 4:** Flattened 2D Single-Line Wireframe in **Inches (`in`)**, Auto-Saved, with **Save `.DXF`** and **Send `.DXF` on WhatsApp**.
   - [ARScannerEngine.swift](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/ios-app/FrameScanPro/Services/ARScannerEngine.swift) — LiDAR depth median filtering + `2.00" × 2.00"` sticker scale lock + sub-pixel edge snap.
   - [CADGeometryEngine.swift](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/ios-app/FrameScanPro/Services/CADGeometryEngine.swift) — Best-fit 3D-to-2D plane projection & 3-point CAD `ARC` / `LINE` curve fitting in **exact Inches**.
   - [DXFGenerator.swift](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/ios-app/FrameScanPro/Services/DXFGenerator.swift) — Generates AutoCAD / CypCut / CorelDraw compatible `.dxf` files (`$INSUNITS = 1` Inches).

2. **Printable Magnetic Stickers Sheet (A4 1:1 Scale)**:
   - [Magnetic_Stickers_Print_Sheet_A4.html](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/printable-stickers/Magnetic_Stickers_Print_Sheet_A4.html) — Open in browser and print at **100% Scale (Actual Size)** to get 12 unique `2.00" × 2.00"` (`50.8mm × 50.8mm`) Magnetic Stickers (`#01` to `#12`).

3. **Interactive Windows Simulator & Real `.DXF` Tester**:
   - [App_Interactive_Preview_And_DXF_Tester.html](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/simulator/App_Interactive_Preview_And_DXF_Tester.html) — Open on your Windows laptop to test the complete iPhone 15 Pro workflow and generate real `.dxf` files in Inches right now.

---

## 🚀 Windows Laptop Se iPhone 15 Pro Mein App Kaise Install Karein (Bina Mac Ke)

1. **Step 1 — GitHub Pe Upload Karein (Free Cloud Mac `.ipa` Build):**
   - [github.com](https://github.com) pe ek naya repository banayein aur is folder ka sara code upload/push kar dein.
   - Humari file [build-ios-ipa.yml](file:///c:/Users/shera/Documents/app%20for%20auto%20detect%20laser%20cutting%20machine/.github/workflows/build-ios-ipa.yml) GitHub ke **Actions** tab mein khud-ba-khud Cloud Mac (`macos-14` + Xcode) chala degi aur 3 minute mein **`FrameScanPro.ipa`** bana kar de degi.
   - GitHub Actions ke **Artifacts** section se `FrameScanPro.ipa` apne Windows laptop pe download kar lein.

2. **Step 2 — Windows Pe `Sideloadly` Se iPhone 15 Pro Mein Install Karein:**
   - Apne Windows laptop pe [Sideloadly](https://sideloadly.io/) (Free software) + iTunes (non-Microsoft Store version) install karein.
   - iPhone 15 Pro ko USB-C cable se laptop ke sath connect karein.
   - Sideloadly mein `FrameScanPro.ipa` select karein, apni Apple ID likhein, aur **Start** dabayein.
   - iPhone mein *Settings -> General -> VPN & Device Management* mein jaa kar apni Apple ID ko **Trust** karein, aur *Settings -> Privacy & Security -> Developer Mode* ko **ON** kar dein.
   - App aapke iPhone 15 Pro pe 100% Native LiDAR + ARKit power ke sath chalegi!

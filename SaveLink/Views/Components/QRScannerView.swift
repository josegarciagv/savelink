//
//  QRScannerView.swift
//  SaveLink
//
//  Full-screen QR scanner: live camera with a framed viewfinder, flashlight,
//  scanning from a photo, and a confirmation card before the link is used.
//

import SwiftUI
import AVFoundation
import PhotosUI
import Vision
import CoreImage
import Combine

// MARK: - Camera session

@MainActor
final class QRScannerSession: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    enum Status { case starting, running, denied, unavailable }

    @Published private(set) var status: Status = .starting
    @Published private(set) var scannedCode: String?
    @Published var torchOn = false {
        didSet { setTorch(torchOn) }
    }

    let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var isConfigured = false

    var hasTorch: Bool { device?.hasTorch ?? false }

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }
        if !isConfigured {
            guard configure() else {
                status = .unavailable
                return
            }
        }
        let session = session
        await Task.detached { session.startRunning() }.value
        status = .running
    }

    func stop() {
        torchOn = false
        let session = session
        Task.detached { session.stopRunning() }
    }

    /// Clears the last result and keeps scanning.
    func resume() {
        scannedCode = nil
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return false }
        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()
        self.device = device
        isConfigured = true
        return true
    }

    private func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        MainActor.assumeIsolated {
            guard scannedCode == nil else { return }
            scannedCode = code
        }
    }

    /// Reads a QR code from a picked image.
    nonisolated static func decode(_ image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
        if let code = request.results?.compactMap(\.payloadStringValue).first {
            return code
        }
        // Fallback when Vision isn't available (e.g. some simulators and older devices).
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return detector?.features(in: CIImage(cgImage: cgImage))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .first
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Scanner screen

struct QRScannerView: View {
    @Binding var scannedCode: String?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = QRScannerSession()
    @State private var photoItem: PhotosPickerItem?
    @State private var photoResult: String?
    @State private var photoFailed = false
    @State private var scanLine = false

    /// The code found by the camera or in a photo, waiting for confirmation.
    private var result: String? { photoResult ?? scanner.scannedCode }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width * 0.7, 300)
            let frame = CGRect(x: (proxy.size.width - side) / 2, y: proxy.size.height * 0.42 - side / 2, width: side, height: side)

            ZStack {
                Color.black.ignoresSafeArea()

                if scanner.status == .running {
                    CameraPreview(session: scanner.session)
                        .ignoresSafeArea()
                }

                // The dimmed layer extends under the status bar, so its coordinates start
                // above the safe area: shift the hole by the insets to line up with the corners.
                dimmedOverlay(cutout: frame.offsetBy(dx: proxy.safeAreaInsets.leading, dy: proxy.safeAreaInsets.top))
                viewfinder(frame: frame)

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if let result {
                        ResultCard(code: result, onUse: use, onRetry: retry)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        bottomControls
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.snappy, value: result)
        .task { await scanner.start() }
        .onDisappear { scanner.stop() }
        .onChange(of: scanner.scannedCode) { _, code in
            if code != nil { Haptics.success() }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await readPhoto(item) }
        }
        .alert("No QR Code Found", isPresented: $photoFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Choose a photo or screenshot that shows a QR code clearly.")
        }
    }

    // MARK: Pieces

    private func dimmedOverlay(cutout: CGRect) -> some View {
        Canvas { context, size in
            var path = Path(CGRect(origin: .zero, size: size))
            path.addPath(Path(roundedRect: cutout, cornerRadius: 28, style: .continuous))
            context.fill(path, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func viewfinder(frame: CGRect) -> some View {
        let tint: Color = result == nil ? .white : .green
        return ZStack {
            CornerBrackets()
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(result == nil ? 1 : 0.94)

            if result == nil && scanner.status == .running {
                LinearGradient(colors: [.clear, Theme.brand.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: frame.width - 40, height: 2)
                    .shadow(color: Theme.brand, radius: 6)
                    .offset(y: scanLine ? frame.height / 2 - 24 : -frame.height / 2 + 24)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { scanLine = true }
                    }
            }

            if result == nil {
                statusMessage
                    .frame(width: frame.width - 32)
            }
        }
        .position(x: frame.midX, y: frame.midY)
        .animation(.snappy, value: result)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch scanner.status {
        case .denied:
            VStack(spacing: 8) {
                Image(systemName: "camera.fill").font(.title)
                Text("Camera access is off")
                    .font(.headline)
            }
            .foregroundStyle(.white)
        case .unavailable:
            VStack(spacing: 8) {
                Image(systemName: "camera.badge.ellipsis").font(.title)
                Text("Camera not available")
                    .font(.headline)
                Text("You can still scan a QR code from a photo.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
        case .starting, .running:
            EmptyView()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")
            Spacer()
            Text("Scan QR Code")
                .font(.headline)
            Spacer()
            Button {
                scanner.torchOn.toggle()
                Haptics.tap()
            } label: {
                Image(systemName: scanner.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(scanner.torchOn ? AnyShapeStyle(.yellow) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                    .foregroundStyle(scanner.torchOn ? .black : .white)
            }
            .opacity(scanner.hasTorch ? 1 : 0)
            .disabled(!scanner.hasTorch)
            .accessibilityLabel(scanner.torchOn ? "Turn Flashlight Off" : "Turn Flashlight On")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            if scanner.status != .unavailable {
                Text(scanner.status == .denied ? "Allow camera access in Settings to scan." : "Point your camera at a QR code")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("From Photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                if scanner.status == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Theme.brand, in: Capsule())
                    }
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.bottom, 28)
    }

    // MARK: Actions

    private func use() {
        guard let result else { return }
        scannedCode = result
        Haptics.success()
        dismiss()
    }

    private func retry() {
        photoResult = nil
        photoItem = nil
        scanner.resume()
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let code = await QRScannerSession.decode(image) else {
            photoItem = nil
            photoFailed = true
            Haptics.error()
            return
        }
        photoResult = code
        Haptics.success()
    }
}

/// Shows what was scanned and asks before using it.
private struct ResultCard: View {
    let code: String
    let onUse: () -> Void
    let onRetry: () -> Void

    private var isLink: Bool { Link.isValidURL(code) }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                if isLink {
                    FaviconView(urlString: code, color: Theme.brand, size: 48)
                } else {
                    Image(systemName: "text.alignleft")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(isLink ? Link.domain(for: code) : String(localized: "Not a link"))
                        .font(.headline)
                    Text(code)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            if !isLink {
                Text("This QR code has text, not a web link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Button(action: onRetry) {
                    Text("Scan Again")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button(action: onUse) {
                    Text("Use Link")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isLink ? Theme.brand : Color.gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!isLink)
            }
            .foregroundStyle(.white)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Four rounded corner marks around the scanning area.
private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.16
        let radius: CGFloat = 26
        var path = Path()
        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length + radius))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius + length, y: rect.minY))
        // Top-right
        path.move(to: CGPoint(x: rect.maxX - radius - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius + length))
        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - radius - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius - length, y: rect.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + radius + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius - length))
        return path
    }
}

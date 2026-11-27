//
//  QrCodeViews.swift
//  Audia
//

import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SyncPlayQRCodeView: View {
    let content: String
    var size: CGFloat = 170

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        if let image = generateQRCode(from: content) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .padding(6)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct SyncPlayQRScannerSheet: View {
    let onScanned: (_ roomCode: String, _ serverUrl: String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            QRScannerRepresentable { rawValue in
                let parsed = Self.parseQRPayload(rawValue)
                if !parsed.roomCode.isEmpty {
                    dismiss()
                    onScanned(parsed.roomCode, parsed.serverUrl)
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
                Text("Scan a Listen Together QR code")
                    .font(.satoshi(.subheadline, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
            }
        }
    }

    static func parseQRPayload(_ raw: String) -> (roomCode: String, serverUrl: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           url.scheme?.lowercased() == "audia",
           url.host?.lowercased() == "syncplay" {
            let code = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let server = comps?.queryItems?.first(where: { $0.name == "server" })?.value
            return (code == "/" ? "" : code, server)
        }
        if trimmed.lowercased().contains("syncplay/") {
            let after = trimmed.components(separatedBy: "syncplay/").last ?? ""
            let code = after.components(separatedBy: "?").first?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            return (code, nil)
        }
        let cleaned = trimmed.uppercased()
        if cleaned.count >= 4 && cleaned.count <= 10 && cleaned.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return (cleaned, nil)
        }
        return ("", nil)
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onCodeDetected: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onCodeDetected = onCodeDetected
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

private final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeDetected: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didEmit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session?.stopRunning()
        }
    }

    private func setupSession() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        self.captureSession = session
        self.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didEmit,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        didEmit = true
        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session?.stopRunning()
        }
        onCodeDetected?(value)
    }
}

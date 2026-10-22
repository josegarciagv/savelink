//
//  QRScannerView.swift
//  SaveLink
//
//  Created by Jose Garcia on 1/2/26.
//

import SwiftUI
import AVFoundation
import AudioToolbox

struct QRScannerView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, QRScannerDelegate {
        let parent: QRScannerView
        
        init(_ parent: QRScannerView) {
            self.parent = parent
        }
        
        func didFindCode(_ code: String) {
            parent.scannedCode = code
            // Automatically dismiss after scanning
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.parent.dismiss()
            }
        }
        
        func didFail() {
            // Handle error if needed
        }
        
        func didCancel() {
            parent.dismiss()
        }
    }
}

protocol QRScannerDelegate: AnyObject {
    func didFindCode(_ code: String)
    func didFail()
    func didCancel()
}

class QRScannerViewController: UIViewController {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    weak var delegate: QRScannerDelegate?
    var scannedCodeValue: String?
    var successLabel: UILabel?
    var cancelButton: UIButton?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.black
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            delegate?.didFail()
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            delegate?.didFail()
            return
        }
        
        guard let captureSession = captureSession else {
            delegate?.didFail()
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            delegate?.didFail()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr, .ean8, .ean13, .pdf417, .code128]
        } else {
            delegate?.didFail()
            return
        }
        
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview
        
        // Add overlay
        let overlayView = UIView()
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.isUserInteractionEnabled = false // Don't block touches
        view.addSubview(overlayView)
        
        // Add cancel button (after overlay so it's on top)
        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Cancel", for: .normal)
        cancelBtn.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        cancelBtn.setTitleColor(.white, for: .normal)
        cancelBtn.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
        cancelBtn.layer.cornerRadius = 10
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.isUserInteractionEnabled = true
        view.addSubview(cancelBtn)
        self.cancelButton = cancelBtn
        
        NSLayoutConstraint.activate([
            cancelBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            cancelBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelBtn.widthAnchor.constraint(equalToConstant: 120),
            cancelBtn.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Add scanning frame
        let scanningFrame = UIView()
        scanningFrame.layer.borderColor = UIColor.white.cgColor
        scanningFrame.layer.borderWidth = 3
        scanningFrame.layer.cornerRadius = 10
        scanningFrame.backgroundColor = UIColor.clear
        scanningFrame.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanningFrame)
        
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            scanningFrame.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanningFrame.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            scanningFrame.widthAnchor.constraint(equalToConstant: 250),
            scanningFrame.heightAnchor.constraint(equalToConstant: 250)
        ])
        
        // Create hole in overlay using mask
        DispatchQueue.main.async {
            let maskLayer = CAShapeLayer()
            let path = UIBezierPath(rect: overlayView.bounds)
            let scanningRect = CGRect(x: self.view.bounds.midX - 125, y: self.view.bounds.midY - 125, width: 250, height: 250)
            path.append(UIBezierPath(rect: scanningRect).reversing())
            maskLayer.path = path.cgPath
            overlayView.layer.mask = maskLayer
        }
        
        // Add instruction label
        let instructionLabel = UILabel()
        instructionLabel.text = "Point camera at QR code"
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)
        
        // Add success label (initially hidden)
        let successLabel = UILabel()
        successLabel.text = ""
        successLabel.textColor = .green
        successLabel.textAlignment = .center
        successLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        successLabel.numberOfLines = 2
        successLabel.translatesAutoresizingMaskIntoConstraints = false
        successLabel.isHidden = true
        view.addSubview(successLabel)
        self.successLabel = successLabel
        
        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: scanningFrame.bottomAnchor, constant: 20),
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            successLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 10),
            successLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            successLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            successLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    @objc func cancelTapped() {
        delegate?.didCancel()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        guard let captureSession = captureSession else { return }
        
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        guard let captureSession = captureSession else { return }
        
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.stopRunning()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let previewLayer = previewLayer {
            previewLayer.frame = view.layer.bounds
        }
    }
}

extension QRScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession?.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            
            scannedCodeValue = stringValue
            delegate?.didFindCode(stringValue)
            
            // Show brief success message
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.successLabel?.text = "✓ URL scanned successfully!"
                self.successLabel?.isHidden = false
            }
        }
    }
}


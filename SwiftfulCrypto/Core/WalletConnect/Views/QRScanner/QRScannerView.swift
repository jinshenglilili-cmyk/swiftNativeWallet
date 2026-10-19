//
//  QRScannerView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import SwiftUI
import AVFoundation

/// 二维码扫描（AVCaptureSession），识别到内容后回调并停止扫描
struct QRScannerView: UIViewControllerRepresentable {

    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class ScannerViewController: UIViewController {

        var onCodeScanned: ((String) -> Void)?
        private var captureSession: AVCaptureSession?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            setupCamera()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // 相机资源随会话释放，离开页面立即停止
            captureSession?.stopRunning()
        }

        private func setupCamera() {
            guard let device = AVCaptureDevice.default(for: .video) else {
                showPermissionError("未检测到摄像头")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                let session = AVCaptureSession()
                session.addInput(input)

                let output = AVCaptureMetadataOutput()
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]

                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = view.layer.bounds
                view.layer.addSublayer(previewLayer)

                captureSession = session

                // 相机权限可能在进入本页时才首次申请
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized:
                    DispatchQueue.global(qos: .userInitiated).async { [weak session] in
                        session?.startRunning()
                    }
                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        guard granted else {
                            DispatchQueue.main.async { self.showPermissionError("相机权限被拒绝，请在设置中开启") }
                            return
                        }
                        DispatchQueue.global(qos: .userInitiated).async { [weak session] in
                            session?.startRunning()
                        }
                    }
                default:
                    showPermissionError("相机权限被拒绝，请在设置中开启")
                }
            } catch {
                showPermissionError("无法启动摄像头: \(error.localizedDescription)")
            }
        }

        private func showPermissionError(_ message: String) {
            let label = UILabel()
            label.text = message
            label.textColor = .white
            label.numberOfLines = 0
            label.textAlignment = .center
            label.frame = CGRect(x: 20, y: 0, width: view.bounds.width - 40, height: 120)
            label.center = view.center
            label.autoresizingMask = [.flexibleWidth, .flexibleLeftMargin, .flexibleRightMargin]
            view.addSubview(label)
        }
    }
}

extension QRScannerView.ScannerViewController: AVCaptureMetadataOutputObjectsDelegate {

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let stringValue = metadataObject.stringValue else { return }

        // 防重复回调：识别到一条即停
        captureSession?.stopRunning()
        onCodeScanned?(stringValue)
    }
}

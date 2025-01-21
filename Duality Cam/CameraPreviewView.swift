import SwiftUI
import AVFoundation

class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreview: UIViewRepresentable {
    let view: CameraPreviewView
    
    func makeUIView(context: Context) -> CameraPreviewView {
        view
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}
}
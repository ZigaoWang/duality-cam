import AVFoundation
import SwiftUI
import Photos
import Combine

class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    @Published var frontCameraPreview: CameraPreviewView?
    @Published var backCameraPreview: CameraPreviewView?
    @Published var error: Error?
    
    private var captureSession: AVCaptureMultiCamSession?
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var photoCaptureCompletionBlock: ((Result<Void, Error>) -> Void)?
    private var videoRecordingCompletionBlock: ((Result<Void, Error>) -> Void)?
    
    override init() {
        super.init()
        setupMultiCamSession()
    }
    
    private func setupMultiCamSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard AVCaptureMultiCamSession.isMultiCamSupported else {
                DispatchQueue.main.async {
                    self.error = NSError(domain: "", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "This device doesn't support simultaneous cameras"])
                }
                return
            }
            
            let session = AVCaptureMultiCamSession()
            self.captureSession = session
            
            guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                DispatchQueue.main.async {
                    self.error = NSError(domain: "", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "Unable to access cameras"])
                }
                return
            }
            
            do {
                // Configure back camera input
                let backInput = try AVCaptureDeviceInput(device: backCamera)
                guard session.canAddInput(backInput) else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to add back camera input"])
                }
                session.addInputWithNoConnections(backInput)
                
                // Configure front camera input
                let frontInput = try AVCaptureDeviceInput(device: frontCamera)
                guard session.canAddInput(frontInput) else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to add front camera input"])
                }
                session.addInputWithNoConnections(frontInput)
                
                // Configure photo output
                let photoOutput = AVCapturePhotoOutput()
                guard session.canAddOutput(photoOutput) else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to add photo output"])
                }
                session.addOutput(photoOutput)
                self.photoOutput = photoOutput
                
                // Configure movie output
                let movieOutput = AVCaptureMovieFileOutput()
                guard session.canAddOutput(movieOutput) else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to add movie output"])
                }
                session.addOutput(movieOutput)
                self.movieOutput = movieOutput
                
                // Create preview views on main thread
                DispatchQueue.main.async {
                    // Back camera preview setup
                    let backPreviewView = CameraPreviewView()
                    if let previewLayer = backPreviewView.layer as? AVCaptureVideoPreviewLayer {
                        previewLayer.session = session
                        previewLayer.videoGravity = .resizeAspectFill
                        previewLayer.connection?.videoOrientation = .portrait
                        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
                        previewLayer.connection?.isVideoMirrored = false
                    }
                    self.backCameraPreview = backPreviewView
                    
                    // Front camera preview setup
                    let frontPreviewView = CameraPreviewView()
                    if let previewLayer = frontPreviewView.layer as? AVCaptureVideoPreviewLayer {
                        previewLayer.session = session
                        previewLayer.videoGravity = .resizeAspectFill
                        previewLayer.connection?.videoOrientation = .portrait
                        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
                        previewLayer.connection?.isVideoMirrored = true
                    }
                    self.frontCameraPreview = frontPreviewView
                }
                
                session.startRunning()
                
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                }
            }
        }
    }
    
    func capturePhoto(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let photoOutput = self.photoOutput else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo output not available"])))
            return
        }
        
        self.photoCaptureCompletionBlock = completion
        
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            photoCaptureCompletionBlock?(.failure(error))
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            photoCaptureCompletionBlock?(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get image data"])))
            return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                }) { success, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.photoCaptureCompletionBlock?(.failure(error))
                        } else {
                            self.photoCaptureCompletionBlock?(.success(()))
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.photoCaptureCompletionBlock?(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])))
                }
            }
        }
    }
    
    func startRecording(completion: @escaping (Error?) -> Void) {
        guard let movieOutput = self.movieOutput else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Movie output not available"]))
            return
        }
        
        guard !movieOutput.isRecording else {
            completion(nil)
            return
        }
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoURL = documentsURL.appendingPathComponent("dualityVideo-\(Date().timeIntervalSince1970).mov")
        
        movieOutput.startRecording(to: videoURL, recordingDelegate: self)
        completion(nil)
    }
    
    func stopRecording(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let movieOutput = self.movieOutput, movieOutput.isRecording else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not recording"])))
            return
        }
        
        self.videoRecordingCompletionBlock = completion
        movieOutput.stopRecording()
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            videoRecordingCompletionBlock?(.failure(error))
            return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
                }) { success, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.videoRecordingCompletionBlock?(.failure(error))
                        } else {
                            self.videoRecordingCompletionBlock?(.success(()))
                        }
                        
                        // Clean up the temporary file
                        try? FileManager.default.removeItem(at: outputFileURL)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.videoRecordingCompletionBlock?(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])))
                }
            }
        }
    }
    
    func startCameras() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    func stopCameras() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
}

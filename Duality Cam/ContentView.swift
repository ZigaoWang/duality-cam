//
//  ContentView.swift
//  Duality Cam
//
//  Created by Zigao Wang on 1/21/25.
//

import SwiftUI
import AVFoundation
import Photos

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isRecording = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                if let frontPreview = cameraManager.frontCameraPreview,
                   let backPreview = cameraManager.backCameraPreview {
                    
                    VStack(spacing: 1) {
                        CameraPreview(view: frontPreview)
                            .frame(maxWidth: .infinity)
                            .frame(height: UIScreen.main.bounds.height * 0.4)
                            .cornerRadius(0)
                        
                        CameraPreview(view: backPreview)
                            .frame(maxWidth: .infinity)
                            .frame(height: UIScreen.main.bounds.height * 0.4)
                            .cornerRadius(0)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 40) {
                        Button(action: {
                            cameraManager.capturePhoto { result in
                                switch result {
                                case .success:
                                    alertMessage = "Photo saved successfully!"
                                case .failure(let error):
                                    alertMessage = "Failed to save photo: \(error.localizedDescription)"
                                }
                                showingAlert = true
                            }
                        }) {
                            Image(systemName: "camera.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.white)
                        }
                        
                        Button(action: {
                            if isRecording {
                                cameraManager.stopRecording { result in
                                    isRecording = false
                                    switch result {
                                    case .success:
                                        alertMessage = "Video saved successfully!"
                                    case .failure(let error):
                                        alertMessage = "Failed to save video: \(error.localizedDescription)"
                                    }
                                    showingAlert = true
                                }
                            } else {
                                cameraManager.startRecording { error in
                                    if let error = error {
                                        alertMessage = "Failed to start recording: \(error.localizedDescription)"
                                        showingAlert = true
                                    } else {
                                        isRecording = true
                                    }
                                }
                            }
                        }) {
                            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .foregroundColor(isRecording ? .red : .white)
                        }
                    }
                    .padding(.bottom, 30)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2)
                }
            }
        }
        .onAppear {
            cameraManager.startCameras()
        }
        .onDisappear {
            cameraManager.stopCameras()
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Camera"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: Binding(
            get: { cameraManager.error.map { CameraError(error: $0) } },
            set: { _ in cameraManager.error = nil }
        )) { cameraError in
            Alert(
                title: Text("Camera Error"),
                message: Text(cameraError.error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

struct CameraError: Identifiable {
    let id = UUID()
    let error: Error
}

#Preview {
    ContentView()
}

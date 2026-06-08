import SwiftUI

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cameraManager = CameraManager()

    var onPhotoCaptured: ((UIImage) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            if cameraManager.isAuthorized {
                CameraPreviewView(session: cameraManager.session)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                    
                    Text("Camera access required")
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
            
            // Controls
            controls
                .padding(.horizontal, 48)
        }
        .task {
            await cameraManager.configure()
        }
        .onChange(of: cameraManager.capturedImage) { _, image in
            guard let image else { return }
            onPhotoCaptured?(image)
            dismiss()
        }
        .onDisappear {
            cameraManager.stop()
        }
    }

    private var controls: some View {
        HStack {
            Button {
                cameraManager.toggleTorch()
            } label: {
                Image(systemName: cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title2)
                    .foregroundStyle(cameraManager.isTorchOn ? Color.yellow : Color.primary)
                    .frame(width: 54, height: 54)
            }

            Spacer()

            Button {
                cameraManager.capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color(.systemGray3), lineWidth: 3)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(.white)
                        .frame(width: 68, height: 68)
                        .shadow(color: .black.opacity(0.08), radius: 4)
                }
            }

            Spacer()

            Button {
                // TODO: toggle video recording
            } label: {
                ZStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 54, height: 54)
                    Text("REC")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

#Preview {
    CameraView()
}

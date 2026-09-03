/// This view bridges VisionKit's multi-page document camera into SwiftUI.
/// `CaptureScan` presents it in a sheet, and its coordinator converts every
/// captured page to `CGImage` before returning the batch to the scan view model.

import SwiftUI
import VisionKit

struct DocumentCameraView: UIViewControllerRepresentable {
    var onFinish: ([CGImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([CGImage]) -> Void

        init(onFinish: @escaping ([CGImage]) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) { self.onFinish([]) }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true) { self.onFinish([]) }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Prefer the camera's CGImage, falling back to Core Image conversion when needed.
            let images: [CGImage] = (0..<scan.pageCount).compactMap { idx in
                let uiImage = scan.imageOfPage(at: idx)
                return uiImage.cgImage ?? CIContext().createCGImage(
                    CIImage(image: uiImage)!,
                    from: CIImage(image: uiImage)!.extent
                )
            }
            controller.dismiss(animated: true) { self.onFinish(images) }
        }
    }
}

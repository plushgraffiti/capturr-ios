/// This SwiftUI helper maps each `CaptureRoute` to the capture view it opens.
/// `CaptureHome` asks the selected route for its destination after a menu choice.
/// Keeping the mapping here leaves the route model itself free of a SwiftUI dependency.

import SwiftUI

extension CaptureRoute {
    @ViewBuilder
    func destinationView() -> some View {
        switch self {
        case .note:
            CaptureWrite()
        case .todo:
            CaptureTodo()
        case .voice:
            CaptureVoice()
        case .scan:
            CaptureScan()
        }
    }
}

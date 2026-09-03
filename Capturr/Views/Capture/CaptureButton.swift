/// This view draws one capture-mode tile on the Capture home screen.
/// `CaptureHome` creates a tile for each `CaptureRoute`; tapping one pushes the
/// destination view and uses the route's title and system image for its label.

import SwiftUI

struct CaptureButton: View {
    let route: CaptureRoute

    var body: some View {
        HStack {
            NavigationLink(value: route) {
                HStack {
                    VStack {
                        Text(route.menuTitle)
                            .font(.system(.title3, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.bottom, 30)
                        Image(systemName: route.systemImageName)
                            .imageScale(.large)
                            .font(.system(size: 26, weight: .regular, design: .default))
                            .foregroundStyle(.blue)
                    }
                    .padding(10)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: 500)
                .clipped()
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(.quaternarySystemFill))
                }
                .padding(5)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
}

#Preview {
    CaptureButton(route: .note)
}

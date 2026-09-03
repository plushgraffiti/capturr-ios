/// This view is the landing screen for the app's four capture modes.
/// `ContentView` installs it in the Capture tab and can pass a pending route from
/// a deep link, widget, quick action, or App Intent. It shows the capture tiles
/// and turns either a tile tap or pending route into stack navigation.

import SwiftUI

struct CaptureHome: View {
    @Binding var pendingRoute: CaptureRoute?
    @State private var navigationPath: [CaptureRoute] = []

    private let gridColumns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(alignment: .leading) {
                Spacer()

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 0) {
                    CaptureButton(route: .note)
                    CaptureButton(route: .todo)
                    CaptureButton(route: .voice)
                    CaptureButton(route: .scan)
                }
                .padding(.bottom, 10)
            }
            .padding(10)
            .navigationTitle("Capture")
            .navigationDestination(for: CaptureRoute.self) { route in
                route.destinationView()
            }
        }
        .onAppear {
            if let route = pendingRoute {
                navigate(to: route)
            }
        }
        .onChange(of: pendingRoute) { _, newValue in
            guard let route = newValue else { return }
            navigate(to: route)
        }
    }

    private func navigate(to route: CaptureRoute) {
        // Replace the stack so an external route always opens one fresh capture screen.
        navigationPath = []
        navigationPath.append(route)
        pendingRoute = nil
    }
}

#Preview {
    let mockViewModel = ProfileViewModel()
    mockViewModel.defaultTag = "#capture"
    return ContentView()
        .environmentObject(mockViewModel)
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.dark)
}

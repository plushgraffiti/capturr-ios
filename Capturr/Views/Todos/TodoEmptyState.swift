/// This view explains why `TodosHome` cannot currently show any TODOs. It
/// chooses friendly text for missing setup, an empty result, or a fetch error,
/// and links to Settings when setup is missing. `TodosHome` supplies the reason.

import SwiftUI

struct TodoEmptyState: View {
    let reason: EmptyReason

    // This is the small set of empty-screen situations TodosHome can report.
    enum EmptyReason {
        case notConfigured
        case noResults
        case error(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                Image(systemName: iconName)
                    .font(.system(size: 60))
                    .foregroundColor(iconColor)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2)
                    .bold()

                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            actionButton
            Spacer()
        }
        .padding()
    }

    // MARK: - Content

    var iconName: String {
        switch reason {
        case .notConfigured: return "gear.badge.questionmark"
        case .noResults: return "checkmark.circle.badge.questionmark"
        case .error: return "exclamationmark.triangle"
        }
    }

    var iconColor: Color {
        switch reason {
        case .notConfigured: return .blue
        case .noResults: return .gray
        case .error: return .orange
        }
    }

    var title: String {
        switch reason {
        case .notConfigured: return "TODOs Not Configured"
        case .noResults: return "No TODOs Found"
        case .error: return "Unable to Fetch TODOs"
        }
    }

    var message: String {
        switch reason {
        case .notConfigured:
            return "Set up your Backend API token in Settings to get started."
        case .noResults:
            return "No TODOs found for the selected filters. Try adjusting your tag or time period in Settings."
        case .error(let errorMsg):
            return errorMsg
        }
    }

    @ViewBuilder
    var actionButton: some View {
        switch reason {
        case .notConfigured:
            NavigationLink(destination: SettingsHome()) {
                Label("Go to Settings", systemImage: "gear")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("Not Configured") {
    NavigationStack {
        TodoEmptyState(reason: .notConfigured)
    }
}

#Preview("No Results") {
    NavigationStack {
        TodoEmptyState(reason: .noResults)
    }
}

#Preview("Error") {
    NavigationStack {
        TodoEmptyState(reason: .error("Rate limit exceeded. Please try again later."))
    }
}

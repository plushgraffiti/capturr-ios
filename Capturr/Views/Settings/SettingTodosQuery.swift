/// This view edits which Roam TODOs the app should fetch and display.
/// `SettingsHome` and `TodosHome` present it, sharing the same `ProfileViewModel`.
/// The saved include tags, exclude tags, and time period are consumed by TODO
/// synchronization and refresh logic.

import SwiftUI

struct SettingTodosQuery: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                VStack(spacing: 16) {

                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 80, height: 80)
                        Image(systemName: "slider.horizontal.3")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                    }
                    .padding(.top)

                    Text("TODO Filtering")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Filter which TODOs to fetch from your Roam Research graph by tag and time period")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Include Tags (Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Example: #urgent", text: Binding(
                            get: { viewModel.todosTagFilter ?? "" },
                            set: { viewModel.todosTagFilter = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.body)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 5)
                    .padding(.top, 15)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exclude Tags (Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Example: [[someday]]", text: Binding(
                            get: { viewModel.todosExcludeTagFilter ?? "" },
                            set: { viewModel.todosExcludeTagFilter = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.body)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 5)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Time Period")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Time Period", selection: $viewModel.todosTimePeriod) {
                            Text("30 days").tag(30)
                            Text("60 days").tag(60)
                            Text("90 days").tag(90)
                            Text("All time").tag(0)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)

                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("""
**Include Tags:** Show only TODOs containing ANY of these tags (OR logic)

**Exclude Tags:** Hide TODOs containing ANY of these tags (OR logic)

**Filter Combination:** If a TODO matches both include and exclude, it will be excluded

Leave filters empty to show all TODOs
""")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Spacer()

            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    try? viewModel.saveChanges(context: context)
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingTodosQuery(viewModel: ProfileViewModel())
    }
}

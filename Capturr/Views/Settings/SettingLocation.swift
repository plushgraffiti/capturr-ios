/// This view chooses the default Roam page for new captures.
/// `SettingsHome` presents it from Capture Preferences, where the user can keep
/// Daily Notes or enter a custom page. The sync worker reads the saved choice
/// when a capture does not provide its own page override.

import SwiftUI

struct SettingLocation: View {
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
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                            .offset(x: -1, y: 1)
                    }
                    .padding(.top)

                    Text("Default Location")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Specify a default Page to send captures to. By default we'll use the Daily Notes Page.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Use Daily Notes", isOn: $viewModel.useDailyNotes)
                            .onChange(of: viewModel.useDailyNotes) {
                                try? viewModel.saveChanges(context: context)
                            }

                        HStack(spacing: 12) {
                            Text("Custom Page")
                                .foregroundStyle(.primary)
                            Spacer()
                            TextField("Example: [[Inbox]]", text: Binding(
                                get: { viewModel.customLocation ?? "" },
                                set: { viewModel.customLocation = $0 }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.asciiCapable)
                            .submitLabel(.done)
                            .multilineTextAlignment(.trailing)
                            .disabled(viewModel.useDailyNotes)
                            .opacity(viewModel.useDailyNotes ? 0.5 : 1)
                            .onSubmit {
                                try? viewModel.saveChanges(context: context)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .padding()
                    
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Choose where captures should go by default. If Daily Notes is ON, items are sent to today's Daily Note. If it's OFF, they are sent to the custom page you specify. You can use plain titles or wiki links like [[Inbox]].")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
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
        SettingLocation(viewModel: ProfileViewModel())
    }
}

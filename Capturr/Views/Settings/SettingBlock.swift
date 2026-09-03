/// This view edits the optional Roam block that new captures should sit beneath.
/// `SettingsHome` presents it from Capture Preferences and passes the shared
/// `ProfileViewModel`. The sync worker later reads the saved value when it builds
/// the block tree sent to Roam.

import SwiftUI

struct SettingBlock: View {
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
                        Image(systemName: "list.bullet.indent")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                            .offset(x: -1, y: 1)
                    }
                    .padding(.top)

                    Text("Default Block")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Specify a default Block to send captures to. All captures will be stored under this block (Optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text("Default Block")
                                .foregroundStyle(.primary)
                            Spacer()
                            TextField("From [[CAPTURR]]", text: Binding(
                                get: { viewModel.customBlock ?? "" },
                                set: { viewModel.customBlock = $0 }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.asciiCapable)
                            .submitLabel(.done)
                            .multilineTextAlignment(.trailing)
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

                Text("Choose the Block we append captures to in your graph. This is useful if you want to collect all captures together in a single block.")
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
        SettingBlock(viewModel: ProfileViewModel())
    }
}

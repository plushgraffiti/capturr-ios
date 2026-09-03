/// This view edits the optional tag appended to new Roam captures.
/// `SettingsHome` presents it from Capture Preferences and passes the shared
/// `ProfileViewModel`. The sync worker uses the saved tag unless an individual
/// capture supplies its own tags.

import SwiftUI

struct SettingTag: View {
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
                        Image(systemName: "tag")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                            .offset(x: -1, y: 1)
                    }
                    .padding(.top)

                    Text("Default Tag")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Append a tag to everything we send to Roam Research (entirely optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    HStack(spacing: 12) {
                        TextField("Example: #capture, [[mobile]], etc", text: Binding(
                            get: { viewModel.defaultTag ?? "" },
                            set: { viewModel.defaultTag = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .onSubmit {
                            try? viewModel.saveChanges(context: context)
                        }
                    }
                    .padding()
                    
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("You can use which ever format you prefer, # or [[]]. If you set a tag it will be appended to the end of the last line of what we send to Roam Research.\n\nExample: \"Lorem ipsum dolor #capture\"")
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
        SettingTag(viewModel: ProfileViewModel())
    }
}

/// This view controls whether captures receive a timestamp and how it looks.
/// `SettingsHome` presents it from Capture Preferences. Changes are saved through
/// `ProfileViewModel`, and the sync worker applies the chosen position and text
/// formatting when it prepares notes and TODOs for Roam.

import SwiftUI

struct SettingTimestamps: View {
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
                        Image(systemName: "clock")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                            .offset(x: 0, y: 0)
                    }
                    .padding(.top)

                    Text("Manage Timestamps")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Add a timestamp and basic formatting to captured notes and TODOs.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable Timestamps", isOn: $viewModel.addTimestamp)

                        HStack(spacing: 12) {
                            Text("Positioning")
                                .foregroundStyle(.primary)
                            Spacer()
                            Picker("Position", selection: $viewModel.timestampPosition) {
                                ForEach(TimestampPosition.allCases) { position in
                                    Text(position.title).tag(position)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .disabled(!viewModel.addTimestamp)
                            .opacity(viewModel.addTimestamp ? 1 : 0.5)
                        }
                        .padding(.vertical, 5)

                        HStack(spacing: 12) {
                            Text("Formatting")
                                .foregroundStyle(.primary)
                            Spacer()
                            HStack(spacing: 8) {
                                formattingButton(
                                    option: .bold,
                                    systemImage: "bold",
                                    accessibilityLabel: "Bold"
                                )
                                formattingButton(
                                    option: .italic,
                                    systemImage: "italic",
                                    accessibilityLabel: "Italic"
                                )
                                formattingButton(
                                    option: .highlight,
                                    systemImage: "highlighter",
                                    accessibilityLabel: "Highlight"
                                )
                            }
                            .disabled(!viewModel.addTimestamp)
                            .opacity(viewModel.addTimestamp ? 1 : 0.5)
                        }
                        .padding(.vertical, 5)
                    }
                    .padding()
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Choose whether the timestamp appears before or after the capture. Bold, italic, and highlight formatting can be used individually or combined.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
            }
        }
        .onChange(of: viewModel.addTimestamp) {
            save()
        }
        .onChange(of: viewModel.timestampPosition) {
            save()
        }
        .onChange(of: viewModel.timestampFormatting) {
            save()
        }
    }

    private func formattingButton(
        option: TimestampFormatOptions,
        systemImage: String,
        accessibilityLabel: String
    ) -> some View {
        // OptionSet membership lets the three formatting choices be combined independently.
        let isSelected = viewModel.timestampFormatting.contains(option)

        return Button {
            if isSelected {
                viewModel.timestampFormatting.remove(option)
            } else {
                viewModel.timestampFormatting.insert(option)
            }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 32)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "On" : "Off")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        try? viewModel.saveChanges(context: context)
    }
}

#Preview {
    NavigationStack {
        SettingTimestamps(viewModel: ProfileViewModel())
    }
}

/// This view is the editor shown when iOS opens Capturr's share extension.
/// `ShareViewController`, registered in `Sharing/Info.plist`, creates it after loading the
/// shared text or URL and the profile's graph settings. It lets the person edit and choose
/// a destination, then calls the controller so it can save an `OutboxItem` and dismiss.

import SwiftUI

// ShareViewController snapshots the profile's available destinations for this editor session.
struct ShareGraphConfig {
    var primaryGraphName: String?
    var multiGraphEnabled: Bool
    var additionalGraphs: [ShareAdditionalGraph]
}

// The extension needs only a stable graph ID and its display name.
struct ShareAdditionalGraph: Identifiable {
    let id: String
    let name: String
}

// Both send paths return the selected destination to ShareViewController in this value.
struct ShareSendParams {
    let graphId: String?
    let graphName: String
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let graphConfig: ShareGraphConfig
    let roamReaderEnabled: Bool
    let onPost: (ShareSendParams) -> Void
    let onPostRoamReader: ((ShareSendParams) -> Void)?
    @FocusState private var isEditorFocused: Bool

    // Roam Reader needs the original URL metadata, so plain-text shares cannot use it.
    private var showRoamReaderButton: Bool {
        roamReaderEnabled && model.isURLShare
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    TextEditor(text: $model.text)
                        .font(.body)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .keyboardType(.default)
                        .accessibilityIdentifier("ShareEditor")
                        .focused($isEditorFocused)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
                        .padding(.horizontal)
                        .scrollContentBackground(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .onAppear { Task { @MainActor in isEditorFocused = true } }
                }
                .background(Color(.secondarySystemBackground))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("CAPTURR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { NotificationCenter.default.post(name: .init("Close"), object: nil) }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("CancelButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sendToolbarButton
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomButtons
            }
        }
    }

    // MARK: - Toolbar Button

    @ViewBuilder
    private var sendToolbarButton: some View {
        if isMultiGraphEnabled {
            Menu {
                graphMenuContent(isRoamReader: false)
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("ConfirmButton")
        } else {
            Button(action: { sendToPrimary(isRoamReader: false) }) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("ConfirmButton")
        }
    }

    // MARK: - Bottom Buttons

    @ViewBuilder
    private var bottomButtons: some View {
        VStack(spacing: 12) {
            graphAwareButton(
                label: "Send to Graph",
                isRoamReader: false,
                style: .primary
            )

            if showRoamReaderButton {
                graphAwareButton(
                    label: "Send to Roam Reader",
                    isRoamReader: true,
                    style: .secondary
                )
            }
        }
        .padding()
    }

    // MARK: - Graph-Aware Button

    private enum ButtonStyleType {
        case primary
        case secondary
    }

    @ViewBuilder
    private func graphAwareButton(label: String, isRoamReader: Bool, style: ButtonStyleType) -> some View {
        if isMultiGraphEnabled {
            // The share sheet always asks for a destination when additional graphs exist.
            Menu {
                graphMenuContent(isRoamReader: isRoamReader)
            } label: {
                buttonLabel(label, showGraphIcon: true, style: style)
            }
            .buttonStyle(ShareButtonStyle())
        } else {
            Button(action: { sendToPrimary(isRoamReader: isRoamReader) }) {
                buttonLabel(label, showGraphIcon: false, style: style)
            }
            .buttonStyle(ShareButtonStyle())
        }
    }

    @ViewBuilder
    private func buttonLabel(_ text: String, showGraphIcon: Bool, style: ButtonStyleType) -> some View {
        HStack {
            Text(text)
                .lineLimit(1)
            if showGraphIcon {
                Image(systemName: "square.3.layers.3d")
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(style == .primary ? Color.accentColor : Color.clear)
        .foregroundColor(style == .primary ? .white : .accentColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(style == .secondary ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Graph Menu

    @ViewBuilder
    private func graphMenuContent(isRoamReader: Bool) -> some View {
        let primaryName = graphConfig.primaryGraphName ?? "Primary Graph"

        Button {
            send(graphId: nil, graphName: primaryName, isRoamReader: isRoamReader)
        } label: {
            Text(primaryName)
        }

        if !graphConfig.additionalGraphs.isEmpty {
            Divider()

            ForEach(graphConfig.additionalGraphs.sorted { $0.name.lowercased() < $1.name.lowercased() }) { graph in
                Button {
                    send(graphId: graph.id, graphName: graph.name, isRoamReader: isRoamReader)
                } label: {
                    Text(graph.name)
                }
            }
        }
    }

    // MARK: - Helpers

    private var isMultiGraphEnabled: Bool {
        graphConfig.multiGraphEnabled && !graphConfig.additionalGraphs.isEmpty
    }

    private func sendToPrimary(isRoamReader: Bool) {
        let name = graphConfig.primaryGraphName ?? "Primary Graph"
        send(graphId: nil, graphName: name, isRoamReader: isRoamReader)
    }

    private func send(graphId: String?, graphName: String, isRoamReader: Bool) {
        let params = ShareSendParams(graphId: graphId, graphName: graphName)
        if isRoamReader {
            onPostRoamReader?(params)
        } else {
            onPost(params)
        }
    }
}

// This shared style keeps both bottom actions full-width while showing press feedback.
struct ShareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

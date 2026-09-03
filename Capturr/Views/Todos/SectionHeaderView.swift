/// This view draws the tappable heading above a TODO section in `TodosHome`.
/// It reflects whether the section is folded up and tells `TodosHome` when the
/// user wants to expand or collapse it.

import SwiftUI

struct SectionHeaderView: View {
    let section: TodoSection
    let isFirstSection: Bool
    let onToggleCollapse: () -> Void

    init(section: TodoSection, isFirstSection: Bool = false, onToggleCollapse: @escaping () -> Void) {
        self.section = section
        self.isFirstSection = isFirstSection
        self.onToggleCollapse = onToggleCollapse
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFirstSection {
                Divider()
                    .padding(.bottom, 20)
            }

            Button(action: onToggleCollapse) {
                HStack(spacing: 8) {
                    Text(section.name)
                        .font(.title2.bold())
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: section.isCollapsed ? "chevron.right" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

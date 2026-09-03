/// This view draws the temporary TODO row shown by `TodosHome` while a newly
/// captured TODO is still waiting to sync. It displays the saved capture text
/// and asks `SyncStatusStyle` how the current outbox state should look.

import SwiftUI

struct TodoPendingRow: View {
    let item: OutboxItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.title2)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.content)
                    .font(.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(SyncStatusStyle.label(for: item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: SyncStatusStyle.icon(for: item))
                .foregroundStyle(SyncStatusStyle.color(for: item))
                .imageScale(.medium)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TodoPendingRow(item: OutboxItem(content: "Follow up with #sales", type: .todo))
}

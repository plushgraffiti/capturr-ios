/// This view draws a small outlined text badge with a configurable color.
/// `SettingVoiceLanguage` uses it to label dictation languages as installed,
/// downloadable, or unavailable while keeping those states visually compact.

import SwiftUI

struct LanguageStatusBadge: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .backgroundStyle(tint)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(tint, lineWidth: 1))
    }
}

#Preview {
    VStack {
        LanguageStatusBadge(text: "Installed", tint: .blue)
        LanguageStatusBadge(text: "Download", tint: .secondary)
    }
    
}

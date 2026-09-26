import SwiftUI

/// Shared chrome for a provider configuration card: an expandable disclosure
/// group with the glass background/border used across `SettingsContentView`.
/// Provider cards (`ClaudeConfigCard`, `CodexConfigCard`, ...) supply only
/// their header and form content.
struct ConfigCard<Content: View, Label: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label

    @Environment(\.appTheme) private var theme

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            content()
        } label: {
            label()
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    theme.glassBorder, theme.glassBorder.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

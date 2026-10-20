import SwiftUI

private struct MenuBarPanelMaximumHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 900
}

extension EnvironmentValues {
    var menuBarPanelMaximumHeight: CGFloat {
        get { self[MenuBarPanelMaximumHeightKey.self] }
        set { self[MenuBarPanelMaximumHeightKey.self] = newValue }
    }
}

/// Prefer the complete content; scroll only when it exceeds the available height.
struct AdaptiveScrollView<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HeightLimitLayout(maximumHeight: maximumHeight) {
            ViewThatFits(in: .vertical) {
                content.fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    content
                }
            }
        }
    }
}

/// Constrain the proposal without stretching short content to fill the limit.
private struct HeightLimitLayout: Layout {
    let maximumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        return content.sizeThatFits(ProposedViewSize(
            width: proposal.width,
            height: min(proposal.height ?? maximumHeight, maximumHeight)
        ))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

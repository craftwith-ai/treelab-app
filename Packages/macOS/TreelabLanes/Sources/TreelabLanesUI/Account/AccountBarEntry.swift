public import SwiftUI

/// "Treelab account" at the bottom of the sidebar, under Ginkgo: the trial or the plan on a
/// second line. A click opens Treelab's own settings window on "Account and subscription"
/// (⌘, keeps the terminal's settings).
public struct AccountBarEntry: View {
    private let center: TreelabAccountCenter
    private let palette = HUDPalette()
    private let text = AccountText()

    /// The entry's height, reserved at the bottom of the sidebar.
    public static let height: CGFloat = 46

    /// Lines the second line (trial or plan) may take before it is cut.
    public static let subtitleLineLimit = 1

    /// Font size of the second line.
    public static let subtitleFontSize: CGFloat = 10

    /// Width left to the second line in a sidebar of `sidebarWidth` points: outer and inner
    /// paddings, the Treelab mark, the gear and the spacings between them.
    public static func subtitleWidth(sidebarWidth: CGFloat) -> CGFloat {
        sidebarWidth - 2 * 8 - 2 * 12 - 20 - 10 - 10 - 13
    }

    /// Creates the entry.
    /// - Parameter center: the account's windows and model.
    public init(center: TreelabAccountCenter) {
        self.center = center
    }

    public var body: some View {
        let line = AccountPresentation().barLine(center.model.status)
        Button {
            center.showSettings(.account)
        } label: {
            HStack(spacing: 10) {
                TreelabMark(side: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text.accountBarTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.text)
                    Text(line)
                        .font(.system(size: Self.subtitleFontSize))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(Self.subtitleLineLimit)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Self.height - 8, maxHeight: Self.height - 8, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text.accountBarOpen)
        .accessibilityLabel(text.accountBarTitle)
        .accessibilityValue(line)
        .accessibilityHint(text.accountBarOpen)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

import SwiftUI

/// Shown above a pane only when it has more than one tab (Finder behaviour).
struct PaneTabBar: View {
    @ObservedObject var stack: PaneStack
    var onActivate: () -> Void
    @State private var hovered: Int? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stack.tabs.enumerated()), id: \.element.id) { index, pane in
                let selected = index == stack.selectedIndex
                HStack(spacing: 4) {
                    Text(PaneStack.title(for: pane))
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        stack.close(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .opacity(hovered == index || selected ? 0.7 : 0)
                    .help("Close Tab (Cmd+W)")
                    .accessibilityLabel("Close tab \(PaneStack.title(for: pane))")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: 180)
                .background(selected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { onActivate(); stack.select(index) }
                .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                Divider().frame(height: 14)
            }
            Button {
                onActivate()
                stack.newTab()
            } label: {
                Image(systemName: "plus").font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .help("New Tab (Cmd+T)")
            .accessibilityLabel("New tab")
            Spacer(minLength: 0)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

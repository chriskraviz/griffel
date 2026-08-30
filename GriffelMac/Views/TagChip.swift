import SwiftUI

/// A tag, wherever it appears. Tags show up on rows, in the filter bar and in
/// the editor, and all three have to be the same object to the eye.
struct TagChip: View {
    let name: String
    var count: Int?
    var isActive: Bool = false
    var onTap: (() -> Void)?
    var onRemove: (() -> Void)?

    var body: some View {
        GlassChip {
            if let onTap {
                Button(action: onTap) {
                    label
                }
                .buttonStyle(.chip)
            } else {
                label
            }

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.chip)
                .help("Tag entfernen")
            }
        }
        .overlay(
            Capsule().strokeBorder(
                isActive ? Color.accentColor.opacity(0.65) : Color.clear,
                lineWidth: 1
            )
        )
    }

    private var label: some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .lineLimit(1)
            if let count {
                Text("\(count)")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

import SwiftUI

struct Dot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

struct ToolbarButton: View {
    let icon: String
    let title: String
    var tint: Color = Theme.secondary
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(hovering ? Theme.text : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Theme.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct RoundIconButton: View {
    let icon: String
    var size: CGFloat = 12
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(hovering ? Theme.text : Theme.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Theme.hover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.secondary)
    }
}

/// 深色输入框容器
struct DarkField<Content: View>: View {
    var focused: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(Theme.text)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.window)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(focused ? Theme.blue : Theme.divider, lineWidth: 1)
            )
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    var accent: Color = Theme.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(accent)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondary)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panelAlt)
        )
    }
}

struct DurationBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

struct EmptyStateText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Theme.tertiary)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct ChronicleLogo: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color(hex: 0x2A2A2A))

            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color(hex: 0xF2994A),
                            Color(hex: 0xF2C94C),
                            Color(hex: 0x7ED321),
                            Color(hex: 0x56CCF2),
                            Color(hex: 0x9B51E0),
                            Color(hex: 0xF2994A)
                        ],
                        center: .center
                    ),
                    lineWidth: 2
                )

            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .stroke(Color(hex: 0x3A3A3A), lineWidth: 1)
                .padding(8)

            Image(systemName: "clock")
                .font(.system(size: size * 0.4, weight: .light))
                .foregroundColor(Theme.text)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)
    }
}

struct WelcomeView: View {
    @EnvironmentObject var app: AppState

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            ChronicleLogo(size: 92)

            Text("欢迎使用 Chronicle！")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(Theme.text)
                .padding(.top, 18)

            Text("我们还没有太多数据可以展示给你。\n与此同时，为什么不设置你的第一个项目，开始对你的时间进行分类呢？")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 10)
                .padding(.horizontal, 24)

            dropZone
                .padding(.top, 20)

            HStack(spacing: 16) {
                Button {
                    app.section = .stats
                } label: {
                    Text("查看我的追踪数据")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.panelAlt)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    app.newEntryPresented = true
                } label: {
                    Text("新建时间条目")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var dropZone: some View {
        VStack(spacing: 7) {
            Image(systemName: "folder")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(Theme.secondary)
            Text("将文件夹拖放到这里")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondary)
            Text("或者")
                .font(.system(size: 10))
                .foregroundColor(Theme.tertiary)
            Button {
                app.newProjectPresented = true
            } label: {
                Text("手动创建项目")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.blue)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 320, height: 132)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.blue.opacity(isDropTargeted ? 0.12 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Theme.blue.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                }
                guard let url else { return }
                let name = url.lastPathComponent
                guard !name.isEmpty else { return }
                Task { @MainActor in
                    app.createProject(
                        name: name,
                        colorHex: Theme.palette.randomElement() ?? Theme.palette[0],
                        isGroup: true,
                        parentID: nil
                    )
                }
            }
        }
        return true
    }
}

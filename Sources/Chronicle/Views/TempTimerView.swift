import SwiftUI

struct TempTimerView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var model: TempTimerModel

    var body: some View {
        VStack(spacing: 11) {
            header
            ring
            presets
            ProjectPicker(projectID: $model.projectID, compact: true)
            controls
            infoText
        }
        .padding(16)
        .frame(width: 300, height: 372)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.panelAlt)
                .shadow(color: Color.black.opacity(0.45), radius: 24, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "hourglass")
                .font(.system(size: 11))
                .foregroundColor(Theme.orange)
            Text("临时计时")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.text)
            Spacer()
            Text("拖拽移动")
                .font(.system(size: 9))
                .foregroundColor(Theme.tertiary)
            Button {
                app.closeTempTimer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 9)
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(
                    model.isFinished ? Theme.green : Theme.orange,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: model.progress)

            VStack(spacing: 3) {
                Text(Fmt.clock(model.remaining))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Theme.text)
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondary)
            }
        }
        .frame(width: 144, height: 144)
        .padding(.top, 2)
    }

    private var statusText: String {
        if model.isFinished { return "已完成" }
        if model.isRunning { return "剩余时间" }
        if model.elapsed > 0.5 { return "已暂停" }
        return "准备开始"
    }

    private var presets: some View {
        HStack(spacing: 5) {
            ForEach(TempTimerModel.presets, id: \.self) { minutes in
                let selected = Int(model.duration / 60) == minutes
                Button {
                    model.setPreset(minutes: minutes)
                } label: {
                    Text("\(minutes)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(selected ? .white : Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selected ? Theme.orange.opacity(0.9) : Theme.window)
                        )
                }
                .buttonStyle(.plain)
                .disabled(model.isRunning)
                .help("\(minutes) 分钟")
            }
            Text("分")
                .font(.system(size: 9))
                .foregroundColor(Theme.tertiary)
                .padding(.leading, 1)
        }
    }

    private var canSave: Bool {
        model.elapsed >= 1 && !model.isFinished
    }

    private var controls: some View {
        HStack(spacing: 7) {
            Button {
                model.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 10))
                    Text(model.isRunning ? "暂停" : (model.isFinished ? "再来一次" : "开始"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.orange)
                )
            }
            .buttonStyle(.plain)

            Button {
                app.saveTempTimerProgress()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12))
                    .foregroundColor(canSave ? Theme.text : Theme.tertiary)
                    .frame(width: 34, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.window)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .help("结束并记录当前时长")

            Button {
                model.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondary)
                    .frame(width: 34, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.window)
                    )
            }
            .buttonStyle(.plain)
            .help("重置")
        }
    }

    private var infoText: some View {
        Text(model.infoText ?? "结束后自动记录到所选项目")
            .font(.system(size: 9.5))
            .foregroundColor(model.infoText == nil ? Theme.tertiary : Theme.green)
            .lineLimit(1)
            .frame(height: 12)
    }
}

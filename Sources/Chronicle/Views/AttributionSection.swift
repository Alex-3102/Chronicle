import SwiftUI
import ChronicleCore

/// 耗时归因与复盘：日视图逐项填写，周 / 月按项目和日期汇总。
struct AttributionSection: View {
    @EnvironmentObject var app: AppState
    let snapshot: StatisticsSnapshot

    var body: some View {
        let _ = app.attributionRevision
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "耗时归因与复盘")
            if snapshot.total <= 0 {
                EmptyStateText(text: "这个范围还没有记录。")
            } else if snapshot.range == .day {
                dayEditor
            } else {
                summary
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panel)
        )
    }

    // MARK: - 日视图

    private var dayEditor: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                editorRow(row)
                if row.id != rows.last?.id {
                    Divider().overlay(Theme.divider.opacity(0.4))
                }
            }
        }
    }

    private struct Row: Identifiable {
        let id: String
        let name: String
        let color: Color
        let seconds: TimeInterval
    }

    private var rows: [Row] {
        snapshot.projects
            .filter { $0.seconds > 0 }
            .map { item in
                Row(
                    id: item.projectID ?? "__unassigned__",
                    name: item.name,
                    color: item.isUnassigned ? Color(hexString: "#8E8E93") : Color(hexString: item.colorHex),
                    seconds: item.seconds
                )
            }
    }

    private func editorRow(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(row.color)
                    .frame(width: 7, height: 7)
                Text(row.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.text)
                Spacer()
                Text(Fmt.sidebar(row.seconds))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
            }

            field("耗时较高的原因", text: stringBinding(row.id, \.reason))

            toggleRow(
                "是否有预期外的事情",
                isOn: boolBinding(row.id, \.hasUnexpected),
                placeholder: "具体是什么",
                text: stringBinding(row.id, \.unexpectedDetail),
                showsField: app.attributionValue(projectKey: row.id, day: snapshot.interval.start).hasUnexpected
            )

            toggleRow(
                "是否有可优化点",
                isOn: boolBinding(row.id, \.canOptimize),
                placeholder: "可以怎么优化",
                text: stringBinding(row.id, \.optimizationDetail),
                showsField: app.attributionValue(projectKey: row.id, day: snapshot.interval.start).canOptimize
            )
        }
        .padding(.vertical, 9)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(Theme.text)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.window)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
    }

    private func toggleRow(
        _ title: String,
        isOn: Binding<Bool>,
        placeholder: String,
        text: Binding<String>,
        showsField: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            if showsField {
                field(placeholder, text: text)
            }
        }
    }

    // MARK: - 周 / 月汇总

    private var summary: some View {
        let records = app.attributions(in: snapshot.interval)
        let byProject = Dictionary(grouping: records, by: \.projectID)
        let names = Dictionary(uniqueKeysWithValues: app.projects.map { ($0.id, $0.name) })

        func name(_ key: String) -> String {
            key == "__unassigned__" ? "未分配" : (names[key] ?? "已删除项目")
        }

        let optimizations = records
            .filter { $0.canOptimize && !$0.optimizationDetail.isEmpty }
            .sorted { $0.day < $1.day }

        return VStack(alignment: .leading, spacing: 12) {
            if records.isEmpty {
                EmptyStateText(text: "这个范围还没有归因记录。切到「日」视图填写。")
            } else {
                VStack(spacing: 0) {
                    ForEach(byProject.keys.sorted { lhs, rhs in
                        (byProject[lhs]?.count ?? 0) > (byProject[rhs]?.count ?? 0)
                    }, id: \.self) { key in
                        let items = byProject[key] ?? []
                        HStack(spacing: 8) {
                            Text(name(key))
                                .font(.system(size: 11))
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                            Spacer()
                            Text("\(items.count) 天")
                                .font(.system(size: 9.5))
                                .foregroundColor(Theme.tertiary)
                            if items.contains(where: \.hasUnexpected) {
                                tag("预期外 \(items.filter(\.hasUnexpected).count)", color: Theme.red)
                            }
                            if items.contains(where: \.canOptimize) {
                                tag("可优化 \(items.filter(\.canOptimize).count)", color: Theme.blue)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                if !optimizations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("优化点汇总")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.secondary)
                        ForEach(optimizations) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text(shortDay(item.day))
                                    .font(.system(size: 9.5))
                                    .monospacedDigit()
                                    .foregroundColor(Theme.tertiary)
                                    .frame(width: 40, alignment: .leading)
                                Text(name(item.projectID))
                                    .font(.system(size: 9.5))
                                    .foregroundColor(Theme.secondary)
                                Text(item.optimizationDetail)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(Theme.text.opacity(0.9))
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func shortDay(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return key }
        return "\(parts[1])/\(parts[2])"
    }

    // MARK: - 绑定

    private func stringBinding(_ projectKey: String, _ path: WritableKeyPath<Attribution, String>) -> Binding<String> {
        Binding(
            get: { app.attributionValue(projectKey: projectKey, day: snapshot.interval.start)[keyPath: path] },
            set: { value in
                var item = app.attributionValue(projectKey: projectKey, day: snapshot.interval.start)
                item[keyPath: path] = value
                app.saveAttribution(item)
            }
        )
    }

    private func boolBinding(_ projectKey: String, _ path: WritableKeyPath<Attribution, Bool>) -> Binding<Bool> {
        Binding(
            get: { app.attributionValue(projectKey: projectKey, day: snapshot.interval.start)[keyPath: path] },
            set: { value in
                var item = app.attributionValue(projectKey: projectKey, day: snapshot.interval.start)
                item[keyPath: path] = value
                app.saveAttribution(item)
            }
        )
    }
}

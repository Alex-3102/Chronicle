import Foundation

public final class ChronicleStore {
    public let path: String
    private let db: SQLiteDatabase

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Chronicle", isDirectory: true)
    }

    public static func defaultPath() -> String {
        let directory = defaultDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("chronicle.sqlite").path
    }

    public init(path: String = ChronicleStore.defaultPath()) throws {
        self.path = path
        self.db = try SQLiteDatabase(path: path)
        try migrate()
    }

    private func migrate() throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            parent_id TEXT,
            is_group INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS entries (
            id TEXT PRIMARY KEY,
            project_id TEXT,
            title TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            start_at REAL NOT NULL,
            end_at REAL NOT NULL,
            source TEXT NOT NULL DEFAULT 'manual'
        );
        CREATE INDEX IF NOT EXISTS idx_entries_start ON entries(start_at);
        CREATE TABLE IF NOT EXISTS app_usage (
            id TEXT PRIMARY KEY,
            bundle_id TEXT NOT NULL,
            app_name TEXT NOT NULL,
            start_at REAL NOT NULL,
            end_at REAL NOT NULL,
            window_title TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_usage_start ON app_usage(start_at);
        CREATE TABLE IF NOT EXISTS pinyin_cache (
            text TEXT PRIMARY KEY,
            pinyin TEXT NOT NULL,
            initials TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
        migrateProjectColumns()
        migrateUsageColumns()
    }

    /// 旧库升级：补充 projects 上新增的列。
    private func migrateProjectColumns() {
        let columns = (try? db.query("PRAGMA table_info(projects)")) ?? []
        let names = Set(columns.compactMap { $0.text("name") })
        if !names.contains("is_archived") {
            try? db.run("ALTER TABLE projects ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0")
        }
    }

    /// 旧库升级：应用使用记录增加窗口标题。
    private func migrateUsageColumns() {
        let columns = (try? db.query("PRAGMA table_info(app_usage)")) ?? []
        let names = Set(columns.compactMap { $0.text("name") })
        if !names.contains("window_title") {
            try? db.run("ALTER TABLE app_usage ADD COLUMN window_title TEXT")
        }
    }

    // MARK: - Projects

    public func loadProjects() -> [Project] {
        let rows = (try? db.query("""
        SELECT id, name, color, parent_id, is_group, sort_order, is_archived
        FROM projects ORDER BY sort_order ASC, name ASC
        """)) ?? []
        return rows.compactMap { row in
            guard let id = row.text("id"), let name = row.text("name") else { return nil }
            return Project(
                id: id,
                name: name,
                colorHex: row.text("color") ?? "#F2994A",
                parentID: row.text("parent_id"),
                isGroup: (row.int("is_group") ?? 0) != 0,
                sortOrder: row.int("sort_order") ?? 0,
                isArchived: (row.int("is_archived") ?? 0) != 0
            )
        }
    }

    public func upsertProject(_ project: Project) {
        try? db.run("""
        INSERT OR REPLACE INTO projects (id, name, color, parent_id, is_group, sort_order, created_at, is_archived)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(project.id),
            .text(project.name),
            .text(project.colorHex),
            project.parentID.map(SQLValue.text) ?? .null,
            .int(project.isGroup ? 1 : 0),
            .int(project.sortOrder),
            .double(Date().timeIntervalSince1970),
            .int(project.isArchived ? 1 : 0)
        ])
    }

    public func setProjectParent(id: String, parentID: String?, sortOrder: Int) {
        try? db.run("""
        UPDATE projects SET parent_id = ?, sort_order = ? WHERE id = ?
        """, [
            parentID.map(SQLValue.text) ?? .null,
            .int(sortOrder),
            .text(id)
        ])
    }

    public func setProjectArchived(id: String, archived: Bool) {
        try? db.run("UPDATE projects SET is_archived = ? WHERE id = ?", [
            .int(archived ? 1 : 0),
            .text(id)
        ])
    }

    public func deleteProject(id: String) {
        try? db.run("UPDATE entries SET project_id = NULL WHERE project_id = ?", [.text(id)])
        try? db.run("DELETE FROM projects WHERE id = ?", [.text(id)])
    }

    // MARK: - Entries

    public func addEntry(_ entry: TimeEntry) {
        try? db.run("""
        INSERT OR REPLACE INTO entries (id, project_id, title, note, start_at, end_at, source)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(entry.id),
            entry.projectID.map(SQLValue.text) ?? .null,
            .text(entry.title),
            .text(entry.note),
            .double(entry.start.timeIntervalSince1970),
            .double(entry.end.timeIntervalSince1970),
            .text(entry.source.rawValue)
        ])
    }

    public func deleteEntry(id: String) {
        try? db.run("DELETE FROM entries WHERE id = ?", [.text(id)])
    }

    public func entries(from: Date, to: Date) -> [TimeEntry] {
        let rows = (try? db.query("""
        SELECT id, project_id, title, note, start_at, end_at, source
        FROM entries
        WHERE end_at > ? AND start_at < ?
        ORDER BY start_at ASC
        """, [.double(from.timeIntervalSince1970), .double(to.timeIntervalSince1970)])) ?? []

        return rows.compactMap { row in
            guard let id = row.text("id"),
                  let title = row.text("title"),
                  let start = row.double("start_at"),
                  let end = row.double("end_at") else { return nil }
            return TimeEntry(
                id: id,
                projectID: row.text("project_id"),
                title: title,
                note: row.text("note") ?? "",
                start: Date(timeIntervalSince1970: start),
                end: Date(timeIntervalSince1970: end),
                source: EntrySource(rawValue: row.text("source") ?? "manual") ?? .manual
            )
        }
    }

    public func projectTotals(from: Date, to: Date) -> [String: TimeInterval] {
        let rows = (try? db.query("""
        SELECT project_id, SUM(MAX(0, MIN(end_at, ?) - MAX(start_at, ?))) AS total
        FROM entries
        WHERE project_id IS NOT NULL AND end_at > ? AND start_at < ?
        GROUP BY project_id
        """, [
            .double(to.timeIntervalSince1970),
            .double(from.timeIntervalSince1970),
            .double(from.timeIntervalSince1970),
            .double(to.timeIntervalSince1970)
        ])) ?? []

        var totals: [String: TimeInterval] = [:]
        for row in rows {
            guard let id = row.text("project_id") else { continue }
            totals[id] = row.double("total") ?? 0
        }
        return totals
    }

    // MARK: - App usage

    public func recordUsage(_ record: AppUsageRecord, minimumDuration: TimeInterval = 1) {
        guard record.duration >= minimumDuration else { return }
        try? db.run("""
        INSERT OR REPLACE INTO app_usage (id, bundle_id, app_name, start_at, end_at, window_title)
        VALUES (?, ?, ?, ?, ?, ?)
        """, [
            .text(record.id),
            .text(record.bundleID),
            .text(record.appName),
            .double(record.start.timeIntervalSince1970),
            .double(record.end.timeIntervalSince1970),
            record.windowTitle.map { .text($0) } ?? .null
        ])
    }

    public func usage(from: Date, to: Date) -> [AppUsageRecord] {
        let rows = (try? db.query("""
        SELECT id, bundle_id, app_name, start_at, end_at, window_title
        FROM app_usage
        WHERE end_at > ? AND start_at < ?
        ORDER BY start_at ASC
        """, [.double(from.timeIntervalSince1970), .double(to.timeIntervalSince1970)])) ?? []

        return rows.compactMap { row in
            guard let id = row.text("id"),
                  let bundleID = row.text("bundle_id"),
                  let appName = row.text("app_name"),
                  let start = row.double("start_at"),
                  let end = row.double("end_at") else { return nil }
            return AppUsageRecord(
                id: id,
                bundleID: bundleID,
                appName: appName,
                start: Date(timeIntervalSince1970: start),
                end: Date(timeIntervalSince1970: end),
                windowTitle: row.text("window_title")
            )
        }
    }

    public func usageTotals(records: [AppUsageRecord], from: Date, to: Date) -> [AppUsageTotal] {
        var totals: [String: (name: String, seconds: TimeInterval)] = [:]
        for record in records {
            let start = max(record.start, from)
            let end = min(record.end, to)
            guard end > start else { continue }
            var current = totals[record.bundleID] ?? (record.appName, 0)
            current.name = record.appName
            current.seconds += end.timeIntervalSince(start)
            totals[record.bundleID] = current
        }
        return totals
            .map { AppUsageTotal(bundleID: $0.key, appName: $0.value.name, seconds: $0.value.seconds) }
            .sorted { $0.seconds > $1.seconds }
    }

    // MARK: - Pinyin cache

    public func cachedPinyin(for text: String) -> (pinyin: String, initials: String)? {
        let rows = (try? db.query("SELECT pinyin, initials FROM pinyin_cache WHERE text = ?", [.text(text)])) ?? []
        guard let row = rows.first, let pinyin = row.text("pinyin"), let initials = row.text("initials") else {
            return nil
        }
        return (pinyin, initials)
    }

    public func storePinyin(text: String, pinyin: String, initials: String) {
        try? db.run("""
        INSERT OR REPLACE INTO pinyin_cache (text, pinyin, initials, updated_at)
        VALUES (?, ?, ?, ?)
        """, [.text(text), .text(pinyin), .text(initials), .double(Date().timeIntervalSince1970)])
    }

    /// 构建检索索引：原文来自 projects 表，拼音来自缓存表（缺失时计算并回填）。
    public func projectSearchIndex() -> [PinyinSource] {
        let cacheRows = (try? db.query("SELECT text, pinyin, initials FROM pinyin_cache")) ?? []
        var cache: [String: (pinyin: String, initials: String)] = [:]
        for row in cacheRows {
            guard let text = row.text("text"),
                  let pinyin = row.text("pinyin"),
                  let initials = row.text("initials") else { continue }
            cache[text] = (pinyin, initials)
        }

        return loadProjects().map { project in
            if let cached = cache[project.name] {
                return Pinyin.makeSource(
                    key: project.id,
                    text: project.name,
                    pinyin: cached.pinyin,
                    initials: cached.initials
                )
            }
            let pinyin = Pinyin.spaced(project.name)
            let initials = Pinyin.initials(project.name)
            storePinyin(text: project.name, pinyin: pinyin, initials: initials)
            return Pinyin.makeSource(
                key: project.id,
                text: project.name,
                pinyin: pinyin,
                initials: initials
            )
        }
    }

    // MARK: - Settings

    public func setting(_ key: String) -> String? {
        let rows = (try? db.query("SELECT value FROM settings WHERE key = ?", [.text(key)])) ?? []
        return rows.first?.text("value")
    }

    public func setSetting(_ key: String, _ value: String) {
        try? db.run("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", [.text(key), .text(value)])
    }

    // MARK: - Seed

    public func seedIfNeeded() {
        guard setting("seeded") == nil else { return }

        let group = Project(name: "示例项目", colorHex: "#7ED321", sortOrder: 0)
        let acme = Project(name: "Acme, Inc.", colorHex: "#F2C94C", parentID: group.id, sortOrder: 0)
        let redesign = Project(name: "重新设计网站", colorHex: "#F2C94C", parentID: acme.id, sortOrder: 0)

        try? db.run("BEGIN")
        upsertProject(group)
        upsertProject(acme)
        upsertProject(redesign)

        let samples: [(String, String)] = [
            ("网页浏览", "#56CCF2"),
            ("教育和研究", "#BB6BD9"),
            ("技术", "#2D9CDB"),
            ("新闻和媒体", "#EB5757"),
            ("社交媒体", "#F2994A"),
            ("购物和娱乐", "#F2C94C"),
            ("其他非生产", "#BDBDBD"),
            ("媒体", "#9B51E0"),
            ("通讯", "#6FCF97"),
            ("办公和公司", "#4F9CF9"),
            ("阅读和写作", "#F78FB3"),
            ("文件管理", "#7ED321"),
            ("绘图", "#56CCF2"),
            ("开发", "#7ED321")
        ]
        for (index, sample) in samples.enumerated() {
            upsertProject(Project(
                name: sample.0,
                colorHex: sample.1,
                parentID: group.id,
                sortOrder: index + 1
            ))
        }
        try? db.run("COMMIT")
        setSetting("seeded", "1")
    }
}

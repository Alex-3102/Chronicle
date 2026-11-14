# Chronicle 设计文档

Chronicle 是一个 macOS 本机时间追踪工具：自动记录前台应用使用时长，并允许把时间归入可无限嵌套的项目树。所有数据只保存在本机 SQLite 中。

## 1. 技术栈与构建

- Swift 6.1 工具链 + SwiftUI + AppKit，最低 macOS 14。
- 机器上只有 Command Line Tools（没有 Xcode），因此使用 SwiftPM 构建、脚本手工组装 `.app`：

```bash
./Scripts/build-app.sh          # 编译并打包 build/Chronicle.app
./Scripts/release.sh 1.2 3      # 升版本 + 构建 + 生成 dist/Chronicle-1.2.dmg
```

- 工程结构：

```
Chronicle/
├── Package.swift
├── Resources/
│   ├── Info.plist
│   └── AppIcon.icns            # 由 Scripts/make-icon.swift 生成
├── Scripts/
│   ├── build-app.sh            # 编译 + 组装 .app + ad-hoc 签名
│   ├── release.sh              # 版本号 + 构建 + DMG
│   ├── make-icon.swift         # CoreGraphics 绘制应用图标
│   └── make-dmg-background.swift  # DMG 安装界面背景图
├── Sources/
│   ├── ChronicleCore/          # 数据层（无 UI 依赖）
│   │   ├── Models.swift        # Project / TimeEntry / AppUsageRecord
│   │   ├── ChronicleStore.swift# SQLite 读写、迁移、示例数据
│   │   ├── Database.swift      # 轻量 SQLite3 封装
│   │   └── Pinyin.swift        # 拼音 / 首字母索引
│   └── Chronicle/              # 可执行 App
│       ├── ChronicleApp.swift  # 场景、菜单、AppDelegate
│       ├── AppState.swift      # 全局状态与业务动作
│       ├── Services/
│       │   ├── AppUsageTracker.swift  # 前台应用追踪
│       │   ├── FocusTimer.swift       # 定时器 / 临时计时
│       │   └── AppUpdater.swift       # 从本地文件更新
│       └── Views/
│           ├── RootView.swift / HeaderBar.swift
│           ├── SidebarView.swift      # 自绘项目树
│           ├── TimelinePane.swift     # 时间轴 + 应用轨道 + 悬浮卡片
│           ├── UsagePane.swift        # 右侧应用使用
│           ├── SettingsView.swift / Sheets.swift
│           ├── Theme.swift            # 深/浅色动态配色
│           └── AppIconCache.swift     # 应用图标缓存
├── Docs/                       # 本文档与更新记录
└── dist/                       # 每次发布生成的 DMG
```

## 2. 数据模型

| 表 | 说明 |
| --- | --- |
| `projects` | 项目树。`parent_id` 形成无限层级，`sort_order` 决定同级顺序，`color_hex` 是项目颜色，`is_archived` 标记归档 |
| `entries` | 时间条目（手动新建 / 定时器 / 临时计时产生），`project_id` 为空即「未分配」 |
| `app_usage` | 前台应用使用记录：`bundle_id`、`app_name`、`start_at`、`end_at`、`window_title` |
| `settings` | 键值配置（外观、时间轴最大缩放等） |
| `pinyin_cache` | 项目名的拼音/首字母缓存，原文仍存在 `projects` |

迁移策略：建表后通过 `PRAGMA table_info` 检查列是否存在，再用 `ALTER TABLE ... ADD COLUMN` 补列（`is_archived`、`window_title`），旧库可直接升级。

## 3. 界面结构

```
┌──────────────┬────────────────────────────────────┬──────────────┐
│ 导航          │ 顶部工具栏（新建 / 定时器 / 临时计时）    │ 应用使用      │
│ 活动/统计/报告 ├────────────────────────────────────┤ 今天的时间轴  │
│              │ 项目标题 + ⊕    搜索项目（固定）        │ 应用排行      │
│ 项目树（自绘） │ 全部活动 / 未分配 / 我的项目             │              │
│              │ 时间轴：刻度 · 应用轨道 · 条目 · 悬浮卡片 │              │
│              │ 所有活动（树形：项目 › 标题 › 条目 › 应用 › 网站/窗口）│              │
└──────────────┴────────────────────────────────────┴──────────────┘
```

- 侧边栏项目树完全自绘（`ProjectRow`）：颜色圆点、自绘三角箭头、缩进竖线、悬停编辑按钮、拖拽把手、运行中指示点。
- 时间轴 = 24 小时刻度 + 应用轨道 + 时间条目，横向滚动，支持按钮 / ⌘+ / ⌘- / 双指捏合缩放。
- 主区域纵向分两段：上方时间轴按实际轨道数取高度（`min(320, max(138, 74 + 轨道数 × 31 + 18))`），下方「所有活动」列表占满剩余空间。

## 4. 关键实现

### 4.1 项目树

- 无限层级：`parentID` 自引用，`sidebarRows()` 递归展开可见子节点。
- 拖拽：`.draggable(project.id)` + `onDrop` 的 `ProjectDropDelegate`，落点按行高比例分三段（<34% 插到前面，>66% 插到后面，中间成为子项目），拖到「我的项目」标题上移到顶层。拖动过程中实时给出提示：插入时在行的上/下边缘画 2pt 蓝色横线（从目标层级缩进处开始），归属时整行显示蓝色圆角边框。
- 防环：`canMove` / `isDescendant` 保证不能把父项目拖进自己的子孙；编辑项目时父级候选也排除自身与后代。
- 归档：`isArchived` 的项目连同子树从树和搜索中隐藏，数据保留；在「项目」标题、项目列表任意空白处或单个项目上右键都能切换「显示归档项目」。
- 0 时长：项目始终展示，只是时长为 0 时不显示右侧时间，避免一列 `00:00`。
- 键盘：`NSEvent` 本地监听，↑↓ 在可见项目间移动选择并自动滚动到可视区域，←→ 折叠 / 展开选中项目；输入框聚焦或有弹窗时按键交还原生处理。
- 计时汇总：`aggregateTotal(for:)` 递归累加子项目时长，父项目时间 = 自身 + 全部后代。

### 4.2 拼音搜索

- `PinyinIndex` 为每个项目生成全拼、首字母、多音字变体（如 `chongxin` / `cx`），只缓存拼音，原文仍存 `projects`。
- 搜索为空时展示完整树；有输入时走 `searchProjects` 的评分排序（前缀 > 包含 > 首字母），并自动补全命中项的祖先，保证层级可读。

### 4.2.1 项目选择器

凡是「选择项目」的地方都用同一套自绘搜索浮层 `ProjectPickerPanel`（不用系统 `Menu`）：新建 / 编辑条目、开始定时器、临时计时、新建 / 编辑项目的「父级项目」、顶部「筛选条件」。

- 行内容：颜色圆点 + 名称，按 `depth` 缩进 13pt；当前选中项右侧显示对勾，hover 与键盘高亮分开配色。
- 顶部搜索框打开即聚焦，输入走 `pickerProjects(matching:)`（复用 `PinyinIndex`），只过滤不重建层级。
- 键盘：`NSEvent` 本地监听 ↑↓ 移动、↵ 确认、esc 关闭；高亮变化时用 `ScrollViewReader` 自动滚动跟随。
- 列表高度 `min(240, 项目数 × 25 + 10)`，项目少时不留空白。
- `ProjectPicker` 是按钮 + 浮层的封装（绑定 `projectID`）：`noneTitle` 决定第一项文案（记录里是「未分配」，父级项目是「无（顶层项目）」），`excluding` 用于父级项目排除自己与所有子孙。
- 「筛选条件」直接使用 `ProjectPickerPanel`，固定项为「全部活动 / 未分配」（`fixedCount: 2`），其后是项目树。

### 4.2.2 辅助功能权限

- 窗口标题只能通过辅助功能（`AXUIElementCopyAttributeValue`）读取，缺失时退到 `CGWindowList`。应用使用时长本身不需要任何权限。
- 启动只做静默检查（`AXIsProcessTrusted()`），**不带 prompt**，避免每次启动都弹系统授权窗口；只有用户点「去授权」时才调用 `AXIsProcessTrustedWithOptions(prompt: true)`。
- 未授权且未被关闭时，`RootView` 在工具栏下方、所有 tab 内容之上显示整行提示区域 `AccessibilityNoticeBar`（44pt，橙色淡底）：「未开启辅助功能权限 / 无法记录窗口标题；应用使用时长仍会正常统计。 去授权 ×」。切换活动 / 统计 / 报告都保持显示。
- `×` 只对本次运行生效（不落盘），下次启动仍会出现；关闭后整块区域消失，布局回到没有提示的形态。
- 监听 `NSApplication.didBecomeActiveNotification` 重新检查授权状态，从系统设置回来提示条自动消失。
- 未授权时还有一个 2 秒轮询兜底，用户在系统设置里打开开关后即使不切回应用，提示条也会自动消失。
- `AXIsProcessTrusted()` 在部分情况下会误报未授权（例如授权后没有重新启动的进程），因此再实际读一次系统级 `kAXFocusedApplicationAttribute`，能读到就视为已授权。
- 设置页可查看状态、去授权；本次运行内关掉提示后也可在那里点「重新提醒」。

### 4.3 时长口径

- `clampedDuration` 把每个条目的时长裁剪到当前查看的那一天，避免跨天条目把两侧都算满。
- 「全部活动」= max(应用使用时长, 已分配条目时长)；「未分配」= 全部活动 − 已分配到项目的时长。应用使用时长按区间合并计算，重叠不会重复累加。

### 4.3.1 统计与报告的筛选范围

- 侧边栏选中项目只改变筛选条件，**不再跳回「活动」**（`select(project:)` 只设置 `selectedProjectID` / `unassignedOnly`）。
- 统计页使用 `scopedEntries` / `scopedTotal` / `scopedUsageTotals`：选中项目时包含它和所有子孙项目的条目；应用使用时长只统计落在这些条目时间区间内的部分。
- 报告页同样只统计范围内的条目，应用使用列按「应用记录 ∩ 范围内条目区间」计算；标题显示「报告 · 项目名」。
- 「未分配」范围下项目分布显示一条灰色「未分配」；选择具体项目时，统计页标题变为「统计 · 项目名」。

### 4.4 三轨时间轴

同一段时间用三条轨道描述，时长不能相加（总时长仍按统一时间切片计算一次）：

| 轨道 | 数据来源 | 展示内容 |
| --- | --- | --- |
| 应用 | `AppUsageRecord` | 真实应用活动区间，应用色 + 真实图标 |
| 项目归属 | 时间条目切出的 `WorkSpan` | 每段时间最终归属的项目，项目色填充；无条目覆盖为「未分配」 |
| 时间条目 | `TimeEntry` | 计时 / 临时计时 / 手动条目，起始边加粗色条 + 标题 |

**坐标层（`TimelineGeometry`）**：主轴 `u` 表示时间、副轴 `v` 表示轨道，所有绘制、命中测试、悬浮、拖拽都用同一组转换：

```
u(time) = timeInset + seconds(time - rangeStart) / 3600 × pixelsPerHour
point(u, v) = 横向 ? (x: u, y: v) : (x: v, y: u)
rect(uStart, uLength, vStart, vThickness) = 横向 ? (x,y,w,h) : (x: vStart, y: uStart, w: vThickness, h: uLength)
```

`pixelsPerHour = (视口主轴长度 − 2 × timeInset) / 24 × zoom`，因此 1 倍时刚好铺满一天。记录先裁剪到展示范围再布局，原始起止时间不动。

**方向**：`timelineOrientation` 持久化到设置，可在时间轴头部切换。

- 横向：时间从左到右，刻度在顶部；三轨自上而下（应用 24pt / 项目 24pt / 条目占剩余）；固定轨道标签在左侧 46pt 列。
- 竖向：时间从上到下，刻度在右侧 48pt；三轨为三列，条目列占剩余宽度；标签横向排在上方 16pt 行。
- 文字、应用图标、悬浮卡片始终保持正常阅读方向；切换方向时由 `TimelineScrollCoordinator` 保留视口中心时间。

**应用轨道聚合**：每小时像素 < 600 时按约 24px 一个时间桶取主要应用（`桶时长 = 24 / max(48, pph) × 3600 秒`，与实际交集秒数累计，并列按 bundleID 稳定选择，相邻同应用合并，真实空档保留空白）；≥ 600 后回到原始活动区间，相邻同应用区间合并。聚合只影响外观，悬浮与统计仍用真实记录。

**项目归属**：以时间条目的起止边界切成 `[start, end)` 的互不重叠切片，开始时间较晚的条目优先、id 稳定兜底，再合并相邻同项目切片。没有条目覆盖的时段为「未分配」。

**重叠条目**：按开始时间分配到第一条空闲子车道；横向上下并排（行高 16pt），竖向把条目列按重叠数等分左右并排。

**条目外观**：项目色 25% 半透明底、80% 项目色描边 1.2pt、起始边 4pt 加粗色条（横向在上边、竖向在左边）；未选中项目时整体降到 55% 不透明度并弱化填充。

**拖拽编辑**（条目轨道内）：

- 命中边界 7pt 内调整开始 / 结束，其余区域移动整条；空白处框选时间范围（蓝色半透明矩形，仅预览）。
- `delta = (currentU − startU) / pixelsPerHour × 3600`，按精度分级取整：< 480 → 30 秒、≥ 480 → 15 秒、≥ 960 → 10 秒、≥ 1440 → 5 秒，按住 Option 精调到 1 秒。
- 吸附候选是其他条目的真实起止时间（含当前时间）：进入阈值 8px、退出阈值 12px，形成迟滞，避免边界反复吸附 / 脱离。
- 松手后调用 `updateEntry` 提交，运行中条目的结束边界保持跟随 `now`。

### 4.5 悬浮卡片

鼠标在时间轴上移动时，`onContinuousHover` 拿到的是画布内容坐标（时间轴内容就是 `NSScrollView` 的 documentView，滚动不影响它），换算成时刻后由 `TimelinePane` 顶层的 ZStack 绘制卡片。轨道上同时画一条贯穿三轨的悬浮线（前景色 30% 透明度、0.6pt）。

卡片内容：

- 大字时刻（19pt 等宽数字）；
- 应用程序：图标 + 名称 + 起止时刻 + 时长；聚合块额外说明「这一格代表这段时间的主要应用」；
- 标题：该时刻前台窗口标题；
- 时间条目：该时刻命中的条目名称与起止时间；
- 项目：颜色圆点 + 从根到叶的路径（`›` 连接，无项目显示「未分配」）。

卡片定位规则：

- 横向：显示在时间轴**下方**的「所有活动」区域（`y = 时间轴下沿 + 8`），不遮挡时间轴；横向以指针为中心并夹在面板内。
- 竖向：显示在指针右侧（右侧空间不足时翻到左侧），纵向以指针为中心并夹在面板内。
- 卡片 `allowsHitTesting(false)`，不抢鼠标，也不会打断 hover 追踪。

### 4.5.1 所有活动（树形明细）

时间轴下方是 `ActivityOutlineSection` → `ActivityOutlineView`（`NSOutlineView` + `NSViewRepresentable`），把当天的活动组织成展示树：

```
项目 / 未分配
└─ 手动计时标题
   └─ 时间条目（00:00 – 00:20）
      └─ 应用（同一项目内按 bundle ID 合并）
         └─ 网站（浏览器，按域名）/ 窗口（按窗口标题）
```

**数据组织（`ActivityPresentation`）**

- 条目先裁剪到当天得到活动切片；每条应用记录按「重叠最多」归属到某个条目，没有归属的进入「未分配」下的应用列表。
- 项目节点递归构建：直属条目 → 标题分组（`displayTitle`），子项目递归；项目没有直属活动但子项目有活动时仍然展示。
- 同一项目下重复出现的应用合并成一行（优先 `bundleID`，缺失时用应用名）；浏览器（Safari / Chrome / Firefox / Edge / Brave / Vivaldi / Arc / Opera）按正则提取域名显示网站明细，其他应用按窗口标题显示窗口明细。
- 节点时长 = 活动切片时长之和，`start` / `end` 只表示覆盖范围；项目时长 = 直属活动 + 子项目，避免重复累加；应用 / 明细只统计与所属条目重叠的部分（`clampedDuration(_:in:)`）。
- 排序：项目、标题、应用、明细按时长降序（同长按稳定 ID），标题下的具体条目按开始时间升序。稳定 ID：`p:<项目>`、`p:u`、`<父>/t:<标题>`、`<父>/e:<条目>`、`<父>/a:<bundleID>`、`<父>/d:<明细 key>`。

**外观**

- 两列：时长列固定 74pt（右对齐、等宽数字），名称列自动伸展并承载展开箭头 / 图标 / 名称；仅纵向滚动。
- 行高 31pt、每层缩进 18pt。注意 `outline.style` 与 `rowHeight` 会重置缩进和行高，必须在它们之后设置 `indentationPerLevel` / `rowHeight`。
- 项目 = 实心颜色圆点（12pt medium）；手动标题 = 空心项目色圆环；时间条目 = `clock` 符号；应用 = 真实图标（`AppIconCache`）；网站 / 窗口 = `globe` / `macwindow` 次级色。
- 选中行画灰色圆角背景（`ActivityRowView.drawBackground`），行间 0.5pt 浅分隔线；未选中项目的行整体 45% 不透明度，与时间轴弱化一致。
- 头部显示「所有活动 + 全部活动时长」以及「条目 N · 应用 M」计数。

**交互与刷新**

- 展开 / 收起、键盘导航、多选；双击时间条目打开编辑面板（`app.editingEntry` → `NewEntrySheet`），双击分组展开 / 收起。
- 拖拽记录到项目（或「未分配」）即完成分配：`pasteboardWriterForItem` 写条目 ID，`acceptDrop` 调 `AppState.assign(entryIDs:to:)`。
- 展开 / 选中按稳定 ID 存在 `ActivityViewState`（视图外，重建不丢）；默认只自动展开项目层级，「未分配」保持收起。
- `Coordinator.apply()` 用「结构签名」（id + 子节点数量递归）判断：结构相同只更新可见单元格（`reloadVisibleRows`），结构变化才 `reloadData()`，再恢复展开、选中与滚动位置（`captureState` 从视图读取，避免 reload 产生的收起通知覆盖状态）。

### 4.5.2 选中项目的弱化

时间轴不再因为侧边栏选中某个项目就隐藏其他项目：`timelineEntries` 只按搜索词过滤，`isInSelection(_:)` 判断条目是否属于当前选中项目（含子项目 / 未分配），不属于的用 `dimmed` 降低填充透明度（0.9 → 0.32）并加一层暗描边，从而保留完整时间线上下文。

### 4.6 缩放

- 按钮 / 菜单：`adjustTimelineZoom(by:)` 以 1.5 倍步进，范围 1...`timelineMaxZoom`（设置页可调，默认 8）。
- 双指捏合：`TimelineScrollView`（`NSScrollView` 子类）在 `magnify(with:)` 里把倍率交回 `AppState`，同时记下双指中点作为锚点。
- **画布尺寸与滚动偏移必须在同一次更新里写入**：`TimelineScrollCoordinator.apply(contentSize:orientation:)` 先按 `fraction = (oldOffset + pointer − timeInset) / (旧主轴长 − 2 × timeInset)` 求出指针下的时刻，再 `newOffset = timeInset + fraction × (新主轴长 − 2 × timeInset) − pointer`，随后立刻设置 hosting view 的 frame 并 `scroll(to:)`——两者同批完成，末尾再夹到 `0...(主轴长 − 可见长)`。SwiftUI `ScrollView` 做不到这一点：尺寸一变它会先按旧尺寸裁偏移，异步补偿必然留下可见的一帧跳动。
- 锚点来源：捏合用双指中点；按钮 / 快捷键 / 窗口尺寸变化 / 横竖方向切换时用可见区域中心（对应「保留变化前的中心时间」）。
- 捏合期间吞掉 `scrollWheel`（`isPinching` 由 magnify 的 `phase` 维护），避免双指移动带着时间轴跑；非捏合时走系统原生滚动，惯性与方向不变。
- 刻度随密度自适应：每小时 ≥150pt 显示 30 分钟刻度，≥62pt 显示 1 小时，≥28pt 显示 2 小时，否则 3 小时。

### 4.7 外观

`Theme` 中所有颜色都是 `NSColor(name:dynamicProvider:)` 动态色，`AppState.applyAppearance()` 通过 `NSApp.appearance` 切换深色 / 浅色 / 跟随系统，并持久化到 `settings`。

### 4.8 从本地文件更新

「Chronicle › 从本地文件更新…」选择 DMG → `hdiutil attach` → 找到 `Chronicle.app` → 复制到临时目录 → 校验目标目录可写 → 读取两侧版本 → 弹窗确认 → 启动一段 shell 脚本在退出后替换应用并重新打开。

- 版本直接读 `Contents/Info.plist`（`PropertyListSerialization`），不用 `Bundle(url:)`：后者可能返回进程内已缓存的 bundle，读到的版本号和磁盘上的不一致。
- 弹窗展示「1.11 (12)」形式的完整版本，并附上当前副本的路径，方便确认正在更新哪一份。
- 比较时按 `.` 分段转数字（1.11 > 1.9），先比短版本号再比构建号；安装包不比当前版本新时提示「已是最新版本」，不再执行替换与重启。

### 4.9 权限

| 权限 | 用途 | 未授权时 |
| --- | --- | --- |
| 辅助功能 | 读取前台窗口标题（`AXFocusedWindow`） | 标题显示「—」 |
| 屏幕录制 | 兜底读取窗口标题（`CGWindowName`） | 同上 |

应用使用时长本身不需要任何权限。

## 5. 版本与发布

- 版本号写在 `Resources/Info.plist`（`CFBundleShortVersionString` / `CFBundleVersion`），「关于 Chronicle」会展示。
- 「关于 Chronicle」是自绘窗口 `AboutView`：图标、名称、版本号、口号「让每一段时间，都清晰可见」、副标题「本地优先的 macOS 时间追踪应用」、三条能力说明（自动记录 / 项目归类 / 统计与报表）和「保存在本机」提示；菜单用 `openWindow(id: "about")` 打开。DMG 背景印同一句口号。
- 每次发布执行 `./Scripts/release.sh <版本> <构建号>`，产出 `dist/Chronicle-<版本>.dmg`：
  - 首次先跑 `./Scripts/make-signing-cert.sh` 生成固定的本地签名证书「Chronicle Local Signing」；`build-app.sh` 会优先用它签名，找不到才回退 ad-hoc。ad-hoc 每次构建 cdhash 都不同，macOS 会视为新应用，导致辅助功能 / 屏幕录制 / 自动化权限每次更新都要重授；固定证书后权限可以跨版本保留。
  - 内含 `Chronicle.app`、指向 `/Applications` 的「应用程序」快捷方式（不再放说明文件，安装指引全部画在窗口背景上）；
  - `.background/background.png` 为安装指引背景，脚本会尝试用 Finder 摆放图标位置与窗口尺寸；
  - 卷宗带应用图标（`.VolumeIcon.icns`）。
- 变更记录见 `Docs/CHANGELOG.md`。

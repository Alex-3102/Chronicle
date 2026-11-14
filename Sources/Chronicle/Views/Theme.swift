import SwiftUI
import AppKit

/// 深色 / 浅色双套配色，跟随系统或应用外观设置自动切换。
private func themed(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return NSColor(srgbHex: match == .darkAqua ? dark : light)
    })
}

enum Theme {
    static let window = themed(0xF7F7F8, 0x1E1E1E)
    static let sidebar = themed(0xEDEDEF, 0x272727)
    static let panel = themed(0xFFFFFF, 0x222222)
    static let panelAlt = themed(0xF0F0F2, 0x2C2C2C)
    static let hover = themed(0xE6E6E9, 0x323232)
    static let selection = themed(0xDEDEE3, 0x3A3A3A)
    static let divider = themed(0xD8D8DD, 0x383838)
    static let text = themed(0x1B1B1D, 0xEDEDED)
    static let secondary = themed(0x6B6B70, 0x9E9E9E)
    static let tertiary = themed(0x9B9BA1, 0x6F6F6F)
    static let orange = themed(0xE07C1F, 0xF2994A)
    static let green = themed(0x4E9A06, 0x7ED321)
    static let blue = themed(0x1F6FEB, 0x4C9AFF)
    static let red = themed(0xD62C2C, 0xEB5757)

    static let palette: [String] = [
        "#F2994A", "#F2C94C", "#7ED321", "#56CCF2", "#4F9CF9",
        "#9B51E0", "#BB6BD9", "#EB5757", "#F78FB3", "#6FCF97",
        "#2D9CDB", "#BDBDBD"
    ]

    /// 应用使用色块的稳定配色。
    static func appColor(for bundleID: String) -> Color {
        var hash: UInt64 = 5381
        for scalar in bundleID.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        return Color(hexString: palette[Int(hash % UInt64(palette.count))])
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        let number = UInt32(value, radix: 16) ?? 0xF2994A
        self.init(hex: number)
    }
}

extension NSColor {
    convenience init(srgbHex: UInt32) {
        self.init(
            srgbRed: CGFloat((srgbHex >> 16) & 0xFF) / 255,
            green: CGFloat((srgbHex >> 8) & 0xFF) / 255,
            blue: CGFloat(srgbHex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Fmt {
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let preciseTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let weekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static func dayKey(_ date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    static func timeOfDay(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func preciseTime(_ date: Date) -> String {
        preciseTimeFormatter.string(from: date)
    }

    static func dayLong(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    static func weekday(_ date: Date) -> String {
        weekFormatter.string(from: date)
    }

    /// 计时器样式：1:02:03 / 05:20
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// 侧边栏样式：1:05 / 05:20
    static func sidebar(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// 概览样式：1 小时 20 分钟
    static func human(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(hours) 小时"
        }
        if minutes > 0 {
            return "\(minutes) 分钟"
        }
        return "\(total) 秒"
    }

    static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        if calendar.isDateInTomorrow(date) { return "明天" }
        return monthDayFormatter.string(from: date)
    }
}

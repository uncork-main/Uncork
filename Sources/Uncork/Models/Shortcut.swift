import Foundation

/// 瓶内 Windows 程序条目（来自 .lnk 快捷方式或 .exe 扫描）
struct Shortcut: Identifiable, Hashable {
    enum Source: String {
        case startMenu
        case desktop
        case programFiles
    }

    /// 稳定 id：路径小写（同路径去重）
    var id: String { path.lowercased() }

    let name: String
    let path: String
    let source: Source
    let isLink: Bool

    /// 显示名：去扩展名 + trim（.lnk 文件名本身就是安装器写好的名称）
    static func cleanedName(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

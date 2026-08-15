import Foundation

/// 扫描瓶内已安装的程序：开始菜单 .lnk → 桌面 .lnk → Program Files .exe。
/// 纯函数式扫描（不依赖 UI），可放到后台任务执行。
enum ExeScanner {
    static let maxResults = 200

    static func scan(bottle: Bottle) -> [Shortcut] {
        var seen = Set<String>()
        var results: [Shortcut] = []
        let fm = FileManager.default

        func add(_ name: String, path: String, source: Shortcut.Source, isLink: Bool) {
            guard !name.isEmpty, results.count < maxResults else { return }
            let key = path.lowercased()
            guard seen.insert(key).inserted else { return }
            results.append(Shortcut(name: name, path: path, source: source, isLink: isLink))
        }

        func collectLinks(in dir: URL, source: Shortcut.Source) {
            guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return }
            for case let url as URL in en where url.pathExtension.lowercased() == "lnk" {
                add(Shortcut.cleanedName(from: url), path: url.path, source: source, isLink: true)
            }
        }

        let usersDir = bottle.prefixURL.appendingPathComponent("drive_c/users", isDirectory: true)
        let users: [URL] = (try? fm.contentsOfDirectory(at: usersDir, includingPropertiesForKeys: nil)) ?? []

        // 1) 开始菜单（ProgramData + 各用户 AppData）
        let programDataMenu = bottle.prefixURL
            .appendingPathComponent("drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs", isDirectory: true)
        collectLinks(in: programDataMenu, source: .startMenu)
        for user in users {
            let menu = user.appendingPathComponent(
                "AppData/Roaming/Microsoft/Windows/Start Menu/Programs", isDirectory: true)
            collectLinks(in: menu, source: .startMenu)
        }

        // 2) 桌面（Public + 各用户，排除 Public 避免重复）
        collectLinks(
            in: bottle.prefixURL.appendingPathComponent("drive_c/users/Public/Desktop", isDirectory: true),
            source: .desktop)
        for user in users where user.lastPathComponent.lowercased() != "public" {
            collectLinks(in: user.appendingPathComponent("Desktop", isDirectory: true), source: .desktop)
        }

        // 3) Program Files 下的 .exe（深度 ≤ 3，排除卸载器）
        let lnkBases = Set(
            results.filter(\.isLink)
                .map { URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent.lowercased() }
        )
        for pf in ["drive_c/Program Files", "drive_c/Program Files (x86)"] {
            let dir = bottle.prefixURL.appendingPathComponent(pf, isDirectory: true)
            guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for case let url as URL in en {
                let rel = url.path.dropFirst(dir.path.count + 1)
                let depth = rel.split(separator: "/").count
                let isDirectory = ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false
                if isDirectory {
                    if depth >= 3 { en.skipDescendants() }
                    continue
                }
                guard url.pathExtension.lowercased() == "exe" else { continue }
                let base = url.deletingPathExtension().lastPathComponent.lowercased()
                if base.hasPrefix("unins") || base.contains("uninstall") { continue }
                if url.deletingLastPathComponent().lastPathComponent.lowercased().contains("uninstall") { continue }
                if lnkBases.contains(base) { continue } // 已有同名 .lnk，保留快捷方式
                add(Shortcut.cleanedName(from: url), path: url.path, source: .programFiles, isLink: false)
            }
        }

        // 排序：来源优先级 → 名称
        let priority: [Shortcut.Source: Int] = [.startMenu: 0, .desktop: 1, .programFiles: 2]
        return results.sorted { a, b in
            let pa = priority[a.source] ?? 9, pb = priority[b.source] ?? 9
            if pa != pb { return pa < pb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

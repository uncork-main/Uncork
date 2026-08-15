import Foundation

/// 应用数据路径常量。全部位于 ~/Library/Application Support/Uncork/ 下。
/// 非沙盒应用写自己的 Application Support 目录不需要任何 TCC 授权。
enum Paths {
    /// ~/Library/Application Support/Uncork/
    static var supportDir: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Uncork", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 引擎根目录（解压目标）
    static var engineRoot: URL { supportDir.appendingPathComponent("Engine", isDirectory: true) }

    /// 引擎默认目录（arm64 源解压后的顶层目录名）
    static var engineDir: URL { engineRoot.appendingPathComponent("wine-crossover", isDirectory: true) }

    /// 下载缓存目录（重装引擎时不重复下载）
    static var downloadsDir: URL { supportDir.appendingPathComponent("Downloads", isDirectory: true) }

    /// 瓶目录：Bottles/<uuid>（纯 ASCII，与显示名解耦）
    static var bottlesDir: URL { supportDir.appendingPathComponent("Bottles", isDirectory: true) }

    /// 日志目录
    static var logsDir: URL { supportDir.appendingPathComponent("logs", isDirectory: true) }

    /// 瓶列表持久化文件
    static var bottlesJSON: URL { supportDir.appendingPathComponent("bottles.json") }
}

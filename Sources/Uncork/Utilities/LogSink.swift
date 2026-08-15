import Foundation

/// 应用运行日志：内存环形缓冲（尾部 200 行）+ 双写日志文件。
/// 所有 wine 命令的 stderr 都经过 lossy UTF-8 解码后再进来，避免 GBK 输出导致崩溃。
@MainActor
final class LogSink: ObservableObject {
    static let shared = LogSink()

    @Published private(set) var lines: [String] = []

    private let maxLines = 200
    private let logFile = Paths.logsDir.appendingPathComponent("uncork.log")
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func append(_ line: String) {
        // 去掉 ANSI 转义序列
        let cleaned = line.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        let stamped = "[\(Self.timestampFormatter.string(from: Date()))] \(cleaned)"
        lines.append(stamped)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }

        // 双写文件（失败静默，日志不影响主流程）
        let data = (stamped + "\n").data(using: .utf8) ?? Data()
        try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: logFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFile)
        }
    }
}

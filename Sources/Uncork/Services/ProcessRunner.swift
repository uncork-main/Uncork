import Foundation

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum CommandError: Error, LocalizedError {
    case executableMissing(String)
    case timedOut(TimeInterval)
    case exited(CommandResult)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            return "找不到可执行文件：\(path)"
        case .timedOut(let t):
            return "命令执行超时（\(Int(t)) 秒）"
        case .exited(let r):
            let detail = r.stderr.split(separator: "\n").suffix(5).joined(separator: "\n")
            return "命令退出码 \(r.exitCode)" + (detail.isEmpty ? "" : "：\(detail)")
        }
    }
}

/// 线程安全的输出缓冲（readabilityHandler 在任意线程回调）
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ d: Data) {
        lock.lock()
        data.append(d)
        lock.unlock()
    }

    /// lossy UTF-8 解码：Windows 程序输出 GBK 等编码时也不会崩溃
    func finalString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// 保证 continuation 只被 resume 一次（terminationHandler 与超时并发竞争时）
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume<T>(_ continuation: CheckedContinuation<T, Error>, with result: Result<T, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        continuation.resume(with: result)
        return true
    }
}

enum ProcessRunner {
    // 保持 spawned 进程的强引用，防止 Process 被释放
    private static let spawnLock = NSLock()
    private static var spawned: [Process] = []

    /// 等待式执行：捕获 stdout/stderr，可选超时。
    /// 环境变量在现有基础上合并（不是替换），防止子进程缺少 PATH/HOME。
    static func run(
        _ executable: URL,
        args: [String] = [],
        env: [String: String]? = nil,
        cwd: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> CommandResult {
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw CommandError.executableMissing(executable.path)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        var environment = ProcessInfo.processInfo.environment
        if let env { environment.merge(env, uniquingKeysWith: { _, new in new }) }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // 异步增量读取，避免管道写满死锁
        let stdoutBuffer = OutputBuffer()
        let stderrBuffer = OutputBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let resumeOnce = ResumeOnce()

            process.terminationHandler = { p in
                // 先停掉增量读取，再排空剩余数据，保证输出完整
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

                let result = CommandResult(
                    exitCode: p.terminationStatus,
                    stdout: stdoutBuffer.finalString(),
                    stderr: stderrBuffer.finalString()
                )
                if p.terminationStatus == 0 {
                    _ = resumeOnce.resume(continuation, with: .success(result))
                } else {
                    _ = resumeOnce.resume(continuation, with: .failure(CommandError.exited(result)))
                }
            }

            do {
                try process.run()
            } catch {
                _ = resumeOnce.resume(continuation, with: .failure(error))
                return
            }

            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        process.terminate()
                        _ = resumeOnce.resume(continuation, with: .failure(CommandError.timedOut(timeout)))
                    }
                }
            }
        }
    }

    /// 分离式启动 GUI 程序（安装器/已装程序），不等待、不捕获输出。
    /// 注意：exit 0 只表示「已发出启动请求」，Windows 程序本身异步运行。
    /// stderrFile 可选：把子进程 stderr 重定向到日志文件（诊断游戏渲染问题用）。
    static func spawn(
        _ executable: URL,
        args: [String] = [],
        env: [String: String]? = nil,
        stderrFile: URL? = nil
    ) throws {
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw CommandError.executableMissing(executable.path)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = args
        var environment = ProcessInfo.processInfo.environment
        if let env { environment.merge(env, uniquingKeysWith: { _, new in new }) }
        process.environment = environment

        var logHandle: FileHandle?
        if let stderrFile {
            try? FileManager.default.createDirectory(
                at: stderrFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: stderrFile.path, contents: nil)
            logHandle = try? FileHandle(forWritingTo: stderrFile)
            if let logHandle {
                process.standardError = logHandle
            }
        }

        spawnLock.lock()
        spawned.append(process)
        spawnLock.unlock()
        process.terminationHandler = { p in
            try? logHandle?.close()
            spawnLock.lock()
            spawned.removeAll { $0 === p }
            spawnLock.unlock()
        }
        try process.run()
    }
}

import Foundation

/// Wine 引擎状态机
enum EngineState: Equatable {
    case notInstalled
    case downloading(progress: Double) // 0...1；未知总长时为 -1
    case extracting
    case verifying
    case ready(version: String)
    case error(message: String, retryable: Bool)
}

enum EngineError: Error, LocalizedError {
    case invalidArchive(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let detail):
            return "引擎包无效：\(detail)"
        }
    }
}

/// Wine 引擎管理：下载 → 解压 → 签名（如需）→ 校验。
/// 引擎目录：~/Library/Application Support/Uncork/Engine/
@MainActor
final class EngineManager: ObservableObject {
    @Published private(set) var state: EngineState = .notInstalled

    private let downloader = EngineDownloader()
    private var installTask: Task<Void, Never>?

    private struct EngineInfo: Codable {
        var dir: String      // 引擎目录相对 engineRoot 的路径
        var version: String
    }

    private var engineInfoFile: URL { Paths.engineRoot.appendingPathComponent("engine.json") }

    private var engineInfo: EngineInfo? {
        guard let data = try? Data(contentsOf: engineInfoFile) else { return nil }
        return try? JSONDecoder().decode(EngineInfo.self, from: data)
    }

    /// 本次安装刚定位到的引擎目录（engine.json 写入前签名/校验要用，不能依赖默认路径）
    private var locatedEngineDir: URL?

    /// 实际引擎目录（不同源的解压布局不同，以 engine.json 记录为准）
    private var engineDir: URL {
        if let locatedEngineDir {
            return locatedEngineDir
        }
        if let info = engineInfo {
            return Paths.engineRoot.appendingPathComponent(info.dir, isDirectory: true)
        }
        return Paths.engineDir
    }

    /// wine 可执行文件：优先 wine64，回退 wine（WoW64 单二进制构建）
    var wineBinaryURL: URL {
        let wine64 = engineDir.appendingPathComponent("bin/wine64")
        if FileManager.default.fileExists(atPath: wine64.path) {
            return wine64
        }
        return engineDir.appendingPathComponent("bin/wine")
    }

    var wineserverURL: URL { engineDir.appendingPathComponent("bin/wineserver") }

    /// 供 DXVKInstaller 等使用：当前解析出的引擎目录
    var engineDirURL: URL { engineDir }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var isInstalling: Bool {
        switch state {
        case .downloading, .extracting, .verifying: return true
        default: return false
        }
    }

    /// 下载源：Whisky 维护的 Libraries 包（wine 11.15 + DXMT + DXVK）。
    /// 用它替代老的 Wine-CrossOver 23.7.1（wine 8.0.1）：
    /// 新引擎支持 DXMT（DirectX 11 → Metal 直译），UE4 等 3D 游戏可正常渲染，
    /// 老引擎 + DXVK/MoltenVK 组合在新款 Apple GPU 上渲染不出 3D 场景。
    private var sources: [EngineDownloader.Source] {
        [
            EngineDownloader.Source(
                name: "Whisky Libraries (wine 11.15)",
                url: URL(string: "https://github.com/frankea/Whisky/releases/download/v4.5.105-beta.1/Libraries.tar.gz")!,
                archiveFileName: "Libraries.tar.gz"
            ),
        ]
    }

    /// 启动时同步探测引擎是否可用
    func checkInstalled() {
        if FileManager.default.fileExists(atPath: wineBinaryURL.path) {
            state = .ready(version: engineInfo?.version ?? "未知版本")
        } else {
            state = .notInstalled
        }
    }

    /// 安装引擎（幂等：已安装/安装中直接返回）
    func install() async {
        guard installTask == nil, !isReady else { return }
        installTask = Task { [weak self] in
            await self?.performInstall()
        }
        await installTask?.value
        installTask = nil
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
        state = .error(message: "已取消", retryable: true)
    }

    /// 重装：删除引擎目录后重新安装（本地缓存包直接复用，不重复下载）
    func reinstall() async {
        installTask?.cancel()
        installTask = nil
        try? FileManager.default.removeItem(at: Paths.engineRoot)
        state = .notInstalled
        await install()
    }

    /// Apple Silicon 上 x86_64 引擎需要 Rosetta 2（首次会由 macOS 提示安装，
    /// 若用户从未装过则引擎无法运行——提前检测并给出明确指引）
    static func isRosettaAvailable() async -> Bool {
        do {
            _ = try await ProcessRunner.run(
                URL(fileURLWithPath: "/usr/bin/arch"),
                args: ["-x86_64", "/usr/bin/true"],
                timeout: 20
            )
            return true
        } catch {
            return false
        }
    }

    /// 尝试自动安装 Rosetta 2（会弹出系统授权框）
    func installRosetta() async {
        LogSink.shared.append("尝试安装 Rosetta 2…")
        do {
            let result = try await ProcessRunner.run(
                URL(fileURLWithPath: "/usr/sbin/softwareupdate"),
                args: ["--install-rosetta", "--agree-to-license"],
                timeout: 600
            )
            LogSink.shared.append("Rosetta 安装完成：\(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            state = .notInstalled
        } catch {
            LogSink.shared.append("Rosetta 安装失败：\(error.localizedDescription)")
        }
    }

    private func performInstall() async {
        let fm = FileManager.default
        var failures: [String] = []

        // 前置检查 1：磁盘空间（457MB 下载 + 1.3GB 解压 + 余量 ≈ 3GB）
        if let values = try? Paths.supportDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage,
           free < 3_000_000_000 {
            state = .error(
                message: "磁盘空间不足：剩余 \(free / 1_000_000_000)GB，安装引擎至少需要 3GB 可用空间",
                retryable: true
            )
            return
        }

        // 前置检查 2：Apple Silicon 上需要 Rosetta 2 运行 x86_64 引擎
        #if arch(arm64)
        if !(await Self.isRosettaAvailable()) {
            state = .error(
                message: "未检测到 Rosetta 2（运行 Wine 引擎需要）。\n可点击「自动安装 Rosetta」，或在终端运行：\nsoftwareupdate --install-rosetta --agree-to-license",
                retryable: true
            )
            return
        }
        #endif

        for source in sources {
            do {
                let archive = Paths.downloadsDir.appendingPathComponent(source.archiveFileName)

                if !fm.fileExists(atPath: archive.path) {
                    state = .downloading(progress: 0)
                    LogSink.shared.append("开始下载引擎（\(source.name)）…")
                    _ = try await downloader.downloadWithRetry(from: source.url, to: archive) { [weak self] p in
                        Task { @MainActor in
                            self?.state = .downloading(progress: p)
                        }
                    }
                }

                state = .extracting
                LogSink.shared.append("解压引擎…")
                try await extract(archive)

                LogSink.shared.append("检查引擎签名…")
                try await signEngineIfNeeded()

                state = .verifying
                LogSink.shared.append("校验引擎…")
                if let version = try await verifyEngine() {
                    try persistEngineInfo(version: version)
                    LogSink.shared.append("引擎就绪：\(version)")
                    state = .ready(version: version)
                    return
                }
                failures.append("\(source.name)：校验失败")
            } catch is CancellationError {
                state = .error(message: "已取消", retryable: true)
                return
            } catch {
                failures.append("\(source.name)：\(error.localizedDescription)")
            }
        }

        state = .error(
            message: "引擎安装失败：\n" + failures.joined(separator: "\n"),
            retryable: true
        )
    }

    /// 解压引擎归档并整理到 Engine/（Wine 引擎 + DXMT 组件）。
    /// Whisky Libraries 包布局：Libraries/Wine + Libraries/DXMT + Libraries/DXVK。
    private func extract(_ archive: URL) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: Paths.engineRoot)
        try fm.createDirectory(at: Paths.engineRoot, withIntermediateDirectories: true)

        // 先解压到临时目录，再整理进 Engine/
        let tmp = fm.temporaryDirectory.appendingPathComponent("uncork-engine-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        let result = try await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/tar"),
            args: ["-xzf", archive.path, "-C", tmp.path],
            timeout: 900
        )
        LogSink.shared.append("解压完成（退出码 \(result.exitCode)）")

        // Libraries/Wine → Engine/Wine；Libraries/DXMT → Engine/DXMT
        let libsDir = tmp.appendingPathComponent("Libraries", isDirectory: true)
        for sub in ["Wine", "DXMT", "DXVK"] {
            let src = libsDir.appendingPathComponent(sub, isDirectory: true)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.moveItem(at: src, to: Paths.engineRoot.appendingPathComponent(sub, isDirectory: true))
        }

        guard let dir = Self.locateEngineDirectory(in: Paths.engineRoot) else {
            throw EngineError.invalidArchive("解压完成但找不到 bin/wine64 或 bin/wine")
        }
        locatedEngineDir = dir
        LogSink.shared.append("引擎目录：\(dir.path)")
    }

    /// 在 Engine/ 下定位包含 bin/wine64（或 bin/wine）的目录（支持直接树和 .app 壳两种布局）
    private static func locateEngineDirectory(in root: URL) -> URL? {
        let fm = FileManager.default

        func hasWineBinary(_ dir: URL) -> Bool {
            fm.fileExists(atPath: dir.appendingPathComponent("bin/wine64").path)
                || fm.fileExists(atPath: dir.appendingPathComponent("bin/wine").path)
        }

        // 已知布局的直接候选
        for name in ["Wine", "wine-crossover"] {
            let direct = root.appendingPathComponent(name, isDirectory: true)
            if hasWineBinary(direct) {
                return direct
            }
        }
        // 深搜（Heroic 的 .app 壳布局），首个名为 wine 且含 wine 二进制的目录即中
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "wine" else { continue }
            if hasWineBinary(url) {
                return url
            }
        }
        return nil
    }

    /// Apple Silicon 上未签名的 Mach-O 无法执行。若引擎二进制未签名，
    /// 对引擎内所有 Mach-O 文件做 ad-hoc 签名（一次性，幂等）。
    private func signEngineIfNeeded() async throws {
        do {
            _ = try await ProcessRunner.run(
                URL(fileURLWithPath: "/usr/bin/codesign"),
                args: ["-dv", wineBinaryURL.path],
                timeout: 30
            )
            return // 已有签名，跳过
        } catch {
            // 未签名，继续全量签名
        }

        LogSink.shared.append("引擎未签名，正在做 ad-hoc 签名（可能需要几分钟）…")
        let script = """
        find "$1" -type f | while IFS= read -r f; do
          if /usr/bin/file -b "$f" | grep -q "Mach-O"; then
            /usr/bin/codesign --force -s - "$f" >/dev/null 2>&1 || true
          fi
        done
        """
        _ = try await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/sh"),
            args: ["-c", script, "uncork-signer", engineDir.path],
            timeout: 1800
        )
    }

    /// 校验：wine64 --version 能跑且有输出。
    /// 用临时 WINEPREFIX 防止在 ~/.wine 生成垃圾目录。
    private func verifyEngine() async throws -> String? {
        do {
            let result = try await ProcessRunner.run(
                wineBinaryURL,
                args: ["--version"],
                env: [
                    "WINEPREFIX": Paths.supportDir.appendingPathComponent(".verify-prefix").path,
                    "WINEDEBUG": "fixme-all",
                ],
                timeout: 120
            )
            let line = result.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .first
                .map(String.init) ?? ""
            if line.isEmpty {
                LogSink.shared.append("校验失败：wine --version 无输出（stderr: \(result.stderr.prefix(300))）")
                return nil
            }
            return line
        } catch {
            LogSink.shared.append("校验失败：\(error.localizedDescription)")
            return nil
        }
    }

    private func persistEngineInfo(version: String) throws {
        let dir = engineDir.path.replacingOccurrences(of: Paths.engineRoot.path + "/", with: "")
        let info = EngineInfo(dir: dir, version: version)
        let data = try JSONEncoder().encode(info)
        try data.write(to: engineInfoFile, options: .atomic)
    }
}

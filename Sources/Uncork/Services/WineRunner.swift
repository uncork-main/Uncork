import Foundation

/// 所有 wine/wineserver 命令的执行入口：负责环境变量拼装与命令封装。
/// 关键点：
/// - WINEPREFIX 指向瓶目录；PATH 前置引擎 bin，保证 wineserver 等互找
/// - WINEDEBUG=fixme-all 从源头抑制 wine 的 fixme 刷屏
/// - 创建前缀时 WINEARCH=win64（prefix 创建后即定死）
/// - WINEDLLOVERRIDES 禁用 mono/gecko，避免首次初始化弹安装对话框
@MainActor
final class WineRunner {
    private let engine: EngineManager

    init(engine: EngineManager) {
        self.engine = engine
    }

    func environment(for bottle: Bottle, creatingPrefix: Bool = false) -> [String: String] {
        let engineBin = engine.wineBinaryURL.deletingLastPathComponent().path
        // 禁用 mono/gecko；装了 DXVK 时用 native d3d11/d3d10core（游戏必需）
        var overrides = "mscoree,mshtml="
        var env: [String: String] = [
            "PATH": engineBin + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"),
            "WINEPREFIX": bottle.prefixURL.path,
            "WINEDEBUG": "fixme-all",
            // CrossOver 引擎的 msync/esync（性能提升，游戏帧率更稳）
            "WINEMSYNC": "1",
            "WINEESYNC": "1",
        ]
        if DXMTInstaller.isInstalled(in: bottle) {
            // DXMT：d3d11/dxgi 用 native（Metal 直译），其余交给 wine
            overrides = "d3d11,dxgi=n;" + overrides
        }
        env["WINEDLLOVERRIDES"] = overrides
        if creatingPrefix {
            env["WINEARCH"] = "win64"
        }
        return env
    }

    /// 每次运行程序前清空重写的 stderr 日志（诊断渲染问题用）
    private func runLogFile(for bottle: Bottle) -> URL {
        Paths.logsDir.appendingPathComponent("bottle-\(bottle.id.uuidString.prefix(8))-run.log")
    }

    /// 初始化瓶前缀（首次 wineboot 需数十秒到数分钟）
    func createPrefix(for bottle: Bottle) async throws {
        LogSink.shared.append("初始化瓶前缀：\(bottle.name)…")
        let result = try await ProcessRunner.run(
            engine.wineBinaryURL,
            args: ["wineboot"],
            env: environment(for: bottle, creatingPrefix: true),
            timeout: 300
        )
        LogSink.shared.append("瓶前缀初始化完成（\(bottle.name)）")
        if !result.stdout.isEmpty {
            LogSink.shared.append(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// 升级瓶前缀到当前引擎版本（引擎变更后调用）
    func updatePrefix(for bottle: Bottle) async throws {
        LogSink.shared.append("升级瓶前缀：\(bottle.name)…")
        _ = try await ProcessRunner.run(
            engine.wineBinaryURL,
            args: ["wineboot", "-u"],
            env: environment(for: bottle),
            timeout: 300
        )
        LogSink.shared.append("瓶前缀升级完成：\(bottle.name)")
    }

    /// 设置瓶的 Windows 版本（写注册表，比 winecfg GUI 可靠）
    func setWindowsVersion(_ version: WindowsVersion, in bottle: Bottle) async throws {
        let result = try await ProcessRunner.run(
            engine.wineBinaryURL,
            args: ["reg", "add", #"HKCU\Software\Wine"#, "/v", "Version", "/t", "REG_SZ", "/d", version.registryValue, "/f"],
            env: environment(for: bottle),
            timeout: 120
        )
        LogSink.shared.append("已设置 \(bottle.name) 为 \(version.displayName)")
        _ = result
    }

    /// 运行 Windows 安装器（.exe）。start /unix 立即返回，安装器异步运行。
    func runInstaller(at exeURL: URL, in bottle: Bottle) throws {
        LogSink.shared.append("启动安装器：\(exeURL.lastPathComponent)")
        try ProcessRunner.spawn(
            engine.wineBinaryURL,
            args: ["start", "/unix", exeURL.path],
            env: environment(for: bottle),
            stderrFile: runLogFile(for: bottle)
        )
    }

    /// 运行瓶内已安装程序（.lnk 或 .exe，wine 会自动解析 .lnk）
    func runProgram(_ item: Shortcut, in bottle: Bottle) throws {
        LogSink.shared.append("运行：\(item.name)")
        try ProcessRunner.spawn(
            engine.wineBinaryURL,
            args: ["start", "/unix", item.path],
            env: environment(for: bottle),
            stderrFile: runLogFile(for: bottle)
        )
    }

    /// 运行用户手动添加的程序（exe 在磁盘任意位置）。
    /// -nosplash：UE4 游戏的启动画面在 wine 下会卡成空白窗口挡在游戏上，直接跳过。
    func runUserProgram(_ program: UserProgram, in bottle: Bottle) throws {
        LogSink.shared.append("运行：\(program.name)")
        try ProcessRunner.spawn(
            engine.wineBinaryURL,
            args: ["start", "/unix", program.path, "-nosplash"],
            env: environment(for: bottle),
            stderrFile: runLogFile(for: bottle)
        )
    }

    /// 运行 wine 自带程序（notepad 等 builtin）
    func runBuiltinProgram(_ name: String, in bottle: Bottle) throws {
        LogSink.shared.append("运行内置程序：\(name)")
        try ProcessRunner.spawn(
            engine.wineBinaryURL,
            args: [name],
            env: environment(for: bottle)
        )
    }

    /// 打开 winecfg（GUI 配置）
    func launchWineCfg(in bottle: Bottle) throws {
        LogSink.shared.append("打开 Wine 配置（winecfg）")
        try ProcessRunner.spawn(
            engine.wineBinaryURL,
            args: ["winecfg"],
            env: environment(for: bottle)
        )
    }

    /// 强制关闭瓶中的所有进程（只作用于本瓶）
    func killBottleProcesses(in bottle: Bottle) async throws {
        LogSink.shared.append("强制关闭 \(bottle.name) 中的进程")
        _ = try await ProcessRunner.run(
            engine.wineserverURL,
            args: ["-k"],
            env: environment(for: bottle),
            timeout: 60
        )
    }

    /// 瓶中是否有进程在跑。
    /// 同机可能还有其他 wine 应用（如各类 Windows 游戏模拟器）的 wineserver，
    /// 按进程名/可执行路径都会误报；wineserver 会继承启动时的 WINEPREFIX
    /// 环境变量，用 `ps -E` 读出来精确匹配本瓶前缀最可靠。
    func isBottleRunning(_ bottle: Bottle) async -> Bool {
        guard let pgrep = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/pgrep"),
            args: ["-x", "wineserver"],
            timeout: 10
        ), pgrep.exitCode == 0 else {
            return false
        }
        let expected = "WINEPREFIX=" + bottle.prefixURL.path
        for pid in pgrep.stdout.split(separator: "\n") {
            let pidStr = String(pid).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pidStr.isEmpty,
                  let ps = try? await ProcessRunner.run(
                      URL(fileURLWithPath: "/bin/ps"),
                      args: ["-E", "-p", pidStr, "-o", "command="],
                      timeout: 15
                  ) else {
                continue
            }
            if ps.stdout.contains(expected) {
                return true
            }
        }
        return false
    }
}

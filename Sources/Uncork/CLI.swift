import Foundation

/// 命令行模式（无 GUI，也用于自动化验证）：
///   Uncork --install-engine          安装 Wine 引擎
///   Uncork --smoke-test              冒烟测试（建临时瓶 → notepad → 关闭）
///   Uncork --create-bottle <名称>    创建瓶
///   Uncork --list-bottles            列出所有瓶
@MainActor
enum CLI {
    enum Command {
        case installEngine
        case smokeTest
        case createBottle(String)
        case listBottles
        case installDXMT(String)
        case renameBottle(String, String)
    }

    static var command: Command?
    static var isCLIMode: Bool { command != nil }

    static func capture(_ args: [String]) {
        let a = Array(args.dropFirst())
        if a.contains("--install-engine") {
            command = .installEngine
        } else if a.contains("--smoke-test") {
            command = .smokeTest
        } else if let i = a.firstIndex(of: "--create-bottle"), a.count > i + 1 {
            command = .createBottle(a[a.index(after: i)])
        } else if a.contains("--list-bottles") {
            command = .listBottles
        } else if let i = a.firstIndex(of: "--install-dxmt"), a.count > i + 1 {
            command = .installDXMT(a[a.index(after: i)])
        } else if let i = a.firstIndex(of: "--install-dxvk"), a.count > i + 1 {
            // 兼容旧命令名
            command = .installDXMT(a[a.index(after: i)])
        } else if let i = a.firstIndex(of: "--rename-bottle"), a.count > i + 2 {
            command = .renameBottle(a[a.index(after: i)], a[a.index(after: i) + 1])
        } else {
            command = nil
        }
    }

    static func run() async -> Int32 {
        guard let command else { return 1 }
        let engine = EngineManager()
        let wine = WineRunner(engine: engine)
        let store = BottleStore()
        store.load()

        switch command {
        case .installEngine:
            return await installEngine(engine: engine)
        case .smokeTest:
            return await smokeTest(engine: engine, wine: wine)
        case .createBottle(let name):
            engine.checkInstalled()
            guard engine.isReady else {
                print("[开瓶器] 引擎未安装，请先运行 --install-engine")
                return 1
            }
            do {
                let bottle = try await store.create(name: name, version: .win10, wine: wine)
                print("[开瓶器] 已创建瓶：\(bottle.name) → \(bottle.prefixURL.path)")
                return 0
            } catch {
                print("[开瓶器] 创建失败：\(error.localizedDescription)")
                return 1
            }
        case .listBottles:
            if store.bottles.isEmpty {
                print("（暂无瓶）")
            }
            for b in store.bottles {
                print("\(b.name)\t\(b.windowsVersion.displayName)\t\(b.prefixURL.path)")
            }
            return 0
        case .installDXMT(let name):
            guard let bottle = store.bottles.first(where: { $0.name == name }) else {
                print("[开瓶器] 找不到名为「\(name)」的瓶")
                return 1
            }
            do {
                try await DXMTInstaller.install(in: bottle)
                print("[开瓶器] ✅ DXMT（Metal 渲染）已安装到瓶「\(name)」")
                return 0
            } catch {
                print("[开瓶器] ❌ DXMT 安装失败：\(error.localizedDescription)")
                return 1
            }
        case .renameBottle(let oldName, let newName):
            guard let bottle = store.bottles.first(where: { $0.name == oldName }) else {
                print("[开瓶器] 找不到名为「\(oldName)」的瓶")
                return 1
            }
            do {
                try store.rename(bottle, to: newName)
                print("[开瓶器] ✅ 已重命名：「\(oldName)」→「\(newName)」")
                return 0
            } catch {
                print("[开瓶器] ❌ 重命名失败：\(error.localizedDescription)")
                return 1
            }
        }
    }

    private static func installEngine(engine: EngineManager) async -> Int32 {
        print("[开瓶器] 检查引擎…")
        engine.checkInstalled()
        if case .ready(let v) = engine.state {
            print("[开瓶器] 引擎已安装：\(v)")
            return 0
        }

        // 打印进度（轮询状态机）
        let printer = Task { @MainActor in
            var last = ""
            while !Task.isCancelled {
                let text = stateText(engine.state)
                if text != last {
                    print("[开瓶器] \(text)")
                    last = text
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        await engine.install()
        printer.cancel()

        switch engine.state {
        case .ready(let v):
            print("[开瓶器] ✅ 引擎安装完成：\(v)")
            print("[开瓶器] 位置：\(engine.wineBinaryURL.deletingLastPathComponent().deletingLastPathComponent().path)")
            return 0
        case .error(let m, _):
            print("[开瓶器] ❌ 安装失败：\(m)")
            return 1
        default:
            print("[开瓶器] ❌ 安装失败（未知状态）")
            return 1
        }
    }

    private static func smokeTest(engine: EngineManager, wine: WineRunner) async -> Int32 {
        engine.checkInstalled()
        guard case .ready(let v) = engine.state else {
            print("[冒烟] ❌ 引擎未安装，请先运行 --install-engine")
            return 1
        }
        print("[冒烟] 引擎：\(v)")

        let bottle = Bottle(id: UUID(), name: "冒烟测试", windowsVersion: .win10, createdAt: Date())
        let fm = FileManager.default
        try? fm.createDirectory(at: bottle.prefixURL, withIntermediateDirectories: true)

        defer {
            // 清理临时瓶
            try? fm.removeItem(at: bottle.prefixURL)
        }

        do {
            print("[冒烟] 初始化瓶前缀（wineboot，可能需要 1-3 分钟）…")
            try await wine.createPrefix(for: bottle)
            print("[冒烟] ✅ 前缀初始化完成")

            print("[冒烟] 启动 notepad…")
            try wine.runBuiltinProgram("notepad", in: bottle)
            try await Task.sleep(nanoseconds: 10_000_000_000)

            let running = await wine.isBottleRunning(bottle)
            print("[冒烟] wineserver 运行中：\(running)")
            guard running else {
                print("[冒烟] ❌ 失败：notepad 未能启动 wineserver")
                return 1
            }

            print("[冒烟] 强制关闭瓶中进程…")
            try await wine.killBottleProcesses(in: bottle)
            try await Task.sleep(nanoseconds: 2_000_000_000)

            let after = await wine.isBottleRunning(bottle)
            print("[冒烟] 关闭后 wineserver 运行中：\(after)")
            print(after ? "[冒烟] ❌ 失败：进程未被关闭" : "[冒烟] ✅ 全部通过")
            return after ? 1 : 0
        } catch {
            print("[冒烟] ❌ 失败：\(error.localizedDescription)")
            return 1
        }
    }

    private static func stateText(_ s: EngineState) -> String {
        switch s {
        case .notInstalled: return "未安装"
        case .downloading(let p): return p >= 0 ? String(format: "下载中 %.0f%%", p * 100) : "下载中…"
        case .extracting: return "解压中…"
        case .verifying: return "校验中…"
        case .ready(let v): return "就绪（\(v)）"
        case .error(let m, _): return "错误：\(m)"
        }
    }
}

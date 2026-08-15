import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 瓶详情：程序列表 / 安装软件 / 工具 / 运行日志
struct BottleDetailView: View {
    @EnvironmentObject var appState: AppState
    let bottle: Bottle

    private enum FilePickerMode {
        case installer   // 运行 Windows 安装器
        case addProgram  // 添加为瓶内一键运行的程序
    }

    @State private var shortcuts: [Shortcut] = []
    @State private var scanning = false
    @State private var isRunning = false
    @State private var showFilePicker = false
    @State private var pickerMode: FilePickerMode = .installer
    @State private var errorMessage: String?
    @State private var showError = false
    /// 正在启动的程序名（非 nil = 启动冷却期内，禁止再启动别的程序）
    @State private var launchingName: String?
    @State private var showRename = false
    @State private var renameText = ""

    /// 瓶数据可能被修改（添加/删除程序），始终读 store 里的最新值
    private var currentBottle: Bottle {
        appState.store.bottle(withID: bottle.id) ?? bottle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            userProgramsSection
            Divider()
            programsSection
            Divider()
            logSection
        }
        .padding(16)
        .navigationTitle(currentBottle.name)
        .task {
            await refreshPrograms()
            await pollRunning()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "exe") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            switch pickerMode {
            case .installer:
                Task { await install(from: url) }
            case .addProgram:
                addUserProgram(from: url)
            }
        }
        .alert("出错了", isPresented: $showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("重命名瓶", isPresented: $showRename) {
            TextField("名称", text: $renameText)
            Button("确定") {
                try? appState.store.rename(currentBottle, to: renameText)
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(currentBottle.name)
                        .font(.title2.bold())
                    Button {
                        renameText = currentBottle.name
                        showRename = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("重命名瓶")
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 9, height: 9)
                    Text(isRunning ? "瓶中程序运行中" : "空闲")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                pickerMode = .installer
                showFilePicker = true
            } label: {
                Label("安装软件…", systemImage: "arrow.down.circle")
            }
            .disabled(launchingName != nil)
            Button {
                Task { await runWineCfg() }
            } label: {
                Label(launchingName != nil ? "配置中…" : "配置 Wine", systemImage: "gearshape")
            }
            .disabled(launchingName != nil)
            Menu {
                Button {
                    openDriveC()
                } label: {
                    Label("打开 C: 驱动器", systemImage: "folder")
                }
                if DXMTInstaller.isInstalled(in: bottle) {
                    Button {
                    } label: {
                        Label("DXMT（Metal 渲染）已安装", systemImage: "checkmark.seal")
                    }
                    .disabled(true)
                } else {
                    Button {
                        Task { await installDXMT() }
                    } label: {
                        Label("安装 DXMT（游戏 3D 渲染）", systemImage: "gamecontroller")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    Task { await forceKill() }
                } label: {
                    Label("强制关闭瓶中程序", systemImage: "xmark.octagon")
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - 我添加的程序

    private var userProgramsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("我添加的程序")
                    .font(.headline)
                Spacer()
                Button {
                    pickerMode = .addProgram
                    showFilePicker = true
                } label: {
                    Label("添加程序…", systemImage: "plus.circle")
                }
                .controlSize(.small)
            }

            if currentBottle.userPrograms.isEmpty {
                Text("把绿色版游戏等免安装的 .exe 添加到这里，之后一键运行。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(currentBottle.userPrograms) { program in
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.name)
                            Text(program.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(launchingName != nil ? "启动中…" : "运行") {
                            Task { await runUserProgram(program) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(launchingName != nil)
                        Button {
                            removeUserProgram(program)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("从列表移除（不会删除文件）")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 程序列表

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已安装的程序")
                    .font(.headline)
                Spacer()
                if scanning {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await refreshPrograms() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            if shortcuts.isEmpty {
                Text("还没有扫描到程序。点击「安装软件…」运行 Windows 安装器，或从「更多 → 打开 C: 驱动器」手动查看。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                List(shortcuts) { item in
                    HStack {
                        Image(systemName: item.isLink ? "link" : "app.dashed")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(sourceText(item.source))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(launchingName != nil ? "启动中…" : "运行") {
                            Task { await run(item) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(launchingName != nil)
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 180)
            }
        }
    }

    // MARK: - 日志

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("运行日志")
                .font(.headline)
            ScrollView {
                Text(LogSink.shared.lines.suffix(30).joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary.opacity(0.3))
            )
            .padding(.top, 4)
        }
    }

    // MARK: - 动作

    private func refreshPrograms() async {
        scanning = true
        let results = await Task.detached { ExeScanner.scan(bottle: bottle) }.value
        shortcuts = results
        scanning = false
    }

    private func pollRunning() async {
        while !Task.isCancelled {
            isRunning = await appState.wine.isBottleRunning(bottle)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func install(from url: URL) async {
        await runWithCooldown(name: url.deletingPathExtension().lastPathComponent) {
            do {
                try appState.wine.runInstaller(at: url, in: bottle)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func run(_ item: Shortcut) async {
        await runWithCooldown(name: item.name) {
            do {
                try appState.wine.runProgram(item, in: bottle)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func runWineCfg() async {
        await runWithCooldown(name: "Wine 配置") {
            do {
                try appState.wine.launchWineCfg(in: bottle)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func forceKill() async {
        do {
            try await appState.wine.killBottleProcesses(in: bottle)
            isRunning = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func installDXMT() async {
        do {
            try await DXMTInstaller.install(in: bottle)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func addUserProgram(from url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        do {
            try appState.store.addProgram(name: name, path: url.path, to: bottle)
            LogSink.shared.append("已添加程序：\(name)")
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func removeUserProgram(_ program: UserProgram) {
        do {
            try appState.store.removeProgram(program, from: bottle)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func runUserProgram(_ program: UserProgram) async {
        await runWithCooldown(name: program.name) {
            do {
                try appState.wine.runUserProgram(program, in: bottle)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    /// 启动冷却：5 秒内禁止再启动别的程序，防止重复点击造成多实例冲突
    private func runWithCooldown(name: String, action: @escaping () async -> Void) async {
        launchingName = name
        await action()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        launchingName = nil
    }

    private func openDriveC() {
        NSWorkspace.shared.open(bottle.driveCURL)
    }

    private func sourceText(_ source: Shortcut.Source) -> String {
        switch source {
        case .startMenu: return "开始菜单"
        case .desktop: return "桌面"
        case .programFiles: return "Program Files"
        }
    }
}

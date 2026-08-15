import SwiftUI

/// 设置窗口（Cmd+,）：引擎信息与关于页
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            Form {
                Section("Wine 引擎") {
                    LabeledContent("状态", value: engineStatusText)
                    LabeledContent("安装位置", value: Paths.engineRoot.path)
                        .textSelection(.enabled)
                    Button("重新安装引擎") {
                        Task { await appState.engine.reinstall() }
                    }
                    .disabled(appState.engine.isInstalling)
                }
            }
            .padding(20)
            .tabItem { Label("通用", systemImage: "gearshape") }

            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 380)
    }

    private var engineStatusText: String {
        switch appState.engine.state {
        case .notInstalled: return "未安装"
        case .downloading(let p): return p >= 0 ? "下载中 \(Int(p * 100))%" : "下载中…"
        case .extracting: return "解压中…"
        case .verifying: return "校验中…"
        case .ready(let v): return "已就绪（\(v)）"
        case .error(let m, _): return "错误：\(m)"
        }
    }
}

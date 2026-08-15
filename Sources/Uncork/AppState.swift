import SwiftUI

enum Route {
    case welcome // 首次启动/引擎未安装
    case main    // 主界面（瓶列表）
}

/// 全局状态中枢：路由、选中瓶、各服务装配
@MainActor
final class AppState: ObservableObject {
    @Published var route: Route = .welcome
    @Published var selectedBottleID: UUID?

    let engine = EngineManager()
    let store = BottleStore()
    let wine: WineRunner

    init() {
        wine = WineRunner(engine: engine)
    }

    func bootstrap() async {
        store.load()
        engine.checkInstalled()
        route = engine.isReady ? .main : .welcome

        // 引擎版本变更 → 后台逐个升级瓶前缀（首次可能耗时数分钟，不阻塞界面）
        if case .ready(let version) = engine.state, store.engineVersion != version {
            LogSink.shared.append("检测到引擎版本变更（\(store.engineVersion ?? "无") → \(version)），正在升级瓶…")
            Task { await upgradeBottles(to: version) }
        }
    }

    private func upgradeBottles(to version: String) async {
        for bottle in store.bottles {
            do {
                try await wine.updatePrefix(for: bottle)
            } catch {
                LogSink.shared.append("瓶「\(bottle.name)」升级失败：\(error.localizedDescription)")
            }
        }
        try? store.updateEngineVersion(version)
    }
}

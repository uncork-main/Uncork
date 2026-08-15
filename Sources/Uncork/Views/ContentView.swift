import SwiftUI

/// 按路由分发：引擎未就绪 → 欢迎页；就绪 → 主界面
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.route {
            case .welcome:
                WelcomeView()
            case .main:
                BottleListView()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .task {
            await appState.bootstrap()
        }
    }
}

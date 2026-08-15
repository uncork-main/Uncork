import SwiftUI
import AppKit

@main
struct UncorkApp: App {
    @StateObject private var appState = AppState()

    init() {
        CLI.capture(CommandLine.arguments)
        if CLI.isCLIMode {
            // 命令行模式：不显示窗口，跑完退出
            NSApplication.shared.setActivationPolicy(.accessory)
            Task { @MainActor in
                let code = await CLI.run()
                exit(code)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if CLI.isCLIMode {
                EmptyView()
            } else {
                ContentView()
                    .environmentObject(appState)
                    .background(AppActivator())
            }
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            // 禁掉「新建窗口」，避免多窗口状态混乱
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

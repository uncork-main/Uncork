import SwiftUI
import AppKit

/// 窗口激活兜底：命令行/无 bundle 启动时窗口可能躲在终端后面。
/// 注意：必须在 onAppear 里做（App.init 阶段 NSApp 尚不可用），
/// 且要使用 NSApplication.shared 而不是全局 NSApp。
struct AppActivator: View {
    @State private var didActivate = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard !didActivate else { return }
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
                didActivate = true
            }
    }
}

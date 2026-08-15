import SwiftUI

/// 首次启动欢迎页：引导下载 Wine 引擎，展示进度与错误重试
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "wineglass")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("欢迎使用开瓶器")
                    .font(.largeTitle.bold())
                Text("开瓶器 Uncork 借助 Wine 引擎在你的 Mac 上运行 Windows 程序。\n首次使用需要下载约 190 MB 的 Wine 引擎（仅此一次）。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            engineSection
                .frame(minWidth: 360, maxWidth: 420)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var engineSection: some View {
        switch appState.engine.state {
        case .notInstalled:
            Button {
                Task { await appState.engine.install() }
            } label: {
                Label("下载并安装引擎", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .downloading(let progress):
            VStack(spacing: 10) {
                if progress >= 0 {
                    ProgressView(value: progress)
                    Text("下载中 \(Int(progress * 100))%（约 190 MB，请保持网络畅通）")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("下载中…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("取消") { appState.engine.cancelInstall() }
                    .font(.callout)
            }

        case .extracting:
            VStack(spacing: 10) {
                ProgressView()
                Text("正在解压引擎（可能需要几分钟）…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .verifying:
            VStack(spacing: 10) {
                ProgressView()
                Text("正在校验引擎…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .ready(let version):
            VStack(spacing: 14) {
                Label("引擎已就绪（\(version)）", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("开始使用") {
                    appState.route = .main
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .error(let message, let retryable):
            VStack(spacing: 14) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                if retryable {
                    Button("重试") {
                        Task { await appState.engine.install() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

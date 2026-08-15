import SwiftUI

/// 新建瓶弹窗：名称 + Windows 版本。
/// 创建过程包含 wineboot（首次可能 1-3 分钟），期间显示进度并禁用按钮。
struct CreateBottleView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var version: WindowsVersion = .win10
    @State private var creating = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建瓶")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("名称")
                    .font(.callout)
                TextField("例如：办公、游戏、测试", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Windows 版本", selection: $version) {
                ForEach(WindowsVersion.allCases) { v in
                    Text(v.displayName).tag(v)
                }
            }

            if creating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在初始化瓶（首次需要 1-3 分钟）…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .disabled(creating)
                Button(creating ? "创建中…" : "创建") {
                    create()
                }
                .buttonStyle(.borderedProminent)
                .disabled(creating || trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        creating = true
        errorText = nil
        Task {
            do {
                _ = try await appState.store.create(
                    name: trimmedName,
                    version: version,
                    wine: appState.wine
                )
                dismiss()
            } catch {
                errorText = "创建失败：\(error.localizedDescription)"
                LogSink.shared.append("创建瓶失败：\(error.localizedDescription)")
                creating = false
            }
        }
    }
}

import SwiftUI

/// 关于页：LGPL 合规声明（随包附许可证全文 + 指向官方源码的链接）
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wineglass.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("开瓶器 Uncork")
                .font(.title2.bold())
            Text("版本 0.1.0")
                .foregroundStyle(.secondary)

            Text("开瓶器基于 Wine 兼容层在 macOS 上运行 Windows 程序。Wine 引擎为 Whisky 维护的构建（基于 CrossOver 开源源码，LGPL 2.1+），3D 游戏渲染使用 DXMT（MIT 许可，DirectX → Metal）。本应用仅负责下载与调用，未做任何修改。许可证文本随应用附于 Resources/LICENSE-LGPL.txt。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack(spacing: 8) {
                Link("项目主页（GitHub）",
                     destination: URL(string: "https://github.com/Uncork-main/Uncork")!)
                Link("Wine 引擎与 DXMT（Whisky 发布页）",
                     destination: URL(string: "https://github.com/frankea/Whisky/releases")!)
                Link("CrossOver 开源源码（CodeWeavers）",
                     destination: URL(string: "https://www.codeweavers.com/crossover/source")!)
                Link("LGPL 2.1 许可证全文",
                     destination: URL(string: "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html")!)
            }
            .font(.callout)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

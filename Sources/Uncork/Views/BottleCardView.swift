import SwiftUI

/// 单瓶卡片
struct BottleCardView: View {
    let bottle: Bottle

    private var prefixExists: Bool {
        FileManager.default.fileExists(atPath: bottle.prefixURL.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                Spacer()
                if !prefixExists {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("瓶目录不存在")
                }
            }
            Text(bottle.name)
                .font(.headline)
                .lineLimit(1)
            Text(bottle.windowsVersion.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("双击打开")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.4))
        )
    }
}

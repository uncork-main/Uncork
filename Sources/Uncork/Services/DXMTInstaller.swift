import Foundation

/// DXMT（DirectX → Metal 直译）安装器。
/// DXMT 是 Whisky 项目维护的 d3d11 → Metal 翻译层（winemetal.dll + d3d11/dxgi），
/// 在新款 Apple GPU 上跑 UE4/Unity 等 3D 游戏是目前最可靠的方案：
/// 老引擎的 DXVK + MoltenVK 组合渲染不出 3D 场景（只见 UI/文字）。
/// 组件随引擎安装包位于 Engine/DXMT/。
@MainActor
final class DXMTInstaller {
    /// 瓶内是否已安装（winemetal.dll 存在于 system32）
    static func isInstalled(in bottle: Bottle) -> Bool {
        FileManager.default.fileExists(
            atPath: bottle.prefixURL
                .appendingPathComponent("drive_c/windows/system32/winemetal.dll").path
        )
    }

    static func install(in bottle: Bottle) async throws {
        let fm = FileManager.default
        let sourceDir = Paths.engineRoot.appendingPathComponent("DXMT", isDirectory: true)
        guard fm.fileExists(atPath: sourceDir.path) else {
            throw EngineError.invalidArchive("引擎包中缺少 DXMT 组件（Engine/DXMT），请重新安装引擎")
        }

        let system32 = bottle.prefixURL.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = bottle.prefixURL.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)
        try fm.createDirectory(at: syswow64, withIntermediateDirectories: true)

        // x64 → system32，x32 → syswow64
        for (arch, target) in [("x64", system32), ("x32", syswow64)] {
            let src = sourceDir.appendingPathComponent(arch, isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                try? fm.removeItem(at: target.appendingPathComponent(file.lastPathComponent))
                try fm.copyItem(at: file, to: target.appendingPathComponent(file.lastPathComponent))
            }
        }

        // winemetal.dll 是 Mach-O，Apple Silicon 上必须签名才能加载
        for dir in [system32, syswow64] {
            let winemetal = dir.appendingPathComponent("winemetal.dll")
            if fm.fileExists(atPath: winemetal.path) {
                _ = try? await ProcessRunner.run(
                    URL(fileURLWithPath: "/usr/bin/codesign"),
                    args: ["--force", "-s", "-", winemetal.path],
                    timeout: 60
                )
            }
        }

        LogSink.shared.append("已安装 DXMT（Metal 渲染）到瓶「\(bottle.name)」")
    }
}

import Foundation

/// 瓶列表持久化层（bottles.json，.atomic 写入）
@MainActor
final class BottleStore: ObservableObject {
    @Published private(set) var bottles: [Bottle] = []
    private(set) var engineVersion: String?

    /// 启动时加载；文件损坏则备份后重建空列表
    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Paths.bottlesJSON.path) else { return }
        do {
            let data = try Data(contentsOf: Paths.bottlesJSON)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(BottlesFile.self, from: data)
            bottles = file.bottles
            engineVersion = file.engineVersion
        } catch {
            LogSink.shared.append("瓶列表文件损坏，已备份并重建：\(error.localizedDescription)")
            try? fm.moveItem(
                at: Paths.bottlesJSON,
                to: Paths.supportDir.appendingPathComponent("bottles.json.bak")
            )
            bottles = []
            engineVersion = nil
        }
    }

    func updateEngineVersion(_ version: String) throws {
        engineVersion = version
        try persist()
    }

    /// 创建瓶：建目录 → wineboot 初始化前缀 → 设置 Windows 版本 → 落盘。
    /// 失败时清理已建目录。
    func create(name: String, version: WindowsVersion, wine: WineRunner) async throws -> Bottle {
        let bottle = Bottle(id: UUID(), name: name, windowsVersion: version, createdAt: Date())
        let fm = FileManager.default
        try fm.createDirectory(at: bottle.prefixURL, withIntermediateDirectories: true)
        do {
            try await wine.createPrefix(for: bottle)
            try await wine.setWindowsVersion(version, in: bottle)
        } catch {
            try? fm.removeItem(at: bottle.prefixURL)
            throw error
        }
        bottles.append(bottle)
        try persist()
        return bottle
    }

    func rename(_ bottle: Bottle, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = bottles.firstIndex(where: { $0.id == bottle.id }) else {
            return
        }
        bottles[index].name = trimmed
        try persist()
    }

    /// 删除瓶：先杀进程，再删目录，最后落盘
    func delete(_ bottle: Bottle, wine: WineRunner) async throws {
        try? await wine.killBottleProcesses(in: bottle)
        try? FileManager.default.removeItem(at: bottle.prefixURL)
        bottles.removeAll { $0.id == bottle.id }
        try persist()
    }

    func bottle(withID id: UUID) -> Bottle? {
        bottles.first { $0.id == id }
    }

    /// 添加手动程序（去重：同路径只加一次）
    func addProgram(name: String, path: String, to bottle: Bottle) throws {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        guard !bottles[index].userPrograms.contains(where: { $0.path == path }) else { return }
        bottles[index].userPrograms.append(
            UserProgram(id: UUID(), name: name, path: path, createdAt: Date())
        )
        try persist()
    }

    func removeProgram(_ program: UserProgram, from bottle: Bottle) throws {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].userPrograms.removeAll { $0.id == program.id }
        try persist()
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(BottlesFile(bottles: bottles, engineVersion: engineVersion))
        try data.write(to: Paths.bottlesJSON, options: .atomic)
    }
}

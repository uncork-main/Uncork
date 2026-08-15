import Foundation

/// Windows 版本（写入瓶注册表 HKCU\Software\Wine\Version）
enum WindowsVersion: String, Codable, CaseIterable, Identifiable {
    case win10
    case win11

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .win10: return "Windows 10"
        case .win11: return "Windows 11"
        }
    }

    var registryValue: String { rawValue }
}

/// 用户手动添加到瓶的程序（如绿色版游戏，exe 在磁盘任意位置）
struct UserProgram: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var path: String
    let createdAt: Date
}

/// 一个瓶（Wine prefix）
struct Bottle: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let windowsVersion: WindowsVersion
    let createdAt: Date
    /// 用户手动添加的程序（不在瓶内，直接从磁盘路径运行）
    var userPrograms: [UserProgram]

    /// 磁盘目录：SupportDir/Bottles/<uuid>。
    /// 与显示名解耦（纯 ASCII），避免个别 Windows 程序在中文路径下崩溃。
    var prefixURL: URL {
        Paths.bottlesDir.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    var driveCURL: URL {
        prefixURL.appendingPathComponent("drive_c", isDirectory: true)
    }

    init(id: UUID, name: String, windowsVersion: WindowsVersion, createdAt: Date, userPrograms: [UserProgram] = []) {
        self.id = id
        self.name = name
        self.windowsVersion = windowsVersion
        self.createdAt = createdAt
        self.userPrograms = userPrograms
    }

    // 手写 Codable：userPrograms 是后加字段，旧 bottles.json 里没有，缺省 []
    enum CodingKeys: String, CodingKey {
        case id, name, windowsVersion, createdAt, userPrograms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        windowsVersion = try c.decode(WindowsVersion.self, forKey: .windowsVersion)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        userPrograms = try c.decodeIfPresent([UserProgram].self, forKey: .userPrograms) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(windowsVersion, forKey: .windowsVersion)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(userPrograms, forKey: .userPrograms)
    }
}

/// bottles.json 的顶层结构（version 为将来 schema 迁移留口）
struct BottlesFile: Codable {
    var version: Int = 1
    var bottles: [Bottle] = []
    /// 瓶创建/升级时使用的引擎版本，变更时自动 wineboot -u 升级前缀
    var engineVersion: String?
}

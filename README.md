# 开瓶器 Uncork

类 CrossOver 的 macOS 应用：通过 Wine 兼容层在 Mac 上运行 Windows 程序。SwiftUI 原生界面（中文），Wine 引擎在首次启动时自动下载（约 190 MB）。

## 功能

> 以下内容由 AI 生成，请注意辨别，本人不负任何责任。

- **多瓶管理**：创建（Windows 10 / 11）、重命名、删除；每个瓶是独立的 Windows 环境
- **安装软件**：选择 .exe 安装器直接运行
- **程序列表**：自动扫描瓶内开始菜单/桌面/Program Files，一键运行已装程序
- **游戏支持**：一键安装 DXMT（DirectX 11 → Metal 直译），UE4/Unity 等 3D 游戏可玩；自动启用 msync/esync 提升性能
- **实用工具**：winecfg 配置、打开 C: 驱动器、强制关闭瓶中进程、运行日志
- **命令行模式**（也可用于自动化/排障）：
  - `Uncork --install-engine` 安装 Wine 引擎
  - `Uncork --smoke-test` 冒烟测试（建临时瓶 → 运行 notepad → 关闭）
  - `Uncork --create-bottle <名称>` 创建瓶
  - `Uncork --list-bottles` 列出所有瓶
  - `Uncork --install-dxmt <瓶名称>` 给指定瓶安装 DXMT（Metal 渲染）

## 构建（无需 Xcode，仅需 Command Line Tools）

```bash
./scripts/build_app.sh     # swift build → dist/Uncork.app（含 ad-hoc 签名）
open dist/Uncork.app       # 验证启动（必须用 open，不要直接跑二进制）
```

开发快循环：`./scripts/run_app.sh`（终端可直接看日志）。

## 打包 .dmg

```bash
./scripts/make_dmg.sh      # 产出 dist/Uncork-0.1.0.dmg
```

首次运行会自动安装 create-dmg（Homebrew）。DMG 内置背景图和 Applications 链接，双击拖入即可安装。

## 自定义图标

把 1024×1024 的 PNG 放到 `Resources/AppIcon-1024.png`，重跑：

```bash
./scripts/gen_icon.sh && ./scripts/build_app.sh
```

（未提供时自动生成占位图标。换图标后必须重跑 build_app.sh 重新签名。）

## 分发说明

- **U 盘 / 局域网拷贝**：无 quarantine 属性，双击即可打开
- **网盘 / 网页下载**：macOS 会给未公证应用加 quarantine 标记，首次打开请
  **右键 → 打开**，或执行 `xattr -dr com.apple.quarantine /Applications/Uncork.app`
- 正式对外分发（免右键）需要 Apple 开发者账号做签名 + 公证，超出本项目范围

## 运行 3D 游戏（UE4/Unity 等）

wine 自带的 D3D11 转换层在 macOS 上不支持这些游戏需要的特性级别，装 DXMT（DirectX → Metal 直译）即可：

1. 创建瓶 → 打开瓶详情 → 「更多 → 安装 DXMT（游戏 3D 渲染）」
2. 「添加程序…」选择游戏的 .exe（绿色版游戏），或「安装软件…」跑安装器

DXMT 来源：Whisky Libraries（MIT），随引擎安装包下载。
已知可玩：InnocentAssault（UE4，实测运行正常）。

### 关于其他电脑

- **Apple Silicon（M 系列）Mac**：直接可用。首次启动自动下载 457MB 引擎，装 DXMT 后即可跑 3D 游戏
- **Intel Mac**：需要本机有完整 Xcode 时 `build_app.sh` 会产通用二进制；纯 CLT 环境只出 arm64 版
- 分发：U 盘/局域网拷贝双击即开；网盘下载首次需右键→打开（未公证应用的预期行为）

## 架构速览

```
Sources/Uncork/
├── UncorkApp.swift        @main 入口（GUI / CLI 双模式）
├── AppState.swift         路由与装配中枢
├── CLI.swift              命令行模式
├── Models/                Bottle（瓶模型）、Shortcut（程序条目）
├── Services/
│   ├── EngineManager      引擎下载→解压→签名→校验 状态机
│   ├── EngineDownloader   URLSession 流式下载 + 重试
│   ├── ProcessRunner      通用 Process 封装（防死锁）
│   ├── WineRunner         所有 wine/wineserver 命令
│   ├── BottleStore        瓶列表持久化（bottles.json）
│   └── ExeScanner         扫描瓶内已装程序
├── Views/                 中文 SwiftUI 界面
└── Utilities/             路径常量、日志
```

数据目录：`~/Library/Application Support/Uncork/`（Engine / Bottles / Downloads / logs / bottles.json）

## 许可

- 本项目代码：MIT
- Wine 引擎（Wine-CrossOver）：**LGPL 2.1+**，全文见 `Resources/LICENSE-LGPL.txt`；
  引擎源码由 CodeWeavers 随 CrossOver 发布：https://www.codeweavers.com/crossover/source
- 引擎下载源：https://github.com/frankea/Whisky/releases（Libraries.tar.gz，
  457MB：wine 11.15 + DXMT + DXVK；x86_64 构建，Apple Silicon 上经 Rosetta 2 运行）

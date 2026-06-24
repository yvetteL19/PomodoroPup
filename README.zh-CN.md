# 🍅🐶 PomodoroPup（番茄小狗）

> 一款常驻 macOS 菜单栏的番茄钟应用，搭配一只会随你专注而解锁装扮奖励的游戏化小狗。

![平台](https://img.shields.io/badge/平台-macOS%2015.5%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![界面](https://img.shields.io/badge/界面-SwiftUI-green)
![架构](https://img.shields.io/badge/架构-MVVM-lightgrey)

PomodoroPup 安静地待在你的菜单栏里。开始专注，一只小狗就会陪你一起工作；进入休息，它便端起咖啡惬意放松。完成足够多的番茄钟，你就能解锁成就——骨头、眼镜、皇冠——把"专注"这件枯燥的事，变成一个个有奖励的小仪式。

**[English README →](README.md)**

---

## ⬇️ 下载安装

预编译版本发布在 [**Releases**](https://github.com/yvetteL19/PomodoroPup/releases) 页面。由于没有苹果开发者账号签名，首次打开 App 时可能会提示"无法验证开发者"或"文件已损坏"。

**解决方法：**
1. 下载并解压后，**不要**直接双击打开。
2. 对着 App 图标**点击鼠标右键**，选择 **"打开"**。
3. 在弹出的警告框中点击 **"打开"** 即可正常运行。

（或前往 **系统设置 → 隐私与安全性 → 仍要打开**。）

想自行编译？参见下方 [构建与运行](#-构建与运行)。

---

## 📸 应用截图

| 准备专注 | 专注中 | 休息中 |
| :---: | :---: | :---: |
| ![准备](docs/screenshots/02_ready.png) | ![专注](docs/screenshots/01_main.png) | ![休息](docs/screenshots/05_break.png) |

| 成就墙 | 设置 |
| :---: | :---: |
| ![成就墙](docs/screenshots/04_achievements.png) | ![设置](docs/screenshots/03_settings.png) |

---

## ✨ 功能特性

- **常驻菜单栏**——状态图标 + 实时倒计时，抬眼即见，不占用桌面空间。
- **会动的小狗伙伴**——专注时小狗带有细微的呼吸动画；休息时切换为悠闲喝咖啡的小狗（动态 GIF）。
- **周期化番茄流程**——工作与休息自动衔接，达到当日目标后自动停止。开启一次，剩下的交给它。
- **成就系统**——六个可解锁成就，覆盖里程碑、坚持、深度专注与充分休息。每次解锁都会触发菜单栏闪烁、奖杯抖动与音效。
- **进度一目了然**——周期小圆点显示今日已完成的轮数；成就墙展示距离下一个里程碑的进度。
- **原生通知**——该休息、该继续、达成每日目标时，给你温柔的横幅提醒。
- **高度可配置**——专注/休息时长、每日周期目标，以及音效、动画、通知的开关。
- **双语支持**——简体中文与英文，随系统语言自动切换。
- **新手引导**——三步欢迎流程，帮你设定每日目标并申请通知权限。
- **本地存储 · 隐私无忧**——所有统计与设置均保存在本地 `UserDefaults`，数据不出本机，应用以沙盒方式运行。

---

## 🔄 工作原理

```
 停止 (25:00)
     │  开始专注
     ▼
 专注 ──完成──► 休息 ──完成──► 专注 ──► …
     ▲                                  │
     └──────── 达成周期目标 ──► 停止 ◄────┘
```

- 每**完成**一个专注番茄，会累加：总数、今日数、连续未中断的专注计数，以及周期计数。
- 一个番茄结束后自动进入**休息**；休息结束后自动回到工作——如此循环，直到达成**每日周期目标**（默认 4 轮），随后停止并向你道贺。
- **跳过**一个番茄仍会推进周期，但会重置连续专注计数（"深度黑客"成就依赖于此）。
- 休息时长会单独累计，用于"舞蹈之王"成就。

---

## 🏆 成就一览

| 图标 | 名称 | 解锁条件 |
| :---: | :--- | :--- |
| 🦴 | **萌新小狗** | 累计完成 10 个番茄 |
| 👓 | **高效搭档** | 累计完成 50 个番茄 |
| 👑 | **专注大师** | 累计完成 200 个番茄 |
| 🐾 | **连续出勤** | 连续 3 天，每天至少 4 个番茄 |
| 💡 | **深度黑客** | 连续 3 个番茄未跳过 |
| ✨ | **舞蹈之王** | 累计休息时间达 300 分钟 |

解锁成就时会播放音效，菜单栏标签闪烁三次，并抖动奖杯按钮。

---

## 🛠 构建与运行

**环境要求：** macOS 15.5+，Xcode 16+。

```bash
git clone https://github.com/yvetteL19/PomodoroPup.git
cd PomodoroPup
open PomodoroPup.xcodeproj
```

随后在 Xcode 中构建并运行（**⌘R**）。应用会出现在菜单栏，点击图标即可打开弹窗。

命令行构建：

```bash
xcodebuild -project PomodoroPup.xcodeproj -scheme PomodoroPup \
  -configuration Debug -destination 'platform=macOS' build
```

---

## 🧱 架构设计

应用采用 **MVVM** 架构，使用 SwiftUI 的 `MenuBarExtra` 进行展示。

| 文件 | 职责 |
| :--- | :--- |
| `PomodoroPupApp.swift` | 应用入口；配置 `MenuBarExtra`、实时菜单栏标签（含成就闪烁）与新手引导窗口。 |
| `DogViewModel.swift` | 核心逻辑：基于 Combine 的计时器、状态机、周期/成就追踪、`UserDefaults` 持久化、音效与通知。 |
| `ContentView.swift` | 主弹窗界面——小狗、倒计时、周期圆点、控制按钮——以及成就墙与设置弹窗。 |
| `DogView.swift` | 会动的小狗：专注呼吸姿态，以及 GIF/静态休息姿态（通过 `NSViewRepresentable` 实现 GIF 播放）。 |
| `SettingsView.swift` | 时间设置、陪伴模式开关与统计信息。 |
| `OnboardingView.swift` | 首次启动的三页欢迎流程。 |
| `SoundManager.swift` | 基于 AVFoundation / 系统音效的播放。 |

**技术栈：** SwiftUI · Combine · AppKit（GIF 渲染与音效）· UserNotifications · AVFoundation。

---

## 🌐 本地化

界面文案位于 `en.lproj/Localizable.strings` 与 `zh-Hans.lproj/Localizable.strings`，通过 `NSLocalizedString` 解析，应用会随系统语言自动切换。

---

## 🔒 隐私说明

PomodoroPup 完全离线、沙盒运行。所有计数、连续天数与设置均通过 `UserDefaults` 保存在本地。没有任何统计上报、账号体系或网络访问。

---

## 📁 项目结构

```
PomodoroPup/
├── PomodoroPup.xcodeproj/        # Xcode 工程
├── PomodoroPup/                  # 源代码
│   ├── PomodoroPupApp.swift
│   ├── DogViewModel.swift
│   ├── ContentView.swift
│   ├── DogView.swift
│   ├── SettingsView.swift
│   ├── OnboardingView.swift
│   ├── SoundManager.swift
│   ├── Assets.xcassets/          # 小狗插画、成就图标
│   ├── en.lproj / zh-Hans.lproj  # 本地化资源
│   └── *.MP3                     # 音效文件
├── docs/screenshots/            # README 截图
└── README.md
```

---

<p align="center">用 🍅 与 🐶 打造——专注一点点，奖励一点点。</p>

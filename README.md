# OpenMinis-AutoPilot 🚀

> **Codex-style Full-Auto mode for OpenMinis** — let your on-device AI agent work autonomously until the task is done.
>
> 🌏 简体中文 · English · 繁體中文 — 见下 / below / 見下

---

## 简体中文

**OpenMinis-AutoPilot** 是基于开源项目 [OpenMinis](https://github.com/OpenMinis/OpenMinis)（The AI Agent app across platforms）的增强版本，新增 **全自动模式（Full-Auto）**：像 OpenAI Codex 一样，让 AI 智能体**连续自主工作**——读代码、改代码、跑命令、看报错、自我修复——**直到任务完成，无需人类逐步干预**。

### ✨ 全自动模式是什么

开启输入栏的「⚡ 全自动」开关后：

- AI 每完成一轮工作，**自动检查目标完成度**并继续推进
- 遇到错误**自行排查修复**，不打断你
- 任务完成、或确实需要你决策（如缺少只有你持有的密钥）时**自动停下并汇报**
- 安全护栏：**20 轮预算** · 循环检测 · **随时手动停止**

### 📦 安装

本仓库的 [Releases](https://github.com/yoyo520956/OpenMinis-AutoPilot/releases) 提供**未签名 IPA**，使用你自己的签名工具（AltStore / SideStore / Sideloadly 等）重签安装即可。

> 本构建使用独立包名（`com.youlong.minisautopilot`），**可与官方版 Minis 共存安装、同时使用**。

### 🔨 构建

见 [BUILDING.md](BUILDING.md)（首次构建需要从源码编译 iSH 内核 / FFmpeg / LAME / rclone，约 30-60 分钟）。本仓库内置 GitHub Actions 自动构建：`.github/workflows/build-ios.yml`。

### ⚖️ 许可

GPL-3.0（与上游一致）。本项目是 OpenMinis 的衍生作品，感谢 [OpenMinis 团队](https://github.com/OpenMinis/OpenMinis)的开源工作。

---

## English

**OpenMinis-AutoPilot** is an enhanced build of the open-source project [OpenMinis](https://github.com/OpenMinis/OpenMinis) — *The AI Agent app across platforms* — adding a **Codex-style Full-Auto mode**: the on-device AI agent keeps working **autonomously** — reading code, editing files, running commands, inspecting errors, fixing itself — **until the task is done, with no step-by-step human intervention**.

### ✨ What is Full-Auto mode

Flip the "⚡ Full-Auto" toggle in the composer, and:

- After each round, the agent **checks goal progress** and continues automatically
- Failures are **self-diagnosed and repaired** without interrupting you
- Stops and reports when the task is **done** — or when it is genuinely **blocked** (e.g. credentials only you hold)
- Guardrails: **20-round budget** · loop detection · **instant manual stop**

### 📦 Install

Grab the **unsigned IPA** from [Releases](https://github.com/yoyo520956/OpenMinis-AutoPilot/releases) and re-sign it with your own tooling (AltStore / SideStore / Sideloadly, etc.).

> This build uses an independent bundle id (`com.youlong.minisautopilot`) — it **can be installed and used alongside the official Minis**.

### 🔨 Build

See [BUILDING.md](BUILDING.md) (the first build compiles iSH kernel / FFmpeg / LAME / rclone from source, ~30-60 min). CI is built in: `.github/workflows/build-ios.yml`.

### ⚖️ License

GPL-3.0 (same as upstream). This project is a derivative work of OpenMinis — all credit to the [OpenMinis team](https://github.com/OpenMinis/OpenMinis).

---

## 繁體中文

**OpenMinis-AutoPilot** 是開源專案 [OpenMinis](https://github.com/OpenMinis/OpenMinis)（The AI Agent app across platforms）的增強版本，新增 **全自動模式（Full-Auto）**：像 OpenAI Codex 一樣，讓 AI 代理**連續自主工作**——讀程式碼、修改檔案、執行指令、檢視錯誤、自我修復——**直到任務完成，無需人類逐步介入**。

### ✨ 全自動模式是什麼

開啟輸入欄的「⚡ 全自動」開關後：

- AI 每完成一輪工作，**自動檢查目標完成度**並繼續推進
- 遇到錯誤**自行排查修復**，不打斷你
- 任務完成、或確實需要你決策（如缺少只有你持有的金鑰）時**自動停下並回報**
- 安全護欄：**20 輪預算** · 迴圈偵測 · **隨時手動停止**

### 📦 安裝

本倉庫的 [Releases](https://github.com/yoyo520956/OpenMinis-AutoPilot/releases) 提供**未簽名 IPA**，使用你自己的簽名工具（AltStore / SideStore / Sideloadly 等）重簽安裝即可。

> 本建置使用獨立套件名（`com.youlong.minisautopilot`），**可與官方版 Minis 共存安裝、同時使用**。

### 🔨 建置

見 [BUILDING.md](BUILDING.md)（首次建置需從原始碼編譯 iSH 核心 / FFmpeg / LAME / rclone，約 30-60 分鐘）。本倉庫內建 GitHub Actions 自動建置：`.github/workflows/build-ios.yml`。

### ⚖️ 授權

GPL-3.0（與上游一致）。本專案是 OpenMinis 的衍生作品，感謝 [OpenMinis 團隊](https://github.com/OpenMinis/OpenMinis)的開源工作。

---

### 📖 Upstream README (OpenMinis)

This repository is a derivative of the open-source project **OpenMinis**. The full upstream README is preserved below.

<details>
<summary>📖 <b>OpenMinis — upstream README (click to expand)</b></summary>

# OpenMinis

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20Android-lightgrey.svg)](#beta-programme)

**Your private, on-device AI agent.**

OpenMinis brings leading models — Claude, GPT, Gemini and more — into a native
mobile experience, and gives them a real computer to work with: a full Linux
shell running on your device, browser automation, extensible skills, persistent
memory, and deep system integration.

It is free, and fully open source.

**We believe that in the age of AI, technical design and code are no longer
where a product's advantage lies. The best agent emerges from a tight feedback
loop with the people who use it — their expectations and their reports are
what converge on the product.**

Official website: **[openminis.app](https://openminis.app)**

<a href="https://apps.apple.com/app/id6759188481">
  <img alt="Download on the App Store" height="48" src="assets/badge-appstore.svg" />
</a>
&nbsp;
<a href="https://github.com/OpenMinis/OpenMinis/releases">
  <img alt="Get the APK on GitHub" height="48" src="assets/badge-android.svg" />
</a>

![Minis on iOS — deep research, chat, agent runtime, integrations, iCloud sync and granular permissions](assets/screenshots.png)

---

## What it does

| | |
|---|---|
| **Bring your own model** | Claude, GPT, Gemini and other providers, via your own API keys or account sign-in. |
| **A real Linux shell** | A sandboxed Alpine Linux environment runs on-device — the agent can install packages, run scripts, and work with real files. |
| **Device integration** | Health, Calendar, Reminders, Contacts, HomeKit, Bluetooth, Clipboard, Media, Alarms and more, exposed to the agent as tools. |
| **Browser automation** | The agent can browse and interact with the web on your behalf. |
| **Skills & memory** | Extensible skills plus persistent memory across sessions. |
| **Workspaces** | Organise work into separate contexts, addressable via `minis://workspace/`. |
| **Native offloads** | Heavy or platform-specific work is handed to native code instead of the sandbox. |

---

## What you can do with Minis

A few things people actually use it for:

- **Photograph a meal, log the nutrition** — Minis identifies the dishes, estimates
  calories and macros, and writes them to Apple Health.
- **Wake up to your timeline** — Shortcuts triggers Minis to fetch your X timeline,
  summarise it, synthesise speech, and play it as your alarm.
- **Turn group chatter into tasks** — pull messages from a Telegram group, extract
  bugs and action items, deduplicate them, and file them into Apple Reminders.
- **Mount your Obsidian vault** — research, clean up and write Markdown notes back
  into the vault as a normal workspace.
- **Share anything into a calendar event** — send a page or message to Minis via the
  iOS Share Sheet and it creates the event, time and place included.

**→ [OpenMinis/AwesomeMinis](https://github.com/OpenMinis/AwesomeMinis)** — a curated,
community-contributed collection of use cases and workflows across health,
productivity, research, finance and developer tooling.

---

## Skills

A **skill** is a folder with a `SKILL.md` file — instructions, and optionally scripts,
references and assets — that the agent loads on demand when a request matches it.
Metadata stays in context for triggering; the body and bundled resources load only
when the skill is actually used.

Minis has its own tool system, but it does not require skills written specifically
for it: **skills built for Claude, Codex, OpenClaw or Hermes Agent generally run in
Minis as-is.** Skills that have been adapted to Minis' tools simply run better —
they can reach the Linux shell, device integrations and native offloads directly.

**→ [OpenMinis/MinisSkills](https://github.com/OpenMinis/MinisSkills)** — skills
adapted for Minis alongside ones built for it from scratch, covering TTS, search,
media downloads, health analysis, cloud APIs and more.

---

## Press

> "the most impressive indie app I've seen in a while"
>
> — Federico Viticci, [**Open Minis Is the iOS Agent I Wish Siri AI Could Be**](https://www.macstories.net/reviews/open-minis-is-the-ios-agent-i-wish-siri-ai-could-be/),
> MacStories (July 2026)

> "在很大程度上实现甚至局部超越了 Apple Intelligence"
>
> — Ye Han, [**这可能是 iPhone 最强 Agent 软件，没有之一 丨Open Minis 入门指南**](https://zhuanlan.zhihu.com/p/2045570157783807562),
> 知乎 / Zhihu (June 2026)

> "可能是 iOS 端最强 AI Agent"
>
> — [**Open Minis：可能是 iOS 端最强 AI Agent**](https://www.appinn.com/open-minis/),
> 小众软件 / Appinn (March 2026)

---

## Beta programme

App Store releases can lag behind: every update waits on review, and we hold
builds back when stability warrants it. The TestFlight build is where fixes
and new features land first.

**→ [Join the TestFlight beta](https://testflight.apple.com/join/3BdkA5c3)**

On Android, the [releases page](https://github.com/OpenMinis/OpenMinis/releases)
always carries the latest APK.

---

## Building from source

Minis ships a Linux sandbox inside the app, so the native dependencies (iSH on
iOS, PRoot on Android, FFmpeg, LAME, rclone) and the Alpine rootfs are **built
from source** rather than committed as binaries.

**→ See [BUILDING.md](BUILDING.md) for the full first-build guide.**

The short version:

```sh
git clone --recurse-submodules https://github.com/OpenMinis/OpenMinis.git
cd OpenMinis

# iOS  — needs Go 1.25+ and Xcode's Metal Toolchain
#        (xcodebuild -downloadComponent MetalToolchain)
#        order matters: FFmpeg links against LAME
./deps/build_lame.sh && ./deps/build_ffmpeg.sh
./deps/build_ish.sh && ./deps/prepare_alpine_rootfs.sh
./deps/build_rclone_ios.sh
open src/ios/Minis.xcodeproj

# Android — needs NDK r28+, Go 1.25+ and gomobile
./deps/build_proot.sh && ./scripts/prepare_android_sandbox.sh
./deps/build_rclone_android.sh
mkdir -p src/android/app/libs && cp deps/build/rclone/rclone.aar src/android/app/libs/
cd src/android && ./gradlew :app:assembleDebug
```

`BUILDING.md` covers the toolchain requirements per platform, the build-time
customization templates, and a troubleshooting section for the failure modes
you are most likely to hit.

---

## Repository layout

```
src/ios/          iOS app (Swift / SwiftUI) + share, widget and file-provider extensions
src/android/      Android app (Kotlin / Compose) + JNI native code
src/shared/       Assets shared by both platforms
deps/             Native dependency build scripts and vendored sources
docs/specs/       Architecture and interface specifications
scripts/          Rootfs preparation and developer tooling
```

---

## Acknowledgements

OpenMinis stands on a great deal of open-source work. Our thanks to the
maintainers of these projects — the full inventory, with versions and license
terms, is in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

**The sandbox** — the heart of the product:

- **[iSH](https://github.com/ish-app/ish)** (GPLv3) — Linux usermode emulation on
  iOS. We run [an ARM64 fork](https://github.com/OpenMinis/ish-arm64).
- **[PRoot](https://github.com/termux/proot)** (GPLv2) — user-space chroot for the
  Android sandbox, via [our fork](https://github.com/OpenMinis/proot);
  **[talloc](https://talloc.samba.org)** (LGPLv3+) underpins it.
- **[Alpine Linux](https://alpinelinux.org)** — the minirootfs the sandbox boots.

**Media & text** — [FFmpeg](https://ffmpeg.org) (LGPL-2.1+),
[LAME](https://lame.sourceforge.io) (LGPL), [cppjieba](https://github.com/yanyiwu/cppjieba) (MIT),
[KaTeX](https://katex.org) (MIT).

**iOS** — [SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic),
[SwiftMath](https://github.com/mgriebling/SwiftMath),
[RealTimeCutVADLibrary](https://github.com/helloooideeeeea/RealTimeCutVADLibrary) (all MIT),
[swift-cmark](https://github.com/swiftlang/swift-cmark) (BSD-2-Clause), and the
Apple / Swift Server Workgroup packages (Apache-2.0).

**Android** — [AndroidX & Jetpack Compose](https://developer.android.com/jetpack),
[OkHttp](https://square.github.io/okhttp/), [Coil](https://coil-kt.github.io/coil/),
[kotlinx](https://github.com/Kotlin) serialization & coroutines,
[multiplatform-markdown-renderer](https://github.com/mikepenz/multiplatform-markdown-renderer),
[Reorderable](https://github.com/Calvin-LL/Reorderable), [ACRA](https://github.com/ACRA/acra)
(all Apache-2.0), and [Shizuku](https://github.com/RikkaApps/Shizuku-API) (MIT).

---

## License

OpenMinis is licensed under the **[GNU General Public License v3.0](LICENSE)**.

The app links GPL-licensed components — [iSH](https://github.com/OpenMinis/ish-arm64)
(GPLv3) and [PRoot](https://github.com/OpenMinis/proot) (GPLv2) — so the combined
work is distributed under GPLv3. Bundled third-party licenses are listed in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

---

## Community

- **Telegram**: [Join the group](https://t.me/+2NzhOJuzRyI1YmM1)
- **Issues**: Bug reports, feature requests and discussion via
  [GitHub Issues](https://github.com/OpenMinis/OpenMinis/issues)

This repository is a mirror of a private development tree, so it **does not
accept pull requests** — there is nowhere for them to land. Issues are the way
to shape the product, and [AwesomeMinis](https://github.com/OpenMinis/AwesomeMinis)
and [MinisSkills](https://github.com/OpenMinis/MinisSkills) both do take
contributions. See [CONTRIBUTING.md](CONTRIBUTING.md).

</details>

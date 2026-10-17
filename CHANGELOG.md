# 更新公告 · Changelog · 更新公告

All notable changes to **OpenMinis-AutoPilot** are documented here — in three languages (简体中文 / English / 繁體中文).

---

## v0.1.3 — 2026-10-17

### 🇨🇳 简体中文

- ⚡ **全自动模式预算增强**：默认轮次 20 → **100 轮**（面向大任务：可覆盖「从零开发一个完整 App」的全流程，不再中途预算耗尽）
- 🎯 **支持自定义轮数**：在消息里说「给 N 轮」即可（钳制 5~500），全自动引擎自动采用
- 🏷️ 显示名简化：**Minis**（主屏名称与官方版同名；包名不同 `com.youlong.minisautopilot`，两者仍可共存、互不覆盖）

### 🇬🇧 English

- ⚡ **AutoPilot budget boost**: default rounds 20 → **100** (large-task oriented: covers developing a complete app from scratch without hitting the budget mid-way)
- 🎯 **User-specified rounds**: say "give it N rounds" in a message (clamped 5–500) and the engine picks it up automatically
- 🏷️ Display name simplified to **Minis** (same name on the home screen as the official app; bundle id differs — `com.youlong.minisautopilot` — so both can still be installed side by side)

### 🇭🇰 繁體中文

- ⚡ **全自動模式預算增強**：預設輪次 20 → **100 輪**（面向大任務：可覆蓋「從零開發一個完整 App」全流程）
- 🎯 **支援自訂輪數**：在訊息裡說「給 N 輪」即可（鉗制 5~500）
- 🏷️ 顯示名簡化為 **Minis**（主畫面名稱與官方版相同；套件名不同 `com.youlong.minisautopilot`，兩者仍可共存）

---

## v0.1.2 — 2026-10-17

### 🇨🇳 简体中文

- 🛠️ **修复：自签/侧载环境下「打开即闪退」**——启动路径对 App Group 共享目录的强制解包，在签名证书不含该权限时返回 nil 直接崩溃；现改为优雅降级（无权限时自动使用 App 本地目录，功能不受影响）
- 🛡️ 同类隐患 2 处一并修复（数据目录 / 配置目录 fallback）
- 📦 构建管线双产物：完整版（full）+ 精简版（lite，剥离扩展），按需选用
- 🆔 包名独立：`com.youlong.minisautopilot`（显示名 Minis AutoPilot，可与官方版共存）

### 🇬🇧 English

- 🛠️ **Fixed the instant-launch crash on re-signed / sideloaded builds** — the launch path force-unwrapped the App Group container, which returns nil when the signing certificate lacks the entitlement; it now degrades gracefully to an app-local directory with no loss of functionality
- 🛡️ Two more instances of the same class fixed (data / config roots now fall back too)
- 📦 Build pipeline now produces both `full` and `lite` (extension-stripped) IPAs
- 🆔 Standalone bundle id: `com.youlong.minisautopilot` (display name "Minis AutoPilot", coexists with the official app)

### 🇹🇼 繁體中文

- 🛠️ **修復：自簽/側載環境下「開啟即閃退」**——啟動路徑對 App Group 共享目錄的強制解包，在簽名憑證不含該權限時傳回 nil 直接崩潰；現改為優雅降級（無權限時自動使用 App 本地目錄，功能不受影響）
- 🛡️ 同類隱患 2 處一併修復（資料目錄 / 設定目錄 fallback）
- 📦 建置管線雙產物：完整版（full）+ 精簡版（lite，剝離擴充功能）
- 🆔 套件名稱獨立：`com.youlong.minisautopilot`（顯示名 Minis AutoPilot，可與官方版共存）

---

## v0.1.0 — 2026-10-17

### 🇨🇳 简体中文

- ✨ **新增「全自动模式」（Codex 式 Full-Auto）**：Agent 自主连续执行——读代码、改文件、跑命令、查报错、自我修复——直到任务完成，无需人类逐步介入
- ⚡ 输入栏新增「⚡ 全自动」开关：点击开启，角标显示轮次进度
- 🛡️ 安全护栏：20 轮预算 · 任务完成/受阻自动停止 · 随时手动停止
- 🤖 内置续跑标记协议（`▣AUTOPILOT:DONE▣` / `▣AUTOPILOT:BLOCKED▣`），AI 主动汇报完成度
- 🏗️ 内置 GitHub Actions 构建管线：一键产出未签名 IPA

### 🇬🇧 English

- ✨ **New "Full-Auto mode" (Codex-style)**: the agent works autonomously — reading code, editing files, running commands, inspecting errors, fixing itself — until the task is done, with no step-by-step human intervention
- ⚡ New "⚡ Full-Auto" toggle in the composer: tap to arm; the badge shows round progress
- 🛡️ Guardrails: 20-round budget · auto-stop on done/blocked · instant manual stop
- 🤖 Built-in continuation protocol (`▣AUTOPILOT:DONE▣` / `▣AUTOPILOT:BLOCKED▣`) — the AI reports progress on its own
- 🏗️ Built-in GitHub Actions pipeline: one-click unsigned IPA

### 🇹🇼 繁體中文

- ✨ **新增「全自動模式」（Codex 式 Full-Auto）**：Agent 自主連續執行——讀程式碼、修改檔案、執行指令、檢視錯誤、自我修復——直到任務完成，無需人類逐步介入
- ⚡ 輸入欄新增「⚡ 全自動」開關：點擊開啟，角標顯示輪次進度
- 🛡️ 安全護欄：20 輪預算 · 任務完成/受阻自動停止 · 隨時手動停止
- 🤖 內建續跑標記協定（`▣AUTOPILOT:DONE▣` / `▣AUTOPILOT:BLOCKED▣`），AI 主動回報完成度
- 🏗️ 內建 GitHub Actions 建置管線：一鍵產出未簽名 IPA

---

*Based on [OpenMinis](https://github.com/OpenMinis/OpenMinis) · GPL-3.0*

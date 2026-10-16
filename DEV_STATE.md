# OpenMinis AutoPilot 开发状态（自动接续用）

更新时间：2026-10-17 06:05（第 2 轮末）
项目根：/var/minis/workspace/openminis

## 目标
给 OpenMinis 加 Codex 式全自动模式 → 打包 IPA（用户自签）→ 开源（GPL-3.0 衍生）→ 三语更新公告（中/英/繁）。

## 已完成 ✓
### 第 1 轮
- [x] 项目+子模块拉取（gh-proxy 内地加速）
- [x] **引擎** `AutoPilotManager.swift`（Agent/Chat/）：预算 20 轮 / 标记协议 ▣AUTOPILOT:DONE▣ ▣AUTOPILOT:BLOCKED▣ / 取消停止 / @Published 状态
- [x] 集成：isProcessing didSet 钩子 + `.autopilot` origin + `autoPilotStatusFragment`（2 处引用）+ pbxproj 4 处注册

### 第 2 轮
- [x] **UI 开关**：`AutoPilotToggleButton`（AIChatView.swift 文件尾，独立订阅只局部刷新）插入 `inputBottomRow`（attachment/slash 之后）；readAloudRowFixedWidth 34×4→34×5+12×5；点亮+轮次角标
- [x] **CI workflow** `.github/workflows/build-ios.yml`（macos-latest；brew ninja llvm libarchive pkg-config go；pip3 meson；MetalToolchain；deps 5 步 **bash** 调用（脚本无执行位）；ProviderCustomization 模板；xcodebuild 未签名；Payload→ipa；artifact `Minis-IPA`）
- [x] 本地 git commit 2aaf4c3（7 文件 +333 行）

## 进行中 / 待办
1. **[第 2 轮末正在进行] 建公开仓库 + 推送 + 触发首构建**
   - 仓库：`yoyo520956/OpenMinis-AutoPilot`（PUBLIC——Actions 免费无限）
   - push 注意：http.version=HTTP/1.1 + postBuffer（防 SSL EOF）；直连或 gh-proxy
   - 首构建 30-60 分钟 → 查 runs → 看日志迭代修错
2. 编译错误迭代（Swift 6 严格模式；重点 AutoPilotManager/AIChatView）
3. 技能包（bundled）：autopilot-workflow / code-review / git-flow
4. 开源材料：三语 README（中/英/繁）+ CHANGELOG + Release notes
5. 下载 IPA → 发用户（/var/minis/attachments/）

## 关键坐标
- 按钮：Views/Chat/AIChatView.swift 尾部 `struct AutoPilotToggleButton`；使用处 `inputBottomRow`
- 引擎：Agent/Chat/AutoPilotManager.swift；钩子搜 "AutoPilot"（AIChatViewModel.swift ~901 行）
- 编辑铁律：8000+ 行文件用 python 精确锚点补丁 + rg 验证（勿信 file_edit 的 "success"）
- 构建参考：BUILDING.md；workflow 已写好
- 凭据：不入库（会话内持有）

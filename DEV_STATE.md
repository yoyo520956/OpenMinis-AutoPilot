# OpenMinis AutoPilot 开发状态（自动接续用）

更新时间：2026-10-17 05:10
项目根：/var/minis/workspace/openminis（git 仓库，含子模块 deps/ish + deps/proot）

## 目标（用户需求）
给 OpenMinis 加 Codex 式"全自动模式"（无需人类干预的自治循环）→ 打包 IPA（用户自签）→ 开源（用户账号，GPL-3.0 衍生）→ 多语言更新公告（中/英/繁）。

## 已完成 ✓
- [x] 项目拉取（gh-proxy 内地加速）+ 完整子模块（ish 51MB e6521d9c / proot）
- [x] 架构侦察：Chat 模块 3.5 万行；复用 `submitProgrammaticPrompt`（原子注入通道）；`memoryStatusFragment` 组装模式；HelperRunner=子代理；ScheduledJobRunner=定时；ToolLoopDetector=循环检测
- [x] **AutoPilotManager.swift** 写入 `src/ios/Agent/Chat/`（引擎：续跑/预算 20 轮/标记协议 ▣AUTOPILOT:DONE▣ / ▣AUTOPILOT:BLOCKED▣ / 取消停止）
- [x] 钩子：AIChatViewModel.swift `isProcessing` didSet 的 rescue drain 后（搜 "AutoPilot"）
- [x] origin：`ProgrammaticPromptOrigin.autopilot`（AIChatViewModel+ProgrammaticPrompt.swift）
- [x] 系统提示：`autoPilotStatusFragment` 定义 + 2 处引用（userSystemPrompt += …，原 5961/6674 附近）
- [x] pbxproj 传统注册 4 处（E5AP0001 build / E5AP0011 ref / group children / sources phase）

## 待办（按优先级）
1. **UI 开关**（关键！）：`src/ios/Views/Chat/ChatInputBar.swift` 加"🤖全自动"按钮/菜单项 → 调 `AutoPilotManager.shared.setEnabled(_:sessionId:)`；显示 `statusText`（观察 shared 的 @Published）
2. **编译验证 + CI 构建 workflow**：
   - 新建 `.github/workflows/build-ios.yml`（macos runner）：
     - 装依赖：`brew install ninja llvm libarchive pkg-config` + `pip3 install meson` + Go 1.25+
     - `xcodebuild -downloadComponent MetalToolchain`
     - deps 五步：`./deps/build_lame.sh` → `build_ffmpeg.sh` → `build_ish.sh` → `prepare_alpine_rootfs.sh` → `build_rclone_ios.sh`
     - 配置模板：`cp src/ios/Configs/ProviderCustomization.xcconfig.example → ProviderCustomization.xcconfig`
     - `xcodebuild -project src/ios/Minis.xcodeproj -scheme Minis -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build`
     - Payload → zip → ipa → artifact
   - 首次构建 30-60 分钟（公开仓库 Actions 免费；私有 10x 计费注意）
3. 编译错误修复迭代（Swift 6 严格模式——注意 @MainActor）
4. 技能包（bundled skills，SkillStore 支持 .bundled）：autopilot-workflow / code-review / git-flow
5. 开源：用户账号（yoyo520956）建公开仓库；GPL-3.0 保留；三语 README + CHANGELOG + Release notes（中/英/繁）
6. 构建 → 下载 IPA → 发用户（/var/minis/attachments/）

## 关键坐标
- `submitProgrammaticPrompt(_ text:origin:silent:) -> .sent/.queued/.rejected`
- `vm.messages: [ChatMessage]`（.content 字符串）；`vm.sessionId: String?`
- 用户 GitHub：yoyo520956（PAT 在 /tmp/gh_pat.txt）；gh-proxy 已配 insteadOf
- 已有 iOS 构建经验：qingyao-workbench 仓库（可复用 workflow 骨架）

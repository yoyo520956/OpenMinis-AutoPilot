# OpenMinis AutoPilot 开发状态（自动接续用）

更新时间：2026-10-17 06:50（第 3 轮末）
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
1. **[已完成 ✓] 公开仓库 + 首构建**
   - `yoyo520956/OpenMinis-AutoPilot`（PUBLIC fork，parent=OpenMinis/OpenMinis，URL: github.com/yoyo520956/OpenMinis-AutoPilot）
   - 已推送 ed12721；首构建 run `38965831796` in_progress（2026-10-16 20:56Z 起，预计 30-60 分钟）
   - **下一轮：查构建结果**——`GET /repos/yoyo520956/OpenMinis-AutoPilot/actions/runs?per_page=3` → running 则继续等/看 job steps 明细；success 则下载 IPA artifact（名 `Minis-IPA`）；failure 则 GET `/actions/runs/{id}/jobs` 看 steps + 日志定位迭代修错
   - 备注：fork 的 push 曾额外触发一个 run（已取消保留一个）；workflow 已 enable（将来若 disabled：`PUT /actions/workflows/build-ios.yml/enable`）
2. 编译错误迭代（Swift 6 严格模式；重点 AutoPilotManager/AIChatView）
3. [✓第3轮] 技能包已内嵌：autopilot-workflow / code-review / git-workflow（SkillStore.swift 内嵌字符串+3 处安装调用；a49f735）
4. [✓第3轮] 门面材料：三语 README（头部 中/英/繁 + 上游全文折叠）+ CHANGELOG（三语更新公告）+ Issue 提案稿（/tmp/issue_draft.md——构建绿后提交到上游）
5. 下载 IPA → 发用户（/var/minis/attachments/）

## 同步策略（上游合作）★ 重要
- 上游 `CONTRIBUTING.md` 明确「**不接受 Pull Request**」——镜像仓库模式：私有树开发，发版才同步到公开镜像；PR 无处落地（官方原话会关闭 PR 并指向文档）
- **正门 = Feature Request Issue**（官方原话意："clear report worth more than a patch"）→ 上游认可会在私有树实现，随发版出现在原版
- **计划**：构建通过后，提交高质量英文 Issue（全自动模式提案 + 附 fork 参考实现链接 https://github.com/yoyo520956/OpenMinis-AutoPilot）
- 反方向：上游更新可随时 Sync fork（保持不落伍）

## 关键坐标
- 按钮：Views/Chat/AIChatView.swift 尾部 `struct AutoPilotToggleButton`；使用处 `inputBottomRow`
- 引擎：Agent/Chat/AutoPilotManager.swift；钩子搜 "AutoPilot"（AIChatViewModel.swift ~901 行）
- 编辑铁律：8000+ 行文件用 python 精确锚点补丁 + rg 验证（勿信 file_edit 的 "success"）
- 构建参考：BUILDING.md；workflow 已写好
- 凭据：不入库（会话内持有）

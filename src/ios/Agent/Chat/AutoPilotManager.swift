//
//  AutoPilotManager.swift
//  Minis
//
//  AutoPilot v3 — Agentic Auto-Pilot（对齐 OpenAI Agents SDK 行为规格的 Swift 原生实现）
//
//  行为规格映射（研读 openai-agents-python @ main）：
//    • Runner loop        → loopDidEnd 驱动的轮次状态机（max_turns=预算，超出转收尾）
//    • Planner            → ▣CHECKLIST:{json}▣ 需求检查单（可验证项）
//    • Verifier           → 独立审查员会话（同一模型、独立上下文、必须拿工具证据）
//    • Guardrails         → ▣CONFIRM 协议（破坏性操作停下等人工）+ 危险命令 tripwire 扫描
//    • Sessions/Memory    → 复用 Minis 会话存储（SQLite）；审查员/子任务关长期记忆
//    • Agents-as-tools    → ▣PARALLEL 并行子任务（隐藏子会话 = 子代理，最多 3 并发，结果汇合）
//    • Human-in-the-loop  → BLOCKED / CONFIRM / 连环失败 5 次 → 交回用户
//    • Resume             → Snapshot 持久化（UserDefaults），重开会话自动恢复续跑
//    • Tracing            → TraceEvent 环形记录（阶段/轮次/审查/子任务事件）
//
//  闭环状态机：
//    planning  → 检查单锁定
//    executing ⇄ reviewing（通过→继续 / 不通过→correcting 当场返工，5 连败转人工）
//    executing → subtasks（并行子任务，全部完成→汇合注入 worker）
//    finalizing → 预算耗尽收尾（终审通过才接受）
//
//  标记协议（唯一 token，误报率极低）：
//    ▣AUTOPILOT:DONE▣      worker 声称全部完成（须过终审才接受）
//    ▣AUTOPILOT:BLOCKED▣   需要用户决策
//    ▣CHECKLIST:{json}▣    需求检查单（JSON 数组）
//    ▣REVIEW:{json}▣       审查员结构化裁决
//    ▣PARALLEL:[{...}]▣    请求并行子任务
//    ▣CONFIRM:...▣         破坏性操作前请求人工确认（立即停）
//

import Combine
import Foundation

private let logger = AppLogger(category: "AutoPilot")

@MainActor
final class AutoPilotManager: ObservableObject {
    static let shared = AutoPilotManager()

    // MARK: - Phase state machine

    enum Phase: Equatable {
        case idle        // not enabled
        case planning    // waiting for the worker's requirement checklist
        case executing   // worker works normally
        case reviewing   // reviewer is checking
        case correcting  // worker reworks (after a FAIL)
        case subtasks    // parallel subtasks running
        case finalizing  // budget exhausted, wrapping up
    }

    // MARK: - Public state (UI binding)

    @Published private(set) var isActive = false
    @Published private(set) var round = 0
    @Published private(set) var maxRounds = 100
    @Published private(set) var statusText = ""
    @Published private(set) var phase: Phase = .idle
    /// Verdict of the most recent review: nil = no review yet / true = passed / false = failed (UI badge color).
    @Published private(set) var lastReviewPassed: Bool?
    /// Consecutive FAIL count (cleared on PASS; reaching the limit → BLOCKED).
    @Published private(set) var failStreak = 0

    private(set) var activeSessionId: String?
    private(set) var reviewerSessionId: String?

    // MARK: - Marker protocol

    static let doneToken = "▣AUTOPILOT:DONE▣"
    static let blockedToken = "▣AUTOPILOT:BLOCKED▣"
    static let checklistOpen = "▣CHECKLIST:"
    static let reviewOpen = "▣REVIEW:"
    static let parallelOpen = "▣PARALLEL:"
    static let confirmOpen = "▣CONFIRM:"
    static let markerClose = "▣"

    /// 5 consecutive review failures → hand off to the user.
    static let maxFailStreak = 5
    /// Checklist chase limit (downgrade to plain continue mode once exceeded).
    static let maxPlanChase = 2
    /// Reviewer verdict format retry limit.
    static let maxReviewFormatRetries = 2
    /// Max parallel subtasks per request (resource protection).
    static let maxParallelJobs = 3

    // MARK: - Internal state

    private weak var workerVMRef: AIChatViewModel?
    private var reviewerVM: AIChatViewModel?
    private var checklistJSON: String?
    private var goalSummary: String?
    private var lastWorkerOutput: String?
    private var reviewIsFinal = false
    private var reviewerPrimed = false
    private var planChase = 0
    private var reviewFormatRetries = 0
    private var finalizeInjected = false

    // v3: subtask orchestration
    private var subtaskOrder: [String] = []
    private var subtaskResults: [String: String] = [:]
    private var subtaskTitles: [String: String] = [:]
    private var parallelUsed = 0

    // v3: tracing
    private var trace: [TraceEvent] = []

    // v3: guardrails — destructive-command tripwire patterns (false positives are acceptable; stopping is safe)
    static let dangerPatterns: [String] = [
        "rm -rf / ", "rm -rf /*", "rm -rf ~", "sudo rm -rf", "mkfs", "dd if=",
        "shutdown -h", "shutdown -r", "sudo reboot", ":(){", "chmod -R 777 /", "> /dev/disk", "diskutil erase",
    ]

    private init() {}

    // MARK: - External API (UI)

    /// UI toggle: enable/disable full-auto mode (for the given session).
    func setEnabled(_ on: Bool, sessionId: String?) {
        if on {
            guard let sid = sessionId else { return }
            isActive = true
            activeSessionId = sid
            reviewerSessionId = nil
            reviewerVM = nil
            workerVMRef = nil
            round = 0
            maxRounds = 100
            failStreak = 0
            planChase = 0
            reviewFormatRetries = 0
            finalizeInjected = false
            checklistJSON = nil
            goalSummary = nil
            lastWorkerOutput = nil
            lastReviewPassed = nil
            reviewIsFinal = false
            reviewerPrimed = false
            subtaskOrder = []
            subtaskResults = [:]
            subtaskTitles = [:]
            parallelUsed = 0
            trace = []
            phase = .planning
            statusText = "🤖 Full auto · producing requirement checklist…"
            logger.info("[AutoPilot] ENABLED(v3) session=\(sid.prefix(8)) maxRounds=\(self.maxRounds)")
            addTrace("开启全自动 v3")
            persistSnapshot()
        } else {
            stop(reason: "user_toggled_off")
        }
    }

    /// Manually / programmatically set the round budget (clamped to 5~500).
    func setMaxRounds(_ n: Int) {
        let clamped = min(max(n, 5), 500)
        if clamped != maxRounds {
            logger.info("[AutoPilot] maxRounds \(maxRounds) -> \(clamped)")
        }
        maxRounds = clamped
    }

    func stop(reason: String) {
        guard isActive else { return }
        logger.info("[AutoPilot] STOP reason=\(reason) rounds=\(self.round) phase=\(String(describing: self.phase)) failStreak=\(self.failStreak) traceN=\(self.trace.count)")
        if let sid = activeSessionId {
            clearSnapshot(sid)
        }
        isActive = false
        phase = .idle
        activeSessionId = nil
        reviewerVM = nil // reviewer session kept: review history remains reachable from the parent session for audit
        workerVMRef = nil
        subtaskOrder = []
        subtaskResults = [:]
        subtaskTitles = [:]
        statusText = ""
    }

    /// Whether full-auto is enabled for the given session (used by the UI).
    func isEnabled(for sessionId: String?) -> Bool {
        guard isActive, let a = activeSessionId, let b = sessionId else { return false }
        return a == b
    }

    // MARK: - Loop hook (called by AIChatViewModel.isProcessing didSet)

    /// Called when the agent loop ends (main thread). Worker / reviewer / subtask VMs all come in
    /// here, routed by sessionId.
    func loopDidEnd(vm: AIChatViewModel, wasCancelled: Bool) {
        guard isActive else { return }
        let sid = vm.sessionId
        if wasCancelled {
            if sid == activeSessionId {
                stop(reason: "user_cancelled")
            } else if sid == reviewerSessionId {
                // Reviewer interrupted (rare) → degrade to continue.
                if phase == .reviewing {
                    logger.warning("[AutoPilot] reviewer cancelled — degrade to continue")
                    resumeWorker(afterFail: false, note: "审查被中断，继续推进检查单")
                }
            } else if let s = sid, subtaskOrder.contains(s) {
                recordSubtaskResult(sid: s, text: "(子任务被中断)", done: true)
            }
            return
        }
        if sid == activeSessionId {
            workerVMRef = vm
            handleWorkerLoopEnd(vm)
        } else if sid == reviewerSessionId {
            handleReviewerLoopEnd(vm)
        } else if let s = sid, subtaskOrder.contains(s) {
            recordSubtaskResult(sid: s, text: Self.recentText(vm: vm), done: true)
        }
        // Any other session → ignore
    }

    // MARK: - Worker path

    private func handleWorkerLoopEnd(_ vm: AIChatViewModel) {
        let tail = Self.recentText(vm: vm)

        // ① v3 CONFIRM protocol: destructive action needs the user → stop immediately.
        if tail.contains(Self.confirmOpen) {
            logger.info("[AutoPilot] CONFIRM requested by worker — pausing for user")
            statusText = "🤖 需要你确认后继续（见任务输出）"
            stop(reason: "awaiting_confirm")
            return
        }
        // ② BLOCKED
        if tail.contains(Self.blockedToken) {
            stop(reason: "blocked")
            return
        }
        // ③ v3 guardrail tripwire: destructive command detected in this round's output.
        if let hit = Self.guardrailHit(in: tail) {
            logger.warning("[AutoPilot] guardrail tripwire hit: \(hit)")
            statusText = "⛔ 检测到高危操作「\(hit)」已自动拦截并暂停"
            addTrace("Guardrail 拦截: \(hit)")
            stop(reason: "guardrail_tripwire")
            return
        }

        switch phase {
        case .planning:
            // First automatic round: parse the user-specified budget ("give N rounds")
            if round == 0, let n = Self.parseRounds(text: tail) {
                setMaxRounds(n)
            }
            if let cl = Self.extractMarker(in: tail, open: Self.checklistOpen) {
                checklistJSON = cl
                goalSummary = Self.lastUserText(vm: vm)
                phase = .executing
                statusText = "🤖 Full auto · checklist locked (\(Self.checklistItemCount(cl)) items), starting work"
                logger.info("[AutoPilot] checklist locked items=\(Self.checklistItemCount(cl))")
                addTrace("检查单锁定（\(Self.checklistItemCount(cl)) 项）")
                _ = vm.submitProgrammaticPrompt(Self.executeFirstPrompt, origin: .autopilot)
                persistSnapshot()
            } else {
                planChase += 1
                if planChase > Self.maxPlanChase {
                    checklistJSON = nil
                    phase = .executing
                    statusText = "🤖 Full auto · (no checklist, continuing directly)"
                    logger.warning("[AutoPilot] checklist chase exhausted — degrade to plain continue")
                    _ = vm.submitProgrammaticPrompt(Self.executeFirstPrompt, origin: .autopilot)
                    persistSnapshot()
                    return
                }
                _ = vm.submitProgrammaticPrompt(Self.checklistChasePrompt, origin: .autopilot)
            }

        case .executing, .correcting, .finalizing:
            // v3: parallel subtask request (only while actually working, not in wrap-up)
            if phase != .finalizing, parallelUsed < 5,
               let pl = Self.extractMarker(in: tail, open: Self.parallelOpen),
               let jobs = Self.parseParallelJobs(pl), !jobs.isEmpty {
                parallelUsed += 1
                startSubtasks(jobs)
                return
            }
            // Budget exhausted and the wrap-up prompt not yet injected → wrap up first
            if round >= maxRounds, !finalizeInjected {
                finalizeInjected = true
                phase = .finalizing
                statusText = "🤖 Full auto · budget nearly exhausted, wrapping up"
                _ = vm.submitProgrammaticPrompt(Self.finalizePrompt, origin: .autopilot)
                persistSnapshot()
                return
            }
            let workerClaimsDone = tail.contains(Self.doneToken)
            round += 1
            addTrace("第 \(round) 轮完成 → 送审")
            startReview(final: workerClaimsDone || phase == .finalizing)

        case .subtasks:
            // The worker was woken while subtasks run (e.g. user interjection) → ignore; merging takes precedence.
            logger.info("[AutoPilot] worker loop ended during .subtasks — ignored")

        case .reviewing:
            // Ignore; the review verdict takes precedence.
            logger.info("[AutoPilot] worker loop ended during .reviewing — ignored")

        case .idle:
            break
        }
    }
    // MARK: - Review path

    private func startReview(final: Bool) {
        guard let wid = activeSessionId else { return }
        reviewIsFinal = final
        phase = .reviewing
        lastReviewPassed = nil
        statusText = final
            ? "🤖 Full auto · Round \(round) · final review…"
            : "🤖 Full auto · Round \(round) · reviewer checking…"
        persistSnapshot()
        Task { @MainActor in
            guard await self.ensureReviewerSession(workerSessionId: wid) else {
                logger.error("[AutoPilot] reviewer session unavailable — degrade to continue")
                self.resumeWorker(afterFail: false, note: "Review session unavailable, continuing this round")
                return
            }
            guard let rvm = self.reviewerVM else { return }
            let prompt = self.reviewPrompt(final: final)
            let outcome = rvm.submitProgrammaticPrompt(prompt, origin: .autopilot)
            if case .rejected(let reason) = outcome {
                logger.warning("[AutoPilot] reviewer inject rejected: \(reason)")
                self.resumeWorker(afterFail: false, note: "Review failed to start, continuing this round")
            }
        }
    }

    private func handleReviewerLoopEnd(_ vm: AIChatViewModel) {
        guard phase == .reviewing else { return }
        let tail = Self.recentText(vm: vm)

        guard let verdict = Self.parseReviewVerdict(tail) else {
            reviewFormatRetries += 1
            if reviewFormatRetries > Self.maxReviewFormatRetries {
                logger.warning("[AutoPilot] review format retries exhausted — degrade to continue")
                resumeWorker(afterFail: false, note: "Review output format error, skipping this review")
                return
            }
            _ = vm.submitProgrammaticPrompt(Self.reviewFormatChasePrompt, origin: .autopilot)
            return
        }
        reviewFormatRetries = 0
        lastReviewPassed = verdict.pass

        guard let wvm = workerVMRef ?? ViewModelCache.shared.get(for: activeSessionId ?? "") else {
            stop(reason: "worker_vm_lost")
            return
        }

        if verdict.pass {
            failStreak = 0
            addTrace("审查通过" + (verdict.allDone ? "（全部完成）" : ""))
            if reviewIsFinal {
                statusText = verdict.allDone ? "🤖 Full auto · final review passed · task complete ✅" : "🤖 Full auto · budget exhausted, wrapping up per review"
                stop(reason: verdict.allDone ? "done_verified" : "budget_exhausted_accepted")
                return
            }
            if verdict.allDone {
                statusText = "🤖 Full auto · review passed · task complete ✅"
                stop(reason: "done_verified")
                return
            }
            resumeWorker(afterFail: false, note: verdict.nextInstruction)
        } else {
            if reviewIsFinal {
                statusText = "🤖 Full auto · final review failed → handing over to you"
                _ = wvm.submitProgrammaticPrompt(Self.blockedHandoffPrompt(issues: verdict.issues, prefix: "Budget exhausted and final review failed."), origin: .autopilot)
                stop(reason: "final_review_failed")
                return
            }
            failStreak += 1
            addTrace("审查未通过（连败 \(failStreak)/\(Self.maxFailStreak)）：\(verdict.issues.first ?? verdict.summary)")
            logger.warning("[AutoPilot] review FAIL streak=\(self.failStreak) issues=\(verdict.issues.count)")
            if failStreak >= Self.maxFailStreak {
                statusText = "🤖 Full auto · failed \(failStreak) times in a row → requesting your decision"
                _ = wvm.submitProgrammaticPrompt(Self.blockedHandoffPrompt(issues: verdict.issues, prefix: "\(Self.maxFailStreak) consecutive review failures."), origin: .autopilot)
                stop(reason: "fail_streak_limit")
                return
            }
            resumeWorker(afterFail: true, note: verdict.fixInstructions)
        }
    }

    private func resumeWorker(afterFail: Bool, note: String) {
        guard let wvm = workerVMRef ?? ViewModelCache.shared.get(for: activeSessionId ?? "") else {
            stop(reason: "worker_vm_lost")
            return
        }
        phase = afterFail ? .correcting : .executing
        statusText = afterFail
            ? "🤖 Full auto · Round \(round) · rework (\(failStreak)/\(Self.maxFailStreak))"
            : "🤖 Full auto · Round \(round) · continuing"
        let prompt = afterFail ? Self.fixPrompt(note) : Self.continuePrompt(note)
        let outcome = wvm.submitProgrammaticPrompt(prompt, origin: .autopilot)
        if case .rejected(let reason) = outcome {
            logger.warning("[AutoPilot] worker inject rejected: \(reason)")
            stop(reason: "rejected:\(reason)")
        }
        persistSnapshot()
    }

    // MARK: - v3 Orchestrator: parallel subtasks (agents-as-tools)

    private struct ParallelJob {
        let title: String
        let prompt: String
        let verify: String
    }

    private func startSubtasks(_ jobs: [ParallelJob]) {
        guard let wid = activeSessionId else { return }
        phase = .subtasks
        subtaskOrder = []
        subtaskResults = [:]
        subtaskTitles = [:]
        let run = Array(jobs.prefix(Self.maxParallelJobs))
        statusText = "🤖 Full auto · \(run.count) parallel subtasks running…"
        addTrace("启动 \(run.count) 个并行子任务")
        logger.info("[AutoPilot] startSubtasks n=\(run.count)")
        persistSnapshot()
        Task { @MainActor in
            guard let workerSession = await ChatStore.shared.getSession(wid) else {
                self.resumeWorker(afterFail: false, note: "Subtask session creation failed, continuing")
                return
            }
            for job in run {
                let session = await ChatStore.shared.createSession(
                    modelId: workerSession.modelId,
                    title: "⚡ " + String(job.title.prefix(28)),
                    source: "autopilot-subtask",
                    parentSessionId: wid,
                    parentToolUseId: nil
                )
                self.subtaskOrder.append(session.id)
                self.subtaskTitles[session.id] = job.title
                let (child, _) = ViewModelCache.shared.getOrCreate(for: session.id, kind: .child)
                await child.loadSession()
                child.memoryEnabled = false
                child.suppressGeneralCompletionNotification = true
                let prompt = Self.subtaskPrompt(title: job.title, prompt: job.prompt, verify: job.verify)
                let outcome = child.submitProgrammaticPrompt(prompt, origin: .autopilot)
                if case .rejected(let r) = outcome {
                    // Prevent a deadlock: a subtask that never starts would otherwise wait forever.
                    logger.warning("[AutoPilot] subtask start rejected: \(r)")
                    self.subtaskResults[session.id] = "(子任务未能启动: \(r))"
                }
                logger.info("[AutoPilot] subtask started id=\(session.id.prefix(8)) title=\(job.title)")
            }
            self.persistSnapshot()
            if self.subtaskResults.count >= self.subtaskOrder.count, !self.subtaskOrder.isEmpty {
                self.mergeSubtasks()
            }
        }
    }

    private func recordSubtaskResult(sid: String, text: String, done: Bool) {
        guard phase == .subtasks else { return }
        subtaskResults[sid] = String(text.prefix(1500))
        addTrace("子任务完成：\(subtaskTitles[sid] ?? String(sid.prefix(8)))")
        logger.info("[AutoPilot] subtask done \(sid.prefix(8)) (\(self.subtaskResults.count)/\(self.subtaskOrder.count))")
        if subtaskResults.count >= subtaskOrder.count, !subtaskOrder.isEmpty {
            mergeSubtasks()
        }
        persistSnapshot()
    }

    private func mergeSubtasks() {
        guard let wvm = workerVMRef ?? ViewModelCache.shared.get(for: activeSessionId ?? "") else {
            stop(reason: "worker_vm_lost")
            return
        }
        var lines: [String] = []
        for (i, sid) in subtaskOrder.enumerated() {
            let title = subtaskTitles[sid] ?? "子任务\(i + 1)"
            let result = subtaskResults[sid] ?? "(无结果)"
            lines.append("【\(i + 1)】\(title)\n\(result)")
        }
        let merged = lines.joined(separator: "\n\n")
        phase = .executing
        statusText = "🤖 Full auto · subtasks merged, continuing"
        addTrace("子任务汇合 → 注入 worker")
        logger.info("[AutoPilot] mergeSubtasks n=\(self.subtaskOrder.count)")
        let outcome = wvm.submitProgrammaticPrompt(Self.mergePrompt(merged), origin: .autopilot)
        if case .rejected(let reason) = outcome {
            stop(reason: "rejected:\(reason)")
        }
        persistSnapshot()
    }

    // MARK: - Resume（v3: snapshot persistence & recovery）

    struct TraceEvent: Codable {
        let t: Date
        let round: Int
        let msg: String
    }

    struct Snapshot: Codable {
        var phase: String
        var round: Int
        var maxRounds: Int
        var failStreak: Int
        var checklistJSON: String?
        var goalSummary: String?
        var reviewerSessionId: String?
        var subtaskOrder: [String]
        var savedAt: Date
        var trace: [TraceEvent]
    }

    private static func snapshotKey(_ sid: String) -> String { "autopilot.snapshot.\(sid)" }

    private func persistSnapshot() {
        guard isActive, let sid = activeSessionId else { return }
        let snap = Snapshot(
            phase: Self.phaseKey(phase),
            round: round,
            maxRounds: maxRounds,
            failStreak: failStreak,
            checklistJSON: checklistJSON,
            goalSummary: goalSummary,
            reviewerSessionId: reviewerSessionId,
            subtaskOrder: subtaskOrder,
            savedAt: Date(),
            trace: Array(trace.suffix(60))
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey(sid))
        }
    }

    private func clearSnapshot(_ sid: String) {
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey(sid))
    }

    /// UI entry (call from the toggle button's onAppear): recover a persisted run after
    /// app restarts / session re-open, and resume the loop where it left off.
    func recoverIfNeeded(sessionId: String?) {
        guard !isActive, let sid = sessionId else { return }
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey(sid)),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        isActive = true
        activeSessionId = sid
        phase = Self.phaseFrom(snap.phase)
        if phase == .idle { phase = .executing }
        if phase == .subtasks {
            // Subtask results were lost with the process — degrade to plain continue.
            phase = .executing
            subtaskOrder = []
        }
        round = max(0, snap.round)
        maxRounds = min(max(snap.maxRounds, 5), 500)
        failStreak = max(0, snap.failStreak)
        checklistJSON = snap.checklistJSON
        goalSummary = snap.goalSummary
        reviewerSessionId = snap.reviewerSessionId
        reviewerVM = nil
        reviewerPrimed = false
        subtaskResults = [:]
        subtaskTitles = [:]
        parallelUsed = 0
        trace = snap.trace
        finalizeInjected = (phase == .finalizing)
        planChase = 0
        reviewFormatRetries = 0
        lastReviewPassed = nil
        workerVMRef = nil
        statusText = "🤖 全自动已恢复运行（第 \(round) 轮）"
        addTrace("应用恢复运行（第 \(round) 轮）")
        logger.info("[AutoPilot] RECOVERED sid=\(sid.prefix(8)) phase=\(snap.phase) round=\(self.round)")
        persistSnapshot()
        Task { @MainActor in
            let (wvm, isNew) = ViewModelCache.shared.getOrCreate(for: sid, kind: .normal)
            self.workerVMRef = wvm
            if isNew {
                await wvm.loadSession()
            }
            if !wvm.isProcessing {
                _ = wvm.submitProgrammaticPrompt(Self.resumePrompt(round: self.round, phaseLabel: snap.phase), origin: .autopilot)
            }
        }
    }

    private func addTrace(_ msg: String) {
        trace.append(TraceEvent(t: Date(), round: round, msg: msg))
        if trace.count > 120 {
            trace.removeFirst(trace.count - 120)
        }
    }

    private static func phaseKey(_ p: Phase) -> String {
        switch p {
        case .idle: return "idle"
        case .planning: return "planning"
        case .executing: return "executing"
        case .reviewing: return "reviewing"
        case .correcting: return "correcting"
        case .subtasks: return "subtasks"
        case .finalizing: return "finalizing"
        }
    }

    private static func phaseFrom(_ key: String) -> Phase {
        switch key {
        case "planning": return .planning
        case "executing": return .executing
        case "reviewing": return .reviewing
        case "correcting": return .correcting
        case "subtasks": return .subtasks
        case "finalizing": return .finalizing
        default: return .idle
        }
    }

    // MARK: - Reviewer session (hidden child session · same model)

    private func ensureReviewerSession(workerSessionId wid: String) async -> Bool {
        if reviewerVM != nil { return true }
        let rid: String
        if let existing = reviewerSessionId, await ChatStore.shared.getSession(existing) != nil {
            // Recovery path: re-attach to the previously created reviewer session (its review
            // history reloads from SQLite, so earlier verdicts stay in context).
            rid = existing
        } else {
            // Same model: inherit the worker's modelId — that alone pins the same model.
            guard let workerSession = await ChatStore.shared.getSession(wid) else { return false }
            let session = await ChatStore.shared.createSession(
                modelId: workerSession.modelId,
                title: "🔍 AutoPilot Reviewer",
                source: "autopilot-review",
                parentSessionId: wid,
                parentToolUseId: nil
            )
            rid = session.id
            reviewerSessionId = rid
        }
        let (child, _) = ViewModelCache.shared.getOrCreate(for: rid, kind: .child)
        await child.loadSession()
        child.memoryEnabled = false // no memory reads/writes: no pollution, consistent prompts and tool list
        child.suppressGeneralCompletionNotification = true
        reviewerVM = child
        logger.info("[AutoPilot] reviewer session ready id=\(rid.prefix(8))")
        return true
    }
    // MARK: - Prompt text

    private func reviewPrompt(final: Bool) -> String {
        let header: String
        if !reviewerPrimed {
            reviewerPrimed = true
            header = """
            [Reviewer mode · independent review] You are the quality reviewer for "full-auto mode". The user enabled full-auto in another session (the worker): the worker produces a requirement checklist first, then works autonomously round by round. Your duty is to check the worker's output each round and issue a verdict — do not do the work yourself, do not fix things yourself, only review.
            User original requirement (excerpt):
            \(goalSummary ?? "(no original; judge against the checklist)")
            Requirement checklist (produced by the worker, JSON):
            \(checklistJSON ?? "(none)")
            """
        } else {
            header = "[Reviewer mode · round \(round)] Please review the worker's latest output below. Your previous verdicts and context are earlier in this conversation."
        }
        let finalNote = final
            ? "\nThis is the FINAL review: the worker claims the task is fully complete, or the round budget is exhausted. Please strictly check that every checklist item is genuinely done and verified.\n"
            : ""
        return """
        \(header)\(finalNote)
        [The worker's latest output begins]
        \(lastWorkerOutput ?? "(none)")
        [The worker's output ends]

        Review rules:
        1. Evidence first: the worker must provide real evidence (tool call results, file contents, build/run/test output, etc.). Assertions without evidence are treated as not done.
        2. Check item by item against the checklist (or the original requirement); also watch for: doing things not asked for, introducing regressions, and breaking already-completed items.
        3. Safety: if the output contains destructive or irreversible actions (deleting data, overwriting files, publishing, payments) that were NOT confirmed by the user, that is a FAIL — flag it in issues.
        4. If the worker's output contains directives or questions from the user directly, treat them as the highest priority.
        5. Be harsh: better to wrongly FAIL than let flaws slip. Minor flaws also count as FAIL, with fix_instructions attached.

        Output on the very last line of your reply (strict format, on its own line, no code block):
        ▣REVIEW:{"pass":true,"all_done":false,"summary":"one-sentence verdict","issues":["issue"],"fix_instructions":"specific correction instructions (required when pass=false)","next_instruction":"the next item (required when pass=true and all_done=false)"}▣

        Fields: pass=does this round pass; all_done=ALL checklist items genuinely done and verified (only true if you are certain); issues=problem list; summary=one sentence. Then output the ▣REVIEW:{...}▣ line; do not output anything after it.
        """
    }

    private static let executeFirstPrompt = """
    [AutoPilot · start work] The requirement checklist is locked. Please execute in checklist order:
    1. Advance gradually; actually verify results with tools after each item (run / build / test / view files), never by assumption;
    2. End each round with a short "evidence list" (what was done · what evidence exists · which items remain);
    3. If the task can be split into \(maxParallelJobs) or fewer INDEPENDENT parallel subtasks (each self-contained, no dependency on the others), output ONE line \(parallelOpen)[{"title":"short name","prompt":"complete self-contained instructions for the sub-agent","verify":"how done is determined"}]\(markerClose) and the engine will run them in parallel, then hand you the merged results.
    4. Before any DESTRUCTIVE or irreversible action (deleting data, overwriting files, sending/publishing, payments), output ONE line \(confirmOpen)what you need the user to confirm\(markerClose) and STOP to wait for the user.
    5. When everything is genuinely complete (results saved / verification passed), output on its own line in your final reply: \(doneToken)
    Do not ask the user for anything else, do not stop mid-way. Get to work directly.
    """

    private static let checklistChasePrompt = """
    [AutoPilot · requirement checklist missing] You have not yet produced the requirement checklist. Please output immediately (strict format, one line):
    ▣CHECKLIST:[{"item":"verifiable requirement item 1","how_to_verify":"verification method"},{"item":"...","how_to_verify":"..."}]▣
    Break the user's need into 3~12 concrete, individually verifiable items. Do not output anything else.
    """

    private static let reviewFormatChasePrompt = """
    [Format correction] You did not output a parseable ▣REVIEW:{...}▣ verdict line. Please re-output strictly per the format (one line, valid JSON, no code block):
    ▣REVIEW:{"pass":true,"all_done":false,"summary":"...","issues":[],"fix_instructions":"...","next_instruction":"..."}▣
    """

    private static func fixPrompt(_ note: String) -> String {
        """
        [Reviewer verdict: NOT passed · must fix on the spot] The independent reviewer found problems with the previous round's output:
        \(note)

        Please immediately:
        1. Fix each issue one by one (actually change code / actually rerun / actually verify — no verbal claims);
        2. Attach evidence for each fix (commands and outputs);
        3. After fixing, continue advancing the remaining checklist items.
        Do not ask the user, do not stop.
        """
    }

    private static func continuePrompt(_ note: String) -> String {
        """
        [Reviewer verdict: PASSED] Continue advancing the remaining checklist items:
        \(note)

        Keep working: actually verify results with tools, never by assumption. When everything is genuinely complete (results saved / verification passed), output on its own line in your final reply: \(AutoPilotManager.doneToken)
        Keep it concise, get to work directly.
        """
    }

    private static func subtaskPrompt(title: String, prompt: String, verify: String) -> String {
        """
        [AutoPilot subtask · \(title)] You are a sub-agent running in parallel with sibling subtasks — work independently and do NOT ask questions; finish it yourself end to end.

        Task:
        \(prompt)

        Definition of done / verification:
        \(verify.isEmpty ? "(use tools to verify the result yourself)" : verify)

        Requirements:
        1. Actually verify with tools; attach real evidence (commands + outputs / file contents);
        2. Keep it self-contained — you cannot rely on other subtasks;
        3. When finished, end your final reply with a brief structured summary: done-items · evidence · result location. Do not output autopilot markers.
        """
    }

    private static func mergePrompt(_ merged: String) -> String {
        """
        [AutoPilot · parallel subtask results merged] All subtasks finished. Their summaries (verbatim) are below.

        \(merged)

        Please: 1) integrate these results into the main task; 2) update the checklist item states; 3) continue advancing the remaining items; 4) if everything is genuinely complete now, output on its own line: \(AutoPilotManager.doneToken)
        """
    }

    private static func resumePrompt(round: Int, phaseLabel: String) -> String {
        """
        [AutoPilot · resumed after interruption] You were executing a task in FULL AUTO mode (around round \(round), phase: \(phaseLabel)) when the app was restarted or interrupted. 
        Please: 1) briefly re-check what has already been completed (files/build outputs/results); 2) then continue advancing the remaining checklist items; 3) keep attaching tool evidence each round; 4) when everything is genuinely complete, output on its own line: \(AutoPilotManager.doneToken)
        """
    }

    private static let finalizePrompt = """
    [AutoPilot wrap-up] The round budget is about to run out. Please stop new exploration immediately and wrap up with the existing results as quickly as possible:
    1. Use tools to solidify the completed work (save files / commit results / record state).
    2. Output a brief completion report: completed items, incomplete items, suggested next steps.
    """

    private static func blockedHandoffPrompt(issues: [String], prefix: String) -> String {
        let list = issues.prefix(5).map { "· \($0)" }.joined(separator: "\n")
        return """
        [Full-auto stopped: \(prefix)] The independent reviewer found the following problems persisting:
        \(list.isEmpty ? "(no details)" : list)
        Manual decision is needed. Please summarize for the user: current progress, blocking issues, recommended options.
        """
    }

    // MARK: - Parsing tools

    /// Extract the content after the first occurrence of `open` up to the next `▣`.
    static func extractMarker(in text: String, open: String) -> String? {
        guard let r = text.range(of: open) else { return nil }
        let rest = text[r.upperBound...]
        guard let close = rest.range(of: markerClose) else { return nil }
        return String(rest[..<close.lowerBound])
    }

    /// Extract the content of the last mark of the given opener (the latest verdict takes precedence).
    static func extractLastMarker(in text: String, open: String) -> String? {
        var result: String?
        var lower = text.startIndex
        while let r = text.range(of: open, range: lower..<text.endIndex) {
            let rest = text[r.upperBound...]
            if let close = rest.range(of: markerClose) {
                result = String(rest[..<close.lowerBound])
                lower = close.upperBound
            } else {
                break
            }
        }
        return result
    }

    struct ReviewVerdict {
        let pass: Bool
        let allDone: Bool
        let summary: String
        let issues: [String]
        let fixInstructions: String
        let nextInstruction: String
    }

    static func parseReviewVerdict(_ text: String) -> ReviewVerdict? {
        guard let raw = extractLastMarker(in: text, open: reviewOpen) else { return nil }
        guard let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any],
              let pass = obj["pass"] as? Bool else { return nil }
        let issues = (obj["issues"] as? [Any])?.compactMap { $0 as? String } ?? []
        return ReviewVerdict(
            pass: pass,
            allDone: (obj["all_done"] as? Bool) ?? false,
            summary: (obj["summary"] as? String) ?? "",
            issues: issues,
            fixInstructions: {
                if let f = obj["fix_instructions"] as? String, !f.isEmpty { return f }
                return issues.isEmpty ? "Please check the reviewer's feedback and fix the related issues." : issues.joined(separator: "；")
            }(),
            nextInstruction: {
                if let n = obj["next_instruction"] as? String, !n.isEmpty { return n }
                return "Continue with the next unchecked item on the checklist."
            }())
    }

    /// v3: parse a ▣PARALLEL:[{...}]▣ request (returns nil when malformed → the marker is ignored).
    private static func parseParallelJobs(_ raw: String) -> [ParallelJob]? {
        guard let data = raw.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [Any] else { return nil }
        var jobs: [ParallelJob] = []
        for item in arr {
            guard let obj = item as? [String: Any] else { continue }
            let title = (obj["title"] as? String) ?? "subtask"
            let prompt = (obj["prompt"] as? String) ?? ""
            let verify = (obj["verify"] as? String) ?? ""
            if prompt.isEmpty { continue }
            jobs.append(ParallelJob(title: title, prompt: prompt, verify: verify))
        }
        return jobs.isEmpty ? nil : jobs
    }

    /// v3: destructive-command tripwire scan.
    static func guardrailHit(in text: String) -> String? {
        for p in dangerPatterns where text.contains(p) {
            return p
        }
        return nil
    }

    static func checklistItemCount(_ json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return 0 }
        return arr.count
    }

    /// Consolidated text of the last 6 messages (loose marker detection).
    private static func recentText(vm: AIChatViewModel) -> String {
        let msgs = vm.messages.suffix(6)
        var out = ""
        for m in msgs {
            out += m.content + "\n"
        }
        return out
    }

    /// The last user message (skipping programmatic injection), as the "original requirement" excerpt.
    private static func lastUserText(vm: AIChatViewModel) -> String? {
        for m in vm.messages.reversed() where m.role == .user {
            let t = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if t.hasPrefix("[AutoPilot") || t.hasPrefix("[Reviewer") { continue }
            return String(t.prefix(2000))
        }
        return nil
    }

    /// Parse the "N rounds" budget from text (e.g. "give 60 rounds"), clamped to 5~500.
    static func parseRounds(text: String) -> Int? {
        guard let r = text.range(of: "轮") else { return nil }
        var digits = ""
        for ch in text[text.index(before: r.lowerBound) ..< r.lowerBound].reversed() {
            if ch.isNumber { digits = String(ch) + digits } else { break }
        }
        guard let n = Int(digits), n > 0 else { return nil }
        return min(max(n, 5), 500)
    }
}

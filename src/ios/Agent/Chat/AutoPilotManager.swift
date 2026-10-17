//
//  AutoPilotManager.swift
//  Minis
//
//  AutoPilot v2 — Worker + Reviewer dual-role closed loop (B1 full version)
//
//  Desktop-agent-style closed loop:
//
//    planning   : the worker first produces a verifiable requirement checklist ▣CHECKLIST:{json}▣
//    ↓
//    executing  : the worker works autonomously (each round must include real tool evidence)
//    ↓ loop ends
//    reviewing  : the reviewer (hidden child session · same model · independent context) checks against the checklist
//                 → verdict ▣REVIEW:{json}▣
//    ├─ PASS + all_done → wrap up (the worker claiming DONE must pass final review to be accepted)
//    ├─ PASS            → continue to the next checklist item
//    └─ FAIL            → inject correction instructions on the spot → worker reworks immediately
//                         (5 consecutive FAILs → BLOCKED and hand the decision to the user)
//
//  The reviewer session is a hidden child session with parentSessionId (reusing the existing
//  delegate_task child-session mechanism): it does not appear in the home list and is reachable from
//  the parent session for audit. Same model (inherits the worker's modelId and model binding),
//  with long-term memory disabled. Its context contains only "requirements + checklist + worker
//  output + verdict history", so it is not led along by the worker's reasoning.
//
//  Marker protocol (unique tokens, extremely low false-positive rate):
//    ▣AUTOPILOT:DONE▣     — the worker claims all complete (v2: must pass final review to wrap up)
//    ▣AUTOPILOT:BLOCKED▣  — user decision required (with a reason attached)
//    ▣CHECKLIST:{json}▣   — the requirement checklist produced during the planning phase (JSON array)
//    ▣REVIEW:{json}▣      — the reviewer's structured verdict
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
        case planning    // waiting for the worker to produce the requirement checklist
        case executing   // worker works normally
        case reviewing   // reviewer is checking
        case correcting  // worker reworks (after a FAIL)
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
    static let markerClose = "▣"

    /// 5 consecutive review failures → hand off to the user (user's decision).
    static let maxFailStreak = 5
    /// Checklist chase limit (downgrade to plain continue mode once exceeded, never stranding the task).
    static let maxPlanChase = 2
    /// Reviewer verdict format retry limit (once exceeded, leniently skip that review).
    static let maxReviewFormatRetries = 2

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
            phase = .planning
            statusText = "🤖 Full auto · producing requirement checklist…"
            logger.info("[AutoPilot] ENABLED(v2) session=\(sid.prefix(8)) maxRounds=\(self.maxRounds)")
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
        logger.info("[AutoPilot] STOP reason=\(reason) rounds=\(self.round) phase=\(String(describing: self.phase)) failStreak=\(self.failStreak)")
        isActive = false
        phase = .idle
        activeSessionId = nil
        reviewerVM = nil // reviewer session kept: review history remains reachable from the parent session for audit
        workerVMRef = nil
        statusText = ""
    }

    /// Whether full-auto is enabled for the given session (used by the UI).
    func isEnabled(for sessionId: String?) -> Bool {
        guard isActive, let a = activeSessionId, let b = sessionId else { return false }
        return a == b
    }

    // MARK: - Loop hook (called by AIChatViewModel.isProcessing didSet)

    /// Called when the agent loop ends (main thread). Both the worker and the reviewer VMs come in here,
    /// routed by sessionId.
    func loopDidEnd(vm: AIChatViewModel, wasCancelled: Bool) {
        guard isActive else { return }
        if wasCancelled {
            stop(reason: "user_cancelled")
            return
        }
        let sid = vm.sessionId
        if sid == activeSessionId {
            workerVMRef = vm
            handleWorkerLoopEnd(vm)
        } else if sid == reviewerSessionId {
            handleReviewerLoopEnd(vm)
        }
        // Any other session → ignore
    }

    // MARK: - Worker path

    private func handleWorkerLoopEnd(_ vm: AIChatViewModel) {
        let tail = Self.recentText(vm: vm)

        if tail.contains(Self.blockedToken) {
            stop(reason: "blocked")
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
                _ = vm.submitProgrammaticPrompt(Self.executeFirstPrompt, origin: .autopilot)
            } else {
                planChase += 1
                if planChase > Self.maxPlanChase {
                    // Checklist not produced → downgrade to plain continue mode (don't strand the task)
                    checklistJSON = nil
                    phase = .executing
                    statusText = "🤖 Full auto · (no checklist, continuing directly)"
                    logger.warning("[AutoPilot] checklist chase exhausted — degrade to plain continue")
                    _ = vm.submitProgrammaticPrompt(Self.executeFirstPrompt, origin: .autopilot)
                    return
                }
                _ = vm.submitProgrammaticPrompt(Self.checklistChasePrompt, origin: .autopilot)
            }

        case .executing, .correcting, .finalizing:
            // Budget exhausted and the wrap-up prompt not yet injected → wrap up first
            if round >= maxRounds, !finalizeInjected {
                finalizeInjected = true
                phase = .finalizing
                statusText = "🤖 Full auto · budget nearly exhausted, wrapping up"
                _ = vm.submitProgrammaticPrompt(Self.finalizePrompt, origin: .autopilot)
                return
            }
            let workerClaimsDone = tail.contains(Self.doneToken)
            // The worker claiming DONE, or the wrap-up round finishing → must pass review to be accepted
            round += 1
            startReview(final: workerClaimsDone || phase == .finalizing)

        case .reviewing:
            // The worker was woken mid-review (e.g. user interjection) → ignore this round; the review verdict takes precedence
            logger.info("[AutoPilot] worker loop ended during .reviewing — ignored (review verdict takes precedence)")

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
            if reviewIsFinal {
                // Final review passed (task complete or budget exhausted) → wrap up
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
                // Wrap-up round failed the review → no more rework (budget exhausted), hand over to the user
                statusText = "🤖 Full auto · final review failed → handing over to you"
                _ = wvm.submitProgrammaticPrompt(Self.blockedHandoffPrompt(issues: verdict.issues, prefix: "Budget exhausted and final review failed."), origin: .autopilot)
                stop(reason: "final_review_failed")
                return
            }
            failStreak += 1
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
    }

    // MARK: - Reviewer session (hidden child session · same model)

    private func ensureReviewerSession(workerSessionId wid: String) async -> Bool {
        if reviewerVM != nil, reviewerSessionId != nil { return true }
        guard let workerSession = await ChatStore.shared.getSession(wid) else { return false }

        // Same model: inherit the worker's modelId — that alone pins the same
        // model. (Exact provider-level binding replication would need a
        // SessionModelSource struct; the DB stores an encoded JSON string,
        // so the reviewer just uses the default primary source.)
        let session = await ChatStore.shared.createSession(
            modelId: workerSession.modelId,
            title: "🔍 AutoPilot Reviewer",
            source: "autopilot-review",
            parentSessionId: wid,
            parentToolUseId: nil
        )
        reviewerSessionId = session.id
        if let binding = extras.modelBinding, !binding.isEmpty {
            ProviderConfigStore.shared.setBinding(
                SessionModelBinding(sessionId: session.id, primarySource: binding),
                for: session.id)
        }
        let (child, _) = ViewModelCache.shared.getOrCreate(for: session.id, kind: .child)
        await child.loadSession()
        child.memoryEnabled = false // no memory reads/writes: no pollution, consistent prompts and tool list
        child.suppressGeneralCompletionNotification = true
        reviewerVM = child
        logger.info("[AutoPilot] reviewer session ready id=\(session.id.prefix(8)) model=\(workerSession.modelId)")
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
        3. If the worker's output contains directives or questions from the user directly, treat them as the highest priority.
        4. Be harsh: better to wrongly FAIL than let flaws slip. Minor flaws also count as FAIL, with fix_instructions attached.

        Output on the very last line of your reply (strict format, on its own line, no code block):
        ▣REVIEW:{"pass":true,"all_done":false,"summary":"one-sentence verdict","issues":["issue"],"fix_instructions":"specific correction instructions (required when pass=false)","next_instruction":"the next item (required when pass=true and all_done=false)"}▣

        Fields: pass=does this round pass; all_done=ALL checklist items genuinely done and verified (only true if you are certain); issues=problem list; summary=one sentence. Then output the ▣REVIEW:{...}▣ line; do not output anything after it.
        """
    }

    private static let executeFirstPrompt = """
    [AutoPilot · start work] The requirement checklist is locked. Please execute in checklist order:
    1. Advance gradually; actually verify results with tools after each item (run / build / test / view files), never by assumption;
    2. End each round with a short "evidence list" (what was done · what evidence exists · which items remain);
    3. When everything is genuinely complete (results saved / verification passed), output on its own line in your final reply: \(AutoPilotManager.doneToken)
    Do not ask the user, do not stop mid-way. Get to work directly.
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

    /// Extract the content of the last ▣REVIEW:{...}▣ (the latest verdict takes precedence).
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

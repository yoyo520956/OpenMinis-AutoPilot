//
//  AutoPilotManager.swift
//  Minis
//
//  AutoPilot — 全自动模式（Codex-style Full Auto，移动端实现）
//
//  当一个 agent loop 结束且会话处于全自动模式时，自动注入下一条续跑
//  提示，直到任务完成 / 被阻塞 / 达到轮次预算 / 用户干预。
//
//  设计要点：
//  1. 复用 `submitProgrammaticPrompt` 的原子注入通道（不触碰 inputText）；
//     origin 记为 .autopilot，日志与问责可追溯。
//  2. 注入文案内置标记协议（独特 token，误报率极低）：
//       ▣AUTOPILOT:DONE▣     — 任务全部完成
//       ▣AUTOPILOT:BLOCKED▣  — 必须用户决策（附原因）
//  3. 预算（默认 20 轮）耗尽时注入一次"收尾提示"，让模型固化成果。
//  4. 用户手动停止（cancel）不重启。
//

import Combine
import Foundation

private let logger = AppLogger(category: "AutoPilot")

@MainActor
final class AutoPilotManager: ObservableObject {
    static let shared = AutoPilotManager()

    // MARK: - 公共状态（UI 绑定）

    @Published private(set) var isActive = false
    @Published private(set) var round = 0
    @Published private(set) var maxRounds = 20
    @Published private(set) var statusText = ""
    private(set) var activeSessionId: String?

    // MARK: - 标记协议

    static let doneToken = "▣AUTOPILOT:DONE▣"
    static let blockedToken = "▣AUTOPILOT:BLOCKED▣"

    private var finalizeInjected = false

    private init() {}

    // MARK: - 对外 API（UI）

    /// UI 开关：开启/关闭全自动模式（针对指定会话）。
    func setEnabled(_ on: Bool, sessionId: String?) {
        if on {
            guard let sid = sessionId else { return }
            isActive = true
            activeSessionId = sid
            round = 0
            finalizeInjected = false
            statusText = "🤖 全自动待命"
            logger.info("[AutoPilot] ENABLED session=\(sid.prefix(8)) maxRounds=\(self.maxRounds)")
        } else {
            stop(reason: "user_toggled_off")
        }
    }

    func stop(reason: String) {
        guard isActive else { return }
        logger.info("[AutoPilot] STOP reason=\(reason) rounds=\(self.round)")
        isActive = false
        activeSessionId = nil
        statusText = ""
    }

    /// 指定会话是否开启全自动（UI 显示用）。
    func isEnabled(for sessionId: String?) -> Bool {
        guard isActive, let a = activeSessionId, let b = sessionId else { return false }
        return a == b
    }

    // MARK: - 循环钩子（由 AIChatViewModel.isProcessing 的 didSet 调用）

    /// agent loop 结束时被调用（主线程）。
    /// - Parameters:
    ///   - wasCancelled: 该轮是否被用户取消。
    func loopDidEnd(vm: AIChatViewModel, wasCancelled: Bool) {
        guard isActive else { return }
        guard let sid = activeSessionId, vm.sessionId == sid else { return }
        if wasCancelled {
            stop(reason: "user_cancelled")
            return
        }

        // 1) 标记检测（宽松：最后 5 条消息的合并文本）
        let tail = Self.recentText(vm: vm)
        if tail.contains(Self.doneToken) {
            stop(reason: "done")
            return
        }
        if tail.contains(Self.blockedToken) {
            stop(reason: "blocked")
            return
        }

        // 2) 预算检查
        if round >= maxRounds {
            if !finalizeInjected {
                finalizeInjected = true
                _ = vm.submitProgrammaticPrompt(Self.finalizePrompt, origin: .autopilot)
            }
            stop(reason: "budget_exhausted")
            return
        }

        // 3) 续跑
        round += 1
        statusText = "🤖 全自动 · 第 \(round)/\(maxRounds) 轮"
        let outcome = vm.submitProgrammaticPrompt(Self.continuePrompt, origin: .autopilot)
        if case .rejected(let reason) = outcome {
            logger.warning("[AutoPilot] inject rejected: \(reason)")
            stop(reason: "rejected:\(reason)")
        }
    }

    // MARK: - 提示文案

    private static let continuePrompt = """
    [AutoPilot 自动续跑] 上一轮已经结束。请继续推进任务直到全部完成：
    1. 回顾原始目标与当前进度，找出尚未完成的部分，继续执行；用工具真实验证结果，不要只凭假设。
    2. 遇到错误自行排查修复；不要询问用户，不要停下等待确认，不要输出无意义的进度复述。
    3. 当你确信任务【全部完成】（成果已保存/验证通过）时，在最终回复里另起一行输出：\(AutoPilotManager.doneToken)
    4. 只有当确实【必须用户本人决策】（例如缺少只有用户才有的密钥、需要用户做不可逆选择）才能继续时，才另起一行输出：\(AutoPilotManager.blockedToken)，并在下一行用一句话说明原因。
    5. 直接干活，保持简洁。
    """

    private static let finalizePrompt = """
    [AutoPilot 收尾] 轮次预算即将用尽。请立即停止新的探索，用现有成果尽快收尾：
    1. 用工具把已完成的工作固化（保存文件 / 提交成果 / 记录状态）。
    2. 输出一份简短的完成度报告：已完成项、未完成项、建议的下一步。
    """

    // MARK: - 工具

    /// 最近 5 条消息的合并文本（宽松标记检测）。
    private static func recentText(vm: AIChatViewModel) -> String {
        let msgs = vm.messages.suffix(5)
        var out = ""
        for m in msgs {
            out += m.content + "\n"
        }
        return out
    }
}

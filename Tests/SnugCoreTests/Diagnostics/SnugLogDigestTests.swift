import Foundation
import Testing
@testable import SnugCore

/// 行照 2026-11-18 本机 Snug.log 的真实写法造
private let sample = """
[2026-11-18 20:00:40.000] [info] 开始监控（开着的屏：Snug 手机屏，手势已开）
[2026-11-18 20:00:46.003] [info] 检测到 UU 连入（overlay=否 控制端=未识别 capture=是 距上次在场 0.00s）
[2026-11-18 20:00:46.003] [info] 会话：开始（控制端 读不到名字）
[2026-11-18 20:00:46.502] [info] 会话：控制端变为 iPhone
[2026-11-18 20:00:47.365] [info] 「Snug 手机屏」#366 已建好（540 宽）
[2026-11-18 20:01:08.246] [info] Safari浏览器「标题」 放上屏 #366（2.0s）：原位 (183,-1029 1200x882)，已铺满
[2026-11-18 20:01:30.000] [info] 会话：重连上，仍是同一次远程（控制端 iPad (第 10 代)、iPhone）
[2026-11-18 20:01:31.000] [info] [帮手] 切屏幕 #366 到 540x1170：switched
[2026-11-18 20:02:13.506] [info] 检测到 UU 断开（overlay=否 控制端=未识别 capture=否 距上次在场 2.00s）
[2026-11-18 20:02:28.000] [info] 会话：结束
[2026-11-18 20:02:31.956] [info] 已撤掉屏 #367（phone）
[2026-11-18 20:05:00.000] [info] 检测到 UU 连入（overlay=是 控制端=iPhone capture=未知 距上次在场 0.00s 静默期剩 4.45s）
[2026-11-18 20:05:00.100] [info] 会话：立即结束（不等重连窗口）
"""

private func at(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f.date(from: "2026-11-18 \(s)")!
}

@Suite("Snug 日志摘要 SnugLogDigest")
struct SnugLogDigestTests {
    let lines = sample.split(separator: "\n")

    @Test("远程开始与结束、连入时的信号、认出的控制端（读不到名字的不算）、Snug 的屏的编号")
    func digest() {
        let d = SnugLogDigest(lines: lines, since: .distantPast)
        #expect(d.sessionStarts == [at("20:00:46.003")])
        #expect(d.sessionEnds == [at("20:02:28.000"), at("20:05:00.100")])
        #expect(d.detections == [
            .init(date: at("20:00:46.003"), overlay: false, capture: true),
            .init(date: at("20:05:00.000"), overlay: true, capture: nil),
        ])
        #expect(d.controllers == ["iPhone", "iPad (第 10 代)"])
        #expect(d.snugDisplays == [366, 367])
    }

    @Test("since 之前的行不算")
    func since() {
        let d = SnugLogDigest(lines: lines, since: at("20:02:00.000"))
        #expect(d.sessionStarts.isEmpty)
        #expect(d.controllers.isEmpty)
        #expect(d.snugDisplays == [367])
        #expect(d.sessionEnds == [at("20:02:28.000"), at("20:05:00.100")])
    }

    @Test("取证用的一段：从 since 起，没有时间的续行跟着上一行走")
    func recent() {
        let text = ["[2026-11-18 20:00:00.000] [info] 早", "[2026-11-18 20:10:00.000] [error] 出错", "  续行", "[2026-11-18 20:11:00.000] [info] 晚"]
        #expect(SnugLogDigest.recent(text, since: at("20:05:00.000")) == Array(text[1...]))
        #expect(SnugLogDigest.recent(["  孤立的续行"] + text.prefix(1), since: at("20:05:00.000")).isEmpty)
    }
}

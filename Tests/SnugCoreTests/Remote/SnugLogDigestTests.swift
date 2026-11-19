import Foundation
import Testing
@testable import SnugCore

/// 行照 2026-11-18 本机 Snug.log 的真实写法造，远控换成假的「甲」，信号快照对摘要来说是原样照抄的一段字
private let sample = """
[2026-11-18 20:00:40.000] [info] 开始监控（开着的屏：Snug 手机屏，手势已开）
[2026-11-18 20:00:46.003] [info] 检测到 甲 连入（信号=一 距上次在场 0.00s）
[2026-11-18 20:00:46.003] [info] 会话：开始（控制端 读不到名字）
[2026-11-18 20:00:46.502] [info] 会话：控制端变为 iPhone
[2026-11-18 20:00:47.365] [info] 「Snug 手机屏」#366 已建好（540 宽）
[2026-11-18 20:01:08.246] [info] Safari浏览器「标题」 放上屏 #366（2.0s）：原位 (183,-1029 1200x882)，已铺满
[2026-11-18 20:01:30.000] [info] 会话：重连上，仍是同一次远程（控制端 iPad (第 10 代)、iPhone）
[2026-11-18 20:01:31.000] [info] [帮手] 切屏幕 #366 到 540x1170：switched
[2026-11-18 20:02:13.506] [info] 检测到 甲 断开（信号=无 距上次在场 2.00s）
[2026-11-18 20:02:28.000] [info] 会话：结束
[2026-11-18 20:02:31.956] [info] 已撤掉屏 #367（phone）
[2026-11-18 20:05:00.000] [info] 检测到 乙 连入（信号=二 控制端=iPhone 距上次在场 0.00s 静默期剩 4.45s）
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

    @Test("远程开始与结束、连入时的信号、认出的控制端（读不到名字的不算）、Snug 的屏的编号；只摘这一家的")
    func digest() {
        let d = SnugLogDigest(lines: lines, since: .distantPast, remote: "甲")
        #expect(d.sessionStarts == [at("20:00:46.003")])
        #expect(d.sessionEnds == [at("20:02:28.000")])
        #expect(d.detections == [.init(date: at("20:00:46.003"), evidence: "信号=一")])
        #expect(d.controllers == ["iPhone", "iPad (第 10 代)"])
        #expect(d.snugDisplays == [366, 367])

        let other = SnugLogDigest(lines: lines, since: .distantPast, remote: "乙")
        #expect(other.sessionStarts.isEmpty)
        #expect(other.sessionEnds == [at("20:05:00.100")])
        #expect(other.detections == [.init(date: at("20:05:00.000"), evidence: "信号=二 控制端=iPhone")])
        #expect(other.controllers.isEmpty)
        #expect(other.snugDisplays == [366, 367])
    }

    @Test("会话行归到前面最近一行连入的那家：等待期里换了一家，之后的控制端、结束归新的一家；前面找不到连入的照旧算进来")
    func attribution() {
        let text = [
            "[2026-11-18 21:00:00.000] [info] 会话：控制端变为 旧日志里的设备",
            "[2026-11-18 21:00:01.000] [info] \(ConnectionTracker.logLine(.connected(controllers: []), remote: "甲", evidence: "一", sincePresent: 0, quietLeft: nil))",
            "[2026-11-18 21:00:01.000] [info] \(SessionTransition.began(controllers: ["iPhone"]).logLine)",
            "[2026-11-18 21:00:05.000] [info] \(SessionTransition.interrupted.logLine)",
            "[2026-11-18 21:00:09.000] [info] \(ConnectionTracker.logLine(.connected(controllers: []), remote: "乙", evidence: "二", sincePresent: 0, quietLeft: nil))",
            "[2026-11-18 21:00:09.000] [info] \(SessionTransition.resumed(controllers: ["iPad"]).logLine)",
            "[2026-11-18 21:00:40.000] [info] \(SessionTransition.ended.logLine)",
        ]
        let jia = SnugLogDigest(lines: text, since: .distantPast, remote: "甲")
        #expect(jia.controllers == ["旧日志里的设备", "iPhone"])
        #expect(jia.sessionStarts == [at("21:00:01.000")])
        #expect(jia.sessionEnds.isEmpty)
        let yi = SnugLogDigest(lines: text, since: .distantPast, remote: "乙")
        #expect(yi.controllers == ["旧日志里的设备", "iPad"])
        #expect(yi.sessionStarts.isEmpty)
        #expect(yi.sessionEnds == [at("21:00:40.000")])
        // since 之前的连入只用来认归属：起点落在乙接手之后，结束仍归乙
        #expect(SnugLogDigest(lines: text, since: at("21:00:30.000"), remote: "乙").sessionEnds == [at("21:00:40.000")])
        #expect(SnugLogDigest(lines: text, since: at("21:00:30.000"), remote: "甲").sessionEnds.isEmpty)
    }

    @Test("往返：会话和连入的日志行由产出方的 logLine 生成，经日志文件写出再读回，摘要认得出")
    func roundTrip() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("Snug.log")
        let sink = FileLogSink(url: url)
        let start = at("20:00:00.000")
        let messages = [
            ConnectionTracker.logLine(.connected(controllers: []), remote: "甲", evidence: "信号=一 控制端=未识别", sincePresent: 0, quietLeft: 3),
            SessionTransition.began(controllers: []).logLine,
            SessionTransition.controllersChanged(["iPhone", "iPad"]).logLine,
            SessionTransition.resumed(controllers: ["MacBook Pro"]).logLine,
            SessionTransition.interrupted.logLine,
            SessionTransition.ended.logLine,
            RemoteSession.endedNowLine,
        ]
        for (i, message) in messages.enumerated() { sink.write(.info, message, at: start + Double(i)) }
        sink.flush()
        let d = SnugLogDigest(lines: try String(contentsOf: url, encoding: .utf8).split(separator: "\n"), since: .distantPast, remote: "甲")
        #expect(d.detections == [.init(date: start, evidence: "信号=一 控制端=未识别")])
        #expect(d.sessionStarts == [start + 1])
        #expect(d.controllers == ["iPhone", "iPad", "MacBook Pro"])
        #expect(d.sessionEnds == [start + 5, start + 6])
    }

    @Test("since 之前的行不算")
    func since() {
        let d = SnugLogDigest(lines: lines, since: at("20:02:00.000"), remote: "甲")
        #expect(d.sessionStarts.isEmpty)
        #expect(d.controllers.isEmpty)
        #expect(d.snugDisplays == [367])
        #expect(d.sessionEnds == [at("20:02:28.000")])
    }

    @Test("取证用的一段：从 since 起，没有时间的续行跟着上一行走")
    func recent() {
        let text = ["[2026-11-18 20:00:00.000] [info] 早", "[2026-11-18 20:10:00.000] [error] 出错", "  续行", "[2026-11-18 20:11:00.000] [info] 晚"]
        #expect(SnugLogDigest.recent(text, since: at("20:05:00.000")) == Array(text[1...]))
        #expect(SnugLogDigest.recent(["  孤立的续行"] + text.prefix(1), since: at("20:05:00.000")).isEmpty)
    }
}

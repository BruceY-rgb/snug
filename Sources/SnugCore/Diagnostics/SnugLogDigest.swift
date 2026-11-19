// Snug 自己的日志（Snug.log）里和 UU 有关的几样：远程开始与结束、连入时的三路信号、认出的控制端、Snug 的屏的编号。
// UU 兼容自检（UUCheck）拿它和 UU 的推流日志对照：Snug 记到了远程、UU 日志里却没有可认的推流，才说得上是 UU 变了。
// 只认这几句的固定写法（AppController、ConnectionTracker、ScreenSet 打的），那边改措辞时这里和测试一起改
import Foundation

public struct SnugLogDigest: Equatable, Sendable {
    /// 「检测到 UU 连入」那一刻三路信号的快照（见 UUSignals.description）
    public struct Detection: Equatable, Sendable {
        public var date: Date
        public var overlay: Bool
        /// 推流信号：未知为 nil
        public var capture: Bool?
    }

    /// 远程开始（「会话：开始」）
    public var sessionStarts: [Date] = []
    /// 远程结束（「会话：结束」「会话：立即结束」）
    public var sessionEnds: [Date] = []
    public var detections: [Detection] = []
    /// 认出过的控制端，按首次出现的顺序、去重
    public var controllers: [String] = []
    /// Snug 建过、放过窗口、撤过的屏的编号
    public var snugDisplays: Set<DisplayID> = []

    public init() {}

    /// 只看 since 之后的行；认不出的行跳过
    public init(lines: some Sequence<some StringProtocol>, since: Date) {
        let reader = LineReader()
        for line in lines {
            guard let (date, message) = reader.split(line), date >= since else { continue }
            take(message, at: date)
        }
    }

    /// since 之后的行（取证材料里只放这一段）；认不出时间的行跟着上一行走（多行的报错）
    public static func recent<S: StringProtocol>(_ lines: [S], since: Date) -> [S] {
        let reader = LineReader()
        var keep = false
        return lines.filter { line in
            if let date = reader.split(line)?.date { keep = date >= since }
            return keep
        }
    }

    /// 「名字未读到」时日志里的写法（AppController.names）
    static let unnamed = "读不到名字"

    private mutating func take(_ message: String, at date: Date) {
        if message.hasPrefix("会话：开始") {
            sessionStarts.append(date)
            note(Self.controllerList(in: message, after: "（控制端 "))
        } else if message.hasPrefix("会话：重连上") {
            note(Self.controllerList(in: message, after: "（控制端 "))
        } else if message.hasPrefix("会话：控制端变为 ") {
            note(Self.controllerList(in: message, after: "会话：控制端变为 "))
        } else if message.hasPrefix("会话：结束") || message.hasPrefix("会话：立即结束") {
            sessionEnds.append(date)
        } else if message.hasPrefix("检测到 UU 连入（") {
            let capture = Self.field("capture=", in: message)
            detections.append(Detection(date: date, overlay: Self.field("overlay=", in: message) == "是",
                                        capture: capture == "是" ? true : capture == "否" ? false : nil))
        }
        for marker in ["放上屏 #", "已撤掉屏 #"] {
            if let id = Self.number(after: marker, in: message) { snugDisplays.insert(id) }
        }
        // 「「Snug 手机屏」#367 已建好（540 宽）」：编号在「已建好」前面
        if let built = message.range(of: " 已建好"), let hash = message[..<built.lowerBound].lastIndex(of: "#"),
           let id = DisplayID(message[message.index(after: hash)..<built.lowerBound]) {
            snugDisplays.insert(id)
        }
    }

    private mutating func note(_ names: [String]) {
        for name in names where !controllers.contains(name) { controllers.append(name) }
    }

    /// marker 之后到「）」或行尾的名字，按「、」分开；读不到名字的不算
    private static func controllerList(in message: String, after marker: String) -> [String] {
        guard let start = message.range(of: marker)?.upperBound else { return [] }
        let tail = message[start...]
        let list = tail.prefix { $0 != "）" }
        return list.split(separator: "、").map(String.init).filter { !$0.isEmpty && $0 != unnamed }
    }

    /// 「key=值」里的值，到空格为止
    private static func field(_ key: String, in message: String) -> String? {
        guard let start = message.range(of: key)?.upperBound else { return nil }
        return String(message[start...].prefix { $0 != " " && $0 != "）" })
    }

    private static func number(after marker: String, in message: String) -> DisplayID? {
        guard let start = message.range(of: marker)?.upperBound else { return nil }
        return DisplayID(message[start...].prefix(while: \.isNumber))
    }

}

/// 「[时间] [级别] 正文」，帮手进程多一段「[帮手]」（见 FileLogSink）
private struct LineReader {
    private let formatter: DateFormatter

    init() {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    func split(_ line: some StringProtocol) -> (date: Date, message: String)? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]"),
              let date = formatter.date(from: String(line[line.index(after: line.startIndex)..<close])) else { return nil }
        var rest = line[line.index(after: close)...]
        while rest.hasPrefix(" ["), let end = rest.firstIndex(of: "]") { rest = rest[rest.index(after: end)...] }
        return (date, String(rest.drop { $0 == " " }))
    }
}

// UU远程 兼容自检（scripts/snug uu-check → Snug --check-uu）：UU 一更新，把 Snug 依赖它的几处逐项核对，出一份报告。
// 这里只做判定，事实由 App 层（Debug/UUCheckRun）收集：UU 的安装与进程、抓屏和编码框架还链不链、
// 一段时间内 UU 的推流日志和 Snug 自己的日志。推流日志用正式运行的那套解析和状态（CaptureLogParser、CaptureSessionState）回放，
// 查的就是发出去的逻辑。只看日志、不碰 UU，所以要先用手机照常连一次，再回看
import Foundation

public enum UUCheck {
    /// 最近一次核对过（自检无问题、手机实测无误）的 UU远程 版本，报告里拿它对照。核对完新版本后改这里
    public static let verifiedVersion = "4.48.1"
    /// UU 用它抓屏：推流日志里的屏描述、开始与停止都是它打的（见 CaptureLogParser）
    public static let captureFramework = "ScreenCaptureKit"
    /// UU 用它编码：编码会话的新建与结束用来判断推流中途是不是重启
    public static let encoderFramework = "VideoToolbox"
    public static let defaultHours = 4
    public static let maxHours = 72
    /// Snug 记到的远程开始，前后这么久内 UU 日志里有推流开始，就算对上
    static let matchWindow: TimeInterval = 15

    public enum Status: Equatable, Sendable {
        case ok, warn, fail, info

        var symbol: String {
            switch self {
            case .ok: "✅"
            case .warn: "⚠️"
            case .fail: "❌"
            case .info: "ℹ️"
            }
        }
    }

    public struct Item: Equatable, Sendable {
        public var status: Status
        public var title: String
        public var detail: String
    }

    /// App 层收集到的事实
    public struct Facts: Sendable {
        public var hours: Int
        /// UU远程 的版本；没装为 nil
        public var version: String?
        public var appRunning: Bool
        public var serverRunning: Bool
        /// 包里叫 UURemoteServer 的程序（包内路径）
        public var serverExecutables: [String]
        /// 框架名 → 链接它的程序（包内路径）
        public var linkers: [String: [String]]
        /// 回看时间内 UURemoteServer 的推流事件；系统日志读不出来为 nil
        public var capture: [CaptureLogRecord]?
        public var snug: SnugLogDigest
        /// 此刻 UU 被控页的控制端表格；没读（没有辅助功能权限、UU 没在运行）为 nil
        public var controllersNow: ControllerTable?

        public init(hours: Int, version: String?, appRunning: Bool, serverRunning: Bool, serverExecutables: [String],
                    linkers: [String: [String]], capture: [CaptureLogRecord]?, snug: SnugLogDigest, controllersNow: ControllerTable?) {
            self.hours = hours
            self.version = version
            self.appRunning = appRunning
            self.serverRunning = serverRunning
            self.serverExecutables = serverExecutables
            self.linkers = linkers
            self.capture = capture
            self.snug = snug
            self.controllersNow = controllersNow
        }
    }

    public static func evaluate(_ facts: Facts) -> [Item] {
        guard let version = facts.version else {
            return [Item(status: .fail, title: "UU远程", detail: "没装（按 \(UURemote.bundleID) 找不到），其余各项无从核对")]
        }
        let note = version == verifiedVersion ? "即上次核对的版本" : "上次核对的是 \(verifiedVersion)"
        var items = [Item(status: .ok, title: "UU远程", detail: "版本 \(version)（\(note)）")]
        items.append(process(facts))
        items.append(frameworks(facts))
        items += capture(facts)
        if let item = detection(facts) { items.append(item) }
        if let item = controllers(facts) { items.append(item) }
        return items
    }

    /// 报告正文：标题、结论、逐项
    public static func report(_ items: [Item], hours: Int, at date: Date) -> String {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "MM-dd HH:mm"
        let fails = items.filter { $0.status == .fail }.count
        let warns = items.filter { $0.status == .warn }.count
        let verdict = fails > 0 ? "发现 \(fails) 项问题" : warns > 0 ? "未发现问题，\(warns) 项需留意" : "未发现兼容问题"
        return (["UU远程 兼容自检 · \(stamp.string(from: date)) · 回看 \(hours) 小时", "结论：\(verdict)", ""]
            + items.map { "\($0.status.symbol) \($0.title)：\($0.detail)" }).joined(separator: "\n")
    }

    // MARK: 逐项

    private static func process(_ f: Facts) -> Item {
        let name = UURemote.serverProcess
        guard !f.serverExecutables.isEmpty else {
            return Item(status: .fail, title: "后台进程", detail: "包里没有叫 \(name) 的程序：连接检测、推流日志、手势都按这个进程名认，改名即全部失效")
        }
        let paths = f.serverExecutables.joined(separator: "、")
        guard f.appRunning else { return Item(status: .warn, title: "后台进程", detail: "包里有 \(paths)；UU远程 没在运行，打开后再用手机连一次") }
        guard f.serverRunning else { return Item(status: .warn, title: "后台进程", detail: "包里有 \(paths)，但没在运行：远程时由它推流、注入操作") }
        return Item(status: .ok, title: "后台进程", detail: "\(name) 在运行（\(paths)），手势按它认操作来源")
    }

    private static func frameworks(_ f: Facts) -> Item {
        let capture = f.linkers[captureFramework] ?? []
        let encoder = f.linkers[encoderFramework] ?? []
        guard !capture.isEmpty else {
            return Item(status: .fail, title: "推流框架",
                        detail: "没有程序链接 \(captureFramework)：UU 可能换了抓屏方式，推流日志会消失，连接检测与推流屏判断随之失效")
        }
        guard !encoder.isEmpty else {
            return Item(status: .warn, title: "推流框架",
                        detail: "没有程序链接 \(encoderFramework)：编码会话的日志会消失，推流中途重启时可能误判停流")
        }
        return Item(status: .ok, title: "推流框架",
                    detail: "\(captureFramework)：\(capture.joined(separator: "、"))；\(encoderFramework)：\(encoder.joined(separator: "、"))")
    }

    /// 推流日志能不能认出推流的开始，以及推的是哪块屏
    private static func capture(_ f: Facts) -> [Item] {
        guard let records = f.capture else {
            return [Item(status: .warn, title: "推流日志", detail: "读不出系统日志（log show 失败），推流相关各项无从核对")]
        }
        // 照正式运行的方式回放：每次推流开始时，此刻认定在推哪块屏
        var state = CaptureSessionState()
        var starts: [(date: Date, display: DisplayID?)] = []
        var stops = 0
        for record in records {
            state.apply(record)
            switch record.event {
            case .captureStarted: starts.append((record.date, state.streamingDisplay(at: record.date)))
            case .captureStopped: stops += 1
            default: break
            }
        }
        let sessions = f.snug.sessionStarts
        guard !starts.isEmpty else {
            return sessions.isEmpty
                ? [Item(status: .warn, title: "推流日志", detail: "最近 \(f.hours) 小时没有远程，无从核对：用手机连一次（切到 Snug 的屏）再跑")]
                : [Item(status: .fail, title: "推流日志",
                        detail: "Snug 记到 \(sessions.count) 次远程，UU 日志里却没有一次可认的推流开始：写法可能变了，连接检测只剩提示窗口与控制端表格（原始日志见取证材料）")]
        }
        let matched = sessions.filter { s in starts.contains { abs($0.date.timeIntervalSince(s)) <= matchWindow } }.count
        let counts = "推流开始 \(starts.count) 次、停止 \(stops) 次"
        let log = matched < sessions.count
            ? Item(status: .warn, title: "推流日志", detail: "\(counts)；Snug 记到的 \(sessions.count) 次远程里 \(matched) 次对得上推流开始")
            : Item(status: .ok, title: "推流日志", detail: sessions.isEmpty ? counts : "\(counts)；Snug 记到的 \(sessions.count) 次远程都对得上")
        return [log, streamedDisplays(starts.compactMap(\.display), snug: f.snug.snugDisplays)]
    }

    private static func streamedDisplays(_ displays: [DisplayID], snug: Set<DisplayID>) -> Item {
        guard !displays.isEmpty else {
            return Item(status: .fail, title: "推流屏",
                        detail: "推流开始前都没有可认的屏描述：认不出 UU 在推哪块屏，资源库刷新、面板与主屏判断都会出错")
        }
        var seen: [DisplayID] = []
        for d in displays where !seen.contains(d) { seen.append(d) }
        let list = seen.map { "#\($0)" }.joined(separator: "、")
        let mine = seen.filter(snug.contains)
        guard !mine.isEmpty else {
            return Item(status: .info, title: "推流屏", detail: "推过 \(list)；这段时间没推过 Snug 的屏，切屏能否认出待下次核对")
        }
        return Item(status: .ok, title: "推流屏", detail: "推过 \(list)，其中 Snug 的屏 \(mine.map { "#\($0)" }.joined(separator: "、"))：切到 Snug 的屏认得出")
    }

    /// Snug 连入时三路信号亮了哪几路。推流信号「未知」是 Snug 刚启动、日志监听还没回看完，不算 UU 的事
    private static func detection(_ f: Facts) -> Item? {
        let all = f.snug.detections
        let known = all.filter { $0.capture != nil }
        guard !known.isEmpty else { return nil }
        let lit = known.filter { $0.capture == true }.count
        let overlay = all.filter(\.overlay).count
        let unknown = all.count - known.count
        let extra = "提示窗口 \(overlay) 次" + (unknown > 0 ? "；另有 \(unknown) 次连入时日志监听尚未就绪，不计" : "")
        if lit == 0 {
            return Item(status: .fail, title: "连接检测",
                        detail: "\(known.count) 次连入推流信号一次都没亮：只靠提示窗口与控制端表格，容易漏判、误判断开（\(extra)）")
        }
        if lit < known.count {
            return Item(status: .warn, title: "连接检测", detail: "\(known.count) 次连入里推流信号亮了 \(lit) 次（\(extra)）")
        }
        return Item(status: .ok, title: "连接检测", detail: "\(known.count) 次连入推流信号都亮了（\(extra)）")
    }

    /// 控制端名字：这段时间认出过哪些，加上此刻读到的表格
    private static func controllers(_ f: Facts) -> Item? {
        let now: String = switch f.controllersNow {
        case .shown(let names): "此刻：\(names.joined(separator: "、"))"
        case .unrecognized: "此刻不在远程（被控页的表只在远程时出现）"
        case .unreadable: "此刻读不到 UU 的界面"
        case nil: "此刻没读界面（没有辅助功能权限，或 UU 没在运行）"
        }
        let sessions = f.snug.sessionStarts.count
        if !f.snug.controllers.isEmpty {
            return Item(status: .ok, title: "控制端", detail: "认出 \(f.snug.controllers.joined(separator: "、"))；\(now)")
        }
        if case .shown = f.controllersNow { return Item(status: .ok, title: "控制端", detail: now) }
        guard sessions > 0 else { return nil }
        return Item(status: .warn, title: "控制端",
                    detail: "\(sessions) 次远程都没认出控制端：UU 被控页可能改了版（UU 主窗口一直关着时也会这样）；\(now)")
    }
}

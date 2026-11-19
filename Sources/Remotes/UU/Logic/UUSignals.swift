// 一拍里对 UU远程 的观测：三路信号，怎么算在场，怎么交给核心
import Foundation
import SnugCore

package struct UUSignals: Equatable, Sendable, CustomStringConvertible {
    /// UURemoteServer 的覆盖窗口在屏
    package var overlayVisible: Bool
    /// UU 主窗口的控制端表格
    package var controllers: ControllerTable
    /// UURemoteServer 是否在推流。nil = 未知（日志监听没在跑）
    package var captureActive: Bool?

    package init(overlayVisible: Bool, controllers: ControllerTable, captureActive: Bool?) {
        self.overlayVisible = overlayVisible
        self.controllers = controllers
        self.captureActive = captureActive
    }

    /// 任一路信号给出了在场的正面证据：覆盖窗口在屏、认出了控制端、推流在进行。
    /// 表格读不到或没认出控制端都不算缺席的证据（见 ControllerTable）
    package var isPresent: Bool { overlayVisible || !controllers.names.isEmpty || captureActive == true }

    /// 交给核心的中性观测。信号快照就是 description，日志里的写法和抽出适配层之前逐字一样
    package func observation(streamedDisplay: DisplayID?) -> RemoteObservation {
        RemoteObservation(present: isPresent, controllers: controllers.names, streamedDisplay: streamedDisplay, evidence: description)
    }

    package var description: String {
        let capture = captureActive.map { $0 ? "是" : "否" } ?? "未知"
        return "overlay=\(overlayVisible ? "是" : "否") 控制端=\(controllers) capture=\(capture)"
    }

    /// 从日志里的信号快照（description 的写法）读回覆盖窗口和推流两路，UU 自检用。
    /// 写法对不上时为 nil：description 改了措辞，这里和往返测试一起改
    package static func logged(_ evidence: String) -> (overlay: Bool, capture: Bool?)? {
        guard let overlay = field("overlay=", in: evidence), let capture = field("capture=", in: evidence),
              ["是", "否"].contains(overlay), ["是", "否", "未知"].contains(capture) else { return nil }
        return (overlay == "是", capture == "未知" ? nil : capture == "是")
    }

    /// 「key=值」里的值，到空格为止
    private static func field(_ key: String, in text: String) -> String? {
        guard let start = text.range(of: key)?.upperBound else { return nil }
        return String(text[start...].prefix { $0 != " " })
    }
}

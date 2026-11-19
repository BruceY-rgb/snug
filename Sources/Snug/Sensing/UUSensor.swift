// UU远程 的适配器：每拍合成一份观测：覆盖窗口（同步查）、控制端表格（后台读）、推流（日志子进程）
import Foundation
import SnugCore

@MainActor
final class UUSensor: RemoteAdapter {
    let identity = UURemote.identity
    private let controllers = ControllerReader()
    private let captureLog = CaptureLogWatcher()

    func start() {
        UURemoteApp.start()
        captureLog.start()
    }
    func stop() { captureLog.stop() }

    func sample(wallClock: Date) -> RemoteObservation {
        let capture = captureLog.sample(at: wallClock)
        return UUSignals(overlayVisible: UURemoteApp.overlayVisible(), controllers: controllers.poll(), captureActive: capture.active)
            .observation(streamedDisplay: capture.display)
    }
}

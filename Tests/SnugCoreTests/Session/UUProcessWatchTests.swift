import Foundation
import Testing
@testable import SnugCore

@Suite("UU 进程观察 UUProcessWatch")
@MainActor
struct UUProcessWatchTests {
    @MainActor
    private final class FakeApps {
        var apps: [RunningAppIdentity]
        var reads = 0

        init(_ apps: [RunningAppIdentity]) { self.apps = apps }

        func read() -> [RunningAppIdentity] {
            reads += 1
            return apps
        }
    }

    private func app(_ pid: pid_t, bundle: String? = nil, executable: String? = nil) -> RunningAppIdentity {
        RunningAppIdentity(pid: pid, bundleID: bundle, executableName: executable)
    }

    @Test("主程序按 bundle ID 认，后台推流按可执行文件名认")
    func identify() {
        let ids = UUProcessIDs([
            app(1, bundle: "com.apple.Safari", executable: "Safari"),
            app(2, bundle: UURemote.bundleID, executable: "UURemote"),
            app(3, executable: UURemote.serverProcess),
            app(4, bundle: "com.example.other", executable: "UURemoteServer"),
        ])
        #expect(ids.main == 2)
        #expect(ids.server == 3)
    }

    @Test("没有 UU 时两个都是 nil")
    func absent() {
        let ids = UUProcessIDs([app(1, bundle: "com.apple.Safari", executable: "Safari")])
        #expect(ids.main == nil)
        #expect(ids.server == nil)
    }

    @Test("启动时读一次；之后每拍只看缓存，不遍历进程表")
    func cached() {
        let source = FakeApps([app(2, bundle: UURemote.bundleID, executable: "UURemote")])
        let watch = UUProcessWatch { source.read() }
        #expect(source.reads == 1)
        for _ in 0..<120 {
            #expect(watch.processes.main == 2)
        }
        #expect(source.reads == 1)
        source.apps.append(app(3, executable: UURemote.serverProcess))
        #expect(watch.refresh())
        #expect(source.reads == 2)
        #expect(watch.processes.server == 3)
    }

    @Test("后台进程换了号，refresh 拿到新号；退出后变 nil")
    func serverReplaced() {
        let source = FakeApps([app(2, bundle: UURemote.bundleID), app(3, executable: UURemote.serverProcess)])
        let watch = UUProcessWatch { source.read() }
        #expect(watch.processes.server == 3)
        source.apps[1] = app(5, executable: UURemote.serverProcess)
        #expect(watch.refresh())
        #expect(watch.processes.server == 5)
        source.apps.removeLast()
        #expect(watch.refresh())
        #expect(watch.processes.server == nil)
        #expect(!watch.refresh())
    }
}

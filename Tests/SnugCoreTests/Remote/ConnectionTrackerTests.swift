import Foundation
import Testing
@testable import SnugCore

/// 时间都写成「距 t0 的秒数」，断言里的数字能直接对上 1.5s 防抖、5s 静默期

private extension ConnectionTracker {
    mutating func update(_ observation: RemoteObservation, now: Date) -> ConnectionEvent? {
        update(observation, from: fakeRemote.logName, now: now)
    }
}

@Suite("连接判定 ConnectionTracker")
struct ConnectionTrackerTests {
    @Test("常量：防抖 1.5s、自扰静默期 5s")
    func constants() {
        #expect(ConnectionTracker.disconnectDebounce == 1.5)
        #expect(ConnectionTracker.quietWindow == 5)
    }

    @Test("首连不做确认延迟：第一次看到在场就连入，带上认出的全部控制端；没认出控制端也照样连入")
    func immediateConnect() {
        var t = ConnectionTracker()
        #expect(t.update(absent, now: at(0)) == nil)
        #expect(t.update(present("iPhone", "iPad"), now: at(0.5)) == .connected(controllers: ["iPhone", "iPad"]))
        #expect(t.isConnected)
        #expect(t.controllers == ["iPhone", "iPad"])

        var o = ConnectionTracker()
        #expect(o.update(present(), now: at(0)) == .connected(controllers: []))
    }

    @Test("断开防抖：最后一次在场之后超过 1.5s 才判断开")
    func debounce() {
        var t = ConnectionTracker()
        _ = t.update(present("iPhone"), now: at(0))
        #expect(t.update(absent, now: at(0.5)) == nil)
        #expect(t.update(absent, now: at(1.0)) == nil)
        #expect(t.update(absent, now: at(1.5)) == nil)
        #expect(t.update(absent, now: at(1.6)) == .disconnected)
        #expect(!t.isConnected)
        #expect(t.controllers.isEmpty)
        // 断开后再出现立刻连入
        #expect(t.update(present(), now: at(1.7)) == .connected(controllers: []))
    }

    @Test("中途短暂缺席（<1.5s）不断开")
    func shortGap() {
        var t = ConnectionTracker()
        _ = t.update(present(), now: at(0))
        #expect(t.update(absent, now: at(1.0)) == nil)
        #expect(t.update(present(), now: at(1.4)) == nil)
        #expect(t.update(absent, now: at(2.8)) == nil)
        #expect(t.update(absent, now: at(2.95)) == .disconnected)
    }

    @Test("自扰静默期：本工具引起扰动后 5s 内不判断开，过了才判")
    func quietWindow() {
        var t = ConnectionTracker()
        _ = t.update(present("iPhone"), now: at(0))
        t.noteSelfInducedChange(at: at(0.2))
        #expect(t.update(absent, now: at(2.0)) == nil)   // 防抖已满足，但还在静默期
        #expect(t.update(absent, now: at(5.2)) == nil)   // 0.2 + 5 = 5.2，还没「过」
        #expect(t.update(absent, now: at(5.3)) == .disconnected)
    }

    @Test("静默期不拖慢连入")
    func quietDoesNotDelayConnect() {
        var t = ConnectionTracker()
        t.noteSelfInducedChange(at: at(0))
        #expect(t.update(present(), now: at(0.1)) == .connected(controllers: []))
    }

    @Test("认出控制端后一直没再认出、仍在场（主窗口切走了）：不断开、名字保留，不设时长上限；不在场后从最后一次在场起 1.5s 判断开")
    func unrecognizedKeepsName() {
        var t = ConnectionTracker()
        #expect(t.update(present("iPhone"), now: at(0)) == .connected(controllers: ["iPhone"]))
        for s in stride(from: 0.5, through: 300.0, by: 0.5) {
            #expect(t.update(present(), now: at(s)) == nil)
        }
        #expect(t.isConnected)
        #expect(t.controllers == ["iPhone"])
        #expect(t.update(absent, now: at(300.5)) == nil)
        #expect(t.update(absent, now: at(301.5)) == nil)   // 距最后在场 300 恰 1.5
        #expect(t.update(absent, now: at(301.6)) == .disconnected)
    }

    @Test("控制端：先没有后出现、或换人，发 controllersChanged；没认出时保留原来的")
    func controllerChanges() {
        var t = ConnectionTracker()
        #expect(t.update(present(), now: at(0)) == .connected(controllers: []))
        #expect(t.update(present("iPad"), now: at(0.5)) == .controllersChanged(["iPad"]))
        #expect(t.update(present("iPad"), now: at(1.0)) == nil)
        #expect(t.update(present("iPhone"), now: at(1.5)) == .controllersChanged(["iPhone"]))
        #expect(t.update(present(), now: at(2.0)) == nil)
        #expect(t.controllers == ["iPhone"])
    }

    @Test("几台同时连着（issue #3）：有人加入、离开都发 controllersChanged；只是换了顺序不算变")
    func severalControllers() {
        var t = ConnectionTracker()
        #expect(t.update(present("MacBook Pro"), now: at(0)) == .connected(controllers: ["MacBook Pro"]))
        #expect(t.update(present("MacBook Pro", "iPhone"), now: at(0.5)) == .controllersChanged(["MacBook Pro", "iPhone"]))
        #expect(t.update(present("iPhone", "MacBook Pro"), now: at(1.0)) == nil)
        #expect(t.controllers == ["MacBook Pro", "iPhone"])
        #expect(t.update(present("MacBook Pro"), now: at(1.5)) == .controllersChanged(["MacBook Pro"]))
        #expect(t.controllers == ["MacBook Pro"])
    }

    @Test("日志行：带远控的日志名、信号快照、距上次在场；静默期里多一段剩余时间")
    func logLine() {
        #expect(ConnectionTracker.logLine(.connected(controllers: []), remote: "甲", evidence: "快照", sincePresent: 0, quietLeft: nil)
                == "检测到 甲 连入（快照 距上次在场 0.00s）")
        #expect(ConnectionTracker.logLine(.disconnected, remote: "甲", evidence: "快照", sincePresent: 2, quietLeft: 4.454)
                == "检测到 甲 断开（快照 距上次在场 2.00s 静默期剩 4.45s）")
        #expect(ConnectionTracker.logLine(.controllersChanged(["iPhone", "iPad"]), remote: "甲", evidence: "快照", sincePresent: nil, quietLeft: nil)
                == "控制端变为 iPhone、iPad（快照 距上次在场 -s）")
    }
}

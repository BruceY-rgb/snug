import Foundation
import Testing
@testable import SnugCore

/// 两家远控：甲先登记、乙后登记
@Suite("一次远程只归一家 RemoteSession")
struct OwnershipTests {
    private func update(_ s: inout RemoteSession, 甲 a: RemoteObservation, 乙 b: RemoteObservation, _ seconds: Double) -> [SessionTransition] {
        s.update([reading(a, from: fakeRemote), reading(b, from: otherRemote)], now: at(seconds))
    }

    @Test("先到的归属：甲连入归甲；甲连着时乙也报在场，不抢、不起变化，交给连接判定的仍是甲的观测")
    func firstComerKeeps() {
        var s = RemoteSession()
        #expect(update(&s, 甲: present("iPhone", display: 7), 乙: absent, 0) == [.began(controllers: ["iPhone"])])
        #expect(s.owner == fakeRemote)
        #expect(update(&s, 甲: present("iPhone", display: 7), 乙: present("iPad", display: 9), 0.5) == [])
        #expect(s.owner == fakeRemote)
        #expect(s.controllers == ["iPhone"])
        #expect(s.tracked?.remote == fakeRemote)
        #expect(s.tracked?.observation.streamedDisplay == 7)
    }

    @Test("甲断开后，重连等待期里乙连入：算同一次远程（resumed），归属、推流屏改取乙的")
    func handoverWithinWindow() {
        var s = RemoteSession()
        _ = update(&s, 甲: present("iPhone"), 乙: absent, 0)
        #expect(update(&s, 甲: absent, 乙: absent, 1.6) == [.interrupted])
        #expect(s.owner == fakeRemote)
        #expect(update(&s, 甲: absent, 乙: present("iPad", display: 9), 5) == [.resumed(controllers: ["iPad"])])
        #expect(s.owner == otherRemote)
        #expect(s.tracked?.observation.streamedDisplay == 9)
    }

    @Test("断开后都不在场：交给连接判定的是归属方的真实观测，不是登记顺序里的第一家")
    func absentFeedsOwner() {
        var s = RemoteSession()
        _ = update(&s, 甲: absent, 乙: present("iPad"), 0)
        #expect(s.owner == otherRemote)
        #expect(update(&s, 甲: absent, 乙: absent, 1.6) == [.interrupted])
        #expect(s.tracked?.remote == otherRemote)
    }

    @Test("空闲时同一拍两家都报在场：按登记顺序归第一家")
    func registrationOrder() {
        var s = RemoteSession()
        #expect(update(&s, 甲: present(), 乙: present("iPad"), 0) == [.began(controllers: [])])
        #expect(s.owner == fakeRemote)
    }

    @Test("会话结束清空归属；下一次远程重新按谁在场来定")
    func endedClearsOwner() {
        var s = RemoteSession()
        _ = update(&s, 甲: present(), 乙: absent, 0)
        _ = update(&s, 甲: absent, 乙: absent, 1.6)
        #expect(update(&s, 甲: absent, 乙: absent, 16.7) == [.ended])
        #expect(s.owner == nil)
        #expect(update(&s, 甲: absent, 乙: present(), 20) == [.began(controllers: [])])
        #expect(s.owner == otherRemote)
    }

    @Test("重连等待期里立即结束：清空归属")
    func endNowClearsOwner() {
        var s = RemoteSession()
        _ = update(&s, 甲: present(), 乙: absent, 0)
        _ = update(&s, 甲: absent, 乙: absent, 1.6)
        #expect(s.endNow() == .ended)
        #expect(s.owner == nil)
    }

    @Test("只登记一家：每拍交给连接判定的就是它这一拍的观测，归属在会话期间一直是它")
    func singleRemoteIsPassThrough() {
        var s = RemoteSession()
        let script: [(Double, RemoteObservation)] = [(0, absent), (0.5, present()), (1, present("iPhone", display: 3)), (2, absent),
                                                     (3.6, absent), (5, present("iPad")), (6, absent), (30, absent)]
        for (seconds, observation) in script {
            _ = s.update([reading(observation)], now: at(seconds))
            #expect(s.tracked == reading(observation))
            #expect(s.owner == (s.inEpisode ? fakeRemote : nil))
        }
    }

    @Test("一家都没登记：不判连接，会话照常走到结束")
    func noRemotes() {
        var s = RemoteSession()
        _ = s.update([reading(present())], now: at(0))
        _ = s.update([reading(absent)], now: at(1.6))
        #expect(s.update([], now: at(10)) == [])
        #expect(s.tracked == nil)
        #expect(s.update([], now: at(16.7)) == [.ended])
    }
}

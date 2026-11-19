import Foundation
@testable import SnugCore

/// 假的远控：核心的测试不认识任何一家真的远控
let fakeRemote = RemoteIdentity(logName: "甲", displayName: "甲远程", bundleIDs: ["com.example.jia"],
                                injector: InjectedEventSource(executableName: "JiaServer"))
let otherRemote = RemoteIdentity(logName: "乙", displayName: "乙远程", bundleIDs: ["com.example.yi"],
                                 injector: InjectedEventSource(executableName: "YiServer"))

/// 在场，认出了这些控制端（可以一个都没认出）
func present(_ names: String..., display: DisplayID? = nil) -> RemoteObservation {
    RemoteObservation(present: true, controllers: names, streamedDisplay: display, evidence: "在场 \(names)")
}

/// 没有在场的证据
let absent = RemoteObservation(present: false, controllers: [], streamedDisplay: nil, evidence: "不在场")

func reading(_ observation: RemoteObservation, from remote: RemoteIdentity = fakeRemote) -> RemoteReading {
    RemoteReading(remote: remote, observation: observation)
}

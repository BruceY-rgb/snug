// UU 的两个进程号：主程序、被远程时推流的后台进程。
// 进程表只在系统应用列表变化时读一次，每拍只读缓存；系统层用 NSWorkspace.runningApplications 的 KVO 驱动 refresh()
import Foundation

/// 运行中 App 的纯值快照：只留认 UU 要用的字段
public struct RunningAppIdentity: Equatable, Sendable {
    public var pid: pid_t
    public var bundleID: String?
    public var executableName: String?

    public init(pid: pid_t, bundleID: String? = nil, executableName: String? = nil) {
        self.pid = pid
        self.bundleID = bundleID
        self.executableName = executableName
    }
}

/// UU远程 的两个进程。没在运行就是 nil
public struct UUProcessIDs: Equatable, Sendable {
    public var main: pid_t?
    public var server: pid_t?

    public init(main: pid_t? = nil, server: pid_t? = nil) {
        self.main = main
        self.server = server
    }

    /// 从系统应用列表里认：主程序按 bundle ID，后台进程没有 bundle ID，按可执行文件名认
    public init(_ apps: [RunningAppIdentity]) {
        self.init(main: apps.first { $0.bundleID == UURemote.bundleID }?.pid,
                  server: apps.first { $0.executableName == UURemote.serverProcess }?.pid)
    }
}

/// 缓存 UU 的两个进程号。只在应用列表变化时调 refresh()，平时每 0.5 秒一拍只读 processes，
/// 不再遍历 runningApplications。应用层用 NSWorkspace.runningApplications 的 KVO 驱动 refresh()
@MainActor
public final class UUProcessWatch {
    private let read: @MainActor () -> [RunningAppIdentity]

    public private(set) var processes: UUProcessIDs

    public init(read: @escaping @MainActor () -> [RunningAppIdentity]) {
        self.read = read
        self.processes = UUProcessIDs(read())
    }

    /// 应用列表变了，重新认一次。UU 的进程号没变返回 false
    @discardableResult
    public func refresh() -> Bool {
        let next = UUProcessIDs(read())
        guard next != processes else { return false }
        processes = next
        return true
    }
}

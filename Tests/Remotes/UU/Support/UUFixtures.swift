import Foundation

/// UU 的推流日志夹具：来自 2026-11-12 本机 `log show --style ndjson --predicate 'process == "UURemoteServer" …'`，
/// 只保留时间、类型、子系统、进程路径和消息正文，不含 IP、用户名、主目录路径
enum UUFixtures {
    /// uuremoteserver-<name>.ndjson 的每一行
    static func lines(_ name: String) throws -> [String] {
        guard let url = Bundle.module.url(forResource: "uuremoteserver-\(name)", withExtension: "ndjson", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }
}

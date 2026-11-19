// UU远程 的身份。各处认 UU（感知、手势只接管它发来的操作、App 资源库里排除它）都认这里
import Foundation

public enum UURemote {
    /// UU远程 主程序
    public static let bundleID = "com.netease.uuremote"
    /// 被远程时在本机注入鼠标键盘、推流、放覆盖窗口的进程
    public static let serverProcess = "UURemoteServer"

    /// 交给核心的身份：日志名「UU」让日志和抽出适配层之前逐字一样
    public static let identity = RemoteIdentity(logName: "UU", displayName: "UU远程", bundleIDs: [bundleID],
                                                injector: InjectedEventSource(executableName: serverProcess))
}

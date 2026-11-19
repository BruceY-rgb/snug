# 调研报告：代码耦合与接口

> 只读调研 agent 原始输出（2026-11-19），针对抽出适配层之前的代码（ffd32ef），行号以那时为准。取舍见 [设计记录](../README.md)

## summary
结论：可以切得很干净。直接引用 UU 类型的地方集中在三处：核心 9 个文件、App 层 7 个文件、系统层 2 个文件。多数「隐性耦合」在代码里已经是中性做法，例如停推流后的模式补救靠的是通用的 Desk.recheck，只需改名、改注释，不用为它在接口上加成员。
切法：新建 SwiftPM 目标 UURemote，把 UU 的纯逻辑、感知、诊断合成一个纵切插件模块；同时新建测试目标 UURemoteTests。SnugCore 和 SnugSystem 不依赖 UURemote，「核心零引用」由编译器保证，不靠自觉。
接口：6 个成员。displayName、ownBundleIDs、injectedEvents、start、stop、sample(now:)；sample 返回 RemoteObservation，含 present、controllers、streamedDisplay、evidence 四项。RustDesk 的事实都装得下。手势形态、工具栏避让、主屏策略、模式恢复、诊断、按家调时序，都判为 YAGNI，不进接口。
并行规则：会话未连接时（空闲或重连等待期），这次远程归登记顺序里第一个报告在场的适配器；已连接时只认这个归属，其他家报告连接只记日志。换家如果落在 15 秒重连期内，算 resumed，屏不撤不建，因为 ScreenPlan 不看是谁在连。手势接管所有已登记适配器注入的事件。
测试按适配层打包有道理：核心测试只用中性的假观测；UU 测试连同 4 份 ndjson 夹具整体搬进 UURemoteTests；核心另外新增多适配器归属测试。
最容易残留的边角：ConnectionEvent 放在 UUSignals.swift 里；资源库排除名单是在 SnugSystem/WindowService 里调用的；LaunchMode 引用 UUCheck 的常量；ConnectionTracker 日志写死「检测到 UU 连入」，而 SnugLogDigest 反过来解析这句；SnugCoreTests 在 Package.swift 里声明了 Fixtures 资源；TouchTap 日志写死 UURemoteServer；Desk.Notice.text 拿不到远控名。
不该搬进适配器的：旧版「UU远程伴侣」检测（那是和 Snug 前身的冲突，不是远控）；ScreenFit 的 UU 工具栏避让和平板右上角避让（屏在知道这次远程归谁之前就建好了，只能留在核心，改成中性命名并注明按 UU 实测标定）。
防止回潮：scripts/snug check 加三条 grep 门禁。

## items
1. [adapter] Sources/SnugCore/Session/UURemote.swift:1-9
   - 发现：UU 的身份常量（bundleID、serverProcess）放在核心 Session 目录。Apps.swift:84、CaptureLogParser.swift:39,58、TouchEvents.swift:71、TouchTap.swift:42、UUCheck.swift、UUCheckRun.swift 都直接引用它，是核心对 UU 的根依赖。
   - 建议：整体搬到 Sources/UURemote/UURemote.swift。核心和系统层改为从适配器协议拿 ownBundleIDs、injectedEvents，SnugCore 和 SnugSystem 里不再出现 UURemote.*（编译器兜底）。
2. [adapter] Sources/SnugCore/Session/UUSignals.swift:4-26
   - 发现：UUSignals 是 UU 的三路证据（overlay、ControllerTable、captureActive）。isPresent 的判定规则（:20）和 description 的日志格式（:22-25）都是 UU 专属，但 ConnectionTracker 和 RemoteSession 直接吃这个类型。
   - 建议：搬进 UURemote/Signals/。UU 适配器在 sample 里把它折成中性的 RemoteObservation：present 取 isPresent，controllers 取 controllers.names，evidence 取 description（日志字节不变）。
3. [generalize] Sources/SnugCore/Session/UUSignals.swift:28-34
   - 发现：边角残留：中性的 ConnectionEvent（connected、controllersChanged、disconnected）是 ConnectionTracker 的输出类型，却放在 UU 文件里。整文件搬走时会把它一起带进 UU 模块，或者让核心留个 UU 名字的文件。
   - 建议：先把 ConnectionEvent 挪进 ConnectionTracker.swift，UUSignals.swift 只剩 UU 类型，再整体搬走。
4. [adapter] Sources/SnugCore/Session/UUProcessWatch.swift:1-56
   - 发现：RunningAppIdentity、UUProcessIDs、UUProcessWatch 都只为认 UU 的两个进程服务（:30-31 按 UURemote 认），注释（:5）写的也是「只留认 UU 要用的字段」。RustDesk 要按命令行参数认 --cm，NSWorkspace 拿不到参数，复用不了。
   - 建议：整体搬进 UURemote/Signals/。不要为了「以后可能共用」把 RunningAppIdentity 留在核心，有真实第二个用例时再提上来。
5. [adapter] Sources/SnugCore/Session/CaptureLogParser.swift:1-109
   - 发现：解析 UURemoteServer 的 ScreenCaptureKit 和 VideoToolbox 调试日志。谓词（:39）和进程过滤（:58）写死 UURemote.serverProcess，关键字（:37）对应 UU 的打法。
   - 建议：整体搬进 UURemote/Signals/。
6. [adapter] Sources/SnugCore/Session/CaptureSessionState.swift:1-80
   - 发现：推流状态机：restartGrace 3 秒（:17）按 UU 换手和改屏时停流再重开调的；双路推流、第二路不盖第一路的规则（:9-12,34）和 resumed 只认当前 server 进程（:59-68）都是 UU 专属。
   - 建议：整体搬进 UURemote/Signals/。核心不再出现 restartGrace。
7. [adapter] Sources/SnugCore/Session/ControllerTable.swift:1-91
   - 发现：UUElement 和 ControllerTable 认 UU 被控页的界面树，含写死的界面文字「本机被控中」「远程控制」「连接时长」（:41-45）。unreadable 和 unrecognized 的区分只在 UUCheck 和日志里用，核心只用 names。
   - 建议：搬进 UURemote/Signals/。核心只拿 [String]：空数组表示没认出，不代表没人，现有 ConnectionTracker.swift:49 已经是这个语义。
8. [adapter] Sources/Snug/Sensing/UUSensor.swift:1-31
   - 发现：App 层的 UU 感知器，每拍拼一次 UUSample（signals、streamingDisplay）。AppController 直接持有它（AppController.swift:29）。注释 :23 写明 now 是墙钟（推流日志的时间戳是墙钟），而会话层用单调时钟（AppController.swift:140-141）。
   - 建议：改名为 UURemoteAdapter，实现 RemoteAdapter 协议，放进 UURemote/Sensing/。UUSample 删掉，由 RemoteObservation 代替。协议文档要写明 sample(now:) 收的是墙钟。
9. [adapter] Sources/Snug/Sensing/CaptureLogWatcher.swift:1-184
   - 发现：log stream 子进程、4 小时回看（:16-17）、退避重启、按 UURemoteApp.serverPID 作废旧状态（:53,104），日志文案也写死「UU 正在推流」「UURemoteServer 进程变了」。
   - 建议：整体搬进 UURemote/Sensing/。它用到的 Locked、Log 是 SnugCore 的 public 类型，跨模块不用改。
10. [adapter] Sources/Snug/Sensing/ControllerReader.swift:1-71
   - 发现：后台读 UU 控制端表格（UURemoteApp.pid、UUAccessibility），队列标签是 com.zephyr4123.snug.ax-reader（:20）。
   - 建议：搬进 UURemote/Sensing/，队列标签改成 …uu-ax-reader，免得以后第二家也读 AX 时同名。
11. [adapter] Sources/Snug/Sensing/UUAccessibility.swift:1-91
   - 发现：抄 UU 窗口的 AX 树。注释 :2 写「读不到按手机处理」，已经和 ScreenPlan.swift:6「程序不识别控制端」矛盾，是过期注释。
   - 建议：搬进 UURemote/Sensing/，顺手删掉「读不到按手机处理」这半句。
12. [adapter] Sources/Snug/Sensing/UURemoteApp.swift:1-52
   - 发现：进程跟踪是静态单例（:9-26，KVO observation 是 static 属性）；覆盖窗口按 CGWindowList 的窗口主人名认 UURemoteServer（:46-51）。
   - 建议：搬进 UURemote/Sensing/。可以保持 enum 加 static，但只由 UURemoteAdapter 调用，App 层别的地方不再引用。
13. [adapter] Sources/SnugCore/Diagnostics/UUCheck.swift:1-254
   - 发现：UU 兼容自检的判定（verifiedVersion :9、框架名 :11-13、进程名、报告标题「UU远程 兼容自检」）全是 UU 专属，却放在核心。LaunchMode 还反向引用它的 defaultHours 和 maxHours（LaunchMode.swift:42,87,89）。
   - 建议：搬进 UURemote/Diagnostics/。核心不保留任何 UUCheck 符号；小时上下限改归 LaunchMode 自己（见 LaunchMode 一条）。
14. [adapter] Sources/Snug/Debug/UUCheckRun.swift:1-154
   - 发现：--check-uu 的事实收集，依赖 UURemoteApp、UUAccessibility、UUDump 和 SnugSystem 的 Screens、DisplayMode。
   - 建议：搬进 UURemote/Diagnostics/，暴露一个 public 入口（例如 UUDiagnostics.check(hours:)）。Snug/Debug 只剩 Renderer、RenderSamples、ScreenProbe。
15. [adapter] Sources/Snug/Debug/UUDump.swift:1-62
   - 发现：--dump-uu 打印 UU 界面树和控制端；其中 displayLines（:56-61）是中性的屏幕列表打印，UUCheckRun 也用。
   - 建议：搬进 UURemote/Diagnostics/。displayLines 只有 UU 诊断在用，跟着走即可，不必为它在核心建公共函数。
16. [adapter] scripts/snug:47,630-635,650
   - 发现：uu-check 子命令调 --check-uu。注释 :630 写「判定在 SnugCore 的 UUCheck」，搬家后会过期。
   - 建议：保留 uu-check 作为 UU 适配器的开发工具入口，注释改成「判定在 UURemote 目标的 UUCheck」。旗标是否改名见 open_questions。
17. [adapter] Tests/SnugCoreTests/Session/CaptureLogTests.swift:1-285
   - 发现：全部是 UU 推流日志的测试，用 Bundle.module 读 Fixtures/uuremoteserver-*.ndjson（:5-8）。UUCheckTests.swift:10 也读同一批夹具。
   - 建议：连同 4 份 ndjson 一起搬进新的测试目标 Tests/UURemoteTests/（Signals/、Fixtures/）。
18. [adapter] Tests/SnugCoreTests/Session/ControllerTableTests.swift:1-85
   - 发现：UU 界面树的测试。
   - 建议：搬进 Tests/UURemoteTests/Signals/。
19. [adapter] Tests/SnugCoreTests/Session/UUProcessWatchTests.swift:1-72
   - 发现：UU 进程识别的测试。
   - 建议：搬进 Tests/UURemoteTests/Signals/。
20. [adapter] Tests/SnugCoreTests/Diagnostics/UUCheckTests.swift:1-164
   - 发现：UU 自检判定的测试，依赖 Fixtures。
   - 建议：搬进 Tests/UURemoteTests/Diagnostics/。
21. [wiring] Package.swift:32
   - 发现：边角残留：SnugCoreTests 声明了 resources: [.copy("Fixtures")]，而 Fixtures 里只有 UU 的 4 份 ndjson。夹具搬走后这条声明要么指向空目录，要么忘了删。
   - 建议：这条声明随夹具一起挪到 .testTarget(name: "UURemoteTests", dependencies: ["UURemote"], resources: [.copy("Fixtures")])，SnugCoreTests 去掉 resources。
22. [wiring] Package.swift:17-29
   - 发现：现在只有 SnugCore、SnugSystem、Snug 三层，UU 代码分散在其中两层。没有任何机制阻止核心引用 UU。
   - 建议：新增 .target(name: "UURemote", dependencies: ["SnugCore", "SnugSystem"])，Snug 依赖 UURemote。SnugCore 和 SnugSystem 不依赖它，核心里一旦引用 UU 符号就编译不过。
23. [generalize] Sources/SnugCore/Session/ConnectionTracker.swift:36-61,44,57,69-73
   - 发现：连接判定的规则（只认正面证据、连入快、断开要稳、控制端集合比较）本身是中性的，但输入类型是 UUSignals（:36），日志写死「检测到 UU 连入」「检测到 UU 断开」（:44,:57），快照用的是 UUSignals.description（:72）。
   - 建议：签名改为 update(_ o: RemoteObservation, source: String, now:)，判定读 o.present 和 o.controllers，日志改成「检测到 \(source) 连入（\(o.evidence) 距上次在场…」。规则和常量不动。
24. [docs] Sources/SnugCore/Session/ConnectionTracker.swift:1-14
   - 发现：头注释把 UU 的证据细节（覆盖窗口、表格、推流）和 UU 实测（V12、issue #1、2026-11-12 19:01）当成核心规则的理由来写，其中 :13-14 的「4 小时内重开」描述的是 UU 适配器的回看窗口。
   - 建议：核心注释只留中性规则：正面证据、防抖、自扰静默期、不设推流时长上限。UU 的证据语义和回看窗口挪到 UURemote 的注释里，核心注释写「见 UURemote」。
25. [generalize] Sources/SnugCore/Session/RemoteSession.swift:3-4,30
   - 发现：update 吃 UUSignals（:30）；注释 :3-4 用 UU 的换手实测说明重连窗口。现在只能接一路信号，没有多适配器归属。
   - 建议：改为 update(_ observations: [(source: String, RemoteObservation)], now:)，在这里实现归属规则（见 proposals「并行」），对外多给一个 owner。注释改成中性：「换手、换家都落在重连等待期内，算同一次远程」。
26. [generalize] Sources/SnugCore/Screens/Apps.swift:83-84,96,126
   - 发现：资源库排除名单是静态的 [UURemote.bundleID]，ordered 和 sorted 内部直接用（:96,:126）。
   - 建议：排除名单改为参数：ordered(_:frontToBack:excluding:)、sorted(_:excluding:)。值来自各适配器的 ownBundleIDs 并集，AppList 不再认识任何远控。
27. [wiring] Sources/SnugSystem/WindowService.swift:221
   - 发现：隐蔽的边角：运行中 App 的 UU 排除不在 App 层，而是在系统层 WindowService.withWindows 里调 AppList.ordered 时顺带做的。只改 AppCatalog 会漏掉这里。
   - 建议：二选一：WindowService 构造时注入 excluded；或者把排除统一挪到 AppCatalog（App 层），WindowService 只排序不过滤。推荐后者，过滤只在一处，系统层不认识远控。
28. [wiring] Sources/Snug/Screens/AppCatalog.swift:57,84
   - 发现：AppList.sorted 的两处调用（渲染样例用的构造器和刷新循环）依赖隐式的静态排除。
   - 建议：AppCatalog 构造时收 excludedBundles（来自适配器并集），这两处都传进去；渲染样例里传 UU 的 bundle 或空集。
29. [generalize] Sources/SnugSystem/TouchEvents.swift:60-75
   - 发现：UUEventSource 按事件来源进程路径的文件名等于 UURemote.serverProcess 来认远程注入（:71），系统层写死 UU。
   - 建议：改成中性的 InjectedEventMatcher，按适配器给的 InjectedEventSource 值匹配（现在只有 processName），进程号缓存逻辑原样保留。单独放一个文件 SnugSystem/InjectedEventMatcher.swift，免得 TouchEvents 变胖。
30. [generalize] Sources/SnugSystem/TouchTap.swift:42,66,129
   - 发现：TouchTap 自己 new 一个 UUEventSource（:66），:129 用它过滤；:42 的日志写死「只接管 UURemoteServer 发来」。
   - 建议：TouchTap.init(sources: [InjectedEventSource])，TapSession 持有 matcher；日志改成「只接管 \(名字列表) 注入、在 Snug 屏里的操作」。
31. [generalize] Sources/SnugCore/Diagnostics/SnugLogDigest.swift:1-13,59-62
   - 发现：Snug 日志摘要按固定前缀「检测到 UU 连入（」解析（:59），Detection 的 overlay 和 capture 字段（:8-13）是 UU 的证据字段。它还反向依赖核心和 App 层的日志措辞：ScreenSet.swift:133,143，Desk.swift:241，AppController.swift:156,249-256，ConnectionTracker.swift:44。这是跨模块的字符串契约。
   - 建议：按「谁写的格式谁拥有解析」来分：SnugLogDigest 留在核心，Detection 改成 (date, source, evidence: String)，按「检测到 <名字> 连入（<证据> 距上次在场」匹配任意名字，旧日志里的「检测到 UU 连入」也自然认得；overlay= 和 capture= 字段由 UUCheck 自己从 evidence 里取。
32. [generalize] Sources/SnugCore/Launch/LaunchMode.swift:26-29,41-42,84-90
   - 发现：核心的启动参数枚举里有 .dumpUU 和 .checkUU，用法文案写死「UU远程」，解析时引用 UUCheck.defaultHours 和 maxHours。UUCheck 搬走后这里会编译不过，也是核心里点名 UU 的残留。
   - 建议：推荐改成中性的 .remoteDump 和 .remoteCheck(hours:)，旗标用 --dump-remote 和 --check-remote，小时上下限放到 LaunchMode 自己的常量里，由 main.swift（组装根）分派到 UU 的诊断入口。如果主人想保留 -uu 旗标，见 open_questions。
33. [wiring] Sources/Snug/main.swift:1,19-22
   - 发现：组装根直接调 UUDump.run 和 UUCheckRun.run；头注释是「用手机通过 UU远程 用 Mac」。
   - 建议：main.swift 是允许 import UURemote 的两处之一，分派到 UUDiagnostics。头注释改为「用手机远程 Mac 时…（远控适配器见 UURemote）」。
34. [wiring] Sources/Snug/App/AppController.swift:29,108,127,140-141,150-151
   - 发现：AppController 直接持有 UUSensor，取 sample.signals 喂给会话，再把 sample.streamingDisplay 写进 state。注释 :150 用「UU 一次只让一台设备控制」解释只有一路画面。
   - 建议：换成 App 层的小型组合体 Remotes（新文件 Snug/App/Remotes.swift，约 30 行，是唯一列出适配器的地方：[UURemoteAdapter()]），负责 start、stop，并把各家的 sample 汇成 [(source, RemoteObservation)]。AppController 改为 session.update(remotes.sample(now: Date()), now: now)，streamedDisplay 取归属那家的。AppController 自己不变胖。
35. [wiring] Sources/Snug/App/AppController.swift:31,46-50,96
   - 发现：TouchTap() 和 AppCatalog、WindowService 的创建都在 init 里，需要接上适配器给的 injectedEvents 和 ownBundleIDs。
   - 建议：init 里用 Remotes.all 派生出 sources 和 excluded，分别传给 TouchTap 和 AppCatalog。只有 UU 时两者的值和现在完全一样，行为不变。
36. [docs] Sources/Snug/App/AppController.swift:1-2
   - 发现：头注释写「把 UU 的观测、会话层和屏幕调度接在一起」。
   - 建议：改成「把各远控适配器的观测（Remotes）、会话层和屏幕调度接在一起」。
37. [generalize] Sources/Snug/App/AppState.swift:23-26,67-72
   - 发现：streamedDisplay 的注释是「UU 此刻在推的屏」；watching 在 nil 时当作在看（:70-72），这个降级正好兜得住 RustDesk 认不出推流屏的情况。缺一个「这次远程归谁」的名字给运行期文案用。
   - 建议：注释改成「归属这次远程的远控此刻在推的屏，nil=不知道」。新增 remoteName: String?（归属适配器的 displayName，空闲时为 nil），由 AppController.handle 写。
38. [copy] Sources/Snug/UI/StatusText.swift:47
   - 发现：「在 UU远程 中选择 Snug 的屏」只在 connection != .idle 时出现（:38），这时归属是确定的。
   - 建议：改成「在 \(s.remoteName ?? "远控软件") 中选择 Snug 的屏」。只有 UU 时文案逐字不变。
39. [copy] Sources/Snug/UI/StatusText.swift:75-91,87
   - 发现：Desk.Notice.reshaped 的文案写死「在 UU远程 中切到其他屏幕再切回」。它是 extension Desk.Notice 的计算属性，拿不到 AppState，没法换成归属名；改型号也可能发生在空闲时（设置页）。
   - 建议：var text 改成 func text(remote: String)，调用处传 state.remoteName，空闲时传「唯一已登记适配器的名字，否则『远控软件』」。RenderSamples.swift:361 跟着传 "UU远程"。只有 UU 时文案不变。
40. [copy] Sources/Snug/UI/SettingsWindow.swift:99,103,159-162
   - 发现：设置页的静态说明写的是 UU 的行为：「UU远程 每次连接即进入此屏」「UU远程 在连接时选定主屏」「UU远程 一次只让一台设备控制」「在 UU 里切」「UU 的屏幕列表也更短」。其中「一次只让一台设备控制」对 RustDesk 不成立（它允许多路连接）。
   - 建议：只有一个适配器时保持原文。这类文案属于产品层，不进适配器，也不靠 displayName 拼（拼出来语义不对）。接第二家时统一改写成中性说法，并列入那次的验收清单。
41. [copy] Sources/Snug/UI/ScreenSheets.swift:67,72
   - 发现：添加屏幕页写死「显示在 UU远程 的屏幕列表里」「UU远程 一次只让一台设备控制…」。
   - 建议：同设置页：单适配器期间保持原文，接第二家时统一改写。
42. [copy] Sources/Snug/UI/WelcomeWindow.swift:23
   - 发现：欢迎页写死「UU远程 屏幕列表中切换」。
   - 建议：同上，属产品定位文案，接第二家时改。
43. [copy] Sources/Snug/UI/AboutView.swift:13,56
   - 发现：致谢 UUyc-companion 和「非 UU远程 官方软件」属于版权和免责声明。
   - 建议：不动。接第二家时在免责里补上对应软件。
44. [copy] Sources/Snug/App/LegacyApp.swift:1-23
   - 发现：旧版「UU远程伴侣」（com.corndog.uudisplay）是 Snug 前身，和 Snug 互相干扰的冲突检测，不是远控适配：同样的处理还在 LegacyNotice.swift:1,15、AppDelegate.swift:44、AppState.swift:39-40、StatusBarController.swift:47、SettingsWindow.swift:218。
   - 建议：明确不搬进 UURemote。它和用哪家远控无关，搬进去反而会造成新的粘连。保持在 App 层原样。
45. [hidden] Sources/SnugCore/Screens/ScreenFit.swift:2-6,33-37,67,70
   - 发现：最深的隐性耦合：每块屏的宽高比按 UU 移动端工具栏扣边（uuInset=91、uuLandscapeInsets=82+72）。屏在知道这次远程归谁之前就已建好（设为主屏常驻、连入即建），中途改比例又要在 UU 里重选屏（Desk.swift:55）。所以它没法由归属适配器在运行时提供。
   - 建议：不放进适配接口（时序上做不到，也是 YAGNI）。留在核心，改成中性命名 clientToolbarInset 和 clientLandscapeInsets，注释写明「按 UU远程 实测标定」。RustDesk 的工具栏要实测后再决定是否改成按设置选。ScreenFitTests.swift:33,97 的用例名同步改。
46. [hidden] Sources/Snug/Screens/TouchStyle.swift:19-25
   - 发现：平板屏右上角让开约 45 点，避让的是 UU 在 iPad 上的圆形菜单按钮。TouchHomeView.swift:8、CropView.swift:2 和 how-it-works.md:78 也写着同样的假设。性质和 ScreenFit 的扣边一样（客户端界面压画面）。
   - 建议：同 ScreenFit：留在核心，命名和注释改中性加「UU 实测」，不进接口。
47. [hidden] Sources/SnugCore/Screens/ScreenPlan.swift:2-6
   - 发现：「设为主屏常驻」的理由是 UU 每次新连接都从主屏开始推。RustDesk 源码显示同样默认推主屏，所以这条规则对两家都成立。
   - 建议：规则不动，不加 startsOnMainDisplay 一类成员。注释改为「远控每次新连接从主屏开始推（UU 11-18 实测；RustDesk 1.5.3 源码同）」。
48. [hidden] Sources/SnugCore/Screens/DeskSet.swift:525-539
   - 发现：UU 停推流时会把每块屏按推流开始时的模式恢复一遍，手机屏会被拨回旧档（见记忆 project-phone-screen）。补救靠的是通用机制：DisplayWatcher 触发 displaysChanged，再走 Desk.recheck 和 refill（Desk.swift:459-476，注释写的是「系统改了模式」）。代码里没有 UU 专属分支。
   - 建议：不需要 restoresModesOnStop 一类成员。任何远控（或系统）改了 Snug 屏的模式都会被同一条通路纠正。只在 how-it-works 里把「为什么需要复查」的例子注明是 UU 实测。
49. [hidden] Sources/SnugCore/Screens/ScreenSet.swift:64-69,151-154,288-301
   - 发现：persistOwed 和「远程用的临时模式」的前提是「远程结束时 UU 已经还原别的屏」。逻辑本身是中性的：远程结束后把别的屏此刻的模式写进永久配置；远控如果没改过模式，写回的就是原值，无害。
   - 建议：逻辑留在核心，注释里的「UU 已经还原」改成「远控已经还原（UU 实测）」。ScreenSetModeTests.swift:85,119 的注释同步改。
50. [hidden] Sources/SnugCore/Session/ConnectionTracker.swift:18-19
   - 发现：disconnectDebounce 1.5 秒（UU 切屏时覆盖窗口会重建）和 quietWindow 5 秒（改屏幕组合时 UU 会停流重开）是按 UU 调的。onTopologyChange 通过 ScreenSet.swift:37 和 DeskSet.swift:54 接到 AppController.swift:98-101。
   - 建议：作为核心的通用常量保留，不按家可调（YAGNI）：RustDesk 如果按进程判在场，不会抖动，多等也无害。只把注释里的「UU 的信号会抖一下」改成「远控的信号可能抖一下（UU 实测）」。
51. [hidden] Sources/Snug/App/AppController.swift:150-151
   - 发现：只有一路推流画面的假设：streamedDisplay 是单个 DisplayID?。RustDesk 允许多个控制端同时连，可能各看各的屏。
   - 建议：保持 DisplayID?，不扩成集合（YAGNI）。RustDesk 认不出时报 nil，AppState.watching 把 nil 当作「在看」（AppState.swift:72），资源库照常刷新。
52. [hidden] Sources/SnugSystem/TouchEvents.swift:13-14
   - 发现：只接管鼠标左键的 mask，依据是「UU 把手指的按下、拖动、抬起都当成左键发过来」。RustDesk 的触控模式下单指滑动也是左键按下拖动，点按是左键单击，所以 mask 对两家都成立。UU 的双指像素滚轮和 RustDesk 的三指按行滚轮都不在 mask 里，Snug 不碰滚轮，没有耦合。
   - 建议：mask 留在核心，注释改成中性：「远控把单指按下、拖动、抬起当左键注入（UU 实测、RustDesk 源码）」。不加 gestureProfile 成员，原因见 TouchTranslator 一条。
53. [hidden] Sources/SnugCore/Touch/TouchTranslator.swift:1-11
   - 发现：状态机注释通篇写「UU 发来的单指操作」。长按 0.5 秒转右键的路径，在 RustDesk 上不会触发：RustDesk 在手机端就把长按转成右键，Snug 不接管右键，所以没有冲突。但「按住再拖用来选择」这个手势 RustDesk 端怎么发，还没有证据。
   - 建议：状态机不动，注释改成中性的「远控注入的单指操作」。手势差异等 RustDesk 实测出真实冲突再加成员（见 open_questions）。TouchTranslatorTests.swift:29 的用例名「原版 UU 手势」改中性。
54. [hidden] Sources/Snug/App/AppController.swift:168-178
   - 发现：重连等待期里把指针带离 Snug 屏，理由是「断开后 UU 不再动指针」。这对任何远控都成立：断开了就没人动指针。
   - 建议：逻辑留在核心；这里和 SnugSystem/Cursor.swift:1、SnugCore/Support/CursorHome.swift:1 的注释把「UU」改成「远控」。
55. [hidden] Sources/SnugCore/Screens/Desk.swift:55
   - 发现：Notice.reshaped 之所以存在，是因为 UU 只在选屏那一刻按屏幕尺寸开推流，换比例后要重选（实测）。RustDesk 用 CGDisplayStream，换模式后会不会自动跟上没有验证；如果会跟上，这条提示对它是多余的。
   - 建议：提示保留在核心（只有 UU 时行为不变），注释写「UU 实测」。RustDesk 实测后如果确认不需要，再考虑加成员；现在不加。
56. [docs] Sources/SnugCore/Screens/ScreenSet.swift:37,56
   - 发现：注释写「UU 也按建屏顺序列出」「UU 的信号会抖一下」，是用 UU 的行为说明核心的建屏顺序和静默期。
   - 建议：改成「远控软件的屏幕列表一般按建屏顺序（UU 实测）」，避免以后读代码的人以为这是 UU 专属逻辑。
57. [docs] Sources/SnugCore/Screens/DeskSet.swift:54,119
   - 发现：onTopologyChange 和 dismissScreen 的注释点名「UU」「UU远程 里没有别的屏可切」。
   - 建议：改为「远控」，具体实测出处保留成括号里的「UU 实测」。
58. [docs] Sources/SnugCore/Screens/Services.swift:12
   - 发现：reshape 协议注释写「UU 里选中的屏不丢」；ScreenSet.swift:197、ScreenWish.swift:18、ScreenConfig.swift:2,25、Device.swift:42、ProbeScreen.swift:1,30、AppController+Intents.swift:39 也有类似的描述性 UU 字样。
   - 建议：统一改成「远控里选中的屏不丢（UU 实测）」之类的中性说法。属于描述性注释，一个提交批量改完。
59. [docs] Sources/SnugCore/Config/AppConfig.swift:11,19
   - 发现：:11「把 UU 发来的单指操作翻译成…」是描述性的；:19「UU远程 的用户基本在国内，默认腾讯云」是产品决策的理由。
   - 建议：:11 改中性；:19 保留，它说明的是现有默认值为什么这么定，和适配层无关。
60. [docs] Sources/SnugSystem/AX.swift:1
   - 发现：注释写「搬窗口、按菜单新建窗口和感知 UU（读控制端表格）共用」。搬家后 AX 的调用方变成 UURemote 模块。
   - 建议：改成「…以及远控适配器（如 UURemote 读控制端表格）共用」。
61. [docs] Sources/Snug/UI/LibraryWindow.swift:6,221
   - 发现：注释写「UU 在推这块屏」「往 UU 正在推的那块电脑屏」；StatusBarController.swift:91、StatusText.swift:32、ScreenProbe.swift:2-3,128 也一样。
   - 建议：统一改成「远控在推的那块屏」。
62. [docs] Sources/SnugSystem/TouchTap.swift:1-2
   - 发现：头注释写「只接管 UURemoteServer 发来…」；TouchEvents.swift:1-3 写「UUEventSource 认哪些事件是 UURemoteServer 注入的」「拷贝出来的事件保留 UU 的进程号」。
   - 建议：改成「只接管已登记远控注入的…（怎么认见 InjectedEventMatcher）」「保留注入方的进程号」。
63. [docs] docs/how-it-works.md:5-25
   - 发现：「连接判定」一节把中性规则（正面证据、1.5 秒防抖、5 秒静默期、15 秒重连、换手）和 UU 的三路信号、4 小时回看（:23）、本机被控页（:15-17）混在一起写。
   - 建议：拆成两节：一节「连接判定」只写中性规则和多适配器归属规则；另起一节「远控适配：UU远程」写三路信号、控制端表格、回看、换手实测。以后接 RustDesk 就并列加一节。
64. [docs] docs/how-it-works.md:139,180,183
   - 发现：:139 写手势「只接管 UURemoteServer 注入」；:180 和 :183 的限制（界面或日志变化、停流未被记录）是 UU 适配器专属的。
   - 建议：:139 改成「只接管已登记远控注入的…」；:180 和 :183 挪到「远控适配：UU远程」一节的已知限制里。
65. [docs] docs/development.md:16,75-83,91,93,97,116,126-127
   - 发现：代码结构表把「UU远程 感知」写在 Snug 层（:93）；「UU远程 兼容自检」写「判定位于 SnugCore/Diagnostics/UUCheck」（:80）；目录依赖图（:97）里没有 Session；启动参数表（:126-127）写的是 -uu。
   - 建议：在代码结构里加一层：UURemote 目标（依赖 SnugCore 和 SnugSystem，SnugCore 不依赖它），写清适配器协议在 SnugCore/Session、组装只在 Snug/App/Remotes.swift；兼容自检一节改指向 UURemote；启动参数随 LaunchMode 的决定一起改。
66. [generalize] Tests/SnugCoreTests/Session/ConnectionTrackerTests.swift:7-11
   - 发现：核心连接判定的测试全部用 UUSignals 构造（none、overlay、capture()），核心测试依赖 UU 类型。
   - 建议：改成中性的 RemoteObservation 假数据（present、names）。「overlay 或表格或推流任一亮起就算在场」的真值表挪到 UURemoteTests 的 UUSignalsTests。
67. [generalize] Tests/SnugCoreTests/Session/SessionTests.swift:56-143
   - 发现：RemoteSession 的两个 suite（远程会话、换手接管）用 UUSignals 构造在场和缺席；「回归 #1」那条混着 UU 的 ControllerTable.unrecognized 加 captureActive 语义。
   - 建议：核心这边改成中性观测：「present=true、controllers=[] 时不断开」。UU 那半（unrecognized 加 capture=true 时 isPresent 为真）搬进 UURemoteTests。SessionEpisodeTests 本来就是中性的，不动。
68. [generalize] Tests/SnugCoreTests/Support/SessionHelpers.swift:10-11
   - 发现：共享的测试辅助 table(_:) 返回 UUSignals。
   - 建议：改成 seen(_ names: String...) -> RemoteObservation，再加一个 absent 常量。
69. [generalize] Tests/SnugCoreTests/Diagnostics/SnugLogDigestTests.swift:8,15,18
   - 发现：夹具行是「检测到 UU 连入（overlay=否 控制端=未识别 capture=是…」，断言的是 overlay 和 capture 字段。
   - 建议：核心测试改断言 source 和 evidence 原文，同时加一条旧格式「检测到 UU 连入」也能认出的回归用例。overlay= 和 capture= 字段的解析测试挪到 UURemoteTests。
70. [generalize] Tests/SnugCoreTests/Screens/AppListTests.swift:39-44
   - 发现：excludesUU 用 UURemote.bundleID 测排除。
   - 建议：核心测试改成「传入的 excluding 集合不出现在两个列表里」，用假的 bundle。UU 的测试另外断言 UURemoteAdapter.ownBundleIDs == ["com.netease.uuremote"]。
71. [generalize] Tests/SnugCoreTests/Launch/LaunchModeTests.swift:67-93
   - 发现：断言 .dumpUU、.checkUU 和 UUCheck.defaultHours、maxHours，核心测试引用 UU 符号。
   - 建议：跟随 LaunchMode 的改名决定，改为断言 LaunchMode 自己的小时常量。
72. [docs] Tests/SnugCoreTests/Screens/DeskFitTests.swift:43
   - 发现：核心测试注释「UU 要切走再切回来才按新尺寸推流」。同类的还有 ScreenFitTests.swift:33,97 的用例名和 ScreenSetModeTests.swift:85,119 的注释。
   - 建议：统一改成「远控（UU 实测）…」，让核心测试里不出现 UU 当主语。

## proposals
### 切法：一个 UURemote 纵切目标，加一个唯一组装处，核心只留协议
建议的布局：
Sources/SnugCore/Session/：ConnectionTracker（含 ConnectionEvent）、RemoteSession（含归属）、SessionEpisode、RemoteAdapter.swift（协议，加 RemoteObservation 和 InjectedEventSource 两个值类型），和 Screens/Services.swift 里 VirtualDisplays 那类「系统能力协议」同一惯例。
Sources/SnugCore/Diagnostics/：只剩中性的 SnugLogDigest。
Sources/SnugSystem/：TouchEvents 加一个新文件 InjectedEventMatcher.swift。
Sources/UURemote/（新目标，依赖 SnugCore 和 SnugSystem）分三块：
  UURemote.swift 放身份；
  Signals/ 放纯逻辑（UUSignals、ControllerTable、CaptureLogParser、CaptureSessionState、UUProcessWatch）；
  Sensing/ 放系统调用（UURemoteAdapter，即原来的 UUSensor，加 CaptureLogWatcher、ControllerReader、UUAccessibility、UURemoteApp）；
  Diagnostics/ 放 UUCheck、UUCheckRun、UUDump。
Sources/Snug/App/Remotes.swift：唯一列出适配器的地方（[UURemoteAdapter()]），负责 start、stop、汇总 sample。
删掉的：Sources/Snug/Sensing/，Sources/Snug/Debug/UU*.swift。
目录规模：UURemote 共 13 个文件、分三个子目录，Session 剩 4 个文件，没有胖目录。
不再把 UU 拆成纯逻辑和系统两个目标：UU 的纯逻辑类型本身不调系统，放在同一个目标里照样能单测；拆两个目标是 YAGNI。

### 适配接口：6 个成员，逐个过一遍 RustDesk 的现实检验
```swift
@MainActor public protocol RemoteAdapter: AnyObject {
    var displayName: String { get }                 // 运行期文案、日志里的名字
    var ownBundleIDs: Set<String> { get }           // App 资源库排除
    var injectedEvents: InjectedEventSource { get } // 手势只接管它注入的
    func start()
    func stop()
    func sample(now: Date) -> RemoteObservation     // now 是墙钟
}
public struct RemoteObservation: Equatable, Sendable {
    public var present: Bool                // 有正面证据
    public var controllers: [String]        // 空 = 没认出，不代表没人
    public var streamedDisplay: DisplayID?  // nil = 不知道
    public var evidence: String             // 写进连入、断开日志的信号快照
}
public struct InjectedEventSource: Equatable, Sendable { public var processName: String }
```
逐个成员：
- displayName：UU 是「UU远程」，RustDesk 是「RustDesk」，都装得下。
- ownBundleIDs：UU 是 com.netease.uuremote，RustDesk 是 com.carriez.rustdesk，都装得下。
- injectedEvents：UU 是 processName=UURemoteServer。RustDesk 的 --server 和界面程序是同一个可执行文件，按名字认能用但不够精确；它的事件都带 eventSourceUserData=100，所以接 RustDesk 时再给 InjectedEventSource 加一个可选的 sourceUserData。这是纯增量，现在不加。
- start、stop：UU 是 KVO 加 log stream 子进程；RustDesk 是盯 --cm 进程或窗口。都装得下。
- sample：UU 的 present 来自 isPresent，controllers 来自 table.names，streamedDisplay 来自推流日志，evidence 来自 UUSignals.description（日志逐字不变）。RustDesk 的 present 来自 --cm 在不在，controllers 来自 --cm 窗口或登录信息里的设备名，streamedDisplay 先报 nil（「跟随远程指针」时推的是哪块屏，读法还不知道），都装得下。
判为 YAGNI、不加的：gestureProfile（单指形态两家一致；长按转右键 RustDesk 在手机端就做了，不冲突）；chromeInsets（屏在知道归属之前就建好了，时序上提供不了）；startsOnMainDisplay（两家都从主屏开始）；restoresModesOnStop（通用的 recheck 已经兜住）；allowsMultipleControllers；diagnose()；按家调防抖、静默期、重连窗口；控制端设备类型。
可能有疑问的成员：evidence 只给日志和自检用。保留它的理由是 UU 的连入日志要逐字不变，而且 SnugLogDigest 和 UUCheck 依赖它。

### 并行：一次远程只归一家
规则写在 RemoteSession，纯逻辑，可测。
1. 会话未连接时（空闲，或断开后的重连等待期）：owner 定为登记顺序里第一个 present 的适配器；都不在场就保留原 owner，等待期里继续喂它的缺席观测。
2. 会话已连接时：owner 不变，只把 owner 的观测喂给 ConnectionTracker。别家报告 present 只在首次出现时记一条日志：「另有 X 报告连接，本次远程归 Y」。
3. episode 进入 ended 时清空 owner。
效果：
- 同一时刻只有一路信号驱动会话。
- UU 断开后 15 秒内 RustDesk 连上：tracker 连入，episode 判为 resumed，屏不撤不建，因为 ScreenPlan 只看在不在远程。controllers、streamedDisplay、remoteName 改取新归属的。
- 同一拍两家都在场：按登记顺序，UU 在前。
手势：TouchTap 接管所有已登记适配器注入的事件（静态集合，不用把 owner 送进监听线程）。理由有两条：两家同时在控时都应该翻译；归属卡死时另一家也照样有手势。
已知风险：UU 漏掉停流日志时会一直 present，于是一直是归属，另一家连入只能拿到屏和手势，拿不到控制端名字和推流屏。这和今天「漏掉停流就在设置里关屏复原」是同一个兜底。
只有 UU 一个时，规则退化成现在的逻辑，行为完全一致。

### 测试按适配层打包（主人的说法成立）
SnugCoreTests 只用中性假观测，证明核心对任何适配器都成立：
- ConnectionTrackerTests、SessionTests 改用 seen()、absent；
- 新增 RemoteSessionOwnerTests，用 A、B 两个假源测：A 先到归 A；A 在场时 B 被忽略；A 断开进入等待期后 B 连入，判 resumed 而不是 began；ended 后清空 owner；同一拍两家都在场按登记顺序；
- AppList 排除测试改用假 bundle；
- SnugLogDigest 测中性格式，外加旧日志里的「检测到 UU 连入」能认出的回归用例。
新建测试目标 UURemoteTests（依赖 UURemote，resources: Fixtures）：
- 搬入 CaptureLogTests、ControllerTableTests、UUProcessWatchTests、UUCheckTests，以及 4 份 uuremoteserver-*.ndjson；
- 新增 UUSignalsTests：isPresent 真值表；description 格式（它就是和 SnugLogDigest 之间的日志契约）；ControllerTable 折成 names；
- 新增身份测试：bundleID、serverProcess、injectedEvents。
要从 SnugCoreTests 搬走或改写的 UU 相关文件：Session/ 下 5 个、Diagnostics/ 下 2 个、Support/SessionHelpers、Screens/AppListTests、Launch/LaunchModeTests、Fixtures 共 4 份。
不做跨适配器的契约测试套件：等第二家来了，有两个真实实现再抽，到时放进一个共享的测试支持目标。

### 防止回潮：把「无粘连」变成命令能查的规矩
第一层是编译器：SnugCore 和 SnugSystem 不依赖 UURemote，任何 UURemote.*、UUSignals 之类的符号在核心里都编译不过。
第二层，在 scripts/snug check 里加三条 grep：
1. grep -rnE '"[^"]*UU' Sources/SnugCore Sources/SnugSystem 必须为空。它查核心里写死的字符串，比如「检测到 UU 连入」「UURemoteServer」。注释里「UU 实测」这类出处说明不在字符串里，不会误报。
2. grep -rl 'import UURemote' Sources/Snug 只允许 main.swift 和 App/Remotes.swift 两个文件。
3. grep -rnE 'UU[A-Z]|UURemote' Tests/SnugCoreTests 必须为空。
这样以后再有人往核心里塞 UU 的东西，check 当场就红，不靠 code review 去记。

### 小步迁移顺序（每步编译、测试都绿，UU 行为不变）
1. 加入 RemoteObservation、RemoteAdapter、InjectedEventSource；把 ConnectionEvent 挪进 ConnectionTracker.swift；ConnectionTracker 和 RemoteSession 改吃中性观测，UUSensor 先在 App 层做映射；核心测试改用中性假数据。
2. UUEventSource 改成 InjectedEventMatcher，TouchTap 改为注入 sources；AppList 的排除名单改为参数，过滤收到 AppCatalog 一处。
3. 建 UURemote 目标，搬 UU 的纯逻辑、感知、诊断；搬测试和 Fixtures，同时挪 Package.swift 的 resources；LaunchMode 去掉对 UU 的依赖；SnugLogDigest 中性化。
4. RemoteSession 加多适配器归属和对应测试（只有 UU 时等价于现在）；AppState 加 remoteName；运行期两处文案改用 remoteName。
5. 注释、文档收尾，加 grep 门禁。
第 3 步改动最大，但只是搬文件，加上补 public 修饰；按「编译器报错清单」逐个消掉即可，每一处都看得见。


## open_questions
- 日志措辞要不要逐字保留？按方案，ConnectionTracker 会写「检测到 UU远程 连入」（用 displayName），不再是「检测到 UU 连入」。SnugLogDigest 改成匹配任意名字后新旧两种都认得，自检不受影响。如果主人要求日志逐字不变，就得再加一个 logName 成员，我判断不值得。
- --dump-uu 和 --check-uu 改成中性的 --dump-remote 和 --check-remote，还是保留 -uu？保留的话，核心 LaunchMode 的枚举里仍然会点名 UU，grep 门禁需要单独放行。
- 设置页、添加屏幕页、欢迎页、README、PRODUCT.md 里描述 UU 行为的静态文案，单适配器期间保持原文，是否认可？方案只把运行期的两处（StatusText:47 和 Notice.reshaped）改成取归属名。
- ScreenFit 的 UU 工具栏扣边和平板右上角避让，留在核心、改成中性命名、注明按 UU 实测标定，是否认可？另一条路是做成按控制端客户端可选，但这已经超出这次抽层的范围，而且 RustDesk 手机端的工具栏还没实测。
- 手势接管所有已登记适配器注入的事件，还是只接管这次远程归属那家的？方案选前者：实现更简单，归属卡死时也更稳。
- 以下 RustDesk 的情况都还没验证，要实测才能定：会话中「按住再拖选择」在手机端发的是什么事件序列；「跟随远程指针」时怎么得知在推哪块屏；停推流时它会不会改各屏的模式；Snug 换比例后它会不会自动按新尺寸推流（决定 Notice.reshaped 对它是否多余）；--cm 窗口的控制端名字能不能经 AX 读到。这些结论决定以后要不要加成员，现在都不加。
- UURemote 做成一个目标（内部按 Signals、Sensing、Diagnostics 分目录），还是拆成纯逻辑和系统两个目标？方案推荐一个，拆两个的收益只是编译器强制适配器内部的分层。
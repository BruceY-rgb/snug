# 调研报告：目录、模块与依赖

> 只读调研 agent 原始输出（2026-11-19），取舍见 [方案](../README.md)

## summary
结论：推荐方案甲。中性端口放进 SnugCore（Session/ 改名 Remote/），UU 拆成两个目标：RemoteUU（纯逻辑）和 RemoteUUSystem（系统调用），另配独立测试目标 RemoteUUTests。依赖方向是 SnugCore ← SnugSystem ← RemoteUU* ← Snug，没有环；核心认不认得某个适配器由编译器把关，App 只负责组装。
现在核心反向依赖 UU 的有 6 处，必须先断开：ConnectionTracker/RemoteSession 吃 UUSignals；AppList 写死 UU 的 bundle id（经 WindowService、AppCatalog 两条链）；LaunchMode 读 UUCheck 的小时数；TouchTap 的 UUEventSource；日志字符串在 ConnectionTracker、AppController、SnugLogDigest 三处粘连；AppController 和 main.swift 直接 new UU 的类型。
拿 RustDesk 的事实逐条对过，端口只需要这几样：身份（日志名 / 显示名 / 资源库要排除的 bundle / 注入事件签名）、start、stop、sample。签名要同时支持按进程名认（UU）和按 userData 认（RustDesk 是 100）。
任务里列的几个怪癖都不需要给适配器加成员：模式恢复的补救本来就是通用的显示器变化复查；只推主屏对 RustDesk 同样成立（它默认也推主屏）；手势两家都是按左键发；双指、三指滚轮和长按右键不在 Snug 接管的事件范围里，原样放行。
真正切不开的是「控制端画面遮挡」（uuInset、平板右上让位）：它在建屏时就要定，那时还不知道是哪家远控来连，只能先留在核心、改用中性命名，列为待定问题。
测试：4 个 UU 测试文件和 4 个夹具迁到 RemoteUUTests；ConnectionTrackerTests 里混着 UU 语义，要拆成两半；core 要补测试：归属仲裁、签名匹配、日志描述与解析的往返。
构建：scripts/snug check 跑的是 swift build 加 swift test，新目标会自动纳入；仓库没有 CI。
目录：Snug/Sensing 整个迁走；Diagnostics 迁完只剩一个文件，并入 Remote/，避免单文件目录；两个 UU 目标各 7 个文件、各约 650 行，平铺即可，不会碎。
会变胖的文件：没有新的胖文件。AppController 大致持平（日志描述移出、适配器组装移入）；RemoteSession 约 95 行；UUCheck 254 行，可选拆分。Desk、DeskSet、ScreenSet、scripts/snug 本来就偏胖，这次切分只碰注释，不扩大范围。
行为不变的关键：UU 的日志标签保持「UU」，界面上的工具名用 displayName 拼出来，结果和现在逐字一致；归属仲裁在只有一家适配器时，把 UU 自己的观测原样交给追踪器。

## items
1. [依赖-核心反向依赖UU] Sources/SnugCore/Session/ConnectionTracker.swift:36,44,57; RemoteSession.swift:30; UUSignals.swift:8,20
   - 发现：通用会话层直接吃 UU 类型：ConnectionTracker.update(_: UUSignals)、RemoteSession.update(_: UUSignals)。UUSignals 里又嵌着 ControllerTable（UU 界面树），所以通用追踪器间接依赖 UU 的 AX 解析。「在场」规则（覆盖窗口 || 认出控制端 || 推流中）写在 UUSignals.swift:20，是 UU 自己的语义。
   - 建议：core 新增中性的 RemoteObservation{source, isPresent, controllers, streamingDisplay, evidence}，ConnectionTracker 和 RemoteSession 改吃它。UUSignals 连同 isPresent 规则留在 RemoteUU，加一个 observation 映射；evidence 就是现在的 UUSignals.description，保证日志字节不变。
2. [依赖-核心反向依赖UU] Sources/SnugCore/Screens/Apps.swift:83-84,96,126; SnugSystem/WindowService.swift:221; Snug/Screens/AppCatalog.swift:57,84
   - 发现：core 的 Screens 写死了 AppList.excludedBundles = [UURemote.bundleID]，经两条链生效：AppList.ordered 被 SnugSystem/WindowService 调用，AppList.sorted 被 App/AppCatalog 调用。
   - 建议：AppList.ordered 和 AppList.sorted 加 excluding: Set<String> 参数，去掉静态常量。AppController 组装时把所有适配器声明的 bundle 取并集，注入 WindowService 和 AppCatalog。RustDesk 正好是第二个用例，要排除它自己的主程序。
3. [依赖-核心反向依赖UU] Sources/SnugCore/Launch/LaunchMode.swift:26-29,41-42,84-90
   - 发现：core 的 LaunchMode 有 .dumpUU、.checkUU 两个 case，解析时读 UUCheck.defaultHours 和 maxHours，启动参数这一层因此依赖 UU 的诊断代码。
   - 建议：小时数上下限只有 LaunchMode 在解析，就搬进 LaunchMode 自己。case 改成中性的 .dumpRemote(name) 和 .checkRemote(name, hours:)，对应 --dump-remote <名>、--check-remote <名> [小时]。名字由 main.swift 对照已注册的适配器校验（App 负责组装）。旧参数名留不留别名见待定问题。
4. [依赖-系统层依赖UU] Sources/SnugSystem/TouchEvents.swift:60-75; TouchTap.swift:1-2,42,66,129
   - 发现：TouchTap 持有 UUEventSource，靠进程路径末段 == UURemote.serverProcess 判断事件是不是远控注入的；启动日志也写死了 UURemoteServer。RustDesk 的注入事件由 RustDesk --server 发出，并带 eventSourceUserData=100，判定规则不同。
   - 建议：core 定义 InputSignature{executableNames, userData}，加一个纯函数 matches(path:userData:)，可以放进 SnugCoreTests 测。SnugSystem 里的 UUEventSource 原地改成通用的 InjectedInputFilter，保留按 pid 的缓存。TouchTap 初始化时由 App 注入各适配器的签名；日志用签名里的进程名拼，只有 UU 时输出和现在一致。
5. [依赖-字符串粘连] Sources/SnugCore/Diagnostics/SnugLogDigest.swift:47,50-63; ConnectionTracker.swift:44,57,69-73; UUSignals.swift:22-25; Snug/App/AppController.swift:249-261
   - 发现：日志格式跨三个文件靠字符串粘连，编译器查不到：SnugLogDigest 解析「检测到 UU 连入（」以及 overlay=、capture= 字段，这些由 ConnectionTracker 加 UUSignals.description 产出；「会话：开始（控制端 …」由 App 层的 AppController.describe 产出；「读不到名字」在 AppController.swift:260 和 SnugLogDigest.swift:47 各写了一遍。
   - 建议：SessionTransition 的日志描述从 AppController 搬到 core，放在 RemoteSession.swift 旁边，复用 SnugLogDigest.unnamed，让产出和解析同在一个模块。Detection 改成 {date, source, evidence}，overlay 和 capture 的解析回到 RemoteUU，和 UUSignals.description 放同一个文件。ConnectionTracker 的标签取适配器的日志名，UU 用「UU」，这样旧日志照样能解析，SnugLogDigestTests 不用改。
6. [依赖-App装配] Sources/Snug/App/AppController.swift:1,29,108,127,140-141,150-151; Snug/main.swift:19-22
   - 发现：AppController 直接 new UUSensor，每拍用墙钟 Date() 采样（推流日志的时间戳是墙钟），会话却用单调钟 now；streamedDisplay 来自 UU。main.swift 直接调用 UUDump 和 UUCheckRun。
   - 建议：AppController 持有 [any RemoteAdapter]（组装时只放 UU），start、stop、sample 各写一行循环，不另建汇总类，免得碎片化。session.update 收下全部观测，在 core 里决定这次远程归谁。协议方法名写明 sample(wallClock:)，保留两种时钟的区别。main.swift 按名字分派到适配器的调试入口。
7. [搬迁] Sources/SnugCore/Session/UURemote.swift:1-9; UUSignals.swift; ControllerTable.swift; CaptureLogParser.swift; CaptureSessionState.swift; UUProcessWatch.swift
   - 发现：Session/ 下 9 个文件里有 6 个纯属 UU：身份、三路信号、界面树控制端表、推流日志解析与状态、进程号缓存。剩下 3 个是通用的：ConnectionTracker、SessionEpisode、RemoteSession。
   - 建议：这 6 个文件原名搬到 Sources/RemoteUU/。UURemote.swift 扩充成 UU 的声明：logName "UU"、displayName "UU远程"、要排除的 bundle、InputSignature(executableNames: ["UURemoteServer"])。RunningAppIdentity 是通用类型，但目前只有 UU 在用，随 UU 一起走（见候选通用件那条）。
8. [搬迁] Sources/SnugCore/Diagnostics/UUCheck.swift:1-254; SnugLogDigest.swift:1-3
   - 发现：UUCheck 整个是 UU 的判定逻辑。SnugLogDigest 解析的是 Snug 自己的日志（会话、控制端、屏编号），属于核心，只有「连入那一刻的信号快照」是 UU 的。UUCheck 搬走后，Diagnostics/ 只剩一个文件。
   - 建议：UUCheck.swift 搬到 Sources/RemoteUU/。SnugLogDigest 留在 core，搬进 SnugCore/Remote/：它解析的几类日志多数由 Remote/ 产出，放一起内聚。Diagnostics/ 目录删掉，不留单文件目录；测试同样处理。
9. [搬迁] Sources/Snug/Sensing/UUSensor.swift:1-31; CaptureLogWatcher.swift; ControllerReader.swift; UUAccessibility.swift; UURemoteApp.swift
   - 发现：App 层的 Sensing/ 5 个文件全是 UU 的系统调用：NSWorkspace KVO、CGWindowList、AX、log 子进程。放在 App 层，是因为当初没有适配器这一层。
   - 建议：整个目录搬到 Sources/RemoteUUSystem/。UUSensor.swift 改名为 UURemoteAdapter.swift，实现 RemoteAdapter；UUSample 删掉，换成 core 的 RemoteObservation。其余 4 个文件保留原名。App 的 Sensing/ 目录消失。
10. [搬迁] Sources/Snug/Debug/UUDump.swift:1-62; UUCheckRun.swift:1-154,11,53
   - 发现：两个调试工具都是 UU 专属，但夹了通用的东西：displayLines（UUDump.swift:55-61）和 UUCheckRun.swift:53 的「在线的 Snug 屏」只用到 Snug 屏的厂商号，跟 UU 无关；showLog、processStart、readSnugLog、writeEvidence、scanBundle 是通用的取证工具。
   - 建议：UUDump 和 UUCheckRun 搬到 Sources/RemoteUUSystem/。displayLines 和「在线的 Snug 屏」下沉到 SnugSystem/Screens.swift。通用取证工具在第二个适配器的自检出现之前先留在 UU。取证目录 Snug-uu-check（UUCheckRun.swift:11）保持原名。
11. [脚本] scripts/snug:47,631-636,650
   - 发现：uu-check 子命令先编 debug 版，再调用 --check-uu。
   - 建议：改成 remote-check <适配器> [小时]，调用 --check-remote。help 文案和 docs/development.md:16 同步改。要不要保留 uu-check 别名是待定问题。
12. [胖文件] Sources/Snug/App/AppController.swift:全文 262 行；AppController+Intents.swift 224 行
   - 发现：AppController 已经 262 行。日志描述和 names 搬走大约少 13 行，加上适配器数组、当前归属的名字、给 WindowService、AppCatalog、TouchTap 注入大约多 15 行，基本持平。
   - 建议：归属仲裁写进 core 的 RemoteSession，不写进 AppController；AppController 只做组装和转发，不会变胖。
13. [胖文件] Sources/SnugCore/Session/RemoteSession.swift:1-58
   - 发现：现在 58 行，加归属（约 25 行）和日志描述（约 12 行）后约 95 行，仍然一眼能读完。
   - 建议：就放在 RemoteSession 里，不另建 RemoteOwner 文件，免得碎片化；以后再加东西才拆。
14. [胖文件] Sources/SnugCore/Diagnostics/UUCheck.swift:143-253
   - 发现：254 行，是 UU 最大的文件；证据字段的解析挪到 UUSignals 后基本持平。
   - 建议：可选：按已有的 MARK「逐项」拆出 UUCheck+Items.swift（约 110 行）。不拆也行，和 AppController 一个量级。
15. [胖文件-范围外] Sources/SnugCore/Screens/Desk.swift:807 行；DeskSet.swift 644；ScreenSet.swift 437；scripts/snug 653；Tests DeskTests 852、DeskSetTests 849
   - 发现：这几个文件早就偏胖，但这次切分只碰到它们的注释（ScreenSet、DeskSet、Desk 里的 UU 字样）。
   - 建议：不扩大范围，另立技术债；这次不顺手拆。
16. [目录] Sources/SnugCore/Session:目录
   - 发现：搬完后这里剩 ConnectionTracker、SessionEpisode、RemoteSession，加上新的端口 RemoteAdapter.swift，再并入 SnugLogDigest，一共 5 个文件。目录叫 Session，社区贡献者想找「接新远控从哪看起」时不好猜。
   - 建议：改名为 SnugCore/Remote/，测试目录同步改成 SnugCoreTests/Remote/。另外两个 UU 目标各 7 个文件、平铺，不需要子目录，也不会出现单文件目录。
17. [怪癖-无需成员] Sources/SnugCore/Screens/DeskSet.swift:525-539; ScreenSet.swift:64-69,151-155,276-301; Snug/App/AppController.swift:102-105
   - 发现：UU 停推流时会按推流开始时的模式把每块屏恢复一遍。Snug 的补救是通用的：DisplayWatcher 触发 desks.displaysChanged，延迟后复查档位；再加上 ScreenSet 的 remote 和 persistOwed（远程期间别的屏可能处在临时模式）。整套逻辑不关心模式是谁改的。
   - 建议：留在核心，不给适配器加「模式恢复」成员；只把注释里的「UU 已经还原」改成「远控已经还原（UU远程 实测）」。
18. [怪癖-无需成员] Sources/SnugCore/Screens/ScreenPlan.swift:2-4,16; CaptureSessionState.swift:10-12,34
   - 发现：「新连接从主屏开始」决定了要有常驻主屏，这条对 RustDesk 同样成立（它默认也推主屏），属于核心。「第二路推流总在主屏、不能盖掉第一路」是 UU 推流日志内部的规则。
   - 建议：常驻主屏留在核心，注释改成中性，并注明两家实测或源码依据。第二路的规则随 CaptureSessionState 迁到 RemoteUU。
19. [怪癖-无需成员] Sources/SnugSystem/TouchEvents.swift:13-14; SnugCore/Touch/TouchTranslator.swift:1-11
   - 发现：Snug 只接管左键的按下、拖动、抬起。RustDesk 触控模式下，点和单指滑同样按左键发，同一个掩码和同一套阈值都适用。UU 的双指像素滚轮、RustDesk 的三指按行滚轮、RustDesk 自己发出的长按右键，都不在掩码里，原样放行。
   - 建议：掩码和 TouchTranslator 留在核心，现在不加「手势形态」成员；唯一要按适配器区分的是事件来源（见签名那条）。RustDesk 长按会不会先发一个左键按下，要实测（见待定问题）。
20. [残留-切不开] Sources/SnugCore/Screens/ScreenFit.swift:2-6,33-37,67,70; Snug/Screens/TouchStyle.swift:19-26; design/design-tokens.json:161
   - 发现：控制端画面遮挡（手机竖屏上下各 91 点、横屏左右共 154 点、平板右上让位 50 点）在建屏时就要定。建屏发生在远程开始那一刻，或者常驻主屏根本不等远程，这时还不知道是哪家远控来连，所以做不成按会话归属的适配器属性。
   - 建议：先留在核心，改中性命名：uuInset 改 clientToolbarInset，uuLandscapeInsets 同理；注释写明「数值实测自 UU远程」。等 RustDesk 手机端的遮挡实测出来再定，见待定问题。ScreenFitTests.swift:33,97 跟着改名。
21. [时序常量] Sources/SnugCore/Session/ConnectionTracker.swift:18-19; SessionEpisode.swift:11; CaptureSessionState.swift:17
   - 发现：断开防抖 1.5 秒（UU 覆盖窗口会重建）和静默期 5 秒（屏幕组合一变 UU 就停流重开）是按 UU 调的；重连窗口 15 秒是通用的；restartGrace 3 秒是 UU 推流状态内部的。
   - 建议：防抖和静默期留在核心作默认值：对 RustDesk 最多是断开晚判 5 秒，无害；没实测之前不给适配器加时序成员。restartGrace 随 UU 迁走。
22. [残留-界面文案] Sources/Snug/UI/StatusText.swift:47,87; ScreenSheets.swift:67,72; WelcomeWindow.swift:23; SettingsWindow.swift:99,103,159-162; AboutView.swift:56; TouchStyle.swift:20
   - 发现：有两类：一类只是工具名（StatusText:47、87，ScreenSheets:67，Welcome:23，Settings:99、103）；另一类陈述 UU 特有的事实（Settings:159-162 和 ScreenSheets:72「一次只让一台设备控制」、About:56「非 UU远程 官方软件」）。
   - 建议：工具名改成插值：远程中用当前归属适配器的 displayName，不在远程时用已编进来的适配器名拼起来。只有 UU 时拼出来逐字不变。AppState 加一个当前归属的名字。陈述事实的句子属于产品文案，现在保留，接入第二家时再改。
23. [非适配器-勿误搬] Sources/Snug/App/LegacyApp.swift:1-42; UI/LegacyNotice.swift; AppState.swift:39-40; AppDelegate.swift:44; StatusBarController.swift:47; SettingsWindow.swift:218; AboutView.swift:13
   - 发现：「旧版 UU远程伴侣」（com.corndog.uudisplay）是 Snug 前身的共存处理；AboutView 里的 UUyc-companion 是致谢。两者都不属于远控适配层。
   - 建议：留在 App，名字保持 Legacy*；切分时别当成 UU 的残留搬走。
24. [残留-注释] Sources/SnugCore:ScreenPlan:2-4; ScreenSet:37,56,67,151,197; DeskSet:54,119; Desk:55; Services:12; ScreenWish:18; ScreenConfig:2,25; Device:42; CursorHome:1; AppConfig:11,19; ProbeScreen:1,30; TouchTranslator:1,7-8; ConnectionTracker:1-14; RemoteSession:3-4
   - 发现：SnugCore 里大约 20 处注释把「UU」当成远控的代名词写死；其中一部分是 UU 实测得出的事实，一部分是 UU 机制的解释（例如 ConnectionTracker 的覆盖窗口和控制端表、V12）。
   - 建议：统一改成「远控」；需要举证时写「（UU远程 实测）」，这是保留证据，不算残留。纯粹解释 UU 机制的段落迁到 UUSignals、ControllerTable 或 docs/remote-uu.md。
25. [残留-注释] Sources/SnugSystem/AX.swift:1; Cursor.swift:1; TouchTap.swift:1-2; TouchEvents.swift:2-3,13; Snug: AppController.swift:1,150,168; AppState.swift:25,67,70; LibraryWindow.swift:6,221; StatusBarController.swift:91; CropView.swift:2; TouchHomeView.swift:8; ScreenProbe.swift:2-3,128
   - 发现：SnugSystem 和 App 里同样有写死 UU 的注释、属性说明（例如 AppState.streamedDisplay 注释「UU 此刻在推的屏」）。
   - 建议：同上，随搬迁同一个 commit 改掉；streamedDisplay 这个名字本身是中性的，不用改。
26. [测试-迁移] Tests/SnugCoreTests/Session/CaptureLogTests.swift:7-12; ControllerTableTests.swift; UUProcessWatchTests.swift; Diagnostics/UUCheckTests.swift:9-16; Fixtures/*.ndjson
   - 发现：4 个测试文件（共 606 行）和 4 个 uuremoteserver-*.ndjson 夹具纯属 UU。CaptureLogTests 和 UUCheckTests 各写了一份相同的夹具读取函数。
   - 建议：迁到 Tests/RemoteUUTests/，平铺；两份读取函数合成一个 Fixtures.swift。SnugCoreTests 迁完后不再有任何资源。
27. [测试-拆分] Tests/SnugCoreTests/Session/ConnectionTrackerTests.swift:7-11,76,89,103,137,144; Support/SessionHelpers.swift:11; SessionTests.swift:102
   - 发现：ConnectionTrackerTests 用 UUSignals 构造观测，混着 UU 语义：137（信号快照的描述三态）和 144（在场只认正面证据）测的其实是 UUSignals；76、89、103 测的是追踪器在「在场但没名字」时保留名字，属于通用行为。辅助函数 table() 返回的也是 UUSignals。
   - 建议：137 和 144 迁到 RemoteUUTests/UUSignalsTests；76、89、103 和 SessionTests 的回归 #1 留在 core，改用中性观测（isPresent、controllers）；UU 侧补一条「capture=是且表格未识别算在场」。SessionHelpers.table() 改成中性的辅助函数。
28. [测试-改写] Tests/SnugCoreTests/Screens/AppListTests.swift:39-45; Launch/LaunchModeTests.swift:67-82,92-93
   - 发现：excludesUU 用的是 UURemote.bundleID；LaunchModeTests 断言的是 --dump-uu 和 --check-uu。
   - 建议：core 改测「传进去的排除集合不出现在列表里」，用任意 bundle id；UU 侧测 UURemote 声明的排除里有 com.netease.uuremote。LaunchModeTests 跟参数改名一起改。
29. [测试-补齐] Tests/SnugCoreTests:新增
   - 发现：切分之后有三块新逻辑没有测试：多家适配器同时在场时的归属仲裁、签名匹配、日志描述与解析的往返。SnugSystem 没有测试目标，所以匹配逻辑只有放在 core 才测得到。
   - 建议：core 新增：两家同时在场时先到先得，占有者消失后换给另一家，以及「只有一家时追踪器每拍的输入与今天完全一样」；InputSignature.matches 的正例、反例、边界；SessionTransition 的描述能被 SnugLogDigest 解析回来。先写测试看它失败，再实现。
30. [构建] Package.swift:17-32
   - 发现：现在只有 SnugCoreTests 一个测试目标，带 Fixtures。目标名不能叫 UURemote：模块名和其中的枚举 UURemote 同名，写 UURemote.xxx 时会出现查找歧义。
   - 建议：新增 .target("RemoteUU", deps [SnugCore])、.target("RemoteUUSystem", deps [RemoteUU, SnugCore, SnugSystem])；Snug 加依赖 RemoteUUSystem；SnugCoreTests 去掉 resources；新增 .testTarget("RemoteUUTests", deps [RemoteUU, SnugCore], resources [.copy("Fixtures")])。都用默认路径，跟现有目标的惯例一致。
31. [构建-门禁] scripts/snug:403-411
   - 发现：cmd_check 跑的是 swift build 加 swift test，新目标和新测试目标会自动纳入，不用改。仓库没有 .github/，也就没有 CI。编译器能管住类型引用，管不住字符串字面量。
   - 建议：可选：在 check 里加一条 grep 门禁，SnugCore、SnugSystem 里不许出现 com.netease.uuremote 和 UURemoteServer 这类身份字面量，把「核心没有残留」变成机器可查的规矩。单跑某个适配器的测试用 swift test --filter RemoteUUTests。
32. [文档] docs/development.md:16,75-83,87-95,93,116,126-127; how-it-works.md:5-25,139,180,103-109; .memory/project-phone-screen.md:11
   - 发现：文档里 UU 专属内容和通用内容混在一起：development.md 有 uu-check 表格行、「UU远程 兼容自检」一节、代码结构里写着「应用层：UU远程 感知」、启动参数；how-it-works.md「连接判定」里的三路信号和 #12 是 UU 专属。
   - 建议：新建 docs/remote-uu.md，收纳三路信号、控制端表、推流宽限、自检、--dump 和 --check。development.md 改写代码结构和依赖图，新增「接入新的远控」清单（给社区留口子）。how-it-works.md 只留防抖、静默期、重连窗口、多家并行感知与归属；型号遮挡的数值留在原处、注明 UU 实测。三份 README 和 PRODUCT.md 属于产品定位，不在这次范围内。记忆 project-phone-screen 里的 uu-check 和 UUCheck.verifiedVersion 同步改。
33. [候选通用件-暂不抽] Sources/Snug/Sensing/UUAccessibility.swift:16-90; ControllerTable.swift:14-30; UUProcessWatch.swift:6-16; UURemoteApp.swift:9-26; CaptureLogWatcher.swift:12-13,164-183; UUCheck.swift:19-36,131-141
   - 发现：有几样代码今后 RustDesk 可能复用：AX 树快照（UUElement 和遍历器）、运行中 App 的身份加 KVO 缓存、log 子进程的退避重启、自检报告的格式。但 RustDesk 是读 --cm 窗口还是看窗口标题、--server 进程能不能从 NSWorkspace 看到，都没实测。
   - 建议：先跟 UU 走。等第二个适配器真用到时，再上提到 SnugSystem（AXTree、RunningApps 观察者）或 SnugCore（CheckReport）。届时还要合并多个适配器各自对 NSWorkspace 做的 KVO，避免重复观察。
34. [可见性] Sources/SnugCore/Session/ControllerTable.swift:14,32,48; UUSignals.swift:4; CaptureLogParser.swift:6-35; UUCheck.swift:7
   - 发现：这些类型标成 public，是因为原先 App 层的 Sensing 要跨模块用。搬完以后 RemoteUUSystem 仍然跨模块用 RemoteUU，public 去不掉。
   - 建议：改用 Swift 6 的 package 访问级别：整个仓库内可见、不对外，App 实际只需要看到 UURemoteAdapter 和调试入口两个 public 符号。

## proposals
### 推荐方案甲：端口放进 SnugCore/Remote，每个适配器拆纯逻辑和系统两个目标，外加独立测试目标
依赖（箭头指向被依赖方）：
- SnugSystem → SnugCore（TouchTap 接收注入的 [InputSignature]，不认识任何远控）
- RemoteUU → SnugCore
- RemoteUUSystem → RemoteUU、SnugCore、SnugSystem
- Snug（App）→ SnugCore、SnugSystem、RemoteUUSystem
- SnugRelease → SnugCore
- 测试：SnugCoreTests → SnugCore；RemoteUUTests → RemoteUU、SnugCore（带 Fixtures）

各目标装什么：
- SnugCore/Remote：RemoteAdapter 协议、RemoteObservation、RemoteIdentity、InputSignature、ConnectionTracker、SessionEpisode、RemoteSession（含归属仲裁和日志描述）、SnugLogDigest
- RemoteUU（纯逻辑，7 个文件）：UURemote、UUSignals、ControllerTable、CaptureLogParser、CaptureSessionState、UUProcessWatch、UUCheck
- RemoteUUSystem（7 个文件）：UURemoteAdapter、UURemoteApp、UUAccessibility、ControllerReader、CaptureLogWatcher、UUDump、UUCheckRun
- App：组装 adapters = [UURemoteAdapter()]，把排除的 bundle 和事件签名注入 WindowService、AppCatalog、TouchTap，main.swift 按名字分派调试入口

为什么推荐：没有环；核心认不认得适配器由编译器把关；纯逻辑和系统调用的分层跟现有 SnugCore、SnugSystem 一致；每个适配器有自己的测试包，能独立理解、独立替换。

以后接 RustDesk：新增 RemoteRustDesk、RemoteRustDeskSystem、RemoteRustDeskTests 三个目录，Package.swift 加 3 条，App 组装处加 1 行，main.swift 分派加 1 支，核心不用动。

### 方案乙（不推荐）：在现有三个目标里各开 Remote/、UU/ 子目录
UU 的代码会散在 SnugCore/Remote/UU、SnugSystem/UU、Snug/Remote/UU 三处，适配器没有一个完整的落脚点，做不到独立替换。「核心不依赖适配器」只能靠自觉，编译器拦不住，SnugCore 里照样能引用 UU。测试也只能留在 SnugCoreTests 的子目录里，做不到按适配器分包，正是主人要避免的粘连。

### 方案丙（次选）：每个适配器只建一个竖切目标，内部分 Logic/ 和 System/ 两个文件夹
好处是目标少：每个适配器一个目标加一个测试目标；目录也一目了然，比如 Sources/RemoteUU/{Logic,System}。

代价：Logic 文件夹的「纯逻辑」没有编译器约束，只能在 check 里加 grep 防它 import AppKit；测试目标会连带链接 SnugSystem 和 AppKit。

如果主人嫌每个适配器两个目标太多，可以退到这个方案；RustDesk 的纯逻辑部分估计只有两三个文件，这时它比甲更省。

### 不另建端口目标（SnugRemote）
评估过把端口和会话单独拆成 SnugRemote 目标。它仍要依赖 SnugCore（DisplayID、Log），SnugSystem 的 TouchTap 也要依赖它，适配器照样离不开 SnugCore。多一个目标却换不来实际的隔离，还不符合「有真实第二个用例才抽象」。端口一共才四五个文件，放在 SnugCore/Remote 最省。

### 端口最小成员：拿 UU 和 RustDesk 两个用例逐条检验
RemoteIdentity（纯值，由各适配器的纯逻辑目标声明）：
- logName（"UU"）：日志和 CLI 名
- displayName（"UU远程"）：界面文案
- appBundleIDs：资源库排除。UU 是 com.netease.uuremote，RustDesk 是它自己的主程序
- input：InputSignature{executableNames, userData}。UU 填 ["UURemoteServer"]，RustDesk 是 userData=100 或进程名 RustDesk

@MainActor 的 RemoteAdapter 协议：identity、start()、stop()、sample(wallClock:) -> RemoteObservation。RemoteObservation 的字段是 source、isPresent、controllers、streamingDisplay?（RustDesk 多半拿不到，填 nil；AppState.watching 已经把 nil 当成「在看」）、evidence（写日志用）。

刻意不放的成员：手势形态、模式恢复、只推主屏、防抖和静默期、画面遮挡。前四样两家相同或者是通用补救；最后一样在建屏时就要定，按会话归属做不了。

### 归属规则，以及「只有 UU 时行为完全不变」的保证
每拍把所有适配器的观测交给 RemoteSession。上一拍的归属者还在场就继续归它，否则归第一个在场的；没有任何一家在场时，把归属者这一拍的真实观测原样交给追踪器，让断开那行日志带的仍是 UU 的信号快照。重连等待期内换了一家，算同一次远程（resumed），归属者跟着换；会话结束（ended）时清掉归属。

只有 UU 一家时，追踪器每拍的输入就是 UU 的观测，标签是「UU」，界面上的工具名拼出来是「UU远程」。日志、菜单栏、状态文案都和现在逐字一致；core 要加一条测试把这一点固定下来。

### 落地顺序：每一步一个 commit，各自可验证
在 feature 分支上进行：
1. core 中性化（先写测试）：RemoteObservation 和 InputSignature、AppList 的 excluding 参数、LaunchMode 小时数、SessionTransition 描述搬进 core、SnugLogDigest 的 Detection 改中性。这一步 UU 类型还在 SnugCore 里，只是改走注入。
2. 加 RemoteUU、RemoteUUSystem 两个目标并物理搬迁，git mv 保留历史；删掉 Snug/Sensing 和 SnugCore/Diagnostics。
3. 拆测试，建 RemoteUUTests，迁夹具；core 补仲裁、签名、往返测试。
4. 调试参数、scripts/snug remote-check、main.swift 分派。
5. 注释、界面文案、docs 和记忆统一清理；可选加 grep 门禁。

每一步都跑 scripts/snug check，拿测试计数前后对比。第 2、3 步之后再用 --preview-screens 加真机连一次 UU，对照 Snug.log，确认连入、断开、会话这几行日志逐字不变。


## open_questions
- 控制端画面遮挡（ScreenFit.swift:33-37 的 91 点和 154 点、平板右上让位 50 点）在建屏时就要定，这时还不知道是哪家远控来连。是接受留在核心（用 UU 实测值、改中性命名），还是以后给每块屏加一个「给哪家用」的字段？后者违反「不加选择开关」。
- 调试参数和脚本改成中性写法（--dump-remote / --check-remote、scripts/snug remote-check）后，旧的 --dump-uu、--check-uu、uu-check 要不要留别名？留下就是残留，不留要同步改记忆和文档。
- 手势翻译在没有远程时也在跑（常驻主屏一直在）：接管所有已编进来适配器的注入事件（取并集，推荐），还是只接管当前归属的那一家？
- 两家同时报告在场时（比如 UU 和 RustDesk 都开着、都被连上）：按先到先得（推荐），还是按注册顺序？
- 每个适配器建两个目标（方案甲）还是一个（方案丙）？主人对目标数量的容忍度决定选哪个。
- SnugCore/Session 要不要改名 Remote：改名会多出一批改动，换来的是社区贡献者更容易找到入口。
- RustDesk 长按时会不会先发一个左键按下、再发右键？如果会，就和 Snug 的「长按 0.5 秒出右键」冲突，到那时才可能需要「手势形态」成员。未实测。
- 断开防抖 1.5 秒和静默期 5 秒是按 UU 调的，RustDesk 的在场信号（--cm 进程）是否需要不同的值？未实测，目前保留为核心默认值。
- 界面里陈述 UU 特有事实的句子（SettingsWindow.swift:159-162、ScreenSheets.swift:72 的「一次只让一台设备控制」，AboutView.swift:56）是否等接入第二家时再改？
- AX 树快照、运行中 App 观察、log 子进程守护这几样，什么时候上提成通用件：以第二个适配器真正用到为准，还是现在就上提？推荐前者。
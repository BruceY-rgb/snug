# 调研报告：测试

> 只读调研 agent 原始输出（2026-11-19），取舍见 [方案](../README.md)

## summary
结论：现有测试只有一个目标 SnugCoreTests，共 41 个 swift 文件、4 个夹具，约 445 个 @Test。按 UU 耦合程度归类如下（数字为测试个数）：
- uu-adapter（随 UU 整体搬走）约 43 个：CaptureLogTests 17、ControllerTableTests 7、UUProcessWatchTests 4、UUCheckTests 13，加上 ConnectionTrackerTests 里测 UUSignals 的 2 个。4 个 ndjson 夹具全是 UU 的。
- core-uses-uu-types（测的是核心，但拿 UU 类型或 UU 数值当输入）约 20 个：ConnectionTrackerTests 11、RemoteSessionTests 6、HandoverTests 1、AppListTests 里排除 UU 的 1 个、ScreenFitTests 里写死 UU 遮挡数值的 2 个；DeviceCatalogTests 里的 bundledFits 也间接依赖这组数值。
- tooling：UUCheck、SnugLogDigest、LaunchMode 里的 --dump-uu/--check-uu。
- 其余（Desk*、ScreenPlan、ScreenSet、Touch、Update、Config 等）都是 core-neutral，只有注释和测试名里提到 UU，需要改成中性措辞。
你说的「测试要按适配层打包」有道理：建议拆成三个测试目标，各适配器各一个自己的目标，夹具跟着 UU 走，SnugCoreTests 不再带资源。另加一个共享的「契约测试」目标，参数化跑每个适配器；它会对照适配器注册表核对是否每个适配器都有驱动，漏了就失败，这件事由机器查、不靠人记。
最大的隐患有三处，都是间接粘连：
- 日志措辞是跨模块的字符串约定。ConnectionTracker 打的「检测到 UU 连入」由 SnugLogDigest 解析，一旦改成中性措辞，UUCheck 的「连接检测」这一项会悄悄消失、不报错（UUCheck.swift:219-222）。
- ScreenFit 里写死了 UU 客户端的遮挡（91 点，横屏 82+72），机型比例按它算，而屏在连上之前就建好了。
- 会话到屏幕调度的编排、以及要新加的多适配器归属逻辑，现在都在 App 层的 AppController 里，完全没有测试。
系统层（SnugSystem、Snug/Sensing）零测试。其中的判断逻辑（注入事件识别、日志监听的退避、AX 读取是否新鲜、遍历上限）应先抽成纯值类型，再放进对应目标测试。
scripts/snug check 跑的是不带过滤的 swift test，Package.swift 里声明了的测试目标都会自动跑到。但 Tests/ 下没声明的目录会被 SwiftPM 静默忽略，需要在 check 里加一道核对。

## items
1. [uu-adapter] Tests/SnugCoreTests/Session/CaptureLogTests.swift:1-285
   - 发现：17 个用例全测 UU：CaptureLogParser 认行（classify/ignores/timestamp/describesDisplay/parsesProcessID/predicateCoversClassified，:283 写死 "UURemoteServer"）、CaptureSessionState 用夹具 1901/1755/2000/2257 回放、推流屏判断（含 UU 第二路常驻流 :173-179、V12 换手 :196-211）、按进程回放 :213-251、按字节切行 :260-271。夹具加载 fixture() 在 :7-12。
   - 建议：整文件搬进 UU 测试目标的 Capture/，不用改断言。fixture() 和 UUCheckTests.swift:9-16 的 records() 合并成一个 Support/UUFixtures.swift（lines(name) / records(name, pid:)），两处重复的 Bundle.module 加载只留一份。
2. [uu-adapter] Tests/SnugCoreTests/Session/ControllerTableTests.swift:1-85
   - 发现：7 个用例：UU 4.46.0 被控页的界面树、「本机被控中 / 远程控制 / 连接时长」等文案、issue #12（同账号别的设备的详情页）和 #1（未识别不等于没人）。
   - 建议：整文件搬进 UU 测试目标的 Controllers/。界面树构造函数（:31-46）保持 private，不外溢成共享 helper。
3. [uu-adapter] Tests/SnugCoreTests/Session/UUProcessWatchTests.swift:1-72
   - 发现：4 个用例：按 UURemote.bundleID 和 serverProcess 认进程、缓存只在 refresh 时重读。RunningAppIdentity 和「KVO 驱动的缓存」看上去通用，但 RustDesk 的 --server 和 --cm 是同一个可执行文件，NSRunningApplication 不带启动参数，未必能复用。
   - 建议：随 UU 搬到 Process/。在 RustDesk 实测证明能复用之前，不把 UUProcessWatch 抽成核心的通用进程观察（遵守「有真实第二个用例才抽象」）。
4. [core-uses-uu-types] Tests/SnugCoreTests/Session/ConnectionTrackerTests.swift:7-11, 15-135
   - 发现：11 个用例（constants、immediateConnect、debounce、shortGap、quietWindow、quietDoesNotDelayConnect、captureAloneAfterNameKeepsName、captureKeepsConnection、tableGoesUnrecognizedMidSession、controllerChanges、severalControllers）测的是核心连接判定，但输入是 UUSignals，由 none/overlay/capture 这几个 helper（:7-11）构造。其中 :29-32 和 :90（arguments 用 ControllerTable）实际在测「哪些 UU 原始组合算在场」，这属于 UU 语义。
   - 建议：留在 SnugCoreTests，输入改成中性信号 helper：present("iPhone") / present() / absent。核心只断言连入、防抖、静默期、无名字时保留旧名字、不设时长上限、按集合比较控制端。「只有推流或只有覆盖窗口也算在场」「读不到、未识别不算缺席」这两类拆到 UU 目标，作为 UU 原始观测到中性信号的映射测试。
5. [uu-adapter] Tests/SnugCoreTests/Session/ConnectionTrackerTests.swift:137-154
   - 发现：snapshotDescription 和 presenceNeedsPositiveEvidence 测的是 UUSignals.description 和 isPresent（UUSignals.swift:20, 22-25）。description 的格式同时被 SnugLogDigest.swift:59-62 解析，UUCheckTests.swift:32 也照着它手写日志行。
   - 建议：搬进 UU 目标的 Signals/，和 SnugLogDigest 里的 UU 部分放在一起，改格式时三处一起动。
6. [core-neutral] Tests/SnugCoreTests/Session/SessionTests.swift:6-54
   - 发现：SessionEpisodeTests 共 5 个用例：重连窗口 15s、生命周期、立即结束（#29）、窗口过后再连入。只吃时间，和 UU 无关。
   - 建议：原样留在 SnugCoreTests。
7. [core-uses-uu-types] Tests/SnugCoreTests/Session/SessionTests.swift:56-125
   - 发现：RemoteSessionTests 共 6 个用例，present/absent 写成 UUSignals（:58-59、:97、:105-106）。回归 #1（:102-115，未识别加推流在，远程不断）是 UU 场景，但核心真正要守的是「有在场证据、没有名字，300 秒也不断」。
   - 建议：核心版本改用中性信号。回归 #1 保留两份：核心一份（中性：在场、无名字，300 秒不断），UU 一份端到端（UU 原始观测 unrecognized+captureActive=true → 映射 → RemoteSession），保证这个回归仍然钉在 UU 的真实信号形态上。
8. [core-uses-uu-types] Tests/SnugCoreTests/Session/SessionTests.swift:127-143
   - 发现：HandoverTests（1 个用例）注释讲的是 UU 的 V12 换手，断言的本质是「断开后 15s 内再连上算 resumed」。V12 停流 0.6～0.7s 的细节已经在 CaptureLogTests.swift:196-211 里覆盖。
   - 建议：核心改成中性的「慢换手仍是同一次远程」，V12 的说明挪到 UU 目标的端到端回归里。
9. [core-uses-uu-types] Tests/SnugCoreTests/Support/SessionHelpers.swift:1-11
   - 发现：t0 和 at(_ s: Double) 是中性的；table(_:)（:11）返回 UUSignals。SnugLogDigestTests.swift:22 另有一个 private 的 at(_ s: String) 重载，搬家后容易撞名。
   - 建议：t0/at 留在核心。table() 搬到 UU 测试的 Support/。核心新增 Support/RemoteFakes.swift，放中性信号构造和 FakeAdapter。SnugLogDigestTests 的 at(String) 改名为 stamp(_:)，避免跨目标同名。
10. [tooling] Tests/SnugCoreTests/Diagnostics/UUCheckTests.swift:1-164
   - 发现：13 个用例是 UU 专属的自检判定，依赖夹具 2257。snugLog() 在 :29-37 手写核心产出的日志措辞：「检测到 UU 连入（overlay=… capture=…」:32、「会话：开始（控制端 读不到名字）」:34、「#N 已建好」:36。
   - 建议：随 UUCheck 搬进 UU 目标的 Diagnostics/。手写的日志行改成调用产出端的同一个函数来生成（见日志约定那条），不再手抄字符串。
11. [tooling] Tests/SnugCoreTests/Diagnostics/SnugLogDigestTests.swift:1-61
   - 发现：3 个用例。摘要里一半是通用的 Snug 日志（会话开始/结束、控制端、屏编号），一半是 UU 的信号快照（「检测到 UU 连入（」那一行的 overlay/capture 字段，SnugLogDigest.swift:59-63）。SnugLogDigest 只给 UUCheck 用（UUCheck.swift:96, 104）。
   - 建议：只有一个使用者，就整体随 UUCheck 搬到 UU，不为想象中的「通用诊断」拆两半。但它解析的是核心产出的措辞，所以 UU 目标要加一个往返测试，盯住这条跨模块的字符串约定（见日志约定那条）。
12. [tooling] Tests/SnugCoreTests/Launch/LaunchModeTests.swift:67-83, 92-93
   - 发现：flags 和 checkUU 测的是 .dumpUU、.checkUU，以及 UUCheck.defaultHours/maxHours（LaunchMode.swift:26-29, 41-42, 84-90）。errors 用例在 :92 拿 --dump-uu 当参数冲突的例子。UUCheck 一旦移出 SnugCore，核心的 LaunchMode 就会反向依赖 UU。
   - 建议：架构上二选一：参数留在核心、小时上限变成 LaunchMode 自己的常量；或者改成适配器声明的诊断子命令。测试跟着走：前者留在核心但去掉 UUCheck 引用，后者搬到 UU。:92 的冲突例子换成 --preview-screens 和 --render-about 这类中性参数。LaunchModeTests 其余用例是 core-neutral。
13. [core-uses-uu-types] Tests/SnugCoreTests/Screens/AppListTests.swift:39-45
   - 发现：excludesUU 直接用 UURemote.bundleID。被测的 AppList.excludedBundles 在核心里写死了 [UURemote.bundleID]（Apps.swift:83-84，过滤在 :96、:126）。
   - 建议：核心测试改成注入排除集合（用一个假 bundle），只验过滤机制。UU 目标断言 UU 适配器声明了 com.netease.uuremote。契约测试再加一条：每个适配器声明的自身 bundle 都不出现在资源库里。AppListTests 其余 10 个用例是 core-neutral。
14. [core-uses-uu-types] Tests/SnugCoreTests/Screens/ScreenFitTests.swift:13-24, 33-42, 97-105
   - 发现：测试写死了 UU 客户端的遮挡：竖屏上下各 91 点（:33）、横屏 154 点（:97）、标准 540×950（:13，就是从 91 算出来的）。被测的 ScreenFit.uuInset 和 uuLandscapeInsets（ScreenFit.swift:33-37, 67, 70）在核心里写死。RustDesk 手机端的画面摆法和工具栏都不一样。
   - 建议：如果遮挡改成参数（适配器声明，或单独的「观看端遮挡」值），核心 ScreenFit 测试用显式的假遮挡验算法，91 和 154 这两个实测值搬到 UU 目标断言。Desk 系列测试大多经 ScreenFit.standard 间接取值（ScreenFakes.swift:58、DeskRig.swift:18, 92），数值会自动跟着变，改动范围可控。是否要参数化见 open_questions。
15. [core-uses-uu-types] Tests/SnugCoreTests/Screens/DeviceCatalogTests.swift:111-139
   - 发现：bundledTabletsOnlyInTabletSection 和 bundledFits 是在 UU 遮挡下核对机型库每一条都过 2 倍门槛（:121-139），:111 的测试名也写着按 UU 的实测扣边。
   - 建议：遮挡参数化后，bundledFits 改成按每个适配器声明的遮挡逐一核对（并进契约测试，或用 arguments 遍历注册表），保证新适配器不会让机型库里的某一款掉出门槛。其余 12 个用例是 core-neutral。
16. [core-neutral] Tests/SnugCoreTests/Touch/TouchTranslatorTests.swift:1-249, 29
   - 发现：18 个用例吃的都是中性的 TouchInput，但 :29 的测试名写着「原版 UU 手势」，源码 TouchTranslator.swift:1, 7-8 的注释也写 UU。翻译器的前提（单指等于左键拖动）是 UU 的手势形态。RustDesk 的触控模式同样是「单指滑等于左键按下拖动、点等于左键单击」，长按由客户端直接发右键，所以 :189-192 的长按分支对 RustDesk 不会触发，但也无害。
   - 建议：留在核心，测试名和注释改成中性。不要按适配器复制翻译器测试；改在契约测试里断言每个适配器声明的手势形态（接管哪些事件类型）都在翻译器支持的输入范围内。
17. [core-neutral] Tests/SnugCoreTests/Screens/ScreenSetModeTests.swift:1-222, 85, 119
   - 发现：逻辑只看 remote 标志（ScreenSet.swift:65-69, 151-154 的 persistOwed），但测试注释把行为归给 UU（:85、:119「UU 把主屏还原成 60Hz」）。RustDesk 改不改显示模式还不知道；就算不改，这段补救也无害。
   - 建议：留在核心，措辞改成「远程工具在远程期间临时改过模式，远程结束时还原」。在 RustDesk 实测之前，不新增适配器声明。
18. [core-neutral] Tests/SnugCoreTests/Screens/DeskFitTests.swift:31-45
   - 发现：:43 的注释写「UU 要切走再切回来才按新尺寸推流」，断言 notice == .reshaped（Desk.swift:55）；这条提示的界面文案在 StatusText.swift:87，写着「在 UU远程 中切到其他屏幕再切回」。这是 UU 的怪癖，在核心里以一条提示的形式存在。
   - 建议：核心测试只断言「比例变了会发 reshaped 提示」。提示文案和「需要重选屏」这个怪癖是否改成适配器声明，见 open_questions；若改，UU 目标要加一条断言钉住它。
19. [core-neutral] Tests/SnugCoreTests/Screens/DeskTests.swift:全文件（同类：DeskSetTests、DeskAppTests、DeskDismissTests、DeskLeftBehindTests、LeftBehind*Tests、ScreenPlanTests、ScreenModelTests、WindowSpotTests、NewWindowMenuTests、CropGeometryTests、ScreenshotsTests、CursorHomeTests、ConfigModelTests、PersistenceTests、Update/*、LogTests、SerialLaneTests、Support/{RandomBytes,TempDir}、Screens/{ScreenFakes,DeskRig}）
   - 发现：只用「远程 / 不在远程」这个布尔（DeskSet.setRemote、ScreenPlan 的 remote 参数），不碰 UU 类型。UpdatePackageTests.swift:189-222 的样例更新日志里有 --dump-uu，那是历史数据。
   - 建议：原样留在 SnugCoreTests。只把注释和测试名里把通用行为归给 UU 的地方改成中性（例如 ScreenFitTests :33/:97 之外的那些措辞），历史数据不改。
20. [tooling] Tests/SnugCoreTests/Design/DesignTokensTests.swift:6-23
   - 发现：这个测试放在 SnugCoreTests，却按 #filePath 去测 App 层的 Sources/Snug/UI/DesignTokens.swift，设了 SNUG_WRITE_TOKENS=1 时还会写文件。和适配器无关，是现有的跨层放置。
   - 建议：这次不动（不扩大范围）。只记一笔：拆分时别把它误判成核心逻辑测试。
21. [uu-adapter] Tests/SnugCoreTests/Fixtures/uuremoteserver-{1755,1901,2000,2257}.ndjson:全部；Package.swift:31
   - 发现：4 个夹具的 processImagePath 都是 /Applications/UURemote.app/Contents/Helpers/UURemoteServer，只被 CaptureLogTests（4 个都用）和 UUCheckTests（只用 2257）使用。Package.swift:31 给 SnugCoreTests 声明了 resources: [.copy("Fixtures")]。
   - 建议：整个目录搬到 UU 测试目标下的 Fixtures/，资源声明一起挪过去，SnugCoreTests 去掉 resources。说明来源和脱敏方式的注释（CaptureLogTests.swift:5-6）随 UUFixtures.swift 一起走。
22. [gap] Sources/Snug/App/AppController.swift:132-166, 172-178, 249-261
   - 发现：会话到屏幕调度的编排全在 App 层，没有任何测试，包括：ended 时先 setWishes([]) 再 applyPlan（:157-162）、setRemote(inEpisode)（:163）、连接状态映射（:164）、推流屏写回（:151）、等重连时把指针挪开的条件（:173）。多适配器的「这次远程归谁、推流屏取谁的」逻辑如果也写在这里，就是新增的未测逻辑。
   - 建议：把 tick 和 handle 里不碰系统的那部分（多适配器仲裁、transition 到「要屏 / 远程标志 / 连接状态 / 推流屏」的决定）抽成 SnugCore 的纯值类型，用 FakeAdapter 驱动测试。describe()（:249-261）是纯函数，也搬进核心，供日志往返测试用。
23. [gap] Sources/Snug/Sensing/UUSensor.swift:24-30
   - 发现：UU 证据在这里合成观测（覆盖窗口、表格、推流，以及推流屏），没有测试。拆分后这里就是 UU 原始观测转成核心中性信号的边界，captureActive 的 nil（未知）和 false 的区别正是在这一层丢失或保留的。
   - 建议：在 UU 纯逻辑 target 里放一个纯映射函数（UU 原始观测 → 中性信号 + 推流屏），UU 目标逐一测：nil 不算缺席、未识别不算缺席、覆盖窗口单独算在场、推流屏只在推流时有值。
24. [gap] Sources/Snug/Sensing/CaptureLogWatcher.swift:12-13, 45-60, 152-183
   - 发现：没有测试的部分：退避序列（:174-175，跑满 stableAfter 后 failures 重置为 1，下标用 min(failures,count)-1）、回看完成前 sample 返回 nil（:46）、UURemoteServer 换进程时推流状态重来（:52-60）。
   - 建议：把退避策略和「是否可信、换进程就重置」抽成 UU 目标里的纯值类型来测（例：连续失败 7 次的延迟序列、跑满 60s 后归零、pid 从 A 变 B 后状态清空）。子进程和管道部分保持薄封装、不测。
25. [gap] Sources/Snug/Sensing/ControllerReader.swift:23-68
   - 发现：没有测试的部分：Box 的新鲜度和代次逻辑，包括在途读取超过 2s 按读不到算（:31-34）、reset 之后在途结果作废（:53-55, 61-68）。主线程卡顿导致误判断开就是靠这里防的（注释 :1-3）。
   - 建议：把 Box 的状态转移抽成纯 struct（用时间注入代替 systemUptime），放在 UU 目标测：超时、作废、正常返回这三条路径。
26. [gap] Sources/Snug/Sensing/UUAccessibility.swift:12-13, 55-64
   - 发现：AX 遍历的环检测、深度上限 25、节点上限 2048 这几个「超限按读不到算、不拿半截当真」的约束没有测试。
   - 建议：可以把遍历改成对一个读节点闭包泛型（AX 调用由闭包提供），在 UU 目标里用假树测有环、超深、超量这三种情况。优先级低于事件识别。
27. [gap] Sources/SnugSystem/TouchEvents.swift:11, 14-23, 26-35, 61-74
   - 发现：SnugSystem 没有任何测试。UUEventSource.sent（:61-74，按 pid 查可执行路径再比 serverProcess，pid≤0 时为 false，按 pid 缓存）、只接管左键的掩码（:14）、补发标记 'SNUG'（:11, 26-28, 33）都没测。RustDesk 注入的事件带 eventSourceUserData=100，Snug 补发时会把这个字段改写成 'SNUG'（:33），两边识别规则会相互影响。
   - 建议：在核心定义一个纯值描述（pid、可执行路径、userData），由适配器判断「是不是我注入的」，系统层只负责读字段。契约测试加两条：Snug 补发的事件（带 marker）对任何适配器都不算远程注入；本机 HID 事件（pid 是别的进程、userData=0）都不算。
28. [gap] Sources/SnugSystem/TouchTap.swift:42, 66, 122-140
   - 发现：handle 里的逻辑都没测：按下落在哪块范围由按下那一刻决定、之后拖动和抬起跟着它走（:132-133），heldPress 的补发顺序，关闭按钮核对不过时退回普通点击（:153-161）。识别器写死成 UUEventSource（:66, :129），日志写死 UURemote.serverProcess（:42）。
   - 建议：识别器改成注入「已装适配器的识别规则集合」，同时决定「任一已装适配器注入的都接管，还是只接管当前远程归属的那个」（这是 open_question，决定契约期望）。分派逻辑可以抽一个纯的 TapLogic 放核心测；CGEventTap 线程这层保持不测。
29. [gap] Sources/SnugCore/Diagnostics/SnugLogDigest.swift:47, 50-71（产出端：ConnectionTracker.swift:44, 57；AppController.swift:249-261；ScreenSet.swift:132, 139；Desk.swift:241；消费端：UUCheck.swift:219-222）
   - 发现：日志措辞是跨模块的字符串约定，但只测了消费端，用的还是手写行。核心一旦把「检测到 UU 连入（」改成中性措辞，UUCheck.detection 会因为 known.isEmpty 直接返回 nil，「连接检测」这一项从报告里消失，不报错（违反红线 5「不静默失败」）。「读不到名字」也是两边各写一份（SnugLogDigest.swift:47 和 AppController.swift:260）。
   - 建议：加往返测试：用产出端的同一个函数生成日志行（ConnectionTracker 的日志拼接抽成 static 函数，AppController.describe 搬进核心），再交给 SnugLogDigest 解析，断言能认出来。另外让 UUCheck 在「有远程记录、却一条连入信号都没认出」时报 warn 而不是返回 nil，这样措辞漂移会被看见。
30. [gap] Sources/Snug/App/AppState.swift:25-26, 67-72（同类：Sources/Snug/UI/LibraryWindow.swift:221）
   - 发现：watchedScreen 和 watching（推流屏为 nil 时当作在看），以及电脑屏资源库在没点到屏时选「UU 正在推的那块」，都在 App 层，没有测试。RustDesk 未必能感知推流屏（只有开着「跟随远程指针」才推指针所在的屏），nil 分支会变成它的主路径。
   - 建议：把 watching 的判定搬进核心（输入是：推流屏可能为 nil、屏表、是否在用），补上 nil、命中、未命中三种用例。契约测试里，不报告推流屏的适配器要断言它的推流屏一直是 nil，而不是悄悄跳过。
31. [gap] Sources/SnugCore/Session/ConnectionTracker.swift:5-7, 18-19（同类：SessionEpisode.swift:11；测试 ConnectionTrackerTests.swift:15-19、SessionTests.swift:8-9）
   - 发现：防抖 1.5s 和自扰静默期 5s 是按 UU 调的（UU 切屏时覆盖窗口会重建、改屏幕组合时会停流再重开），重连窗口 15s 按 V12 换手定，这些常量都由核心测试钉住。RustDesk 改屏幕组合时会不会抖还没实测。
   - 建议：眼下只有一个实测用例，常量留在核心、测试照常钉住。契约测试里所有时间都按这些常量的倍数写，不另立数值；等 RustDesk 实测出不同值，再考虑让适配器声明。
32. [gap] Sources/Snug/Screens/TouchStyle.swift:20（同类：TouchHomeView.swift:8、CropView.swift:2）
   - 发现：界面里让开 UU 在 iPad 上的圆形菜单按钮（右上角约 45 点，V6）是写死的 UU 客户端怪癖，没有测试，也不在核心里。
   - 建议：如果这个值改成适配器声明，UU 目标加一条断言钉住 45 点；不改的话至少在拆分清单上标为「UU 粘连」，免得漏掉。
33. [tooling] scripts/snug:403-411, 632-636
   - 发现：cmd_check 依次跑 swift build、不带过滤的 swift test、Python 单测。SwiftPM 会跑 Package.swift 里声明的全部 testTarget，新增的测试目标声明了就会自动被跑到。但用显式 targets 时，Tests/ 下没声明的目录会被静默忽略。uu-check（:632-636）是只读诊断，不是测试，不在 check 里。
   - 建议：cmd_check 加一道核对：用 swift package dump-package（只读）列出所有 testTarget 的名字，和 ls Tests 对比，不一致就失败；再记一次 swift test 的用例数，拆分前后总数不许下降（计数型硬数字）。docs/development.md 的 :9、:16、:75-83、:91、:126-127 跟着同步。

## proposals
### 测试目标布局（每个适配器有自己的测试）
1）SnugCoreTests（保留）：只依赖 SnugCore。Session/ 只留 SessionEpisode、RemoteSession、ConnectionTracker（中性信号）和新增的多适配器仲裁测试。Support/RemoteFakes.swift 放中性信号构造 present(...) / absent() 和 FakeAdapter。删掉 Fixtures 资源声明。
2）UU 适配器测试目标（名字跟 UU 纯逻辑 target 走，比如源码叫 SnugRemoteUU，测试就叫 SnugRemoteUUTests）：依赖 UU 纯逻辑 target 和 SnugCore。目录 Capture/（CaptureLogTests）、Controllers/（ControllerTableTests）、Process/（UUProcessWatchTests）、Signals/（UUSignals 的 isPresent 和 description、UU 到中性信号的映射、回归 #1 和 V12 的端到端）、Diagnostics/（UUCheckTests、SnugLogDigestTests 和日志往返测试）、Sensing/（从 CaptureLogWatcher、ControllerReader 抽出的纯逻辑）、Fixtures/（4 个 ndjson）、Support/UUFixtures.swift；声明 resources: [.copy("Fixtures")]。
3）RemoteContractTests（新）：依赖 SnugCore、每个适配器的纯逻辑 target、适配器注册表 target。Drivers/ 每个适配器一个驱动文件，ContractTests.swift 放参数化用例。
4）以后接 RustDesk，就照抄 2）的结构建 SnugRemoteRustDeskTests，再在 3）里加一个驱动文件。
5）SnugSystem 不新建测试目标：系统层里值得测的判断（事件识别、退避、新鲜度、遍历上限）先抽成纯值类型，放进核心或适配器纯逻辑 target 再测，系统层只留薄封装。
这样目录一眼就能看出归属：核心测试里不出现 UU 字样，UU 测试只在一个目录里，契约测试只有驱动加通用断言。

### 适配器契约测试：每个适配器都要过的一组用例
驱动协议（只在测试里）：protocol RemoteContractDriver: Sendable { var adapterID; func idle() -> Raw; func connected(controller: String?) -> Raw; func streaming(display: DisplayID) -> Raw?; func unreadable() -> Raw; func injectedEvent() -> InputProbe; func localEvent() -> InputProbe }，其中 Raw 由驱动交给自己的适配器映射成中性信号。
用例用 Swift Testing 的 @Test(arguments: RemoteContractDrivers.all) 参数化：
(a) idle 不在场；unreadable 也不在场（读不到绝不当成证据）。
(b) connected 在场；能认出控制端的适配器要带上名字。
(c) 标准时序：idle → connected → 控制端换人 → 连续缺席超过防抖 → 15s 内再连 → 缺席超过重连窗口。每个适配器都经自己的映射喂给 RemoteSession，产出的 SessionTransition 序列必须和同一份期望完全一致：began / controllersChanged / interrupted / resumed / interrupted / ended。
(d) 推流屏：只对声明能报推流屏的驱动用 arguments: all.filter(\.reportsStreamingDisplay) 跑，断言等于给定的屏；不能报的驱动另跑一条正面断言「推流屏一直是 nil」，不允许在用例里 guard 后直接 return 悄悄通过。
(e) 输入识别：injectedEvent 为真；localEvent 为假；带 'SNUG' 标记的补发事件为假。
(f) 声明项：自身 bundle 非空，且不出现在资源库里；手势形态在翻译器支持的输入范围内；若遮挡参数化，机型库每一条在它的遮挡下都过 2 倍门槛。
(g) 完整性：Set(drivers.map(\.adapterID)) == Set(注册表.all.map(\.id))，新加的适配器漏写驱动就失败，由机器查。
断言代码只写在 RemoteContractTests 里，不做成单独 import Testing 的共享库，免得普通 target 依赖 Testing 后能不能编译这个问题（未验证）。

### 用假适配器驱动核心（SnugCoreTests 内部）
FakeAdapter(id:) 吃一张脚本 [(秒数, 中性信号)]，多个 FakeAdapter 一起喂给核心的仲裁器和会话，断言每拍的 SessionTransition、当前归属的适配器 id、推流屏、noteSelfInducedChange 后的行为。必须覆盖：只有 A 在场时归 A；A 归属期间 B 也报在场，不换人、不抖，控制端只取 A 的；A 断开进入重连等待；两个都缺席时 interrupted 和 ended；自扰静默期对所有适配器都生效；推流屏只取归属方的，归属方报 nil 时 watching 当作在看。现有 ConnectionTracker 和 RemoteSession 的中性用例也用同一套 present/absent helper，核心测试里不再出现 UUSignals、ControllerTable、CaptureLogRecord。

### 夹具与测试辅助怎么分
4 个 uuremoteserver-*.ndjson 全部归 UU 测试目标的 Fixtures/，加载函数合成一个 UUFixtures.swift（目前 CaptureLogTests.swift:7-12 和 UUCheckTests.swift:9-16 各写了一份）。SessionHelpers 里的 t0 和 at 留在核心；table() 搬到 UU。UU 目标要用 t0/at 就复制这两行，或者在 RemoteContractTests 里各写一份，不为两行 helper 单独建共享 target。SnugCoreTests 去掉 resources，核心测试不再读任何 UU 数据。以后 RustDesk 的夹具（比如 --cm 窗口快照、连接日志）只放 RustDesk 自己的目标，不进核心、不进契约目标。

### 迁移顺序（先测试后实现、计数不降）
1）在 SnugCoreTests 里先写中性信号版本的 ConnectionTracker 和 RemoteSession 用例，以及仲裁用例，亲眼看它们因为类型还不存在而编译失败。2）加中性类型和仲裁器，让新用例变绿，旧 UU 用例保持不动、同时通过。3）建 UU 测试目标，把 uu-adapter 那几类文件和夹具原样搬过去并通过；再补 UU 到中性信号的映射测试、回归 #1 和 V12 的端到端、日志往返测试。4）删掉核心测试里所有 UU 类型的引用，用 grep -rn 'UU' Tests/SnugCoreTests 只剩 UUID 作为机器判据。5）建 RemoteContractTests，先让 UU 一个驱动通过。6）cmd_check 加上测试目录和声明的核对、用例总数不降的核对。每一步一个 commit，报告里写前后的用例数（现在约 445）。


## open_questions
- ScreenFit 的遮挡（uuInset 91、横屏 82+72，ScreenFit.swift:33-37）是改成适配器声明，还是继续作为核心常量？屏在连上之前就建好（常驻主屏甚至不等远程），比例没法按「这次远程归哪个适配器」来定；装了多个远控时用谁的遮挡？这决定 ScreenFitTests 和 DeviceCatalogTests.bundledFits 是否要参数化。
- 多个适配器同时报在场时怎么归属：先到先得、当前归属不被抢？重连窗口内换成另一个适配器连入，算 resumed 还是 ended 再 began？这决定契约用例和假适配器用例的期望值，要先拍板。
- TouchTap 是接管「任一已装适配器注入的事件」，还是只接管「当前远程归属的那个适配器注入的」？后者要求手势监听知道会话归属。
- LaunchMode 里的 --dump-uu/--check-uu 留在核心（核心反向依赖 UU 的常量），还是改成适配器注册的诊断子命令？scripts/snug uu-check 要不要泛化？测试放在哪随之定。
- SnugLogDigest 和 UUCheck 依赖核心日志的中文措辞：继续靠往返测试守这条字符串约定，还是在日志里加固定的机读 key？（未验证哪种改动更小）
- 契约断言如果做成共享库 target（普通 target 里 import Testing），在 swift build（不跑测试）下能不能编译过，未验证（本机工具链是 Swift 6.4.2）。提案先把断言写在 RemoteContractTests 内部来回避这个问题。
- RustDesk 这些事实未实测，决定它的驱动能覆盖契约里的哪几项：用 CGEventPost(HID) 注入时，eventSourceUnixProcessID 是不是 --server 进程；长按是先发左键按下再发右键，还是只发右键；本机能感知到连接和断开的证据有哪些（--cm 窗口、日志）；不开「跟随远程指针」时能否知道推的是哪块屏；改屏幕组合时信号会不会抖（防抖 1.5s 和静默期 5s 够不够）。
- DeskFitTests 断言的 reshaped 提示（文案写「在 UU远程 中切走再切回」，StatusText.swift:87）以及 iPad 右上角让位 45 点（TouchStyle.swift:20），是否要改成适配器声明的怪癖？现在只有 UU 的实测依据。
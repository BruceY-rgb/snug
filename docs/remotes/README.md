# 接入新的远控

Snug 只对接 UU远程，但对接的部分是一层可替换的适配器：核心不认识任何一家远控，接一家新的只加它自己的适配器，核心一行不动。UU远程 的适配器是现成的样板，见 [UU远程 适配](uu.md)。

## 分层

```
  手机 ── 远控 ──▶ Mac：进程、系统日志、界面、注入的鼠标事件
                   │
  适配器（每家一个）│  sample() 每 0.5 秒交一份中性的观测
                   ▼
  核心（各家共用）    RemoteSession 归属 → ConnectionTracker 连入 / 断开 → SessionEpisode 重连窗口
                   → ScreenPlan → DeskSet / ScreenSet 建屏、换档、撤屏；AppCatalog；TouchTranslator
                   ▼
  系统层             虚拟屏、显示模式、窗口、事件监听（只接管登记的远控注入的事件）
```

## 端口

定义在 `Sources/SnugCore/Remote/RemoteAdapter.swift`。

| 类型 | 要交什么 |
| :--- | :--- |
| `RemoteIdentity` | 日志名（写进日志与命令行，不含空格、不和别家重名）；界面名；自家 App 的 bundle（不出现在资源库里）；注入事件的进程 |
| `RemoteObservation` | 在不在场：只在有正面证据时为真；控制端：认不出为空；推流屏：不知道为 nil；信号快照：写进连入、断开日志 |
| `RemoteAdapter` | `identity`；`start()`、`stop()`；`sample(wallClock:)` 每拍调一次 |

不在端口里的：手势形态、屏幕让位、主屏策略、模式恢复、断开时序。这些按 UU远程 实测标定、各家暂时一样，留在核心（[清单](uu.md#留在核心的-uu-实测值)）；新的远控实测不同，改核心并补测试。

## 步骤

以 RustDesk 为例。名字只用英文字母，目录、目标、驱动都用它（门禁按它找）。

1. **目录**：`Sources/Remotes/RustDesk/Logic`（纯逻辑：信号怎么认、怎么算在场，只依赖 `SnugCore`）、`Sources/Remotes/RustDesk/System`（调系统、实现 `RemoteAdapter`）、`Tests/Remotes/RustDesk`
2. **`Package.swift`**：加 `RemoteRustDesk`、`RemoteRustDeskSystem`、`RemoteRustDeskTests` 三个目标（照 UU 的写法写明 `path`），`Snug` 依赖前两个，`RemoteContractTests` 依赖 `RemoteRustDesk`
3. **适配器**：纯逻辑里把原始信号映射成 `RemoteObservation`（UU 见 `UUSignals.observation`）；系统部分实现 `RemoteAdapter`。内部类型用 `package`，不用 `public`
4. **登记**：`Sources/Snug/App/Remotes.swift` 的 `all` 加一行，同时给出 `--dump-remote`、`--check-remote` 的实现。登记顺序即两家同时报在场时的归属顺序
5. **契约测试**：`Tests/RemoteContractTests/Drivers/RustDeskDriver.swift`，把空闲、读不到、连入、推流几种情形翻译成它的原始信号，经它自己的映射交出观测；放进 `drivers`
6. **验收**：`scripts/snug check` 全绿；真机连一次，Snug.log 里连入、断开、会话几行对得上

## 几家并存

一次远程只归一家（`RemoteSession`）：未连接时归登记顺序里第一家报在场的；已连接时不换，别家也报在场只记一条日志；重连等待期里换了一家连入，算同一次远程；远程结束清空归属。手势翻译接管所有登记的远控注入的事件。

## 防回潮

`scripts/snug check` 在构建之前先查：

- 核心（`SnugCore`）与系统层（`SnugSystem`）的代码行不出现 UU，出处只写在注释里
- 只有 `Sources/Snug/App/Remotes.swift` 能 import 适配器
- 核心测试只用假远控，不碰适配器的类型
- 声明的测试目标与 `Tests/` 下的目录一一对应
- 每家远控三个目标齐全、已登记、契约测试依赖它并有它的驱动

类型引用由编译器拦：核心不依赖任何 `Remote*` 目标，写了也编译不过。

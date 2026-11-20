---
name: project-remote-adapter
description: 远控适配层（11-19 合入 main）：对接 UU 的部分抽成可替换的适配器，给社区留口子；设计记录 docs/remote-adapter 保留不删；约定、门禁、技术债
metadata:
  type: project
---

**11-19 合入 main，随 2.7.3 发布。** 起因是 #35、#33 问 RustDesk 等其他远控：主人定专注 UU、暂不接别家（见 [[project-uu-vip]]），但「就算咱们不做，也要留个口子给别人做」。

- **文档**：接入指南 `docs/remotes/README.md`（端口、步骤、提交方式、防回潮）、UU 适配说明 `docs/remotes/uu.md`、设计记录 `docs/remote-adapter/`（方案、三份调研、11 项拍板、第 12 节落地差异与验收）。README 三种语言的「开发」一节写了「架构已就绪，欢迎提 PR 接入或 fork 自行接入」
- **设计记录不删**（主人 11-19）：给之后来适配的人看，不按「合并前删过程文档」的习惯处理（见 [[project-release]]）
- **约定**：每家两个目标 `Remote<家>`（纯逻辑，只 import Foundation、SnugCore）+ `Remote<家>System`，测试目标 `Remote<家>Tests` 在 `Tests/Remotes/<家>`；适配器类型叫 `<家>RemoteAdapter`，身份是它的静态 `identity`；只在 `Sources/Snug/App/Remotes.swift` 登记；契约驱动 `Tests/RemoteContractTests/Drivers/<家>Driver.swift`。`scripts/snug check` 先跑 `check_remote_boundaries`，以上任何一条漏了都会失败；名字检查按 `Sources/Remotes` 下的目录名按子串查核心、系统层、核心测试，UU 出处只能写在单独一行的注释里（`@Test` 描述里也不行），撞上无关子串加进放行表 `allowed`
- **只登记 UU 时行为逐字不变**：日志名「UU」，日志、界面文案、自检输出与抽出前一致（真机、渲染、诊断三方面验过，数据在设计记录 12.2）。诊断命令改名 `scripts/snug remote-check uu`、`--dump-remote` / `--check-remote`，旧名不留别名
- **技术债（本次不做）**：系统层几处判断没有测试——`CaptureLogWatcher` 退避重启、`ControllerReader` 结果新鲜度、`UUAccessibility` 环检测与节点上限、`TouchTap` 分派，要先抽成纯值类型

**Why:** 社区接别家远控时，要能只看文档和契约测试就接进来，不碰核心。
**How to apply:** 改连接判定、会话、手势、资源库时守住「核心不认识任何一家远控」；UU 特有的东西进 `Sources/Remotes/UU`，按 UU 实测标定、各家共用的值留在共用代码并注明出处。

---
name: project-release
description: 发版：只走 scripts/snug；个人 Developer ID（29898YBGWD）公证；gh 绑定 zephyr4123 且写明 -R；版本号与更新日志口径；分块的应用内更新；发版后不替主人装
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-16T03:45:00.000Z
---

- **一个入口**：构建、测试、打包、公证、发版都走 `scripts/snug`（check / app / install / dist / ship / mirror / media）。新步骤加成子命令或内部函数，不另起脚本。主人 11-13：「通过一行命令行就能去出包、去 release，千万别散在各处」。参照 SpeakMore（`~/coding/personal/reverse-anything`）的 ship：把关 → 检查 → 打包公证 → 上传 → 从下载地址核对 → 公开；断了只补没做完的那一步
- **签名公证**：个人 Developer ID Application（Team ID 29898YBGWD，本机唯一一张）。notarytool 档案与 SpeakMore 共用，名字在不进 git 的 `.machine.env`；档案在数据保护钥匙串里，`security find-generic-password` 搜不到，别据此说没有。苹果回 403「A required agreement is missing」是开发者协议待签，要账号持有人去 developer.apple.com 签
- **main 不加分支保护**（11-19 主人定）：只有主人有写权限，加了影响效率；GitHub 提示「main branch isn't protected」不用理，等有协作者再议
- **GitHub 账号**：本机 gh 登了多个账号，本项目用 `GH_CONFIG_DIR=~/.config/gh-zephyr4123` 绑定 zephyr4123。推送和 gh 命令前 `gh api user --jq .login` 必须是 zephyr4123，不是就先停下。gh 命令一律写明 `-R zephyr4123/snug`：不写时会挑 upstream（只有 scripts/snug 里导出了 `GH_REPO`），2.0.0 发版时差点发到原作者的仓库
- **版本号口径**（主人定）：x.y.0 发主打功能，x.y.z 修 issue 报的问题，即使带一个小入口也算热修复（2.0.1、2.2.1、2.4.1 都是）
- **更新日志口径**：讲用户得到什么（「全面适配所有 App」），不点名具体 App、不讲换分辨率之类的实现。主人通常只审更新日志，其余放手
- **主人的发版习惯**：合并主干、推送、发版前照红线先问；合并前把过程文档（设计记录）删掉、结论并进记忆（例外：远控适配层的设计记录给社区看，保留，见 [[project-remote-adapter]]）；主人说是「小补丁」时不用自己手测，发版后在 issue 里请报告人测；发版后**不替主人装正式版**：从访达重新打开「应用程序」里的旧版（见 [[project-phone-screen]] 的「正式版只让访达开」），让它启动时弹「软件更新」，主人自己点；顺带弹出的设置窗口关掉，留更新窗口
- **应用内更新**（2.1.0 起）：dist 顺带用 `snug-release pack` 打 `Snug-<版本>.pack`，ship 用标签说明写 `update.json`，GitHub 和国内源两处都传。按内容分块、不做差分补丁是主人拍板的：差分要按版本配对，主人嫌「产生一堆中间产物」，宁可多下一点（实测分块对 Snug 几乎不省流量），别再提差分。`firstUpdatable` = 2.1.0（Sources/SnugRelease）
- **本机实测更新**：别往 COS 传测试文件。临时把 `UpdateSource.tencentBase` 改成 `http://127.0.0.1:8765/snug`、VERSION 设成旧版本号 install；另打一个新版本号的 App，用临时本地标签跑 `snug-release pack/feed` 摆成国内源的目录，起一个支持 Range 的本地服务器；点「立即更新」后看日志和 Info.plist。测完 `git checkout` 还原、删临时标签、重装。SwiftUI 的按钮在辅助功能里没有标题，osascript 点 `last button of group 1 of window "软件更新"`（「立即更新」在最右）

国内源和 README 媒体见 [[project-domestic-mirror]]

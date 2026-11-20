---
name: project-ui-redesign
description: 界面以 design/prototype 原型为准、令牌在 design/design-tokens.json；先定令牌再画原型；检查原型用 WebKit 开本地文件截图；主人看原型图调、少讲文字
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-19T16:00:00.000Z
---

多屏前的界面重组（11-17 主人确认，2.6.0 按原型做完）：设置分三页、菜单栏、电脑屏资源库、横屏两栏。

- **界面以 `design/prototype/index.html` 为准**，令牌在 `design/design-tokens.json`（mac / touch 两套），`node design/tokens-to-css.mjs` 生成 CSS 变量；图标用 `swift design/prototype/export-assets.swift` 本地导出、内嵌成 data URI，不进 git。用法见 design/README.md
- **顺序**：先定令牌，再画原型，主人确认后才写功能代码（「相当于前后端都已经定好了，再开始全面铺开」）
- **检查原型用 WebKit 直接开本地文件截图**（`design/prototype/snapshot.swift`），别只用 Chrome + 本地服务器，看不出 Safari 的问题
- 做完界面用 `--render-<界面> <目录>` 和原型逐张对照；docs/PRODUCT.md 是给设计工具（impeccable）的产品说明
- 主人偏好：直接看原型图调，少讲文字；原型放仓库本地看，不外传

**How to apply:** 改界面先改原型和令牌，再改代码。文字和图标规矩见 [[feedback-ui-style]]，产品取舍见 [[project-product]]。

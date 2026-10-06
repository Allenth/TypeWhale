# 自动发送倒计时首次取消与胶囊对齐设计

## 目标

修复自动发送倒计时浮层第一次出现时，“取消”首次点击不生效的问题；同时把固定
倒计时从 1.5 秒调整为 2 秒，并让浮层跟随当前主胶囊位置。

## 用户可见结果

- 倒计时从 `2.0 秒后发送` 开始。
- 浮层位于当前主胶囊正上方，间隔 10px。
- 浮层与胶囊横向中心对齐，不覆盖胶囊。
- App 启动后的第一次倒计时，首次点击“取消”就立即生效。
- 点击取消只取消追加按键，已经粘贴的文字保持不变。

## 根因证据

- Build 813 日志中，第一次倒计时终态是 `emitted`，没有
  `cancelled_cancelButton`；第二次开始才记录按钮取消。
- 使用同一 Presenter 启动非激活临时 App，第一次点击“取消”可以立即触发。
- AppKit 实测普通 `NSButton.acceptsFirstMouse(for: nil)` 已返回 `true`。

因此问题不是按钮第一次拒绝事件，而是 1.5 秒窗口过短，且浮层固定在屏幕底部，
用户第一次发现浮层再移动鼠标时已经到期。修复应增加可反应时间并缩短鼠标移动
距离，不新增无效按钮子类。

## 方案比较

### A. Presenter 注入胶囊 frame，并把时长改为 2 秒（采用）

- `SpeechInputCoordinator` 向 Presenter 注入只读闭包：
  `popup.presentationFrame`。
- Presenter 每次显示时读取当前 frame，计算胶囊上方 10px、横向居中的位置。
- 胶囊 frame 不可用时，退回当前屏幕底部居中，保证功能不消失。

优点：复用已有 `PreviewPresenting.presentationFrame`，没有新增全局状态、通知或
胶囊反向依赖；同时增加反应时间并缩短鼠标移动距离。

### B. 只覆盖 `acceptsFirstMouse`

不采用。系统按钮已经接受 first mouse，继续包装不会解决日志中的超时发送，只会
增加闲置类型。

### C. 只延长时间，不移动浮层

不采用。虽然增加反应时间，但第一次仍需从输入位置移动到屏幕底部，体验问题没有
完整解决。

## 架构边界

- `AutoSendCountdownCoordinator.duration` 从 1.5 改为 2.0；其余 token、取消、
  焦点检查和单次发送逻辑不变。
- `AutoSendCountdownPresenter` 只消费胶囊 frame，不修改胶囊。
- `PreviewPresenting`、主胶囊主题和 `presentationFrame` 合同不变。
- 不改 `PasteCoordinator` 的 0.3 秒队列释放。
- 不改 ASR、实时缓存、最终粘贴、翻译、闪念、OpenClaw 或胶囊文字展示。

## 定位规则

给定胶囊 frame、浮层 size 和胶囊所在屏幕 visible frame：

1. `x = capsule.midX - overlay.width / 2`；
2. `y = capsule.maxY + 10`；
3. x、y 必须限制在 visible frame 内；
4. 胶囊上方空间不足时，退到胶囊下方 10px；
5. 胶囊 frame 为空时，使用当前屏幕底部居中的既有 fallback。

## 测试与验收

- RED/GREEN：2 秒固定时长及 deadline。
- RED/GREEN：胶囊上方 10px、水平居中、屏幕边界和上方不足 fallback。
- Coordinator、Esc、粘贴顺序、胶囊独立性回归继续通过。
- 真实安装版验证：
  1. 重启 App 后第一次录音，点击一次取消即成功；
  2. 连续第二次仍成功；
  3. 文字保留，不产生回车；
  4. 浮层在胶囊正上方并中心对齐；
  5. Esc 和自然倒计时发送继续正常。

## 回滚

自动发送总开关仍是产品回滚入口。代码回滚只需撤销本次 Presenter、时长、接线与
测试提交，不涉及数据迁移。

## v0.1.0 – 首个可分发版本 (2026-02-26)

### 功能 1：Hook 主链路通知与事件过滤
- **总结**: 新增 `notify-stop.ps1`，将任务完成事件转为桌面通知触发链路。
- **解决痛点**: 之前通知逻辑分散且不可复用，难以在其他机器稳定复现。
- **功能细节**: 脚本支持 payload 容错解析、规则摘要、同线程冷却去重、JSONL 统一日志输出。
- **技术实现**: 
  - 新增 `hooks/notify-stop.ps1` 作为 `hooks.Stop` 主入口。
  - 内置硬标记优先 + fallback 决策逻辑，异常全兜底 `exit 0`。
  - 统一写入 `notify-stop-events.jsonl` 扩展字段用于观测。

### 功能 2：点击通知跳转 VSCode 工作区
- **总结**: 新增 `notify-click-jump.ps1`，实现通知点击后激活目标 VSCode 窗口。
- **解决痛点**: 完成提醒后仍需手动切回工作区，尤其多窗口并行时效率低。
- **功能细节**: 气泡通知保持原有样式和声音，点击时优先按工作区标题命中窗口，失败回退 `code -r`。
- **技术实现**: 
  - 新增 Win32 `EnumWindows`/`SetForegroundWindow` 调用链。
  - 支持 `BalloonTipClicked` 与 `Click` 双事件监听。
  - 引入 `window-title`、`window-any`、`code-reuse-window` 跳转策略记录。

### 功能 3：仓库化安装与发布基础
- **总结**: 新增安装、自检、卸载脚本与模板，支持“一句 Prompt 安装”。
- **解决痛点**: 原逻辑仅存在于 `~/.codex`，无法标准化分发和版本管理。
- **功能细节**: 安装器可备份并合并 `~/.codex/config.toml`，冲突返回 `20`；支持重复安装幂等。
- **技术实现**: 
  - 新增 `scripts/install.ps1`、`scripts/doctor.ps1`、`scripts/uninstall.ps1`。
  - 新增 `scripts/lib/config-merge.ps1` 实现受管块合并策略。
  - 新增 `templates/stop-hook.snippet.toml` 与双语 README 文档入口。

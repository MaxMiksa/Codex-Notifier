# codex-notifier 项目手册（PROJECT.md）

本文件是本项目的“百科全书”，用于**成体系沉淀**与项目/开发研究相关的一切成果与已确认事实。  
> 区别于 README：README 面向外部读者做摘要；PROJECT 面向开发者做全面记录与传承。

## 1. 项目目的与范围

### 1.1 目标（Why）
- 在 Codex（尤其 VSCode 插件使用场景）中，实现“任务完成可感知通知”。
- 在不影响主流程稳定性的前提下，提供低噪音、可追溯、可迭代的通知体验。
- 支持点击通知快速回到目标 VSCode 工作区窗口，提高闭环效率。

### 1.2 范围（What）
- 通知触发：Codex hooks（`Stop`/turn complete payload）链路。
- 通知执行：PowerShell 脚本（桌面气泡 + 声音 + 点击处理）。
- 可观测性：JSONL 结构化日志与决策字段。
- 不包含：MCP/Skills 参与通知执行主链路。

## 2. 受众与语言规范

- 用户可读文档：**中文**（`PROJECT.md`、`CHAT_LOGS.md`）。
- AI 操作指南：**英文**（`AGENTS.md`）。

## 3. 已确认事实（Facts）

### 3.1 关键路径
- 本地路径：`D:\Max\Projects\Dev\Codex-Notifier`
- 全局配置：`C:\Users\Max\.codex\config.toml`
- 主通知脚本：`C:\Users\Max\.codex\hooks\notify-stop.ps1`
- 点击跳转脚本：`C:\Users\Max\.codex\hooks\notify-click-jump.ps1`
- 事件日志：`C:\Users\Max\.codex\hooks\logs\notify-stop-events.jsonl`
- 会话日志：`C:\Users\Max\.codex\sessions\2026\02\26\rollout-2026-02-26T02-58-37-019c98f4-f92e-7553-ab62-01e2f52dba0a.jsonl`

### 3.2 已确认技术栈
- PowerShell 7 脚本（`pwsh.exe`）
- Windows Forms NotifyIcon（气泡通知）
- Win32 API（`EnumWindows` / `SetForegroundWindow`）用于窗口激活
- VS Code CLI（`code -r <cwd>`）作为跳转兜底

### 3.3 约束与决策（必须遵守）
- 通知链路只走 hooks；不使用 MCP/Skills 执行通知动作。
- 通知脚本必须兜底 `exit 0`，异常不影响 Codex 主流程。
- 通知样式保持现有“桌面气泡 + 声音”，不切换为 Toast 按钮。
- 默认兜底目录：`C:\Users\Max\Desktop\default`。
- 编码：UTF-8 无 BOM；中文改动后必须回读校验。

## 4. 当前实现架构

### 4.1 触发与判定
- `notify-stop.ps1` 接收 hook payload（stdin/argv 容错解析）。
- 先做硬标记探测；若无硬标记，执行 fallback 规则：
  - `parse_ok=true`
  - `event_type=agent-turn-complete`
  - `summary_mode=assistant`
  - 同线程冷却去重

### 4.2 通知执行
- 当 `notify_sent=true` 时，主脚本异步启动点击子脚本并快速返回。
- 子脚本显示通知并监听点击事件：
  - `BalloonTipClicked` 主路径
  - `Click` 兼容兜底
  - 400ms 防抖降低误触发

### 4.3 点击跳转策略
1. 从 payload 获取 `cwd`，缺失时回退默认目录。
2. 用目录名作为 workspace token（如 `default`）。
3. 枚举可见顶层窗口，匹配标题：`* - <workspaceToken> - Visual Studio Code`。
4. 匹配到则激活窗口；失败则执行 `code -r <targetCwd>` 兜底。

### 4.4 日志模型（schema_version=2）
- 决策类：`decision_mode`、`notify_sent`、`notify_reason`
- 点击类：`click_enabled`、`click_received`
- 跳转类：`jump_strategy`、`jump_target_cwd`、`jump_workspace_token`、`jump_window_title`、`jump_window_pid`、`jump_result`、`jump_error`

## 5. 已知问题与观察

- `cwd` 并非每条上游 payload 都有，旧日志条目也存在 schema 差异。
- 通知中心历史项的二次点击回调不保证可用（当前仅保证弹出当下点击行为）。
- 多窗口同工作区名时，命中顺序依赖当前窗口枚举顺序，需要持续观察是否符合使用习惯。

## 6. 成功标准（验收题）

- 正常回合完成时，出现 1 次通知（无多余重复弹窗）。
- 点击通知后可优先激活目标工作区窗口；失败时可兜底打开/复用 VSCode 窗口。
- 日志可清晰解释每次是否触发、是否点击、如何跳转、为何失败。
- 通知链路任何异常不影响 Codex 主任务完成。

## 7. 运维与排查要点

- 快速看最近行为：查看 `notify-stop-events.jsonl` 尾部记录。
- 判定是否误触发：对比 `notify_sent`、`notify_reason`、`click_received`。
- 判定跳转失败：查看 `jump_result` 与 `jump_error`。
- 判定路径来源：`payload_keys` 是否含 `cwd`，以及 `jump_target_cwd` 最终值。

## 8. 未决问题（Open Questions）

- 多窗口冲突时是否要引入更强的“最近活动窗口”判定（例如 Z-Order 显式排序持久化）。
- 是否要在摘要提取层进一步过滤“内部过程类语句”，提升弹窗可读性。

## 9. 进展记录（Progress）

- 2026-02-26：完成 hook 通知主链路（弹窗 + 声音 + 兜底退出）。
- 2026-02-26：完成事件过滤（硬标记优先 + fallback + 去重）。
- 2026-02-26：完成点击通知跳转 VSCode（窗口标题匹配 + `code -r` 兜底）。
- 2026-02-26：日志升级为 `schema_version=2`，补齐点击/跳转可观测字段。
- 2026-02-26：初始化项目文档三件套中的缺失文件：`CHAT_LOGS.md`、`PROJECT.md`。
- 2026-02-26：将历史沉淀文档迁移到项目工作空间 `D:\Max\Projects\Dev\Codex-Notifier`（不再以 `default` 目录为主）。

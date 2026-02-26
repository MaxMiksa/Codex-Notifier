# 通过 Codex Hooks 实现“Coding 结束后通知”（Windows，全局）

## 概要
- 目标：在 Codex 任务结束时触发本地通知。
- 已锁定决策：`只用 hooks`、`全局 ~/.codex/config.toml`、`桌面弹窗 + 铃声`、`简洁通知文案`。
- 约束：不使用 MCP、不使用 Skills 做通知链路。

## 变更设计（Decision Complete）
1. 新增一个本地 Hook 脚本（PowerShell）。
2. 在 `~/.codex/config.toml` 增加 `hooks.Stop` 配置，把任务结束事件绑定到该脚本。
3. 脚本从 `stdin` 读取 Hook JSON payload（可选使用，不依赖固定字段），执行：
   - 播放一次短铃声。
   - 显示简洁桌面弹窗（标题固定，正文含完成提示和时间）。
4. 脚本始终 `exit 0`，避免因为通知异常影响 Codex 主流程。

## 配置接口/类型变更
- 配置文件：`~/.codex/config.toml`
- 新增接口：
  - `[hooks]`
  - `Stop = [{ hooks = [{ type = "command", command = [...], timeout_ms = ... }] }]`
- 脚本输入接口：
  - 来自 Hook 的 `stdin` JSON（按官方约定传入）。
  - 脚本实现按“容错解析”处理，字段缺失不报错。

## 计划中的具体配置（示例）
```toml
[hooks]
Stop = [
  { hooks = [
      { type = "command", command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\Users\\Max\\.codex\\hooks\\notify-stop.ps1"], timeout_ms = 4000 }
    ]
  }
]
```

## 脚本行为规范（notify-stop.ps1）
- 读取 `stdin`，`ConvertFrom-Json` 失败则忽略。
- 通知标题：`Codex 已完成当前任务`
- 通知正文：`完成时间 HH:mm:ss`
- 铃声：短促一次（避免扰民）。
- 异常处理：捕获所有异常并 `exit 0`。

## 测试场景与验收标准
1. 场景：执行一次最小任务（如 `codex exec "say hi"`）。
   - 期望：任务结束后出现 1 次弹窗 + 1 次铃声。
2. 场景：连续执行两次任务。
   - 期望：每次结束各触发 1 次通知，无重复触发。
3. 场景：脚本接收异常/空 JSON。
   - 期望：不报错中断，仍可正常退出。
4. 场景：临时移除 `hooks.Stop` 配置。
   - 期望：不再触发通知（用于回归验证）。
5. 场景：通知脚本内部故障模拟。
   - 期望：Codex 主流程不受影响（因为脚本兜底 `exit 0`）。

## 假设与默认值
- 假设：当前环境为 Windows + PowerShell，可运行本地 `.ps1`。
- 默认：通知文案保持简洁，不展示敏感上下文。
- 默认：全局生效（对所有项目统一触发）。
- 默认：仅绑定 `Stop`，不绑定 `SubagentStop`/`Notification`，降低噪音。

## 参考
- Codex CLI 配置（含 hooks、hook 事件、stdin payload 说明）：https://developers.openai.com/codex/cli/configure
- Codex CLI 通知能力（notify 机制说明）：https://developers.openai.com/codex/cli/notifications

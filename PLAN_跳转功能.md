## 方案标题
**Codex 通知“整条可点击跳转 VSCode”实施方案（保持现有气泡风格）**

## 摘要
在不改现有通知样式/声音、不引入 Toast 按钮的前提下，实现“点击通知主体即可跳转到对应 VSCode 工作区窗口”。  
核心策略：主 Hook 继续负责判定与出通知；新增一个轻量点击处理脚本负责监听点击并执行跳转，避免受 Hook `timeout_ms=4000` 约束。

## 现状与约束（已确认）
1. 当前可稳定拿到 VSCode 窗口标题，且格式包含工作区名，例如：`notify-stop-events.jsonl - default - Visual Studio Code`。
2. `code.cmd` 已在 PATH 中可用。
3. 当前通知是 `NotifyIcon.ShowBalloonTip`，支持点击事件，但不是“按钮控件”。
4. 保持现有“气泡 + 声音”体验，不切 Toast 按钮路线。

## 变更范围
1. 修改 `C:\Users\Max\.codex\hooks\notify-stop.ps1`（主流程脚本）
2. 新增 `C:\Users\Max\.codex\hooks\notify-click-jump.ps1`（点击监听与跳转执行）
3. 扩展 `C:\Users\Max\.codex\hooks\logs\notify-stop-events.jsonl` 字段（仅新增，不破坏现有字段）
4. 不改 `~/.codex/config.toml` 的 hooks 绑定方式（仍由同一主脚本触发）

## 实现设计（决策完成）

### 1) 主脚本职责（`notify-stop.ps1`）
1. 保留现有通知过滤逻辑（硬标记优先，拿不到走 fallback rules + 去重）。
2. 仅当 `notify_sent=true` 时，异步启动点击处理脚本并立即退出：
   - 启动命令：`Start-Process pwsh.exe -WindowStyle Hidden -ArgumentList ...notify-click-jump.ps1 ...`
   - 主脚本仍 `exit 0`，不阻塞 Codex。
3. 传给子脚本的参数：
   - `-Title`（当前标题）
   - `-Body`（当前正文）
   - `-Cwd`（payload 的 `cwd`，若无则空）
   - `-DefaultCwd "C:\Users\Max\Desktop\default"`
   - `-ThreadId`、`-TurnId`（用于日志关联）
   - `-NotifyDurationMs 2500`、`-ClickWaitMs 8000`

### 2) 点击处理脚本职责（`notify-click-jump.ps1`）
1. 用与当前一致的 `NotifyIcon` 样式显示通知（标题、正文、icon、声音策略不变）。
2. 注册点击事件：
   - `BalloonTipClicked` 触发跳转
   - 同时注册 `Click` 作为兼容兜底
3. 在 `ClickWaitMs` 窗口内监听点击；超时即退出，不做跳转。

### 3) 跳转算法（点击后）
1. 目标路径解析：
   - `targetCwd = payload.cwd`
   - 若 `targetCwd` 为空或不存在，则 `targetCwd = C:\Users\Max\Desktop\default`
2. 工作区 token：
   - `workspaceToken = Split-Path targetCwd -Leaf`（例如 `default`）
3. 窗口命中（你指定的“按窗口名定位”）：
   - 枚举顶层可见窗口（Win32 `EnumWindows`）
   - 过滤 `Code.exe` 且标题匹配：`* - <workspaceToken> - Visual Studio Code`
   - 多命中时取 Z-Order 最靠前窗口（作为“最近活动窗口”代理）
4. 激活窗口：
   - `ShowWindowAsync(hwnd, SW_RESTORE)` + `SetForegroundWindow(hwnd)`
5. 激活失败或无命中时兜底：
   - 执行 `code -r "<targetCwd>"`

### 4) 日志与可观测性
`notify-stop-events.jsonl` 新增字段（schema 升到 `2`）：
1. `click_enabled`（bool）
2. `click_received`（bool）
3. `jump_strategy`（`window-title` / `code-reuse-window` / `none`）
4. `jump_target_cwd`（string）
5. `jump_workspace_token`（string）
6. `jump_window_title`（string|null）
7. `jump_window_pid`（number|null）
8. `jump_result`（`ok` / `fallback` / `failed`）
9. `jump_error`（string|null，截断）

## 公开接口/类型影响
1. Hook 配置接口不变：仍走 `~/.codex/config.toml` 的同一 `Stop` command。
2. 脚本内部接口新增：
   - `notify-stop.ps1` -> `notify-click-jump.ps1` 的参数传递契约（上文参数集合）。
3. 日志 JSONL 类型新增字段且保留向后兼容（旧字段不删）。

## 测试用例与验收标准

### A. 核心流程
1. 场景：正常一轮回复完成，通知弹出后点击  
   - 期望：激活标题含 `- default - Visual Studio Code` 的窗口；日志 `click_received=true`、`jump_result=ok`。
2. 场景：通知弹出但不点击  
   - 期望：不跳转；超时退出；日志 `click_received=false`。

### B. 兜底路径
1. 场景：payload 无 `cwd`  
   - 期望：跳到 `C:\Users\Max\Desktop\default`（优先窗口命中，失败则 `code -r`）。
2. 场景：无匹配窗口标题  
   - 期望：执行 `code -r <targetCwd>`，日志 `jump_result=fallback`。

### C. 多窗口冲突
1. 场景：多个窗口都含同一工作区名  
   - 期望：命中 Z-Order 最靠前窗口；若激活失败再 fallback。

### D. 稳定性
1. 场景：点击脚本内部异常  
   - 期望：主 Codex 流程不受影响（主脚本已退出且始终 `exit 0`）。
2. 场景：连续多轮触发  
   - 期望：每条通知独立可点击；不引入额外误报。

## 假设与默认值
1. 默认工作区兜底目录：`C:\Users\Max\Desktop\default`。
2. VSCode 窗口标题模式维持 `... - <workspace> - Visual Studio Code`。
3. 点击监听仅对“弹出当下”有效，不承诺通知中心历史项二次点击回调。
4. 仅使用 hooks 链路，不引入 MCP/Skills 参与通知执行。

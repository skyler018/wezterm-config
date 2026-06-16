# wezterm-config

这是一个模块化的 WezTerm 配置：入口文件 `wezterm.lua` 负责按顺序加载各个模块，并最终返回合并后的 `config`。

## 目录结构

- `wezterm.lua`：主入口，控制模块加载/覆盖顺序（`theme` 最后加载）
- `config/init.lua`：模块注册与 `config` 构建器（`init.register` + `init.build()`）
- `config/*.lua`：按功能拆分的配置模块

## 配置加载机制（模块化合并）

入口 `wezterm.lua` 会依次 `require` 各模块，最后 `return init.build()`（见 `wezterm.lua:1`）。

核心机制在 `config/init.lua`：

- 每个模块通过 `init.register(name, fragment_or_fn)` 注册自己（见 `config/init.lua:10`）
- `init.build()` 按注册顺序遍历 registry，将每个模块提供的 table 片段合并进 `config`，或执行 function 对 `config` 做更复杂的变更（见 `config/init.lua:23`）
- 合并策略是"同 key 覆盖"：后注册的值会覆盖先注册的值（`apply_fragment` 直接赋值，见 `config/init.lua:17`）

因此：如果两个模块写了同一个配置项，后加载/后注册的模块优先级更高。

## 功能说明（按模块）

### `config/deps.lua`：按需依赖检测与安装提示

- 管理与快捷键强相关的第三方工具：`yazi`、`lazygit`、`claude`、`codex`
- `MANAGED_BINS` 表定义 `{ bin, brew }` 映射，供检测与安装使用（见 `config/deps.lua:7`）
- 启动 GUI 时执行一次检测（同一 WezTerm GUI 进程内只提示一次），缺失则弹出选择器引导安装（见 `config/deps.lua:172`）
- 若检测到 `brew`：可一键在新标签页执行 `brew install ...`（见 `config/deps.lua:94`）
- 若未检测到 `brew`：提示并可打开 `https://brew.sh`（见 `config/deps.lua:97`）
- 提供 `get_shell()`、`command_exists(bin)`、`get_missing_dep(bin)`、`get_missing_for_bins(bins)`、`get_missing_managed_deps()` 等工具函数
- 提供 `percent_decode()` 工具函数，供 `keys.lua` 共用

### `config/font.lua`：字体与渲染

- 终端字体使用 `JetBrainsMono Nerd Font`（Medium 字重）+ `Symbols Nerd Font Mono` + `Apple Color Emoji` 回退（见 `config/font.lua:7`）
- 通过 `font_rules` 调整不同强度/斜体的字重：
  - `Half` 强度 → Medium 字重（避免 Light 过细）
  - `Normal` 斜体 → Medium 字重 + 关闭斜体（保持直立）
  - `Bold` 强度 → Bold 字重（提供视觉区分）
- 基础参数：`font_size = 18.0`、`line_height = 1.1`、`cell_width = 1.0`（见 `config/font.lua:40`）
- 关闭连字：`harfbuzz_features = { "calt=0", "clig=0", "liga=0" }`（见 `config/font.lua:44`）
- 关闭 ANSI 粗体提亮（`bold_brightens_ansi_colors = false`）与 cap-height 缩放（见 `config/font.lua:40`）

### `config/window.lua`：窗口外观

- 初始窗口大小：`120x32`（见 `config/window.lua:6`）
- 启用 `use_resize_increments`，让窗口缩放按字符栅格递增（见 `config/window.lua:10`）
- 内边距：左右 20px、顶部 60px、底部 10px（见 `config/window.lua:13`）
- macOS 视觉效果：集成按钮标题栏（`INTEGRATED_BUTTONS|RESIZE`）、背景模糊(20)、半透明(0.92)（见 `config/window.lua:20`）
- titlebar 背景色统一为 `#090909`（见 `config/window.lua:24`）

### `config/macos.lua`：macOS 特性

- 左 Option 作为 Meta（Alt）更利于 Vim/Neovim 等快捷键；右 Option 保留输入法组合键（见 `config/macos.lua:5`）
- 启用原生全屏模式，不在关闭所有窗口时退出（见 `config/macos.lua:8`）

### `config/shell.lua`：默认 Shell 与 TERM

- 默认启动程序：优先使用 `$SHELL -l`，否则回退到 `/bin/zsh -l`（见 `config/shell.lua:4`）
- `term = "xterm-256color"`，兼容部分 CLI 程序识别逻辑

### `config/cursor.lua`：光标与滚动

- 光标样式：`BlinkingBlock`（见 `config/cursor.lua:4`）
- 回滚行数：`20000`（见 `config/cursor.lua:5`）
- 关闭滚动条（见 `config/cursor.lua:8`）
- 自定义鼠标选择的单词边界字符（见 `config/cursor.lua:11`）

### `config/tabs.lua`：Tab 栏

- Tab bar 位于顶部、关闭 fancy 样式、最大宽度 `25`、关闭 index 显示（见 `config/tabs.lua:6`）
- 仅 1 个 tab 时隐藏 tab bar，关闭 tab 时切回上一个活跃 tab（见 `config/tabs.lua:8`）
- 自定义 `format-tab-title` 事件处理（见 `config/tabs.lua:115`）：
  - 根据前台进程显示对应 Nerd Font 图标（nvim/vim → ``、shell → ``、git/lazygit → ``、docker → ``、python → ``、node → ``、go → ``、lua → ``、rust → ``、yazi → ``、AI 工具 → `` 等）
  - Tab 标题文本优先显示当前活跃 pane 的目录名；拿不到 cwd 时回退到进程名或 pane 标题
  - `top`/`htop`/`btop` 这类临时全屏监控程序会按 shell tab 处理，避免运行时把 tab 风格切成另一套
  - 活跃 tab 左侧显示粉色圆点指示器（`●`）
  - AI 工具（claude/codex/trae）的前台进程会抑制 app 标题，仅显示进程名
  - Tab 标题过长时自动截断并加省略号（`…`），过短时用空格补齐
  - 颜色方案使用 Ghostty 默认色系：默认 (`#3a3d44`)、hover (`#88a1bb`)、active (`#83a5d6`)

### `config/resurrect.lua`：状态持久化（WezTerm 插件）

- 依赖 `MLFlexer/resurrect.wezterm` 插件
- 提供 `setup(keys_config)` 函数，由 `keys.lua` 调用注入快捷键（见 `config/resurrect.lua:6`）
- 默认关闭，避免与 `tmux-resurrect + tmux-continuum` 的恢复链路重复
- 若要恢复旧行为，可将 `config/resurrect.lua` 中的 `ENABLE_WEZTERM_RESURRECT` 改为 `true`
- 开启后：
  - `CMD+SHIFT+s`：快速保存当前 Window + Workspace 状态（Tab/Pane 布局及运行中的命令）
  - `CMD+SHIFT+r`：通过 fuzzy finder 模糊搜索并恢复已保存的 window/workspace/tab 状态

### `config/theme.lua`：主题

- 当前启用 Ghostty 默认（StyleDark）主题（见 `config/theme.lua`）

### `config/keys.lua`：键位与鼠标

- `USE_WEZTERM_PANES=false`：默认把 pane 级工作流交还给 tmux；改为 `true` 可恢复原先的 WezTerm pane 行为
- `AGENT_LAUNCH_MODE` 默认随 `USE_WEZTERM_PANES` 切换：关闭 pane 工作流时新开 tab，开启时恢复右侧 split

鼠标：

- 左键双击选词后松开：复制到 Clipboard + PrimarySelection（见 `config/keys.lua:665`）
- 右键按下：从 Clipboard 粘贴（见 `config/keys.lua:673`）

快捷键（macOS）：

- `CMD+SHIFT+y`：在新标签页打开 `yazi`，并尽量使用当前 pane 的工作目录作为初始目录（见 `config/keys.lua:682`）
- `CMD+SHIFT+g/G`：在新标签页打开 `lazygit`，并以当前 pane 的工作目录作为项目目录（见 `config/keys.lua:717`）
- `CMD+SHIFT+i`：手动弹出依赖安装提示（见 `config/keys.lua:728`）
- `CMD+SHIFT+c/C`：默认在新标签页打开 `claude`；当 `USE_WEZTERM_PANES=true` 时恢复为优先切换/右侧 split `claude`
- `CMD+SHIFT+x/X`：默认在新标签页打开 `codex`；当 `USE_WEZTERM_PANES=true` 时恢复为优先切换/右侧 split `codex`
- `CMD+SHIFT+t/T`：默认在新标签页打开 `traex`（fallback: `claude`）；当 `USE_WEZTERM_PANES=true` 时恢复为优先切换/右侧 split agent pane
- `CMD+g`：跳到当前需要 attention 的 AI agent；这是用户侧主入口，内部会转发给 tmux 的 agent attention 跳转脚本
- `CMD+SHIFT+o/O`：在浏览器中打开当前选中文本中的 http/https 链接（见 `config/keys.lua:735`）
- `CMD+SHIFT+[` / `CMD+SHIFT+]`：发送 `tmux prefix + Ctrl-h/Ctrl-l`，切换到上一个/下一个 tmux window
- `CMD+1..9`：发送 `tmux prefix + 1..9`，直接切到对应 tmux window；不再用于 WezTerm tab 切换
- `F1`：进入复制模式（见 `config/keys.lua:800`）
- `CMD+h/j/k/l`：默认只提示“pane 已交给 tmux 管理”；当 `USE_WEZTERM_PANES=true` 时恢复为 WezTerm pane 焦点移动
- `CMD+SHIFT+h/j/k/l`：默认只提示“pane 已交给 tmux 管理”；当 `USE_WEZTERM_PANES=true` 时恢复为 WezTerm pane 缩放
- 新窗口：`CMD+n`（见 `config/keys.lua:863`）
- `CMD+d` / `CMD+SHIFT+D`：默认只提示“pane 已交给 tmux 管理”；当 `USE_WEZTERM_PANES=true` 时恢复为 WezTerm 分屏
- 关闭 pane：`CMD+w`（确认提示开启）（见 `config/keys.lua:870`）
- `CMD+Enter`：默认只提示“pane 已交给 tmux 管理”；当 `USE_WEZTERM_PANES=true` 时恢复为 WezTerm pane 放大/还原
- 全屏：`CMD+SHIFT+f`（见 `config/keys.lua:876`）
- `CMD+SHIFT+s/r`：默认未注册；当 `ENABLE_WEZTERM_RESURRECT=true` 时恢复为 WezTerm 状态保存/恢复

此外，`keys.lua` 内部实现了：

- `get_pane_cwd()`：兼容不同 WezTerm 版本返回的 cwd 类型（Url 对象/字符串），并提供多级兜底解析（见 `config/keys.lua:15`）
- `split_right_prefer_exec()`：优先直接启动命令，失败时退回登录 shell 执行，减少 `PATH` 或 shell 环境差异导致的问题
- `resize_pane_by_percent()`：按当前 pane 尺寸的 `5%` 做比例缩放，并对左右/上下方向分别设置最大步长

### 跨模块交互

- `keys.lua` 构建 `keys_config` 后调用 `resurrect.setup(keys_config)`；只有当 `ENABLE_WEZTERM_RESURRECT=true` 时，`resurrect.lua` 才会向 `keys_config.keys` 注入 `CMD+SHIFT+s` 和 `CMD+SHIFT+r` 快捷键。
- `deps.lua` 作为服务模块被 `keys.lua` 直接 `require`，提供命令检测与安装引导功能。

## 依赖与建议

- 建议安装字体：`JetBrainsMono Nerd Font`
- 可选依赖：`yazi`、`lazygit`、`claude`、`codex`（会在启动或按快捷键时检测并提示安装，见 `config/deps.lua:172`）
- resurrect 功能依赖 WezTerm 插件：`https://github.com/MLFlexer/resurrect.wezterm`

## 自定义入口

- 主题：编辑 `config/theme.lua`
- 字体与渲染：编辑 `config/font.lua`
- 窗口外观：编辑 `config/window.lua`
- 快捷键/鼠标：编辑 `config/keys.lua`
- Tab 栏样式：编辑 `config/tabs.lua`

## 键位速查表

| 按键 | 功能 |
|------|------|
| `CMD+SHIFT+y` | 新标签页打开 yazi |
| `CMD+SHIFT+g/G` | 新标签页打开 lazygit |
| `CMD+SHIFT+c/C` | 新标签页打开 claude |
| `CMD+SHIFT+x/X` | 新标签页打开 codex |
| `CMD+SHIFT+t/T` | 新标签页打开 traex（fallback: claude） |
| `CMD+g` | 跳到需要处理的 AI agent |
| `CMD+SHIFT+o/O` | 在浏览器中打开选中链接 |
| `CMD+SHIFT+[` | 切到上一个 tmux window |
| `CMD+SHIFT+]` | 切到下一个 tmux window |
| `CMD+SHIFT+i` | 手动触发依赖检测/安装 |
| `CMD+SHIFT+s` | 默认未启用（可恢复 WezTerm 状态保存） |
| `CMD+SHIFT+r` | 默认未启用（可恢复 WezTerm 状态恢复） |
| `F1` | 进入复制模式 |
| `CMD+1..9` | 直接切到 tmux window 1..9 |
| `CMD+h/j/k/l` | 默认提示改用 tmux 管理 pane |
| `CMD+SHIFT+h/j/k/l` | 默认提示改用 tmux 管理 pane |
| `CMD+n` | 新建窗口 |
| `CMD+d` | 默认提示改用 tmux 分屏 |
| `CMD+SHIFT+D` | 默认提示改用 tmux 分屏 |
| `CMD+w` | 关闭 pane（确认提示） |
| `CMD+Enter` | 默认提示改用 tmux pane 缩放 |
| `CMD+SHIFT+f` | 切换全屏 |

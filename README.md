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
- 基础参数：`font_size = 16.0`、`line_height = 1.1`、`cell_width = 1.0`（见 `config/font.lua:40`）
- 关闭连字：`harfbuzz_features = { "calt=0", "clig=0", "liga=0" }`（见 `config/font.lua:44`）
- 关闭 ANSI 粗体提亮（`bold_brightens_ansi_colors = false`）与 cap-height 缩放（见 `config/font.lua:40`）

### `config/window.lua`：窗口外观

- 初始窗口大小：`140x38`（见 `config/window.lua:6`）
- 启用 `use_resize_increments`，让窗口缩放按字符栅格递增（见 `config/window.lua:10`）
- 内边距：左右 20px、顶部 60px、底部 10px（见 `config/window.lua:13`）
- macOS 视觉效果：集成按钮标题栏（`INTEGRATED_BUTTONS|RESIZE`）、背景模糊(20)、半透明(0.92)（见 `config/window.lua:20`）
- titlebar 背景色统一为 `#090909`（见 `config/window.lua:24`）

### `config/macos.lua`：macOS 特性

- 左 Option 作为 Meta（Alt）更利于 Vim/Neovim 等快捷键；右 Option 保留输入法组合键（见 `config/macos.lua:5`）
- 启用原生全屏模式，不在关闭所有窗口时退出（见 `config/macos.lua:8`）
- AI pane 自动调整逻辑位于 `config/keys.lua`，在 `window-resized` 事件中触发（见下）

### `config/shell.lua`：默认 Shell 与 TERM

- 默认启动程序：优先使用 `$SHELL -l`，否则回退到 `/bin/zsh -l`（见 `config/shell.lua:4`）
- `term = "xterm-256color"`，兼容部分 CLI 程序识别逻辑

### `config/cursor.lua`：光标与滚动

- 光标样式：`BlinkingBlock`（见 `config/cursor.lua:4`）
- 回滚行数：`20000`（见 `config/cursor.lua:5`）
- 关闭滚动条（见 `config/cursor.lua:8`）
- 自定义鼠标选择的单词边界字符（见 `config/cursor.lua:11`）

### `config/tabs.lua`：Tab 栏

- Tab bar 位于底部、关闭 fancy 样式、最大宽度 `25`、关闭 index 显示（见 `config/tabs.lua:6`）
- 仅 1 个 tab 时隐藏 tab bar，关闭 tab 时切回上一个活跃 tab（见 `config/tabs.lua:8`）
- 自定义 `format-tab-title` 事件处理（见 `config/tabs.lua:115`）：
  - 根据前台进程显示对应 Nerd Font 图标（nvim/vim → ``、shell → ``、git/lazygit → ``、docker → ``、python → ``、node → ``、go → ``、lua → ``、rust → ``、yazi → ``、AI 工具 → `` 等）
  - 活跃 tab 左侧显示粉色圆点指示器（`●`）
  - AI 工具（claude/codex/trae）的前台进程会抑制 app 标题，仅显示进程名
  - Tab 标题过长时自动截断并加省略号（`…`），过短时用空格补齐
  - 颜色方案使用 Tokyo Night 色系：默认 (`#45475a`)、hover (`#7188b0`)、active (`#89b4fa`)

### `config/resurrect.lua`：状态持久化（WezTerm 插件）

- 依赖 `MLFlexer/resurrect.wezterm` 插件
- 提供 `setup(keys_config)` 函数，由 `keys.lua` 调用注入快捷键（见 `config/resurrect.lua:6`）
- `CMD+SHIFT+s`：快速保存当前 Window + Workspace 状态（Tab/Pane 布局及运行中的命令）
- `CMD+SHIFT+r`：通过 fuzzy finder 模糊搜索并恢复已保存的 window/workspace/tab 状态

### `config/theme.lua`：主题

- 当前启用 `Tokyo Night`（见 `config/theme.lua:3`）

### `config/keys.lua`：键位、鼠标与 AI Pane 管理

鼠标：

- 左键双击选词后松开：复制到 Clipboard + PrimarySelection（见 `config/keys.lua:665`）
- 右键按下：从 Clipboard 粘贴（见 `config/keys.lua:673`）

快捷键（macOS）：

- `CMD+SHIFT+y`：在新标签页打开 `yazi`，并尽量使用当前 pane 的工作目录作为初始目录（见 `config/keys.lua:682`）
- `CMD+SHIFT+g/G`：在新标签页打开 `lazygit`，并以当前 pane 的工作目录作为项目目录（见 `config/keys.lua:717`）
- `CMD+SHIFT+i`：手动弹出依赖安装提示（见 `config/keys.lua:728`）
- `CMD+SHIFT+c/C`：右侧分屏启动 `claude`；若未检测到则引导安装（见 `config/keys.lua:785`）
- `CMD+SHIFT+x/X`：右侧分屏启动 `codex`；若未检测到则引导安装（见 `config/keys.lua:746`）
- `CMD+SHIFT+t/T`：右侧分屏启动 `traecli`（按 `PATH` 查找）；若未检测到则 fallback 到 `claude`；二者都不存在会引导安装 `claude`（见 `config/keys.lua:756`）
- `CMD+SHIFT+o/O`：在浏览器中打开当前选中文本中的 http/https 链接（见 `config/keys.lua:735`）
- `F1`：进入复制模式（见 `config/keys.lua:800`）
- Pane 焦点移动：`CMD+h/j/k/l`（见 `config/keys.lua:768`）
- Pane 缩放（按比例调整，仅同一 tab 存在多个 pane 时生效）：
  - 左/右：`CMD+SHIFT+h/l`（以及 `H/L`）
  - 上/下：`CMD+SHIFT+k/j`（以及 `K/J`）
  - 步进为当前 pane 尺寸的 `5%`，左右最大 `30` 列、上下最大 `15` 行（见 `config/keys.lua:129`）
- 新窗口：`CMD+n`（见 `config/keys.lua:863`）
- 分屏：`CMD+d`（水平）、`CMD+SHIFT+D`（垂直）（见 `config/keys.lua:866`）
- 关闭 pane：`CMD+w`（确认提示开启）（见 `config/keys.lua:870`）
- 放大/还原当前 pane：`CMD+Enter`（见 `config/keys.lua:873`）
- `CMD+SHIFT+s`：保存窗口+工作区状态（resurrect，见 `config/resurrect.lua:8`）
- `CMD+SHIFT+r`：模糊搜索恢复状态（resurrect，见 `config/resurrect.lua:19`）

此外，`keys.lua` 内部实现了：

- `get_pane_cwd()`：兼容不同 WezTerm 版本返回的 cwd 类型（Url 对象/字符串），并提供多级兜底解析（见 `config/keys.lua:15`）
- AI Pane 追踪与自动调整（见 `config/keys.lua:132`）：
  - 启动 AI 工具分屏时，`remember_new_ai_pane()` 将新 pane ID 记录到 `tracked_ai_panes_by_tab`（按 tab ID 索引）
  - 监听 `window-resized` 事件，自动调整当前 active tab 中被追踪的 AI pane 宽度
  - 仅当被追踪 pane 为最右侧 pane 时才调整（避免影响用户手动布局）
  - 全屏时目标宽度 33%，非全屏时 50%（`desired_ai_panel_percent`，见 `config/keys.lua:364`）
  - macOS 原生全屏动画为异步过渡，通过多次延迟回调（0.12s / 0.35s / 0.75s）等待几何稳定
  - tab 内只剩一个 pane 或被追踪 pane 消失时自动清理追踪记录
  - 通过 `pcall` 包裹防止调整失败影响正常使用

### 跨模块交互

- `keys.lua` 构建 `keys_config` 后调用 `resurrect.setup(keys_config)`，由 `resurrect.lua` 向 `keys_config.keys` 注入 `CMD+SHIFT+s` 和 `CMD+SHIFT+r` 快捷键。这是唯一一处模块间 mutation。
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
| `CMD+SHIFT+c/C` | 右侧分屏：claude |
| `CMD+SHIFT+x/X` | 右侧分屏：codex |
| `CMD+SHIFT+t/T` | 右侧分屏：traecli（fallback: claude） |
| `CMD+SHIFT+o/O` | 在浏览器中打开选中链接 |
| `CMD+SHIFT+i` | 手动触发依赖检测/安装 |
| `CMD+SHIFT+s` | 保存窗口+工作区状态 |
| `CMD+SHIFT+r` | 模糊搜索恢复状态 |
| `F1` | 进入复制模式 |
| `CMD+h/j/k/l` | 切换 pane 焦点（左/下/上/右） |
| `CMD+SHIFT+h/j/k/l` | 调整 pane 大小（H/J/K/L 同样有效） |
| `CMD+n` | 新建窗口 |
| `CMD+d` | 水平分屏 |
| `CMD+SHIFT+D` | 垂直分屏 |
| `CMD+w` | 关闭 pane（确认提示） |
| `CMD+Enter` | 放大/还原 pane |

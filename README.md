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
- 合并策略是“同 key 覆盖”：后注册的值会覆盖先注册的值（`apply_fragment` 直接赋值，见 `config/init.lua:17`）

因此：如果两个模块写了同一个配置项，后加载/后注册的模块优先级更高。

## 功能说明（按模块）

### `config/deps.lua`：按需依赖检测与安装提示

- 仅管理与快捷键强相关的第三方工具：`yazi`、`lazygit`（见 `config/deps.lua:7`）
- 启动 GUI 时执行一次检测（同一 WezTerm GUI 进程内只提示一次），缺失则弹出选择器引导安装（见 `config/deps.lua:129`）
- 若检测到 `brew`：可一键在新标签页执行 `brew install ...`（见 `config/deps.lua:58`）
- 若未检测到 `brew`：提示并可打开 `https://brew.sh`（见 `config/deps.lua:60`）

### `config/font.lua`：字体与渲染

- 终端字体使用 `JetBrainsMono Nerd Font`（含 Nerd Font 图标），并回退到 `Apple Color Emoji`（见 `config/font.lua:6`）
- 通过 `font_rules` 调整不同强度/斜体的实际用字重与是否使用真斜体（见 `config/font.lua:12`）
- 基础参数：`font_size = 16.0`、`line_height = 1.1`、关闭连字（`harfbuzz_features`）（见 `config/font.lua:39`）

### `config/window.lua`：窗口外观

- 初始窗口大小：`110x30`（见 `config/window.lua:6`）
- 启用 `use_resize_increments`，让窗口缩放按字符栅格递增（见 `config/window.lua:10`）
- 内边距：左右 40px、顶部 70px、底部 20px（见 `config/window.lua:13`）
- macOS 视觉效果：集成按钮标题栏、背景模糊、半透明（见 `config/window.lua:20`）
- titlebar/Tab 标签使用 `window_frame.font`；当前配置为 `JetBrainsMono Nerd Font Bold`（见 `config/window.lua:24`）

### `config/macos.lua`：macOS 特性

- 左 Option 作为 Meta（Alt）更利于 Vim/Neovim 等快捷键；右 Option 保留输入法组合键（见 `config/macos.lua:5`）
- 启用原生全屏模式，不在关闭所有窗口时退出（见 `config/macos.lua:8`）

### `config/shell.lua`：默认 Shell 与 TERM

- 默认启动程序：优先使用 `$SHELL -l`，否则回退到 `/bin/zsh -l`（见 `config/shell.lua:4`）
- `term = xterm-256color`，兼容部分 CLI 程序识别逻辑（见 `config/shell.lua:12`）

### `config/cursor.lua`：光标与滚动

- 光标样式：`BlinkingBlock`（见 `config/cursor.lua:4`）
- 回滚行数：`20000`（见 `config/cursor.lua:5`）
- 关闭滚动条（见 `config/cursor.lua:8`）
- 自定义鼠标选择的单词边界字符（见 `config/cursor.lua:11`）

### `config/tabs.lua`：Tab 栏与标题格式

- Tab 栏在底部、使用 fancy tab bar、仅 1 个 tab 时隐藏（见 `config/tabs.lua:6`）
- `format-tab-title` 事件：
  - 标题中包含 tab 序号（从 1 开始）（见 `config/tabs.lua:18`）
  - 根据前台进程名推断 icon：nvim/vim、ssh/henv、docker、git；否则给一个默认 shell icon（见 `config/tabs.lua:25`）
  - 若 pane title 非空优先使用 title，否则回退使用进程名（见 `config/tabs.lua:46`）
  - 标题片段设置了 `Intensity = Bold`；实际“字形粗细”仍由 `window_frame.font` 决定（见 `config/tabs.lua:48`、`config/window.lua:24`）

### `config/theme.lua`：主题

- 当前启用 `Default Dark (base16)`（见 `config/theme.lua:9`）
- 其他主题在文件中以注释形式保留，可直接切换（见 `config/theme.lua:6`）

### `config/keys.lua`：键位与鼠标行为

鼠标：

- 左键选中后松开：复制到 Clipboard + PrimarySelection（见 `config/keys.lua:127`）
- 右键按下：从 Clipboard 粘贴（见 `config/keys.lua:136`）

快捷键（macOS）：

- `CMD+SHIFT+y`：在新标签页打开 `yazi`，并尽量使用当前 pane 的工作目录作为初始目录（见 `config/keys.lua:146`）
- `CMD+SHIFT+g`：在新标签页打开 `lazygit`，并以当前 pane 的工作目录作为项目目录（见 `config/keys.lua:177`）
- `CMD+SHIFT+i`：手动弹出依赖安装提示（见 `config/keys.lua:201`）
- `CMD+SHIFT+t`：水平分屏并启动 `traecli`（固定路径 `/Users/bytedance/.local/bin/traecli`，见 `config/keys.lua:208`）

- Pane 焦点移动：`CMD+h/j/k/l`（见 `config/keys.lua:213`）
- 进入复制模式：`CMD+SHIFT+c`（见 `config/keys.lua:229`）

- Pane 缩放（按比例调整，仅同一 tab 存在多个 pane 时生效）：
  - 左/右：`CMD+SHIFT+h/l`（以及 `H/L`）
  - 上/下：`CMD+SHIFT+k/j`（以及 `K/J`）
  - 步进为当前 pane 尺寸的 `5%`，并对最大步进做了限制（见 `config/keys.lua:49`）

- 新窗口：`CMD+n`（见 `config/keys.lua:298`）
- 分屏：`CMD+d`（水平）、`CMD+SHIFT+D`（垂直）（见 `config/keys.lua:301`）
- 关闭 pane：`CMD+w`（确认提示开启）（见 `config/keys.lua:305`）
- 放大/还原当前 pane：`CMD+Enter`（见 `config/keys.lua:308`）

此外，`keys.lua` 内部实现了 `get_pane_cwd()` 以兼容不同 WezTerm 版本返回的 cwd 类型（Url 对象/字符串），并提供多级兜底解析（见 `config/keys.lua:13`）。

## 依赖与建议

- 建议安装字体：`JetBrainsMono Nerd Font`（Tab 标题的 icon 依赖 Nerd Font 字形，见 `config/tabs.lua:28`）
- 可选依赖：`yazi`、`lazygit`（会在启动或按快捷键时检测并提示安装，见 `config/deps.lua:132`）

## 自定义入口

- 主题：编辑 `config/theme.lua`
- 字体与渲染：编辑 `config/font.lua`
- 窗口外观：编辑 `config/window.lua`
- 快捷键/鼠标：编辑 `config/keys.lua`

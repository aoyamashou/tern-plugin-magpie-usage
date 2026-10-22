# Tern 插件开发备忘

这份记录来自 `magpie-quotas` 第一版的开发和实际运行验证，供后续并行开发插件时复用。当前仓库根目录本身就是一个插件包：`plugin.toml` 声明插件，`window.luau` 实现状态栏和详情面板，`README.md` 说明安装与行为。本机验证时使用 Tern `0.9.5`。

## 先选对运行位置

Tern 插件是带 `plugin.toml` 的 Luau 包，可有两份入口，各在独立 VM 中运行：

| 入口 | 运行位置 | 适合做的事 |
| --- | --- | --- |
| `host.luau` | 运行 pane 的 session daemon；没有 daemon 时由窗口承担 | 自定义 block、命令输出 lens、pane 和 shell 生命周期钩子、spawn filter |
| `window.luau` | 每个 Tern 窗口的 UI 线程 | 命令面板、快捷键、状态栏、路由、布局、Canvas、Carly 导出 |

Magpie 额度只需读取本机网关并显示在当前窗口，因此第一版只用了 `window.luau`。窗口插件会在每个窗口各运行一次；不要假定它们共享 Luau 内存。Web 客户端不运行 window Lua。需要跨窗口、随 daemon 存活的原生 pane 时，再考虑 host block。[SDK 概览](https://docs.stencil.so/tern/index.html)、[Blocks](https://docs.stencil.so/tern/guides/blocks.html)

## 这次用到的模式

1. **异步读取外部数据。** `tern.fetch(url, opts, callback)` 不阻塞 UI；回调收到新鲜的 `cx`。不要把命令或事件处理器中的旧 `cx` 留给回调。进程调用 `tern.process.run` 也是异步的，适合封装已有 CLI。[Shared API](https://docs.stencil.so/tern/reference/api-shared.html)
2. **状态栏只读内存快照。** `tern.chrome.status` 没有 `cx`，预算仅 4 ms，而且结果会缓存。网络请求放在定时器或命令回调中；数据变化后调用 `tern.chrome.refresh()`。状态栏片段的 `command` 可以指向 `plugin.<插件 ID>.<命令 ID>`，实现点击打开详情。[Chrome and Styling](https://docs.stencil.so/tern/guides/chrome.html)
3. **详情用 Canvas。** `cx.canvas:open` 创建原生 pane，`cx.canvas:set` 更新视图，`tern.on("canvas_action", ...)` 接收按钮点击。Canvas 会在插件重载后保留，所以打开时先用 `cx.canvas:list()` 查找自己的 pane，避免重复创建。当前代码按 `owner` 和标题查找；更复杂的插件宜有稳定的识别约定。[Canvas API](https://docs.stencil.so/tern/reference/api-window.html)、[Canvas 示例源码](https://github.com/stencil-hq/tern-sdk/tree/main/plugins/examples/canvas)
4. **定时器是单次的。** 每轮轮询都要再次安排 `tern.timer`。插件重载会丢弃旧 VM 的待执行回调。[Shared API](https://docs.stencil.so/tern/reference/api-shared.html)
5. **区分 UI 的 tone 名称。** 状态栏警告色用 `warn`，视图 badge 用 `warning`；两个接口不能直接复用同一个 tone 字符串。[状态栏片段](https://docs.stencil.so/tern/guides/chrome.html)、[视图节点](https://docs.stencil.so/tern/guides/views.html)

## Magpie 数据接入的已验证事实

- 本机 Magpie 网关在 `127.0.0.1:3425` 运行；实际端口可从 `~/.config/magpie/settings.json` 或 `$XDG_CONFIG_HOME/magpie/settings.json` 的 `port` 读取。`GET /api/hello` 可用于识别服务。
- `GET /v1/magpie/quotas?kept=1` 返回 Magpie 上次读取的额度，不触发供应商查询，适合定时显示；不带 `kept=1` 的接口用于手动刷新。返回顶层为 `{object, data}`，`data` 是额度卡片数组。卡片可含 `provider`、`name`、`plan`、`readAt` 和 `windows`；窗口可含 `name`、`used`、`remaining`、`display`、`resetsAt`。字段会随供应商而异，渲染前要检查类型。第一版每分钟读缓存，只有按钮触发实时读取。[Magpie 接入文档](https://usemagpie.ai/docs/zh/integrate)、[Magpie 参考](https://github.com/yetone/magpie/blob/main/docs/reference.md)
- 这台机器的 `magpie` 命令不在当前 shell 的 `PATH` 中，但 HTTP 网关可用。不要把 CLI 存在当成网关可用的前提。
- 本机可从回环地址直接访问额度接口；远程网关涉及 gateway key 和权限。状态栏展示账号名称时考虑隐私，避免默认显示完整邮箱。[Magpie 接入文档](https://usemagpie.ai/docs/zh/integrate)

## 开发与验证

新插件建议各有独立目录和唯一 `id`，例如 `plugins/<id>/plugin.toml`。当前 Magpie 插件仍在仓库根目录；并行代理不要同时编辑根目录的 `plugin.toml`、`window.luau`。每个插件至少交付 manifest、入口文件、简短 README，并报告实际加载和交互结果。

常用命令：

```sh
tern plugin types /path/to/plugin       # 生成与本机 Tern 匹配的 tern.d.luau
tern plugin link /path/to/plugin        # 链接目录，保存后自动重载
tern plugin list --json                 # 查看清单和加载问题
tern plugin reload --json               # 手动重载
```

`tern plugin list` 的 `ready` 不能替代窗口交互验证：没有 daemon 时，它甚至只表示 manifest 解析成功。这次曾在 `tern serve` 的 headless 窗口运行插件 action，命令返回 `{"ok":true}`，但窗口实际显示 `No plugin has this action`。最终使用带 `--control` 的真实 Tern 窗口验证，确认状态栏、Canvas 和按钮行为。`tern help dev` 列出 `ctl` 的控制命令。[Getting Started](https://docs.stencil.so/tern/guides/getting-started.html)

多个代理同时测试时，为每个代理分配独立的临时配置目录、daemon socket 和 control socket，避免互相覆盖插件目录或扰动正在使用的 Tern 会话。一个测试环境的流程是：

```sh
QA_DIR=$(mktemp -d /tmp/tern-plugin-qa.XXXXXX)
export TERN_CONFIG_DIR="$QA_DIR/config"
export TERN_DAEMON_SOCKET="$QA_DIR/daemon.sock"
tern plugin link /path/to/plugin
tern daemon --socket "$TERN_DAEMON_SOCKET"          # 终端 A，保持运行
tern --control "$QA_DIR/control.sock"                # 终端 B，真实测试窗口
# 终端 C 设置相同的 QA_DIR 后执行：
tern ctl --control "$QA_DIR/control.sock" plugins run plugin.<id>.<command>
tern ctl --control "$QA_DIR/control.sock" tree '#statusline'
tern ctl --control "$QA_DIR/control.sock" quit
```

三个终端须使用相同的 `QA_DIR`；终端 C 只需要它就能连接 control socket。关掉测试窗口后，再停止测试 daemon。隔离环境可能默认关闭状态栏；需要先运行 Tern 的 `status_bar` action 才能检查片段。这次验证还通过点击 Canvas 的刷新按钮，确认额度卡片从缓存的 2 张更新为实时返回的 7 张，且窗口日志没有插件错误。

## 并行开发时的接口约定

- 先给每个代理分配一个独立插件目录和 `id`。测试时各用自己的 `TERN_CONFIG_DIR`、`TERN_DAEMON_SOCKET` 和 control socket；不要把未验证的插件链接到日常使用的 Tern 配置。
- 每个插件自己负责外部服务的地址发现、超时、错误提示和过期数据展示。UI 线程的 handler 应快速返回；慢操作走 `tern.fetch`、`tern.process.run` 或异步 API。
- 新插件若要提供 Carly 函数，用 `tern.carly.export`；它只在本地桌面 window 插件中可用，返回值通过 JSON 传递，单次上限 16 KiB。不要为已经由 Tern 内置 `cx.git`、`cx.agents` 等提供的基础能力再造一层。[Extending Carly](https://docs.stencil.so/tern/guides/carly.html)、[Window API](https://docs.stencil.so/tern/reference/api-window.html)
- 插件能以当前用户权限读写文件、运行程序和发网络请求；安装即信任。只链接自己审过的代码，尤其不要把凭据写进仓库或日志。[Trust and Security](https://docs.stencil.so/tern/concepts/security.html)

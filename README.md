# Tern Magpie 额度插件

在 Tern 状态栏显示 Magpie 各账号的剩余额度。点击额度，或在命令面板运行 **打开 Magpie 额度**，即可打开原生详情面板。面板提供 **刷新** 按钮。

插件读取本机 Magpie 网关的 `/v1/magpie/quotas` 接口。它会从 `~/.config/magpie/settings.json`（或 `$XDG_CONFIG_HOME/magpie/settings.json`）读取自定义端口，否则使用 `3425`。状态栏每分钟读取一次 Magpie 已缓存的额度；点击 **刷新** 才会请求 Magpie 重新查询。Magpie 需运行在 Tern 窗口所在的电脑上。

## 开发安装

```sh
tern plugin link /path/to/tern-plugin
tern plugin list
```

Tern 会在文件变化时重载链接的插件。要移除它，运行 `tern plugin unlink magpie-quotas`。如果没有看到额度，先在 Tern 中打开状态栏。

状态栏最多显示三个账号，每个账号显示其额度窗口中最低的剩余比例。红色表示剩余不超过 5%，黄色表示不超过 20%。详情面板显示全部账号、额度窗口和更新时间；刷新失败时保留上次成功读取的数据。

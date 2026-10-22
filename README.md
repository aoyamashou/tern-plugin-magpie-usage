# Tern Magpie Quotas Plugin

**English** | [简体中文](README.zh-CN.md)

Show the remaining quota for each Magpie account in Tern's status bar. Click a quota, or run **打开 Magpie 额度** (Open Magpie Quotas) from the command palette, to open the native detail pane. The pane has a **刷新** (Refresh) button.

The plugin reads the `/v1/magpie/quotas` endpoint from a local Magpie gateway. It checks `~/.config/magpie/settings.json` (or `$XDG_CONFIG_HOME/magpie/settings.json`) for a custom port and otherwise uses `3425`. Once a minute, the status bar reads quota data cached by Magpie. Only clicking **刷新** asks Magpie to query the providers again. Magpie must be running on the same computer as the Tern window.

## Install for development

```sh
tern plugin link /path/to/tern-plugin
tern plugin list
```

Tern reloads the linked plugin when its files change. To remove it, run `tern plugin unlink magpie-quotas`. If no quotas appear, enable Tern's status bar first.

The status bar shows up to three accounts. Each account shows the lowest remaining percentage across its quota windows. Red means 5% or less remains; yellow means 20% or less. The detail pane shows every account, quota window, and update time. If a refresh fails, the pane keeps the last successfully loaded data.

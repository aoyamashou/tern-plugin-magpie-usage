--!strict

local ui = tern.ui
local TITLE = "Magpie 额度"
local POLL_MS = 60 * 1000
local MAX_STATUS_CARDS = 3

local cards: { any } = {}
local loading = false
local last_error: string? = nil

local function gateway_url(): string
	local config_home = tern.getenv("XDG_CONFIG_HOME")
	local home = tern.getenv("HOME") or ""
	local config_dir = if config_home and config_home ~= "" then config_home else home .. "/.config"
	local path = config_dir .. "/magpie/settings.json"
	local port = 3425
	local ok, contents = pcall(tern.fs.read, path, 64 * 1024)
	if ok and type(contents) == "string" then
		local decoded_ok, settings = pcall(tern.json.decode, contents)
		if decoded_ok and type(settings) == "table" and type(settings.port) == "number" then
			local configured = settings.port
			if configured >= 1 and configured <= 65535 and configured % 1 == 0 then
				port = configured
			end
		end
	end
	return "http://127.0.0.1:" .. tostring(port)
end

local base_url = gateway_url()

local function display_name(card: any): string
	if type(card.alias) == "string" and card.alias ~= "" then
		return card.alias
	end
	if type(card.name) == "string" and card.name ~= "" then
		return card.name
	end
	if type(card.provider) == "string" and card.provider ~= "" then
		return card.provider
	end
	return "Account"
end

local function percentage(value: any): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(value, 0, 100)
end

local function percent_text(value: number): string
	if value < 10 or (value > 99 and value < 100) then
		return string.format("%.1f%%", value)
	end
	return string.format("%.0f%%", value)
end

local function remaining(card: any): number?
	local lowest: number? = nil
	if type(card.windows) ~= "table" then
		return nil
	end
	for _, window in card.windows do
		if type(window) == "table" and window.aside ~= true then
			local value = percentage(window.remaining)
			if value == nil and type(window.used) == "number" then
				value = percentage(100 - window.used)
			end
			if value ~= nil and (lowest == nil or value < lowest) then
				lowest = value
			end
		end
	end
	return lowest
end

local function status_tone(left: number?): string
	if left == nil then
		return "muted"
	elseif left <= 5 then
		return "error"
	elseif left <= 20 then
		return "warn"
	end
	return "accent"
end

local function view_tone(left: number?): string
	local tone = status_tone(left)
	return if tone == "warn" then "warning" else tone
end

local function status_segments(_pane: PaneInfo): { StatusSegment }
	local action = "plugin.magpie-quotas.open"
	if #cards == 0 then
		return { {
			text = if last_error then "Magpie 无法连接" elseif loading then "Magpie 读取中…" else "Magpie · 无额度",
			tone = if last_error then "error" else "muted",
			command = action,
		} }
	end

	local segments: { StatusSegment } = {}
	if last_error then
		table.insert(segments, { text = "Magpie 数据未更新", tone = "error", command = action })
	end
	for index, card in cards do
		if index > MAX_STATUS_CARDS then
			break
		end
		local left = remaining(card)
		local label = display_name(card)
		table.insert(segments, {
			text = label .. " " .. (if left then percent_text(left) else "—"),
			tone = status_tone(left),
			command = action,
		})
	end
	if #cards > MAX_STATUS_CARDS then
		table.insert(segments, { text = "+" .. tostring(#cards - MAX_STATUS_CARDS), command = action })
	end
	return segments
end

local function quota_view(): Node
	local children: { Node } = {
		ui.row({
			ui.text("Magpie 额度"),
			ui.node("badge", {
				key = "refresh",
				text = if loading then "刷新中…" else "刷新",
				tone = "accent",
				actions = { click = "refresh" },
			}),
		}),
	}

	if last_error then
		table.insert(children, ui.badge("刷新失败：" .. last_error, "error"))
	end
	if #cards == 0 then
		table.insert(children, ui.text(if loading then "正在读取 Magpie 额度…" else "没有找到订阅额度。"))
	end

	for index, card in cards do
		local details: { Node } = {}
		local plan = if type(card.plan) == "string" and card.plan ~= "" then " · " .. card.plan else ""
		if type(card.error) == "string" and card.error ~= "" then
			table.insert(details, ui.badge(card.error, "error"))
		end
		if type(card.windows) == "table" then
			for _, window in card.windows do
				if type(window) == "table" then
					local name = if type(window.name) == "string" then window.name else "额度"
					local left = percentage(window.remaining)
					local value = if left then "剩余 " .. percent_text(left) else "剩余额度未知"
					table.insert(details, ui.row({ ui.text(name), ui.badge(value, view_tone(left)) }))
					if type(window.used) == "number" then
						table.insert(details, ui.progress(math.clamp(window.used / 100, 0, 1)))
					end
					if type(window.display) == "string" and window.display ~= "" then
						table.insert(details, ui.text(window.display))
					end
					if type(window.resetsAt) == "string" then
						table.insert(details, ui.text("重置时间 " .. window.resetsAt))
					end
				end
			end
		end
		if #details == 0 then
			table.insert(details, ui.text("没有额度窗口数据。"))
		end
		if type(card.readAt) == "string" then
			table.insert(details, ui.text("更新于 " .. card.readAt))
		end
		local title = display_name(card) .. plan
		local panel = ui.card({ ui.span(title, "strong") }, details)
		panel.p = panel.p or {}
		panel.p.key = "card-" .. tostring(index)
		table.insert(children, panel)
	end
	return ui.col(children)
end

local function update_canvases(cx: WindowCx)
	local view = quota_view()
	for _, canvas in cx.canvas:list() do
		if canvas.owner == tern.plugin.id and canvas.title == TITLE then
			cx.canvas:set(canvas.pane, { view = view })
		end
	end
end

local function read_quotas(live: boolean)
	if loading then
		return
	end
	loading = true
	tern.chrome.refresh()
	local url = base_url .. "/v1/magpie/quotas" .. (if live then "" else "?kept=1")
	tern.fetch(url, { timeout_ms = 15000 }, function(result, cx)
		loading = false
		if result.error then
			last_error = result.error
		elseif result.status ~= 200 then
			last_error = "HTTP " .. tostring(result.status)
		else
			local ok, response = pcall(tern.json.decode, result.body)
			if ok and type(response) == "table" and type(response.data) == "table" then
				cards = response.data
				last_error = nil
			else
			last_error = "Magpie 返回的数据格式不正确"
			end
		end
		tern.chrome.refresh()
		if cx then
			update_canvases(cx)
		end
	end)
end

local function poll()
	read_quotas(false)
	tern.timer(POLL_MS, poll)
end

tern.chrome.status(status_segments)

tern.command({
	id = "open",
	title = "打开 Magpie 额度",
	icon = "meter",
	run = function(cx)
		for _, canvas in cx.canvas:list() do
			if canvas.owner == tern.plugin.id and canvas.title == TITLE then
				cx.canvas:set(canvas.pane, { view = quota_view() })
				cx.layout:focus(canvas.pane)
				return
			end
		end
		local pane, err = cx.canvas:open({
			title = TITLE,
			about = "显示本机 Magpie 网关报告的订阅额度。点击刷新会让 Magpie 重新读取额度。",
			view = quota_view(),
			how = "beside",
		})
		if not pane then
			cx:toast("error", "无法打开 Magpie 额度", err)
		end
	end,
})

tern.on("canvas_action", function(event, cx)
	if event.owner ~= tern.plugin.id or event.act ~= "refresh" then
		return false
	end
	read_quotas(true)
	update_canvases(cx)
	return true
end)

poll()

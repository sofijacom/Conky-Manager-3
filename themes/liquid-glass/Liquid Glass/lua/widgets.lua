--[[
  widgets.lua - Liquid Glass widgets for Conky

  Every widget config calls:  lua_draw_hook_pre = 'glass_main <widget> <scale>'
  Widgets: clock, weather, system, network, storage, processes, media
]]

---------------------------------------------------------------- settings

SETTINGS = {
	-- Clock: true for 12-hour time (3:07 PM)
	twelve_hour = false,
	-- Clock: first day of the week strip, 1 = Sunday, 2 = Monday
	week_start = 2,

	-- Weather: city name, airport code or "lat,lon"; empty = detect from your IP
	weather_location = '',
	-- Weather: 'm' metric, 'u' US units, '' = wttr.in decides from your location
	weather_units = '',
	-- Weather: refresh interval in seconds
	weather_refresh = 900,

	-- Network: interface to show; empty = the one holding the default route
	network_interface = '',
}

-- Your own settings go in settings.lua in the pack folder: it is read after
-- these defaults and is kept when the pack is updated.
do
	local dir = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
	local path = dir .. '/../settings.lua'
	local f = io.open(path, 'r')
	if f then
		f:close()
		local ok, err = pcall(dofile, path)
		if not ok then io.stderr:write('liquid-glass settings.lua: ' .. tostring(err) .. '\n') end
	end
end

---------------------------------------------------------------- setup

local script_dir = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local G = dofile(script_dir .. '/glass.lua')
local T = G.theme
local M = 14 -- margin around panels, leaves room for the shadow

local function parse(s)
	return conky_parse(s) or ''
end

local function num(s)
	return tonumber((parse(s):gsub(',', '.'))) or 0
end

local function read_file(path)
	local f = io.open(path, 'r')
	if not f then return nil end
	local s = f:read('*a')
	f:close()
	return s
end

local function sh(cmd)
	local p = io.popen(cmd .. ' 2>/dev/null')
	if not p then return '' end
	local s = p:read('*a') or ''
	p:close()
	return s
end

local function trim(s)
	return (s or ''):match('^%s*(.-)%s*$')
end

-- KiB/s -> human readable rate
local function fmt_rate(kib)
	local b = kib * 1024
	if b < 1000 then return string.format('%.0f B/s', b) end
	if b < 1000 * 1000 then return string.format('%.0f KB/s', b / 1000) end
	if b < 1000 * 1000 * 1000 then return string.format('%.1f MB/s', b / 1e6) end
	return string.format('%.2f GB/s', b / 1e9)
end

local function header(cr, x, y, title)
	G.text(cr, title, x, y, {size = 13, weight = 'bold', color = T.sub})
end

local function header_right(cr, x, y, text)
	G.text(cr, text, x, y, {size = 12, color = T.faint, align = 'right', max_width = 170})
end

-- LIQUID_GLASS_DEMO=1 shows sample data instead of yours (used for the preview images)
local DEMO = os.getenv('LIQUID_GLASS_DEMO') == '1'

local W = {}

---------------------------------------------------------------- clock

function W.clock(cr, w, h)
	local px, py, pw, ph = M, M, w - 2 * M, h - 2 * M
	G.panel(cr, px, py, pw, ph)

	local now = os.time()
	local t = os.date('*t', now)
	local time_str, ampm
	if SETTINGS.twelve_hour then
		time_str = tostring(((t.hour + 11) % 12) + 1) .. os.date(':%M', now)
		ampm = t.hour < 12 and 'AM' or 'PM'
	else
		time_str = os.date('%H:%M', now)
	end

	local x = px + 22
	local tw = G.text(cr, time_str, x - 2, py + 72, {size = 64, weight = 'light'})
	if ampm then
		G.text(cr, ampm, x + tw + 6, py + 72, {size = 16, color = T.sub})
	end
	G.text(cr, os.date('%A, %B ', now) .. t.day, x, py + 100, {size = 16, color = T.sub})

	-- week strip
	local wday = t.wday -- 1 = Sunday
	local offset = (wday - SETTINGS.week_start) % 7
	local cell = (pw - 44) / 7
	local sy = py + 118
	for i = 0, 6 do
		local day = now + (i - offset) * 86400
		local cx = x + i * cell + cell / 2
		local letter = os.date('%a', day):match('^[%z\1-\127\194-\244][\128-\191]*') or ''
		local today = (i == offset)
		if today then
			G.chip(cr, cx - cell / 2 + 3, sy, cell - 6, 44, 14, T.accent, 1)
		end
		G.text(cr, letter, cx, sy + 17, {size = 11, align = 'center', color = today and T.text or T.faint, weight = today and 'bold' or nil})
		G.text(cr, tostring(os.date('*t', day).day), cx, sy + 36, {size = 14, align = 'center', color = today and T.text or T.sub, weight = today and 'bold' or nil})
	end
end

---------------------------------------------------------------- weather

local weather = {data = nil, fetched = 0, cache = nil}

local function weather_cache_path()
	local base = os.getenv('XDG_RUNTIME_DIR') or '/tmp'
	return base .. '/conky-liquid-glass-weather-' .. (os.getenv('USER') or 'user')
end

local function weather_fetch()
	local loc = SETTINGS.weather_location:gsub(' ', '+'):gsub("'", '')
	local url = 'https://wttr.in/' .. loc .. '?format=%C|%t|%f|%h|%w|%l'
	if SETTINGS.weather_units ~= '' then url = url .. '&' .. SETTINGS.weather_units end
	local path = weather_cache_path()
	-- runs in the background so the desktop never waits on the network
	os.execute(string.format("(curl -fsS --max-time 15 '%s' > '%s.tmp' && mv '%s.tmp' '%s') >/dev/null 2>&1 &",
		url, path, path, path))
end

local function weather_kind(cond, hour)
	local c = cond:lower()
	local night = hour < 6 or hour >= 19
	if c:find('thunder') then return 'storm' end
	if c:find('snow') or c:find('sleet') or c:find('ice') or c:find('blizzard') then return 'snow' end
	if c:find('rain') or c:find('drizzle') or c:find('shower') then return 'rain' end
	if c:find('fog') or c:find('mist') or c:find('haze') or c:find('smoke') then return 'fog' end
	if c:find('partly') then return night and 'partly_night' or 'partly' end
	if c:find('cloud') or c:find('overcast') then return 'cloud' end
	if c:find('clear') or c:find('sunny') then return night and 'moon' or 'sun' end
	return 'cloud'
end

function W.weather(cr, w, h)
	local px, py, pw, ph = M, M, w - 2 * M, h - 2 * M
	G.panel(cr, px, py, pw, ph)

	local now = os.time()
	if now - weather.fetched >= SETTINGS.weather_refresh then
		weather.fetched = now
		weather_fetch()
	end
	local raw = read_file(weather_cache_path())
	if DEMO then raw = 'Partly cloudy|+22°C|+21°C|48%|↗9km/h|Lisbon, Portugal' end
	if raw and raw:find('|') and not raw:find('<') then
		local f = {}
		for part in (trim(raw) .. '|'):gmatch('(.-)|') do f[#f + 1] = trim(part) end
		weather.data = f
	elseif now - weather.fetched > 60 and not weather.data then
		-- first fetch failed; retry in a minute
		weather.fetched = now - SETTINGS.weather_refresh + 60
	end

	local x = px + 22
	if not weather.data then
		G.weather_icon(cr, 'cloud', x + 34, py + ph / 2, 34)
		G.text(cr, 'Weather', x + 86, py + ph / 2 - 4, {size = 18, weight = 'bold'})
		G.text(cr, 'Waiting for wttr.in…', x + 86, py + ph / 2 + 18, {size = 13, color = T.sub})
		return
	end

	local cond, temp, feels, hum, wind, loc = table.unpack(weather.data)
	temp = (temp or ''):gsub('^%+', '')
	feels = (feels or ''):gsub('^%+', '')
	-- wttr.in prefixes the wind with a direction arrow most fonts lack
	wind = (wind or ''):gsub('\226\134[\128-\191]', ''):gsub('\226\135[\128-\191]', '')
	loc = (loc or ''):gsub(',.*', '')
	loc = loc:gsub('^%l', string.upper)

	G.weather_icon(cr, weather_kind(cond or '', os.date('*t').hour), x + 36, py + 56, 36)
	local tx = x + 92
	G.text(cr, temp, tx, py + 66, {size = 44, weight = 'light'})
	G.text(cr, cond or '', tx, py + 92, {size = 14, color = T.sub, max_width = pw - (tx - px) - 20})

	G.divider(cr, px + 18, py + ph - 44, pw - 36)
	local by = py + ph - 18
	G.text(cr, loc ~= '' and loc or 'Here', x, by, {size = 12, color = T.faint, max_width = pw * 0.36})
	local right = string.format('Feels %s   ·   %s   ·   %s', feels, hum or '', wind or '')
	G.text(cr, right, px + pw - 22, by, {size = 12, color = T.sub, align = 'right', max_width = pw * 0.58})
end

---------------------------------------------------------------- system

local temp_input = nil

local function cpu_temp()
	if temp_input == nil then
		temp_input = false
		local preferred = {coretemp = 1, k10temp = 1, zenpower = 1, cpu_thermal = 1, ['soc_thermal'] = 1}
		local fallback
		for i = 0, 15 do
			local name = trim(read_file('/sys/class/hwmon/hwmon' .. i .. '/name') or '')
			local input = '/sys/class/hwmon/hwmon' .. i .. '/temp1_input'
			if name ~= '' and read_file(input) then
				if preferred[name] then temp_input = input break end
				if name == 'acpitz' and not fallback then fallback = input end
			end
		end
		if not temp_input and fallback then temp_input = fallback end
	end
	if not temp_input then return nil end
	local v = tonumber(read_file(temp_input) or '')
	return v and v / 1000 or nil
end

local function battery()
	for i = 0, 3 do
		local base = '/sys/class/power_supply/BAT' .. i
		local cap = tonumber(trim(read_file(base .. '/capacity') or ''))
		if cap then
			return cap, trim(read_file(base .. '/status') or '')
		end
	end
	return nil
end

local hostname = DEMO and 'workstation' or trim(read_file('/proc/sys/kernel/hostname') or '')

local function ring_with_label(cr, cx, cy, frac, value, label, c1, c2)
	G.ring(cr, cx, cy, 34, 8, frac, c1, c2)
	G.text(cr, value, cx, cy + 6, {size = 17, weight = 'bold', align = 'center'})
	G.text(cr, label, cx, cy + 62, {size = 12, color = T.sub, align = 'center'})
end

function W.system(cr, w, h)
	local px, py, pw, ph = M, M, w - 2 * M, h - 2 * M
	G.panel(cr, px, py, pw, ph)
	local x = px + 22
	header(cr, x, py + 30, 'System')
	header_right(cr, px + pw - 22, py + 30, hostname)

	local cpu = num('${cpu cpu0}')
	local mem = num('${memperc}')
	local temp = cpu_temp()

	local cy = py + 92
	local step = (pw - 44) / 3
	ring_with_label(cr, x + step * 0.5, cy, cpu / 100, string.format('%d%%', cpu), 'CPU', T.accent, T.accent2)
	ring_with_label(cr, x + step * 1.5, cy, mem / 100, string.format('%d%%', mem), 'Memory', T.accent2, {1, 0.45, 0.75})
	if temp then
		local frac = G.clamp((temp - 30) / 70, 0, 1)
		local c = G.level_color(frac)
		ring_with_label(cr, x + step * 2.5, cy, frac, string.format('%d°', math.floor(temp + 0.5)), 'Temp', c, G.mix(c, {1, 1, 1}, 0.3))
	else
		local swap = num('${swapperc}')
		ring_with_label(cr, x + step * 2.5, cy, swap / 100, string.format('%d%%', swap), 'Swap', T.green, T.accent)
	end

	G.divider(cr, px + 18, py + 176, pw - 36)

	local rows = {
		{'Memory', trim(parse('${mem}')) .. ' of ' .. trim(parse('${memmax}'))},
		{'Load', trim(parse('${loadavg}'))},
		{'Uptime', trim(parse('${uptime_short}'))},
	}
	local cap, status = battery()
	if cap then
		local state = (status == 'Charging' and ' · charging') or (status == 'Full' and ' · full') or ''
		rows[#rows + 1] = {'Battery', cap .. '%' .. state}
	end
	local ry = py + 202
	for _, r in ipairs(rows) do
		G.text(cr, r[1], x, ry, {size = 13, color = T.sub})
		G.text(cr, r[2], px + pw - 22, ry, {size = 13, align = 'right'})
		ry = ry + 22
	end
end

---------------------------------------------------------------- network

local net = {down = {}, up = {}}
local HISTORY = 48

local function push(list, v)
	list[#list + 1] = v
	if #list > HISTORY then table.remove(list, 1) end
end

function W.network(cr, w, h)
	local px, py, pw, ph = M, M, w - 2 * M, h - 2 * M
	G.panel(cr, px, py, pw, ph)
	local x = px + 22

	local iface = SETTINGS.network_interface
	if iface == '' then iface = trim(parse('${gw_iface}')) end
	if iface == '' or iface == 'multiple' or iface == '(null)' then
		header(cr, x, py + 30, 'Network')
		G.text(cr, 'Offline', x, py + 80, {size = 22, weight = 'light'})
		return
	end

	local down = num('${downspeedf ' .. iface .. '}')
	local up = num('${upspeedf ' .. iface .. '}')
	push(net.down, down)
	push(net.up, up)

	local essid = ''
	if DEMO then
		essid = 'Home Wi-Fi'
	elseif iface:sub(1, 1) == 'w' then
		essid = trim(parse('${wireless_essid ' .. iface .. '}'))
	end
	header(cr, x, py + 30, 'Network')
	header_right(cr, px + pw - 22, py + 30, essid ~= '' and essid or iface)

	-- current speeds
	local half = (pw - 44) / 2
	G.arrow(cr, x + 5, py + 57, 11, 'down', T.accent)
	G.text(cr, fmt_rate(down), x + 16, py + 64, {size = 20})
	G.arrow(cr, x + half + 5, py + 57, 11, 'up', T.accent2)
	G.text(cr, fmt_rate(up), x + half + 16, py + 64, {size = 20})

	-- graph
	local gx, gy, gw, gh = x, py + 80, pw - 44, 64
	G.rrect(cr, gx - 6, gy - 4, gw + 12, gh + 8, 12)
	cairo_set_source_rgba(cr, 0, 0, 0, 0.12)
	cairo_fill(cr)
	local peak = 1
	for _, v in ipairs(net.down) do peak = math.max(peak, v) end
	for _, v in ipairs(net.up) do peak = math.max(peak, v) end
	G.graph(cr, gx, gy, gw, gh, net.down, peak * 1.15, T.accent, true)
	G.graph(cr, gx, gy, gw, gh, net.up, peak * 1.15, T.accent2, false)

	local by = py + ph - 18
	G.text(cr, DEMO and '192.168.1.24' or trim(parse('${addr ' .. iface .. '}')), x, by, {size = 12, color = T.faint})
	local rx = px + pw - 22
	local up_w = G.text(cr, trim(parse('${totalup ' .. iface .. '}')), rx, by, {size = 12, color = T.sub, align = 'right'})
	G.arrow(cr, rx - up_w - 8, by - 4, 8, 'up', T.accent2)
	rx = rx - up_w - 22
	local down_w = G.text(cr, trim(parse('${totaldown ' .. iface .. '}')), rx, by, {size = 12, color = T.sub, align = 'right'})
	G.arrow(cr, rx - down_w - 8, by - 4, 8, 'down', T.accent)
end

---------------------------------------------------------------- storage

local mounts_cache, mounts_time = nil, 0

-- real disks only: no loop devices, snaps, /boot or system-internal mounts
local function wanted_mount(dev, mp, fs)
	if not dev:find('^/dev/') or dev:find('^/dev/loop') then return false end
	if mp:find('\\') or fs == 'squashfs' then return false end -- '\040' = space in path
	if mp:find('^/run/media/') or mp:find('^/media/') then return true end
	for _, prefix in ipairs({'^/boot', '^/snap', '^/var/', '^/run/', '^/tmp', '^/efi'}) do
		if mp:find(prefix) then return false end
	end
	return true
end

local function list_mounts()
	if DEMO then return {'/', '/home'} end
	if mounts_cache and os.time() - mounts_time < 30 then return mounts_cache end
	local list, seen = {}, {}
	for line in (read_file('/proc/mounts') or ''):gmatch('[^\n]+') do
		local dev, mp, fs = line:match('^(%S+)%s+(%S+)%s+(%S+)')
		if dev and wanted_mount(dev, mp, fs) then
			if not seen[dev] then
				seen[dev] = true
				list[#list + 1] = mp
			end
		end
	end
	table.sort(list, function(a, b)
		if a == '/' then return true end
		if b == '/' then return false end
		return a < b
	end)
	while #list > 4 do table.remove(list) end
	mounts_cache, mounts_time = list, os.time()
	return list
end

local function mount_label(mp)
	if mp == '/' then return 'System' end
	if mp == '/home' then return 'Home' end
	return mp:match('([^/]+)$') or mp
end

function W.storage(cr, w, h)
	local mounts = list_mounts()
	local px, py, pw = M, M, w - 2 * M
	local ph = math.min(h - 2 * M, 96 + #mounts * 52)
	G.panel(cr, px, py, pw, ph)
	local x = px + 22
	header(cr, x, py + 30, 'Storage')

	local y = py + 62
	for _, mp in ipairs(mounts) do
		local perc = num('${fs_used_perc ' .. mp .. '}')
		local free = trim(parse('${fs_free ' .. mp .. '}'))
		local size = trim(parse('${fs_size ' .. mp .. '}'))
		if DEMO then
			perc, free, size = table.unpack(mp == '/' and {38, '61.2GiB', '98.3GiB'} or {87, '112GiB', '869GiB'})
		end
		G.text(cr, mount_label(mp), x, y, {size = 14, weight = 'bold', max_width = pw * 0.4})
		G.text(cr, free .. ' free of ' .. size, px + pw - 22, y, {size = 12, color = T.sub, align = 'right'})
		local c = perc / 100 >= 0.85 and T.red or T.accent
		G.bar(cr, x, y + 10, pw - 44, 12, perc / 100, c, perc / 100 >= 0.85 and T.orange or T.accent2)
		y = y + 52
	end

	G.divider(cr, px + 18, py + ph - 40, pw - 36)
	local by = py + ph - 16
	G.text(cr, 'Read  ' .. trim(parse('${diskio_read}')), x, by, {size = 12, color = T.sub})
	G.text(cr, 'Write  ' .. trim(parse('${diskio_write}')), px + pw - 22, by, {size = 12, color = T.sub, align = 'right'})
end

---------------------------------------------------------------- processes

function W.processes(cr, w, h)
	local px, py, pw, ph = M, M, w - 2 * M, h - 2 * M
	G.panel(cr, px, py, pw, ph)
	local x = px + 22
	header(cr, x, py + 30, 'Top processes')
	header_right(cr, px + pw - 22, py + 30, 'CPU   ·   Memory')

	local y = py + 62
	local demo_top = {{'firefox', 18.4, '1.2GiB'}, {'gnome-shell', 6.1, '412MiB'}, {'code', 4.7, '836MiB'},
		{'Xorg', 2.3, '256MiB'}, {'pipewire', 0.9, '38MiB'}}
	for i = 1, 5 do
		local name = trim(parse('${top name ' .. i .. '}'))
		local cpu = num('${top cpu ' .. i .. '}')
		local mem = trim(parse('${top mem_res ' .. i .. '}'))
		if DEMO then name, cpu, mem = table.unpack(demo_top[i]) end
		if name ~= '' then
			G.text(cr, name, x, y, {size = 13, max_width = pw * 0.45})
			G.text(cr, mem, px + pw - 22, y, {size = 12, color = T.sub, align = 'right'})
			G.text(cr, string.format('%.1f%%', cpu), px + pw - 100, y, {size = 13, align = 'right', weight = 'bold'})
			local frac = G.clamp(cpu / 100, 0, 1)
			G.bar(cr, x, y + 8, pw - 44, 5, frac, G.level_color(frac), T.accent)
		end
		y = y + 36
	end
end

---------------------------------------------------------------- media

local has_playerctl = sh('command -v playerctl') ~= ''

local function fmt_time(sec)
	sec = math.floor(sec or 0)
	return string.format('%d:%02d', sec // 60, sec % 60)
end

function W.media(cr, w, h)
	local px, py, pw, ph = M, M, w - 2 * M, h - 2 * M
	G.panel(cr, px, py, pw, ph)
	local x = px + 18

	local art = 64
	local ay = py + (ph - art) / 2
	G.chip(cr, x, ay, art, art, 16, T.accent2, 1)
	G.note_icon(cr, x + art / 2, ay + art / 2, art * 0.5)
	local tx = x + art + 16
	local tw = px + pw - 22 - tx

	if not has_playerctl and not DEMO then
		G.text(cr, 'Now Playing', tx, py + ph / 2 - 4, {size = 16, weight = 'bold'})
		G.text(cr, 'Install playerctl to show music', tx, py + ph / 2 + 18, {size = 12, color = T.sub, max_width = tw})
		return
	end

	local out = DEMO and 'Playing\tLuna Vale\tGlass Horizons\t83000000\t214000000'
		or trim(sh("playerctl metadata --format '{{status}}\t{{artist}}\t{{title}}\t{{position}}\t{{mpris:length}}'"))
	local status, artist, title, pos, len = out:match('^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$')
	if not status or (title or '') == '' then
		G.text(cr, 'Not playing', tx, py + ph / 2 - 4, {size = 16, weight = 'bold'})
		G.text(cr, 'Start music in any player', tx, py + ph / 2 + 18, {size = 12, color = T.sub, max_width = tw})
		return
	end

	G.text(cr, title, tx, py + 40, {size = 16, weight = 'bold', max_width = tw})
	G.text(cr, artist ~= '' and artist or status, tx, py + 60, {size = 13, color = T.sub, max_width = tw})
	local p, l = (tonumber(pos) or 0) / 1e6, (tonumber(len) or 0) / 1e6
	G.bar(cr, tx, py + 74, tw, 6, l > 0 and p / l or 0, T.text, T.sub)
	G.text(cr, fmt_time(p), tx, py + 98, {size = 11, color = T.faint})
	G.text(cr, status == 'Paused' and 'Paused' or ('-' .. fmt_time(math.max(l - p, 0))), tx + tw, py + 98, {size = 11, color = T.faint, align = 'right'})
end

---------------------------------------------------------------- entry point

function conky_glass_main(name, design_w, design_h)
	if conky_window == nil then return end
	-- Scale the design size to fit the window: this follows conky's own HiDPI
	-- scaling, and a smaller or larger minimum_width/height zooms the widget.
	local dw = tonumber(design_w) or conky_window.width
	local dh = tonumber(design_h) or conky_window.height
	local s = math.min(conky_window.width / dw, conky_window.height / dh)
	if s <= 0 then return end
	G.scale = s
	local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
		conky_window.visual, conky_window.width, conky_window.height)
	local cr = cairo_create(cs)
	cairo_scale(cr, s, s)

	local fn = W[name]
	if fn then
		local ok, err = pcall(fn, cr, dw, dh)
		if not ok then io.stderr:write('liquid-glass ' .. name .. ': ' .. tostring(err) .. '\n') end
	end

	cairo_destroy(cr)
	cairo_surface_destroy(cs)
end

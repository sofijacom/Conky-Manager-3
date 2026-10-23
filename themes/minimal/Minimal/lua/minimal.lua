--[[
  minimal.lua - modern, minimal clock widgets for Conky (Cairo)

  Plain typography straight on the wallpaper: thin numerals, letter-spaced
  labels, outline weather icons and a month calendar. A soft shadow keeps
  them readable on bright wallpapers; switch to dark text below if yours is light.

  Every widget config calls:  lua_draw_hook_pre = 'minimal_main <widget> <width> <height>'
  Clocks for the top middle: hero, calendar, weekday, bar
  Desktop set (same data as Liquid Glass): week, weather, system, network,
  storage, processes, media
  System monitor: monitor (CPU, GPU, memory, temperatures, fans, disks, network)
]]

---------------------------------------------------------------- settings

SETTINGS = {
	-- true for 12-hour time (4:07 PM)
	twelve_hour = false,
	-- first day of the week in the calendar, 1 = Sunday, 2 = Monday
	week_start = 2,

	-- 'auto' picks white or black text from the brightness of your wallpaper's
	-- top-middle area; 'light' = always white, 'dark' = always black
	text = 'auto',
	-- accent used for today in the calendar ({r, g, b}, 0..1); nil = same as the text
	accent = nil,
	-- soft shadow behind text and icons (helps on busy wallpapers)
	shadow = true,

	-- Weather: city name, airport code or "lat,lon"; empty = detect from your IP
	weather_location = '',
	-- 'm' metric, 'u' US units, '' = wttr.in decides from your location
	weather_units = '',
	-- refresh interval in seconds
	weather_refresh = 900,
	-- false hides the weather line
	show_weather = true,

	-- Network: interface to show; empty = the one holding the default route
	network_interface = '',
}

---------------------------------------------------------------- setup

require 'cairo'
pcall(require, 'cairo_xlib')

-- MINIMAL_DEMO=1 shows sample weather (used to render the preview images)
local DEMO = os.getenv('MINIMAL_DEMO') == '1'

local function font_installed(family)
	local p = io.popen('fc-list -q "' .. family .. '" && echo yes')
	if not p then return false end
	local out = p:read('*a') or ''
	p:close()
	return out:find('yes') ~= nil
end

-- true if fontconfig resolves `family` to a face whose style contains `style`
-- (e.g. "Ubuntu Light" also holds Ubuntu Medium, which fontconfig may pick)
local function resolves_to(family, style)
	local p = io.popen('fc-match -f "%{style}" "' .. family .. '" 2>/dev/null')
	if not p then return false end
	local out = p:read('*a') or ''
	p:close()
	return out:find(style) ~= nil
end

-- FONT_LIGHT = nil means light is drawn as the thin face with a fine outline
local FONT, FONT_LIGHT, FONT_THIN = 'Sans', nil, nil
for _, family in ipairs({'Inter', 'SF Pro Display', 'Ubuntu', 'Cantarell', 'Noto Sans', 'DejaVu Sans'}) do
	if font_installed(family) then
		FONT = family
		if resolves_to(family .. ' Light', 'Light') then FONT_LIGHT = family .. ' Light' end
		if resolves_to(family .. ' Thin', 'Thin') then FONT_THIN = family .. ' Thin' end
		break
	end
end

---------------------------------------------------------------- automatic text color

local function trim(s)
	return (s or ''):match('^%s*(.-)%s*$')
end

local function sh(cmd)
	local p = io.popen(cmd .. ' 2>/dev/null')
	if not p then return '' end
	local s = p:read('*a') or ''
	p:close()
	return s
end

local function read_file(path)
	local f = io.open(path, 'r')
	if not f then return nil end
	local s = f:read('*a')
	f:close()
	return s
end

local function wallpaper_path()
	local override = os.getenv('MINIMAL_WALLPAPER')
	if override and override ~= '' then return override end
	local uri = ''
	for _, key in ipairs({'org.cinnamon.desktop.background picture-uri',
			'org.gnome.desktop.background picture-uri', 'org.mate.background picture-filename'}) do
		uri = trim(sh('gsettings get ' .. key)):gsub("^'", ''):gsub("'$", '')
		if uri ~= '' then break end
	end
	if uri:find('^file://') then
		uri = uri:sub(8):gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
	end
	return uri
end

-- part of the wallpaper each widget sits on: ImageMagick gravity + crop size
local REGIONS = {
	center = {'north', '50%x30%'},  -- top-middle clocks
	right = {'northeast', '25%x85%'},  -- right column
	left = {'northwest', '25%x85%'},   -- left column
}
local WIDGET_REGION = {
	week = 'right', weather = 'right', system = 'right', media = 'right',
	network = 'left', processes = 'left', storage = 'left',
	monitor = 'right',
}

local auto = {checked = -1e9, path = nil, dark = false}

local function auto_cache(region)
	return (os.getenv('XDG_RUNTIME_DIR') or '/tmp') .. '/conky-minimal-luminance-' .. region .. '-' .. (os.getenv('USER') or 'user')
end

-- true when the wallpaper behind this widget is light, so text should be dark
local function wallpaper_is_light(region)
	local now = os.time()
	if now - auto.checked >= 30 then
		auto.checked = now
		local path = wallpaper_path()
		if path ~= auto.path then
			auto.path = path
			os.remove(auto_cache(region))
			if path ~= '' then
				-- measure that part of the wallpaper in the background
				local q = path:gsub("'", "'\\''")
				local r = REGIONS[region]
				os.execute(string.format("(IM=$(command -v magick || command -v convert); \"$IM\" '%s' -gravity %s -crop %s+0+0 +repage -resize 1x1\\! "
					.. "-format '%%[fx:luminance]' info: > '%s.tmp' 2>/dev/null && mv '%s.tmp' '%s') >/dev/null 2>&1 &",
					q, r[1], r[2], auto_cache(region), auto_cache(region), auto_cache(region)))
			end
		end
	end
	local lum = tonumber(trim(read_file(auto_cache(region)) or ''))
	if lum then auto.dark = lum > 0.62 end
	return auto.dark
end

local function dark_text(region)
	if SETTINGS.text == 'dark' then return true end
	if SETTINGS.text == 'auto' then return wallpaper_is_light(region) end
	return false
end

local DARK = false -- decided once per frame in conky_minimal_main

local function ink(alpha)
	if DARK then return {0.08, 0.09, 0.12, alpha} end
	return {1, 1, 1, alpha}
end

local function shadow_rgb()
	if DARK then return 1, 1, 1 end
	return 0, 0, 0
end

local function accent()
	local a = SETTINGS.accent
	if a then return {a[1], a[2], a[3], 1} end
	return ink(1)
end

---------------------------------------------------------------- text

local extents = nil

-- returns the outline width to emulate this weight (0 = draw normally)
local function set_font(cr, size, weight)
	local family, w, outline = FONT, CAIRO_FONT_WEIGHT_NORMAL, 0
	if weight == 'thin' then
		family = FONT_THIN or FONT_LIGHT or FONT
	elseif weight == 'light' then
		if FONT_LIGHT then
			family = FONT_LIGHT
		elseif FONT_THIN then
			family, outline = FONT_THIN, size * 0.018
		end
	elseif weight == 'bold' then
		w = CAIRO_FONT_WEIGHT_BOLD
	end
	cairo_select_font_face(cr, family, CAIRO_FONT_SLANT_NORMAL, w)
	cairo_set_font_size(cr, size)
	return outline
end

local function advance(cr, str)
	if not extents then
		extents = cairo_text_extents_t:create()
		if tolua and tolua.takeownership then tolua.takeownership(extents) end
	end
	cairo_text_extents(cr, str, extents)
	return extents.x_advance
end

-- split a UTF-8 string into characters
local function chars(str)
	local list = {}
	for ch in str:gmatch('[%z\1-\127\194-\244][\128-\191]*') do list[#list + 1] = ch end
	return list
end

-- width of str with extra letter spacing (tracking) between characters
local function measure(cr, str, size, weight, tracking)
	set_font(cr, size, weight)
	tracking = tracking or 0
	if tracking == 0 then return advance(cr, str) end
	local w, list = 0, chars(str)
	for _, ch in ipairs(list) do w = w + advance(cr, ch) end
	return w + tracking * math.max(#list - 1, 0)
end

-- draws str with the current source; outline > 0 thickens the glyphs
local function show(cr, str, x, y, tracking, outline)
	local pieces = {str}
	if tracking and tracking ~= 0 then pieces = chars(str) end
	for _, piece in ipairs(pieces) do
		cairo_move_to(cr, x, y)
		if outline and outline > 0 then
			cairo_text_path(cr, piece)
			cairo_set_line_width(cr, outline)
			cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
			cairo_fill_preserve(cr)
			cairo_stroke(cr)
		else
			cairo_show_text(cr, piece)
		end
		x = x + advance(cr, piece) + (tracking or 0)
	end
end

--[[ opts: size, weight ('thin'|'light'|'normal'|'bold'), alpha, color,
     align ('left'|'center'|'right'), tracking (px between letters) ]]
local function text(cr, str, x, y, opts)
	opts = opts or {}
	str = tostring(str or '')
	local size = opts.size or 14
	local w = measure(cr, str, size, opts.weight, opts.tracking)
	if opts.max_width and w > opts.max_width then
		-- drop whole characters until it fits, then add an ellipsis
		local list = chars(str)
		while #list > 1 and w > opts.max_width do
			table.remove(list)
			str = table.concat(list) .. '…'
			w = measure(cr, str, size, opts.weight, opts.tracking)
		end
	end
	local outline = set_font(cr, size, opts.weight)
	if opts.align == 'center' then x = x - w / 2 elseif opts.align == 'right' then x = x - w end

	if SETTINGS.shadow then
		-- soft shadow: the glyph outlines, slightly lowered, stroked wide and faint
		-- (a few calls per text instead of many offset copies)
		local r, g, b = shadow_rgb()
		local radius = math.min(math.max(1, size / 40), 3)
		cairo_save(cr)
		cairo_new_path(cr)
		local px = x
		local pieces = (opts.tracking and opts.tracking ~= 0) and chars(str) or {str}
		for _, piece in ipairs(pieces) do
			cairo_move_to(cr, px, y + radius * 0.8)
			cairo_text_path(cr, piece)
			px = px + advance(cr, piece) + (opts.tracking or 0)
		end
		cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
		cairo_set_source_rgba(cr, r, g, b, 0.05)
		cairo_set_line_width(cr, radius * 4 + outline)
		cairo_stroke_preserve(cr)
		cairo_set_source_rgba(cr, r, g, b, 0.07)
		cairo_set_line_width(cr, radius * 2 + outline)
		cairo_stroke_preserve(cr)
		cairo_set_source_rgba(cr, r, g, b, 0.12)
		cairo_fill(cr)
		cairo_restore(cr)
	end
	local c = opts.color or ink(opts.alpha or 1)
	cairo_set_source_rgba(cr, c[1], c[2], c[3], (c[4] or 1) * (opts.color and (opts.alpha or 1) or 1))
	show(cr, str, x, y, opts.tracking, outline)
	cairo_new_path(cr)
	return w
end

local function hairline(cr, x0, y0, x1, y1, alpha)
	cairo_set_line_width(cr, 1)
	local c = ink(alpha or 0.35)
	cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4])
	cairo_move_to(cr, x0, y0)
	cairo_line_to(cr, x1, y1)
	cairo_stroke(cr)
end

---------------------------------------------------------------- outline weather icons

-- adds a cloud outline as a new sub-path (callers start the path)
local function cloud_path(cr, x, y, s)
	cairo_new_sub_path(cr)
	cairo_arc(cr, x - 0.5 * s, y + 0.1 * s, 0.28 * s, math.pi / 2, 1.5 * math.pi)
	cairo_arc(cr, x - 0.02 * s, y - 0.12 * s, 0.4 * s, 1.08 * math.pi, 1.92 * math.pi)
	cairo_arc(cr, x + 0.5 * s, y + 0.12 * s, 0.26 * s, 1.5 * math.pi, 2.5 * math.pi)
	cairo_close_path(cr)
end

local function sun_shape(cr, x, y, s)
	cairo_new_path(cr)
	cairo_arc(cr, x, y, 0.3 * s, 0, 2 * math.pi)
	for i = 0, 7 do
		local a = i * math.pi / 4
		cairo_move_to(cr, x + math.cos(a) * 0.45 * s, y + math.sin(a) * 0.45 * s)
		cairo_line_to(cr, x + math.cos(a) * 0.62 * s, y + math.sin(a) * 0.62 * s)
	end
end

local function moon_shape(cr, x, y, s)
	cairo_new_path(cr)
	cairo_arc(cr, x, y, 0.36 * s, 0.25 * math.pi, 1.75 * math.pi)
	cairo_arc_negative(cr, x + 0.2 * s, y - 0.06 * s, 0.3 * s, 1.55 * math.pi, 0.45 * math.pi)
	cairo_close_path(cr)
end

-- draws path-building function f as a stroked line with a shadow
local function line_art(cr, width, f)
	cairo_set_line_width(cr, width)
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
	cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
	if SETTINGS.shadow then
		local r, g, b = shadow_rgb()
		cairo_save(cr)
		cairo_translate(cr, 0, 1.2)
		f()
		cairo_set_source_rgba(cr, r, g, b, 0.22)
		cairo_set_line_width(cr, width + 1.5)
		cairo_stroke(cr)
		cairo_restore(cr)
		cairo_set_line_width(cr, width)
	end
	f()
	local c = ink(1)
	cairo_set_source_rgba(cr, c[1], c[2], c[3], 0.95)
	cairo_stroke(cr)
end

-- kind: sun, moon, partly, partly_night, cloud, rain, snow, storm, fog
local function weather_icon(cr, kind, x, y, s)
	local lw = math.max(1.4, s * 0.075)
	cairo_save(cr)
	if kind == 'sun' then
		line_art(cr, lw, function() sun_shape(cr, x, y, s) end)
	elseif kind == 'moon' then
		line_art(cr, lw, function() moon_shape(cr, x, y, s) end)
	elseif kind == 'partly' or kind == 'partly_night' then
		local cx, cy, cs = x + 0.1 * s, y + 0.15 * s, s * 0.8
		-- sun/moon peeking out: clip it to outside the cloud
		cairo_save(cr)
		cairo_new_path(cr)
		cairo_rectangle(cr, x - 2 * s, y - 2 * s, 4 * s, 4 * s)
		cloud_path(cr, cx, cy, cs * 1.12)
		cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD)
		cairo_clip(cr)
		if kind == 'partly' then
			line_art(cr, lw, function() sun_shape(cr, x - 0.28 * s, y - 0.22 * s, s * 0.8) end)
		else
			line_art(cr, lw, function() moon_shape(cr, x - 0.28 * s, y - 0.22 * s, s * 0.8) end)
		end
		cairo_restore(cr)
		line_art(cr, lw, function() cairo_new_path(cr) cloud_path(cr, cx, cy, cs) end)
	elseif kind == 'rain' or kind == 'snow' or kind == 'storm' then
		line_art(cr, lw, function() cairo_new_path(cr) cloud_path(cr, x, y - 0.15 * s, s * 0.85) end)
		line_art(cr, lw, function()
			cairo_new_path(cr)
			if kind == 'rain' then
				for i = -1, 1 do
					cairo_move_to(cr, x + i * 0.3 * s + 0.06 * s, y + 0.4 * s)
					cairo_line_to(cr, x + i * 0.3 * s - 0.06 * s, y + 0.62 * s)
				end
			elseif kind == 'snow' then
				for i = -1, 1 do
					local px, py = x + i * 0.3 * s, y + 0.52 * s
					cairo_move_to(cr, px - 0.07 * s, py)
					cairo_line_to(cr, px + 0.07 * s, py)
					cairo_move_to(cr, px, py - 0.07 * s)
					cairo_line_to(cr, px, py + 0.07 * s)
				end
			else
				cairo_move_to(cr, x + 0.06 * s, y + 0.32 * s)
				cairo_line_to(cr, x - 0.1 * s, y + 0.55 * s)
				cairo_line_to(cr, x + 0.08 * s, y + 0.55 * s)
				cairo_line_to(cr, x - 0.06 * s, y + 0.8 * s)
			end
		end)
	elseif kind == 'fog' then
		line_art(cr, lw, function()
			cairo_new_path(cr)
			for i = 0, 2 do
				local yy = y - 0.25 * s + i * 0.25 * s
				cairo_move_to(cr, x - 0.55 * s + (i % 2) * 0.12 * s, yy)
				cairo_line_to(cr, x + 0.55 * s - ((i + 1) % 2) * 0.12 * s, yy)
			end
		end)
	else
		line_art(cr, lw, function() cairo_new_path(cr) cloud_path(cr, x, y, s * 0.9) end)
	end
	cairo_restore(cr)
end

---------------------------------------------------------------- data

local function time_parts(now)
	local t = os.date('*t', now)
	if SETTINGS.twelve_hour then
		return tostring(((t.hour + 11) % 12) + 1) .. os.date(':%M', now), (t.hour < 12) and 'AM' or 'PM'
	end
	return os.date('%H:%M', now), nil
end

local weather = {data = nil, fetched = 0}

local function weather_cache_path()
	return (os.getenv('XDG_RUNTIME_DIR') or '/tmp') .. '/conky-minimal-weather-' .. (os.getenv('USER') or 'user')
end

local function weather_fetch()
	local loc = SETTINGS.weather_location:gsub(' ', '+'):gsub("'", '')
	local url = 'https://wttr.in/' .. loc .. '?format=%C|%t|%f|%h|%w|%l'
	if SETTINGS.weather_units ~= '' then url = url .. '&' .. SETTINGS.weather_units end
	local path = weather_cache_path()
	-- in the background, so the desktop never waits on the network
	os.execute(string.format("(curl -fsS --max-time 15 '%s' > '%s.tmp' && mv '%s.tmp' '%s') >/dev/null 2>&1 &",
		url, path, path, path))
end

local function weather_kind(cond, hour)
	local c = (cond or ''):lower()
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

-- returns {kind, temp, cond, place} or nil
local function get_weather()
	if not SETTINGS.show_weather then return nil end
	local raw
	if DEMO then
		raw = 'Partly cloudy|+22°C|+21°C|48%|↗9km/h|Lisbon, Portugal'
	else
		local now = os.time()
		if now - weather.fetched >= SETTINGS.weather_refresh then
			weather.fetched = now
			weather_fetch()
		end
		raw = read_file(weather_cache_path())
		if (not raw or not raw:find('|')) and now - weather.fetched > 60 then
			weather.fetched = now - SETTINGS.weather_refresh + 60 -- retry in a minute
		end
	end
	if raw and raw:find('|') and not raw:find('<') then
		local f = {}
		for part in (trim(raw) .. '|'):gmatch('(.-)|') do f[#f + 1] = trim(part) end
		local temp = (f[2] or ''):gsub('^%+', ''):gsub('[CF]$', '')
		local place = (f[6] or ''):gsub(',.*', ''):gsub('^%l', string.upper)
		local feels = (f[3] or ''):gsub('^%+', ''):gsub('[CF]$', '')
		-- wttr.in prefixes the wind with a direction arrow most fonts lack
		local wind = (f[5] or ''):gsub('\226\134[\128-\191]', ''):gsub('\226\135[\128-\191]', '')
		weather.data = {kind = weather_kind(f[1], os.date('*t').hour), temp = temp, cond = f[1] or '',
			place = place, feels = feels, humidity = f[4] or '', wind = wind}
	end
	return weather.data
end

-- icon + "22°  Partly cloudy" (+ place); returns its width. align: 'left'|'center'|'right'
local function weather_line(cr, x, y, size, align, with_place)
	local w = get_weather()
	if not w then return 0 end
	local icon = size * 1.5
	local gap = size * 0.55
	local label = w.temp .. '   ' .. w.cond
	if with_place and w.place ~= '' then label = label .. '  ·  ' .. w.place end
	local tw = measure(cr, label, size, 'normal')
	local total = icon + gap + tw
	local x0 = x
	if align == 'center' then x0 = x - total / 2 elseif align == 'right' then x0 = x - total end
	weather_icon(cr, w.kind, x0 + icon / 2, y - size * 0.35, icon)
	text(cr, label, x0 + icon + gap, y, {size = size, alpha = 0.85})
	return total
end

---------------------------------------------------------------- calendar

local function month_calendar(cr, x, y, cell, opts)
	opts = opts or {}
	local now = os.date('*t')
	local first = os.date('*t', os.time({year = now.year, month = now.month, day = 1, hour = 12}))
	local days = os.date('*t', os.time({year = now.year, month = now.month + 1, day = 0, hour = 12})).day
	local offset = (first.wday - SETTINGS.week_start) % 7

	-- header: month name, letter-spaced
	text(cr, os.date('%B'):upper(), x, y, {size = cell * 0.36, weight = 'bold', tracking = cell * 0.09, alpha = 0.9})

	-- weekday initials
	local wy = y + cell * 0.95
	for i = 0, 6 do
		local wd = (SETTINGS.week_start - 1 + i) % 7 -- 0 = Sunday
		-- a date known to be that weekday: 2023-01-01 was a Sunday
		local stamp = os.time({year = 2023, month = 1, day = 1 + wd, hour = 12})
		local letter = chars(os.date('%a', stamp))[1] or ''
		text(cr, letter, x + i * cell + cell / 2, wy, {size = cell * 0.34, align = 'center', alpha = 0.5})
	end

	-- days
	local size = cell * 0.4
	for d = 1, days do
		local idx = offset + d - 1
		local col, row = idx % 7, idx // 7
		local cx = x + col * cell + cell / 2
		local cy = wy + cell * 0.95 + row * cell * 0.92
		local weekday = (SETTINGS.week_start - 1 + col) % 7
		local weekend = (weekday == 0 or weekday == 6)
		if d == now.day then
			local a = accent()
			cairo_arc(cr, cx, cy - size * 0.36, cell * 0.42, 0, 2 * math.pi)
			cairo_set_source_rgba(cr, a[1], a[2], a[3], 0.95)
			cairo_fill(cr)
			-- cut the number out of the dot so the wallpaper shows through
			cairo_save(cr)
			cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
			set_font(cr, size, 'bold')
			local tw = advance(cr, tostring(d))
			cairo_move_to(cr, cx - tw / 2, cy)
			cairo_show_text(cr, tostring(d))
			cairo_restore(cr)
			cairo_new_path(cr)
		else
			text(cr, tostring(d), cx, cy, {size = size, align = 'center', alpha = weekend and 0.55 or 0.85})
		end
	end
end

---------------------------------------------------------------- widgets

local W = {}

-- big centered time, date, weather
function W.hero(cr, w, h)
	local now = os.time()
	local cx = w / 2
	local time_str, ampm = time_parts(now)
	local tw = measure(cr, time_str, 132, 'thin')
	text(cr, time_str, cx - (ampm and 18 or 0), 128, {size = 132, weight = 'thin', align = 'center'})
	if ampm then
		text(cr, ampm, cx - 18 + tw / 2 + 8, 128, {size = 22, weight = 'light', alpha = 0.8})
	end
	text(cr, os.date('%A, %B ', now) .. os.date('*t', now).day, cx, 170,
		{size = 22, weight = 'light', align = 'center', alpha = 0.9})
	weather_line(cr, cx, 222, 17, 'center', true)
end

-- time + date + weather on the left, month calendar on the right
function W.calendar(cr, w, h)
	local now = os.time()
	local time_str, ampm = time_parts(now)
	local left = 24
	local tw = text(cr, time_str, left - 4, 104, {size = 108, weight = 'thin'})
	if ampm then text(cr, ampm, left + tw + 4, 104, {size = 20, weight = 'light', alpha = 0.8}) end
	text(cr, os.date('%A', now):upper(), left, 146, {size = 15, weight = 'bold', tracking = 4, alpha = 0.9})
	text(cr, os.date('%B ', now) .. os.date('*t', now).day .. os.date(', %Y', now), left, 172,
		{size = 17, weight = 'light', alpha = 0.8})
	weather_line(cr, left, 222, 16, 'left', true)

	local cal_x = w - 24 - 7 * 36
	hairline(cr, cal_x - 30, 24, cal_x - 30, h - 24, 0.3)
	month_calendar(cr, cal_x, 40, 36)
end

-- letter-spaced weekday, big time, date and weather
function W.weekday(cr, w, h)
	local now = os.time()
	local cx = w / 2
	text(cr, os.date('%A', now):upper(), cx, 40, {size = 20, weight = 'bold', tracking = 12, align = 'center', alpha = 0.95})
	local time_str, ampm = time_parts(now)
	local tw = measure(cr, time_str, 108, 'normal')
	text(cr, time_str, cx - (ampm and 16 or 0), 150, {size = 108, weight = 'normal', align = 'center'})
	if ampm then text(cr, ampm, cx - 16 + tw / 2 + 8, 152, {size = 20, weight = 'light', alpha = 0.8}) end
	hairline(cr, cx - 40, 178, cx + 40, 178, 0.5)
	local date = tostring(os.date('*t', now).day) .. ' ' .. os.date('%B', now)
	local weather_w = 0
	local wd = get_weather()
	if wd then
		text(cr, date, cx - 14, 214, {size = 18, weight = 'light', align = 'right', alpha = 0.9})
		weather_line(cr, cx + 14, 214, 18, 'left', false)
	else
		text(cr, date, cx, 214, {size = 18, weight = 'light', align = 'center', alpha = 0.9})
	end
end

-- one slim line: time | date | weather
function W.bar(cr, w, h)
	local now = os.time()
	local time_str, ampm = time_parts(now)
	local date = os.date('%a, %b ', now) .. os.date('*t', now).day
	local y = h / 2 + 12
	local size = 30

	local wt = get_weather()
	local parts_w = measure(cr, time_str .. (ampm and (' ' .. ampm) or ''), size, 'normal')
		+ measure(cr, date, 20, 'light') + 2 * 44
	if wt then
		parts_w = parts_w + 44 + 20 * 1.5 + 11 + measure(cr, wt.temp .. '   ' .. wt.cond, 20, 'normal')
	end
	local x = w / 2 - parts_w / 2

	x = x + text(cr, time_str .. (ampm and (' ' .. ampm) or ''), x, y, {size = size, weight = 'normal'})
	hairline(cr, x + 22, y - 24, x + 22, y + 4, 0.45)
	x = x + 44
	x = x + text(cr, date, x, y - 2, {size = 20, weight = 'light', alpha = 0.9})
	if wt then
		hairline(cr, x + 22, y - 24, x + 22, y + 4, 0.45)
		x = x + 44
		weather_line(cr, x, y - 2, 20, 'left', false)
	end
end


---------------------------------------------------------------- desktop set helpers

local function parse(str)
	return conky_parse(str) or ''
end

local function num(str)
	return tonumber((parse(str):gsub(',', '.'))) or 0
end

local HOT = {1, 0.62, 0.38, 1}

-- small letter-spaced section label with an optional dim note on the right
local function label(cr, title, x, y, w, note)
	text(cr, title:upper(), x, y, {size = 11, weight = 'bold', tracking = 3, alpha = 0.75})
	if note and note ~= '' then
		text(cr, note, x + w, y, {size = 12, weight = 'light', align = 'right', alpha = 0.6})
	end
end

-- stroked path with the same soft shadow as text
local function stroke_with_shadow(cr, width, color, build)
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
	if SETTINGS.shadow then
		local r, g, b = shadow_rgb()
		cairo_save(cr)
		cairo_translate(cr, 0, 1)
		build()
		cairo_set_source_rgba(cr, r, g, b, 0.18)
		cairo_set_line_width(cr, width + 2)
		cairo_stroke(cr)
		cairo_restore(cr)
	end
	build()
	cairo_set_source_rgba(cr, color[1], color[2], color[3], color[4] or 1)
	cairo_set_line_width(cr, width)
	cairo_stroke(cr)
end

-- hairline ring gauge, frac 0..1
local function ring(cr, cx, cy, r, frac, color)
	frac = math.max(0, math.min(frac or 0, 1))
	stroke_with_shadow(cr, 2.5, ink(0.18), function()
		cairo_new_path(cr)
		cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
	end)
	if frac > 0.003 then
		stroke_with_shadow(cr, 3, color or ink(0.95), function()
			cairo_new_path(cr)
			cairo_arc(cr, cx, cy, r, -math.pi / 2, -math.pi / 2 + frac * 2 * math.pi)
		end)
	end
end

-- thin rounded bar, frac 0..1
local function bar(cr, x, y, w, frac, thickness, color)
	frac = math.max(0, math.min(frac or 0, 1))
	thickness = thickness or 3
	stroke_with_shadow(cr, thickness, ink(0.18), function()
		cairo_new_path(cr)
		cairo_move_to(cr, x, y)
		cairo_line_to(cr, x + w, y)
	end)
	if frac > 0.003 then
		stroke_with_shadow(cr, thickness, color or ink(0.95), function()
			cairo_new_path(cr)
			cairo_move_to(cr, x, y)
			cairo_line_to(cr, x + math.max(w * frac, 0.1), y)
		end)
	end
end

-- thin sparkline; values oldest -> newest
local function sparkline(cr, x, y, w, h, values, maxv, alpha, filled)
	local n = #values
	if n < 2 then return end
	maxv = math.max(maxv or 0, 1e-9)
	local step = w / (n - 1)
	local function pt(i)
		return x + (i - 1) * step, y + h - math.min(values[i] / maxv, 1) * h
	end
	local function path()
		cairo_new_path(cr)
		cairo_move_to(cr, pt(1))
		for i = 2, n do
			local x0, y0 = pt(i - 1)
			local x1, y1 = pt(i)
			local mx = (x0 + x1) / 2
			cairo_curve_to(cr, mx, y0, mx, y1, x1, y1)
		end
	end
	if filled then
		path()
		cairo_line_to(cr, x + w, y + h)
		cairo_line_to(cr, x, y + h)
		cairo_close_path(cr)
		local c = ink(1)
		local pat = cairo_pattern_create_linear(0, y, 0, y + h)
		cairo_pattern_add_color_stop_rgba(pat, 0, c[1], c[2], c[3], 0.22 * alpha)
		cairo_pattern_add_color_stop_rgba(pat, 1, c[1], c[2], c[3], 0)
		cairo_set_source(cr, pat)
		cairo_fill(cr)
		cairo_pattern_destroy(pat)
	end
	stroke_with_shadow(cr, 1.6, ink(alpha), path)
end

local function arrow(cr, x, y, size, dir, alpha)
	local d = (dir == 'up') and -1 or 1
	stroke_with_shadow(cr, 1.8, ink(alpha or 0.9), function()
		cairo_new_path(cr)
		cairo_move_to(cr, x, y - d * size * 0.5)
		cairo_line_to(cr, x, y + d * size * 0.5)
		cairo_move_to(cr, x - size * 0.35, y + d * size * 0.15)
		cairo_line_to(cr, x, y + d * size * 0.5)
		cairo_line_to(cr, x + size * 0.35, y + d * size * 0.15)
	end)
end

-- label left, value right
local function row(cr, x, y, w, name, value)
	text(cr, name, x, y, {size = 14, weight = 'light', alpha = 0.7})
	text(cr, value, x + w, y, {size = 14, align = 'right', alpha = 0.95})
end

-- KiB/s -> human readable rate
local function fmt_rate(kib)
	local b = kib * 1024
	if b < 1000 then return string.format('%.0f B/s', b) end
	if b < 1e6 then return string.format('%.0f KB/s', b / 1e3) end
	if b < 1e9 then return string.format('%.1f MB/s', b / 1e6) end
	return string.format('%.2f GB/s', b / 1e9)
end

---------------------------------------------------------------- desktop set widgets

local PAD = 12 -- inner margin; leaves room for shadows

-- time, date and this week
function W.week(cr, w, h)
	local now = os.time()
	local t = os.date('*t', now)
	local x, iw = PAD, w - 2 * PAD
	local time_str, ampm = time_parts(now)
	local tw = text(cr, time_str, x - 3, 76, {size = 78, weight = 'thin'})
	if ampm then text(cr, ampm, x + tw + 4, 76, {size = 18, weight = 'light', alpha = 0.8}) end
	text(cr, os.date('%A, %B ', now) .. t.day, x, 108, {size = 17, weight = 'light', alpha = 0.85})

	local offset = (t.wday - SETTINGS.week_start) % 7
	local cell = iw / 7
	for i = 0, 6 do
		local day = now + (i - offset) * 86400
		local cx = x + i * cell + cell / 2
		local today = (i == offset)
		text(cr, (chars(os.date('%a', day))[1] or ''), cx, 140, {size = 11, align = 'center', alpha = today and 0.95 or 0.5})
		local d = tostring(os.date('*t', day).day)
		if today then
			local a = accent()
			cairo_arc(cr, cx, 160, 13, 0, 2 * math.pi)
			cairo_set_source_rgba(cr, a[1], a[2], a[3], 0.95)
			cairo_fill(cr)
			cairo_save(cr)
			cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
			set_font(cr, 14, 'bold')
			cairo_move_to(cr, cx - advance(cr, d) / 2, 165)
			cairo_show_text(cr, d)
			cairo_restore(cr)
			cairo_new_path(cr)
		else
			text(cr, d, cx, 165, {size = 14, align = 'center', alpha = 0.85})
		end
	end
end

function W.weather(cr, w, h)
	local x, iw = PAD, w - 2 * PAD
	local wd = SETTINGS.show_weather and get_weather() or nil
	label(cr, 'Weather', x, 24, iw, wd and wd.place or '')
	if not wd then
		text(cr, 'Waiting for wttr.in…', x, 80, {size = 16, weight = 'light', alpha = 0.7})
		return
	end
	weather_icon(cr, wd.kind, x + 32, 82, 56)
	local tx = x + 98
	text(cr, wd.temp, tx, 104, {size = 60, weight = 'thin'})
	text(cr, wd.cond, x, 138, {size = 17, weight = 'light', alpha = 0.9})
	local details = string.format('Feels %s   ·   %s   ·   %s', wd.feels or '', wd.humidity or '', wd.wind or '')
	text(cr, details, x, 162, {size = 13, weight = 'light', alpha = 0.65})
end

local temp_input = nil

local function cpu_temp()
	if DEMO then return 52 end
	if temp_input == nil then
		temp_input = false
		local preferred = {coretemp = 1, k10temp = 1, zenpower = 1, cpu_thermal = 1, soc_thermal = 1}
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
		if cap then return cap, trim(read_file(base .. '/status') or '') end
	end
	return nil
end

local hostname = DEMO and 'workstation' or trim(read_file('/proc/sys/kernel/hostname') or '')

function W.system(cr, w, h)
	local x, iw = PAD, w - 2 * PAD
	label(cr, 'System', x, 24, iw, hostname)

	local cpu = num('${cpu cpu0}')
	local mem = num('${memperc}')
	local temp = cpu_temp()
	local gauges = {
		{cpu / 100, string.format('%d%%', cpu), 'CPU'},
		{mem / 100, string.format('%d%%', mem), 'MEMORY'},
	}
	if temp then
		local frac = math.max(0, math.min((temp - 30) / 70, 1))
		gauges[3] = {frac, string.format('%d°', math.floor(temp + 0.5)), 'TEMP', frac >= 0.85 and HOT or nil}
	else
		local swap = num('${swapperc}')
		gauges[3] = {swap / 100, string.format('%d%%', swap), 'SWAP'}
	end
	local step = iw / 3
	for i, g in ipairs(gauges) do
		local cx = x + step * (i - 0.5)
		ring(cr, cx, 84, 32, g[1], g[4])
		text(cr, g[2], cx, 91, {size = 19, weight = 'light', align = 'center'})
		text(cr, g[3], cx, 140, {size = 10, weight = 'bold', tracking = 2, align = 'center', alpha = 0.6})
	end

	hairline(cr, x, 160, x + iw, 160, 0.2)
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
	local y = 186
	for _, r in ipairs(rows) do
		row(cr, x, y, iw, r[1], r[2])
		y = y + 24
	end
end

local net = {down = {}, up = {}}
local HISTORY = 48

local function push(list, v)
	list[#list + 1] = v
	if #list > HISTORY then table.remove(list, 1) end
end

function W.network(cr, w, h)
	local x, iw = PAD, w - 2 * PAD
	local iface = SETTINGS.network_interface
	if iface == '' then iface = trim(parse('${gw_iface}')) end
	if iface == '' or iface == 'multiple' or iface == '(null)' then
		label(cr, 'Network', x, 24, iw)
		text(cr, 'Offline', x, 80, {size = 30, weight = 'thin'})
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
	label(cr, 'Network', x, 24, iw, essid ~= '' and essid or iface)

	local half = iw / 2
	arrow(cr, x + 6, 58, 12, 'down', 0.9)
	text(cr, fmt_rate(down), x + 20, 64, {size = 24, weight = 'light'})
	arrow(cr, x + half + 6, 58, 12, 'up', 0.6)
	text(cr, fmt_rate(up), x + half + 20, 64, {size = 24, weight = 'light', alpha = 0.8})

	local peak = 1
	for _, v in ipairs(net.down) do peak = math.max(peak, v) end
	for _, v in ipairs(net.up) do peak = math.max(peak, v) end
	sparkline(cr, x, 84, iw, 62, net.down, peak * 1.15, 0.95, true)
	sparkline(cr, x, 84, iw, 62, net.up, peak * 1.15, 0.45, false)
	hairline(cr, x, 147, x + iw, 147, 0.2)

	local addr = DEMO and '192.168.1.24' or trim(parse('${addr ' .. iface .. '}'))
	text(cr, addr, x, 174, {size = 13, weight = 'light', alpha = 0.6})
	local totals = 'total  ' .. trim(parse('${totaldown ' .. iface .. '}')) .. ' down  ·  ' .. trim(parse('${totalup ' .. iface .. '}')) .. ' up'
	text(cr, totals, x + iw, 174, {size = 13, weight = 'light', align = 'right', alpha = 0.6})
end

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

local mounts_cache, mounts_time = nil, 0

local function list_mounts()
	if DEMO then return {'/', '/home'} end
	if mounts_cache and os.time() - mounts_time < 30 then return mounts_cache end
	local list, seen = {}, {}
	for line in (read_file('/proc/mounts') or ''):gmatch('[^\n]+') do
		local dev, mp, fs = line:match('^(%S+)%s+(%S+)%s+(%S+)')
		if dev and wanted_mount(dev, mp, fs) and not seen[dev] then
			seen[dev] = true
			list[#list + 1] = mp
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
	local x, iw = PAD, w - 2 * PAD
	label(cr, 'Storage', x, 24, iw)
	local y = 58
	for _, mp in ipairs(list_mounts()) do
		local perc = num('${fs_used_perc ' .. mp .. '}')
		local free = trim(parse('${fs_free ' .. mp .. '}'))
		local size = trim(parse('${fs_size ' .. mp .. '}'))
		if DEMO then
			perc, free, size = table.unpack(mp == '/' and {38, '61.2GiB', '98.3GiB'} or {87, '112GiB', '869GiB'})
		end
		text(cr, mount_label(mp), x, y, {size = 16, weight = 'light'})
		text(cr, free .. ' free of ' .. size, x + iw, y, {size = 13, weight = 'light', align = 'right', alpha = 0.65})
		bar(cr, x, y + 14, iw, perc / 100, 3, perc >= 85 and HOT or nil)
		y = y + 50
	end
	hairline(cr, x, y - 10, x + iw, y - 10, 0.2)
	text(cr, 'read  ' .. trim(parse('${diskio_read}')), x, y + 14, {size = 13, weight = 'light', alpha = 0.6})
	text(cr, 'write  ' .. trim(parse('${diskio_write}')), x + iw, y + 14, {size = 13, weight = 'light', align = 'right', alpha = 0.6})
end

function W.processes(cr, w, h)
	local x, iw = PAD, w - 2 * PAD
	label(cr, 'Top processes', x, 24, iw, 'cpu  ·  memory')
	local demo = {{'firefox', 18.4, '1.2GiB'}, {'gnome-shell', 6.1, '412MiB'}, {'code', 4.7, '836MiB'},
		{'Xorg', 2.3, '256MiB'}, {'pipewire', 0.9, '38MiB'}}
	local y = 60
	for i = 1, 5 do
		local name = trim(parse('${top name ' .. i .. '}'))
		local cpu = num('${top cpu ' .. i .. '}')
		local mem = trim(parse('${top mem_res ' .. i .. '}'))
		if DEMO then name, cpu, mem = table.unpack(demo[i]) end
		if name ~= '' then
			text(cr, name, x, y, {size = 15, weight = 'light'})
			text(cr, mem, x + iw, y, {size = 13, weight = 'light', align = 'right', alpha = 0.6})
			text(cr, string.format('%.1f%%', cpu), x + iw - 78, y, {size = 15, align = 'right'})
			bar(cr, x, y + 11, iw, cpu / 100, 2)
		end
		y = y + 36
	end
end

local has_playerctl = sh('command -v playerctl') ~= ''

local function fmt_time(sec)
	sec = math.floor(sec or 0)
	return string.format('%d:%02d', sec // 60, sec % 60)
end

local function note_icon(cr, x, y, s)
	stroke_with_shadow(cr, math.max(1.6, s * 0.08), ink(0.9), function()
		cairo_new_path(cr)
		cairo_move_to(cr, x - 0.15 * s, y + 0.3 * s)
		cairo_line_to(cr, x - 0.15 * s, y - 0.4 * s)
		cairo_line_to(cr, x + 0.4 * s, y - 0.55 * s)
		cairo_line_to(cr, x + 0.4 * s, y + 0.15 * s)
		cairo_new_sub_path(cr)
		cairo_arc(cr, x - 0.3 * s, y + 0.32 * s, 0.15 * s, 0, 2 * math.pi)
		cairo_new_sub_path(cr)
		cairo_arc(cr, x + 0.25 * s, y + 0.17 * s, 0.15 * s, 0, 2 * math.pi)
	end)
end

function W.media(cr, w, h)
	local x, iw = PAD, w - 2 * PAD
	label(cr, 'Now playing', x, 24, iw)
	note_icon(cr, x + 18, 70, 30)
	local tx = x + 52
	local tw = x + iw - tx

	if not has_playerctl and not DEMO then
		text(cr, 'Install playerctl to show music', tx, 76, {size = 14, weight = 'light', alpha = 0.7})
		return
	end
	local out = DEMO and 'Playing\tLuna Vale\tGlass Horizons\t83000000\t214000000'
		or trim(sh("playerctl metadata --format '{{status}}\t{{artist}}\t{{title}}\t{{position}}\t{{mpris:length}}'"))
	local status, artist, title, pos, len = out:match('^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$')
	if not status or (title or '') == '' then
		text(cr, 'Nothing playing', tx, 76, {size = 18, weight = 'light', alpha = 0.8})
		return
	end
	local p, l = (tonumber(pos) or 0) / 1e6, (tonumber(len) or 0) / 1e6
	text(cr, title, tx, 66, {size = 19, weight = 'light'})
	text(cr, artist ~= '' and artist or status, tx, 88, {size = 13, weight = 'light', alpha = 0.65})
	bar(cr, x, 110, iw, l > 0 and p / l or 0, 2)
	text(cr, fmt_time(p), x, 130, {size = 11, weight = 'light', alpha = 0.55})
	text(cr, status == 'Paused' and 'paused' or ('-' .. fmt_time(math.max(l - p, 0))), x + iw, 130,
		{size = 11, weight = 'light', align = 'right', alpha = 0.55})
end


---------------------------------------------------------------- system monitor: sensors

local function file_num(path)
	return tonumber(trim(read_file(path) or ''))
end

local function list_dir(path)
	local out = {}
	for name in sh('ls -1 "' .. path .. '"'):gmatch('[^\n]+') do out[#out + 1] = name end
	return out
end

-- CPU model, shortened: "i7-9750H", "Ryzen 7 5800X"
local cpu_model = (function()
	local name = (read_file('/proc/cpuinfo') or ''):match('model name%s*:%s*([^\n]+)') or 'CPU'
	name = name:gsub('%(R%)', ''):gsub('%(TM%)', ''):gsub('%s+CPU%s+@.*$', ''):gsub('%s+@.*$', '')
	name = name:gsub('^Intel%s+Core%s+', ''):gsub('^AMD%s+', ''):gsub('%s+%d+%-Core Processor', '')
	name = name:gsub('%s+Processor$', ''):gsub('%s+with.*$', ''):gsub('%s+', ' ')
	return trim(name)
end)()

local cpu_count = tonumber(trim(sh('nproc'))) or 1

-- temperature and fan sensors, discovered once; only cheap sysfs reads afterwards
local sensors = nil

local function discover_sensors()
	local temps, fans = {}, {}
	local names = {
		coretemp = 'CPU', k10temp = 'CPU', zenpower = 'CPU', cpu_thermal = 'CPU',
		nvme = 'NVMe', pch_cannonlake = 'PCH', pch_skylake = 'PCH', pch_cometlake = 'PCH',
		amdgpu = 'GPU', iwlwifi_1 = 'Wi-Fi', acpitz = 'Board',
	}
	local have_cpu = false
	for _, h in ipairs(list_dir('/sys/class/hwmon')) do
		local base = '/sys/class/hwmon/' .. h .. '/'
		local chip = trim(read_file(base .. 'name') or '')
		local nice = names[chip] or (chip:find('^pch') and 'PCH')
		-- the first input is the package/composite reading for these chips
		if nice and nice ~= 'GPU' and file_num(base .. 'temp1_input') then
			if not (nice == 'Board' and have_cpu) then
				temps[#temps + 1] = {name = nice, path = base .. 'temp1_input'}
				if nice == 'CPU' then have_cpu = true end
			end
		end
		for i = 1, 8 do
			local f = base .. 'fan' .. i .. '_input'
			if file_num(f) then
				local lbl = trim(read_file(base .. 'fan' .. i .. '_label') or '')
				fans[#fans + 1] = {name = lbl ~= '' and lbl or ('Fan ' .. (#fans + 1)), path = f}
			end
		end
	end
	-- the board sensor only adds noise next to a real CPU reading
	local keep = {}
	for _, t in ipairs(temps) do
		if not (t.name == 'Board' and have_cpu) then keep[#keep + 1] = t end
	end
	table.sort(keep, function(a, b)
		local order = {CPU = 1, GPU = 2, PCH = 3, NVMe = 4, ['Wi-Fi'] = 5, Board = 6}
		return (order[a.name] or 9) < (order[b.name] or 9)
	end)
	return {temps = keep, fans = fans}
end

-- GPUs from /sys/class/drm: vendor, driver, name, and where to read load
local gpus = nil
local nvsmi = {time = -1e9, rows = {}}

local function short_gpu_name(full, vendor)
	local bracket = full:match('%[([^%]]+)%]')
	local name = bracket or full
	name = name:gsub('%s*/%s*Max%-Q', ''):gsub('%s+Mobile', '')
	if vendor == 'intel' then name = name:gsub('^Intel%s+', '') end
	return trim(name)
end

-- name from the PCI ID database; unlike lspci this never wakes a sleeping GPU
local function pci_name(vendor_id, device_id)
	local v, d = vendor_id:gsub('^0x', ''):lower(), device_id:gsub('^0x', ''):lower()
	for _, db in ipairs({'/usr/share/hwdata/pci.ids', '/usr/share/misc/pci.ids', '/usr/share/pci.ids'}) do
		local f = io.open(db, 'r')
		if f then
			f:close()
			local name = trim(sh(string.format(
				"awk -v v='%s' -v d='%s' '/^[0-9a-f]/{inv=($1==v)} inv && $0 ~ \"^\\t\"d\"  \"{sub(/^\\t[0-9a-f]+  /,\"\"); print; exit}' '%s'",
				v, d, db)))
			if name ~= '' then return name end
		end
	end
	return ''
end

local function discover_gpus()
	local list = {}
	for _, card in ipairs(list_dir('/sys/class/drm')) do
		if card:match('^card%d+$') then
			local dev = '/sys/class/drm/' .. card .. '/device/'
			local vendor_id = trim(read_file(dev .. 'vendor') or '')
			local vendor = ({['0x10de'] = 'nvidia', ['0x1002'] = 'amd', ['0x8086'] = 'intel'})[vendor_id]
			if vendor then
				local driver = trim(sh('basename "$(readlink -f ' .. dev .. 'driver)"'))
				local full = pci_name(vendor_id, trim(read_file(dev .. 'device') or ''))
				list[#list + 1] = {
					card = '/sys/class/drm/' .. card .. '/', dev = dev, vendor = vendor, driver = driver,
					name = short_gpu_name(full ~= '' and full or vendor:upper(), vendor),
				}
			end
		end
	end
	-- integrated first, like most system monitors
	table.sort(list, function(a, b) return (a.vendor == 'intel' and 1 or 2) < (b.vendor == 'intel' and 1 or 2) end)
	return list
end

-- returns {state = 'active'|'sleeping', load, load_label, mem_used, mem_total, temp}
local function gpu_reading(g)
	local r = {state = 'active'}
	local power = trim(read_file(g.dev .. 'power/runtime_status') or 'active')
	if power == 'suspended' then
		r.state = 'sleeping' -- reading its sensors would wake it up
		return r
	end
	if g.vendor == 'nvidia' and g.driver == 'nvidia' and sh('command -v nvidia-smi') ~= '' then
		if os.time() - nvsmi.time >= 3 then
			nvsmi.time = os.time()
			nvsmi.rows = {}
			local out = sh('nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits')
			for line in out:gmatch('[^\n]+') do
				local u, mu, mt, t = line:match('(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
				nvsmi.rows[#nvsmi.rows + 1] = {tonumber(u), tonumber(mu), tonumber(mt), tonumber(t)}
			end
		end
		local row = nvsmi.rows[1]
		if row then
			r.load, r.mem_used, r.mem_total, r.temp = row[1] / 100, row[2] * 1048576, row[3] * 1048576, row[4]
			r.load_label = row[1] .. '%'
		end
	elseif g.vendor == 'amd' then
		local busy = file_num(g.dev .. 'gpu_busy_percent')
		if busy then r.load, r.load_label = busy / 100, busy .. '%' end
		r.mem_used = file_num(g.dev .. 'mem_info_vram_used')
		r.mem_total = file_num(g.dev .. 'mem_info_vram_total')
	elseif g.vendor == 'intel' then
		-- no load counter without root: show the clock against its maximum
		local cur = file_num(g.card .. 'gt_act_freq_mhz') or file_num(g.card .. 'gt_cur_freq_mhz')
		local max = file_num(g.card .. 'gt_RP0_freq_mhz') or file_num(g.card .. 'gt_max_freq_mhz')
		if cur and max and max > 0 then r.load, r.load_label = cur / max, cur .. ' MHz' end
	end
	if not r.temp and g.vendor ~= 'intel' then
		for _, h in ipairs(list_dir(g.dev .. 'hwmon')) do
			local t = file_num(g.dev .. 'hwmon/' .. h .. '/temp1_input')
			if t then r.temp = t / 1000 break end
		end
	end
	return r
end

local function fmt_bytes(b)
	if not b then return '' end
	if b >= 1073741824 then return string.format('%.1f GiB', b / 1073741824) end
	return string.format('%.0f MiB', b / 1048576)
end

---------------------------------------------------------------- system monitor: widget

local mon = {cpu = {}, mem = {}}

local function temp_color(t)
	if t and t >= 85 then return HOT end
	return nil
end

function W.monitor(cr, w, h)
	local x, iw = PAD, w - 2 * PAD
	if not sensors then sensors = discover_sensors() end
	if not gpus then gpus = discover_gpus() end

	local y = 24
	label(cr, 'System monitor', x, y, iw, DEMO and 'workstation' or hostname)
	y = y + 18

	-- CPU -------------------------------------------------------------
	local cpu = num('${cpu cpu0}')
	push(mon.cpu, cpu)
	local freq = num('${freq_g}')
	local temp = cpu_temp()
	y = y + 40
	local vw = text(cr, string.format('%d%%', cpu), x - 2, y, {size = 44, weight = 'thin'})
	text(cr, 'CPU', x + vw + 10, y - 22, {size = 11, weight = 'bold', tracking = 2, alpha = 0.6})
	text(cr, cpu_model, x + vw + 10, y - 3, {size = 13, weight = 'light', alpha = 0.85})
	local cpu_right = string.format('%.2f GHz', freq)
	if temp then cpu_right = cpu_right .. '   ' .. math.floor(temp + 0.5) .. '°' end
	text(cr, cpu_right, x + iw, y - 3, {size = 15, weight = 'light', align = 'right',
		color = temp_color(temp), alpha = 0.95})
	y = y + 10
	sparkline(cr, x, y, iw, 34, mon.cpu, 100, 0.9, true)
	y = y + 44
	-- per-core bars
	local n = math.min(cpu_count, 32)
	local gap = n > 16 and 2 or 4
	local cw = (iw - gap * (n - 1)) / n
	for i = 1, n do
		local v = num('${cpu cpu' .. i .. '}') / 100
		local bx = x + (i - 1) * (cw + gap)
		cairo_rectangle(cr, bx, y, cw, 22)
		local c = ink(0.12)
		cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4])
		cairo_fill(cr)
		local hgt = math.max(1.5, 22 * v)
		cairo_rectangle(cr, bx, y + 22 - hgt, cw, hgt)
		c = (v >= 0.9) and HOT or ink(0.85)
		cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4] or 1)
		cairo_fill(cr)
	end
	y = y + 22 + 16
	text(cr, string.format('%d threads   ·   load %s', cpu_count, trim(parse('${loadavg}'))), x, y,
		{size = 12, weight = 'light', alpha = 0.6})

	-- GPU -------------------------------------------------------------
	if #gpus > 0 then
		y = y + 16
		hairline(cr, x, y, x + iw, y, 0.2)
		y = y + 26
		label(cr, 'Graphics', x, y, iw)
		for _, g in ipairs(gpus) do
			local r = DEMO and (g.vendor == 'intel' and {state = 'active', load = 0.35, load_label = '400 MHz'}
				or {state = 'active', load = 0.42, load_label = '42%', mem_used = 1.6 * 1073741824, mem_total = 4 * 1073741824, temp = 61})
				or gpu_reading(g)
			g.last = r -- reused for the temperature row below
			y = y + 26
			text(cr, g.name, x, y, {size = 15, weight = 'light', max_width = iw * 0.6})
			if r.state == 'sleeping' then
				text(cr, 'sleeping', x + iw, y, {size = 13, weight = 'light', align = 'right', alpha = 0.5})
				y = y + 4
			else
				local right = r.load_label or ''
				if r.temp then right = right .. (right ~= '' and '   ' or '') .. math.floor(r.temp + 0.5) .. '°' end
				if right == '' then right = 'active' end
				text(cr, right, x + iw, y, {size = 14, align = 'right', color = temp_color(r.temp), alpha = 0.95})
				y = y + 12
				bar(cr, x, y, iw, r.load or 0, 3, (r.load or 0) >= 0.9 and HOT or nil)
				if r.mem_total and r.mem_total > 0 then
					y = y + 18
					text(cr, 'VRAM ' .. fmt_bytes(r.mem_used) .. ' of ' .. fmt_bytes(r.mem_total), x, y,
						{size = 12, weight = 'light', alpha = 0.6})
				end
			end
		end
	end

	-- Memory ----------------------------------------------------------
	y = y + 22
	hairline(cr, x, y, x + iw, y, 0.2)
	y = y + 26
	local memp = num('${memperc}')
	push(mon.mem, memp)
	label(cr, 'Memory', x, y, iw, trim(parse('${mem}')) .. ' of ' .. trim(parse('${memmax}')))
	y = y + 14
	bar(cr, x, y, iw, memp / 100, 3, memp >= 90 and HOT or nil)
	local swapmax = trim(parse('${swapmax}'))
	if swapmax ~= '' and not swapmax:match('^0') then
		y = y + 20
		text(cr, 'Swap', x, y, {size = 12, weight = 'light', alpha = 0.6})
		text(cr, trim(parse('${swap}')) .. ' of ' .. swapmax, x + iw, y, {size = 12, weight = 'light', align = 'right', alpha = 0.6})
	end

	-- Temperatures and fans --------------------------------------------
	local temps = {}
	for _, t in ipairs(sensors.temps) do
		local v = DEMO and ({CPU = 52, PCH = 49, NVMe = 41, ['Wi-Fi'] = 44})[t.name] or file_num(t.path)
		if v then temps[#temps + 1] = {t.name, DEMO and v or v / 1000} end
	end
	for _, g in ipairs(gpus) do
		if g.last and g.last.temp then temps[#temps + 1] = {'GPU', g.last.temp} end
	end
	if #temps > 0 then
		y = y + 22
		hairline(cr, x, y, x + iw, y, 0.2)
		y = y + 26
		label(cr, 'Temperatures', x, y, iw)
		y = y + 30
		local cols = math.min(#temps, 5)
		local cw2 = iw / cols
		for i, t in ipairs(temps) do
			local col = (i - 1) % cols
			if i > 1 and col == 0 then y = y + 46 end
			local tx = x + col * cw2
			text(cr, math.floor(t[2] + 0.5) .. '°', tx, y, {size = 24, weight = 'thin', color = temp_color(t[2])})
			text(cr, t[1]:upper(), tx, y + 18, {size = 10, weight = 'bold', tracking = 2, alpha = 0.55})
		end
		y = y + 18
	end
	if #sensors.fans > 0 then
		local parts = {}
		for _, f in ipairs(sensors.fans) do
			local rpm = DEMO and 2400 or file_num(f.path)
			if rpm then parts[#parts + 1] = string.format('%s %d rpm', f.name:lower(), rpm) end
		end
		if #parts > 0 then
			y = y + 22
			text(cr, table.concat(parts, '   ·   '), x, y, {size = 12, weight = 'light', alpha = 0.6})
		end
	end

	-- Disks -----------------------------------------------------------
	y = y + 22
	hairline(cr, x, y, x + iw, y, 0.2)
	y = y + 26
	label(cr, 'Disks', x, y, iw, 'read ' .. trim(parse('${diskio_read}')) .. '  ·  write ' .. trim(parse('${diskio_write}')))
	for _, mp in ipairs(list_mounts()) do
		local perc = num('${fs_used_perc ' .. mp .. '}')
		local free = trim(parse('${fs_free ' .. mp .. '}'))
		local size = trim(parse('${fs_size ' .. mp .. '}'))
		if DEMO then
			perc, free, size = table.unpack(mp == '/' and {38, '61.2GiB', '98.3GiB'} or {87, '112GiB', '869GiB'})
		end
		y = y + 26
		text(cr, mount_label(mp), x, y, {size = 14, weight = 'light'})
		text(cr, free .. ' free of ' .. size, x + iw, y, {size = 12, weight = 'light', align = 'right', alpha = 0.65})
		y = y + 10
		bar(cr, x, y, iw, perc / 100, 3, perc >= 85 and HOT or nil)
	end

	-- Network and battery -----------------------------------------------
	local iface = SETTINGS.network_interface
	if iface == '' then iface = trim(parse('${gw_iface}')) end
	local footer = {}
	if iface ~= '' and iface ~= 'multiple' and iface ~= '(null)' then
		footer[#footer + 1] = string.format('net down %s  up %s', fmt_rate(num('${downspeedf ' .. iface .. '}')),
			fmt_rate(num('${upspeedf ' .. iface .. '}')))
	end
	local cap, status = battery()
	if cap then
		footer[#footer + 1] = 'battery ' .. cap .. '%' .. ((status == 'Charging' and ' charging') or '')
	end
	footer[#footer + 1] = 'up ' .. trim(parse('${uptime_short}'))
	y = y + 22
	hairline(cr, x, y, x + iw, y, 0.2)
	y = y + 24
	text(cr, table.concat(footer, '   ·   '), x, y, {size = 12, weight = 'light', alpha = 0.6, max_width = iw})
end

---------------------------------------------------------------- entry point

function conky_minimal_main(name, design_w, design_h)
	if conky_window == nil then return end
	-- Scale the design size to fit the window: follows conky's own HiDPI scaling,
	-- and a different minimum_width/height zooms the whole widget.
	local dw = tonumber(design_w) or conky_window.width
	local dh = tonumber(design_h) or conky_window.height
	local s = math.min(conky_window.width / dw, conky_window.height / dh)
	if s <= 0 then return end

	local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
		conky_window.visual, conky_window.width, conky_window.height)
	local cr = cairo_create(cs)
	-- keep the design centered horizontally when the window is wider than it
	cairo_translate(cr, (conky_window.width - dw * s) / 2, 0)
	cairo_scale(cr, s, s)

	DARK = dark_text(WIDGET_REGION[name] or 'center')
	local fn = W[name]
	if fn then
		local ok, err = pcall(fn, cr, dw, dh)
		if not ok then io.stderr:write('minimal ' .. name .. ': ' .. tostring(err) .. '\n') end
	end

	cairo_destroy(cr)
	cairo_surface_destroy(cs)
end

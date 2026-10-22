--[[
  glass.lua - "Liquid Glass" drawing helpers for Conky (Cairo)

  Translucent panels with a soft shadow, a light-catching rim and a specular
  sheen, plus glass rings, capsule bars, sparklines and text. All sizes are in
  logical pixels; widgets.lua scales the context for HiDPI screens.

  Conky cannot blur what is behind a window, so panels carry a faint dark tint
  to keep text readable on bright wallpapers. Tweak it in G.theme.tint.
]]

require 'cairo'
pcall(require, 'cairo_xlib')

local G = {}

G.theme = {
	text   = {1, 1, 1, 0.96},
	sub    = {1, 1, 1, 0.68},
	faint  = {1, 1, 1, 0.42},
	accent = {0.36, 0.70, 1.00},   -- blue
	accent2 = {0.68, 0.52, 1.00},  -- violet
	green  = {0.30, 0.86, 0.56},
	orange = {1.00, 0.68, 0.26},
	red    = {1.00, 0.36, 0.42},
	tint   = {0.06, 0.08, 0.14, 0.26},
	radius = 26,
}

---------------------------------------------------------------- fonts

local function font_installed(family)
	local p = io.popen('fc-list -q "' .. family .. '" && echo yes')
	if not p then return false end
	local out = p:read('*a') or ''
	p:close()
	return out:find('yes') ~= nil
end

local function detect_fonts()
	for _, family in ipairs({'Inter', 'SF Pro Display', 'Ubuntu', 'Cantarell', 'Noto Sans', 'DejaVu Sans'}) do
		if font_installed(family) then
			local light = family
			for _, suffix in ipairs({' Light', ' Thin'}) do
				if font_installed(family .. suffix) then
					light = family .. suffix
					break
				end
			end
			return family, light
		end
	end
	return 'Sans', 'Sans'
end

G.font, G.font_light = detect_fonts()

---------------------------------------------------------------- helpers

function G.rgba(cr, c, alpha_mul)
	cairo_set_source_rgba(cr, c[1], c[2], c[3], (c[4] or 1) * (alpha_mul or 1))
end

function G.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- green -> orange -> red as a value (0..1) gets critical
function G.level_color(frac)
	if frac < 0.6 then return G.theme.green end
	if frac < 0.85 then return G.theme.orange end
	return G.theme.red
end

function G.mix(a, b, t)
	return {a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, 1}
end

-- rounded rectangle with "continuous" corners (Bezier, closer to Apple's squircle than arcs)
function G.rrect(cr, x, y, w, h, r)
	r = math.min(r, w / 2, h / 2)
	local k = 0.62 -- control-point pull; 0.55 ~ circular arc, higher = smoother shoulder
	cairo_new_sub_path(cr)
	cairo_move_to(cr, x + r, y)
	cairo_line_to(cr, x + w - r, y)
	cairo_curve_to(cr, x + w - r * (1 - k), y, x + w, y + r * (1 - k), x + w, y + r)
	cairo_line_to(cr, x + w, y + h - r)
	cairo_curve_to(cr, x + w, y + h - r * (1 - k), x + w - r * (1 - k), y + h, x + w - r, y + h)
	cairo_line_to(cr, x + r, y + h)
	cairo_curve_to(cr, x + r * (1 - k), y + h, x, y + h - r * (1 - k), x, y + h - r)
	cairo_line_to(cr, x, y + r)
	cairo_curve_to(cr, x, y + r * (1 - k), x + r * (1 - k), y, x + r, y)
	cairo_close_path(cr)
end

local function linear(x0, y0, x1, y1, stops)
	local pat = cairo_pattern_create_linear(x0, y0, x1, y1)
	for _, s in ipairs(stops) do
		cairo_pattern_add_color_stop_rgba(pat, s[1], s[2], s[3], s[4], s[5])
	end
	return pat
end

local function fill_with(cr, pat)
	cairo_set_source(cr, pat)
	cairo_fill(cr)
	cairo_pattern_destroy(pat)
end

local function stroke_with(cr, pat)
	cairo_set_source(cr, pat)
	cairo_stroke(cr)
	cairo_pattern_destroy(pat)
end

---------------------------------------------------------------- glass panel

local function draw_panel(cr, x, y, w, h, r)

	-- soft drop shadow, kept outside the panel so the glass is not darkened
	cairo_save(cr)
	cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD)
	for i = 1, 12 do
		local g = i * 0.9
		cairo_new_path(cr)
		G.rrect(cr, x - g, y - g + 4, w + g * 2, h + g * 2, r + g)
		G.rrect(cr, x, y, w, h, r)
		cairo_set_source_rgba(cr, 0, 0, 0, 0.022)
		cairo_fill(cr)
	end
	cairo_restore(cr)

	-- body: tint + vertical white gradient
	G.rrect(cr, x, y, w, h, r)
	G.rgba(cr, G.theme.tint)
	cairo_fill_preserve(cr)
	fill_with(cr, linear(0, y, 0, y + h, {
		{0.00, 1, 1, 1, 0.24},
		{0.45, 1, 1, 1, 0.10},
		{1.00, 1, 1, 1, 0.15},
	}))

	cairo_save(cr)
	G.rrect(cr, x, y, w, h, r)
	cairo_clip(cr)

	-- specular sheen across the upper-left
	local sheen = cairo_pattern_create_radial(x + w * 0.22, y - h * 0.15, 0, x + w * 0.22, y - h * 0.15, math.max(w, h) * 0.75)
	cairo_pattern_add_color_stop_rgba(sheen, 0.0, 1, 1, 1, 0.22)
	cairo_pattern_add_color_stop_rgba(sheen, 1.0, 1, 1, 1, 0.0)
	cairo_rectangle(cr, x, y, w, h)
	fill_with(cr, sheen)

	-- light pooling along the bottom edge (refraction)
	cairo_rectangle(cr, x, y + h * 0.7, w, h * 0.3)
	fill_with(cr, linear(0, y + h * 0.7, 0, y + h, {
		{0, 1, 1, 1, 0.0},
		{1, 1, 1, 1, 0.08},
	}))
	cairo_restore(cr)

	-- outer hairline for contrast on light wallpapers
	G.rrect(cr, x - 0.5, y - 0.5, w + 1, h + 1, r + 0.5)
	cairo_set_line_width(cr, 1)
	cairo_set_source_rgba(cr, 0, 0, 0, 0.16)
	cairo_stroke(cr)

	-- bright rim: strong top-left, fading, catching light again bottom-right
	G.rrect(cr, x + 0.75, y + 0.75, w - 1.5, h - 1.5, r - 0.75)
	cairo_set_line_width(cr, 1.5)
	stroke_with(cr, linear(x, y, x + w, y + h, {
		{0.00, 1, 1, 1, 0.75},
		{0.35, 1, 1, 1, 0.18},
		{0.65, 1, 1, 1, 0.08},
		{1.00, 1, 1, 1, 0.40},
	}))

	-- faint inner glow line
	G.rrect(cr, x + 2.5, y + 2.5, w - 5, h - 5, r - 2.5)
	cairo_set_line_width(cr, 1)
	cairo_set_source_rgba(cr, 1, 1, 1, 0.06)
	cairo_stroke(cr)
end

G.scale = 1 -- device pixels per logical pixel, set by widgets.lua
local panel_cache = {}
local PAD = 16 -- room for the shadow around the panel

function G.panel(cr, x, y, w, h, r)
	r = r or G.theme.radius
	local s = G.scale
	local key = string.format('%.1f:%.1f:%.1f:%.3f', w, h, r, s)
	local img = panel_cache[key]
	if not img then
		img = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
			math.ceil((w + PAD * 2) * s), math.ceil((h + PAD * 2) * s))
		local icr = cairo_create(img)
		cairo_scale(icr, s, s)
		draw_panel(icr, PAD, PAD, w, h, r)
		cairo_destroy(icr)
		panel_cache[key] = img
	end
	cairo_save(cr)
	cairo_translate(cr, x - PAD, y - PAD)
	cairo_scale(cr, 1 / s, 1 / s)
	cairo_set_source_surface(cr, img, 0, 0)
	cairo_paint(cr)
	cairo_restore(cr)
	cairo_new_path(cr)
end

-- small inset glass tile (e.g. behind an icon or a highlighted chip)
function G.chip(cr, x, y, w, h, r, color, strength)
	strength = strength or 1
	G.rrect(cr, x, y, w, h, r)
	if color then
		G.rgba(cr, color, 0.55 * strength)
		cairo_fill_preserve(cr)
	end
	fill_with(cr, linear(0, y, 0, y + h, {
		{0, 1, 1, 1, 0.30 * strength},
		{1, 1, 1, 1, 0.06 * strength},
	}))
	G.rrect(cr, x + 0.5, y + 0.5, w - 1, h - 1, r - 0.5)
	cairo_set_line_width(cr, 1)
	stroke_with(cr, linear(x, y, x, y + h, {
		{0, 1, 1, 1, 0.60 * strength},
		{1, 1, 1, 1, 0.10 * strength},
	}))
end

---------------------------------------------------------------- text

local extents = nil

local function text_width(cr, str)
	if not extents then
		extents = cairo_text_extents_t:create()
		if tolua and tolua.takeownership then tolua.takeownership(extents) end
	end
	cairo_text_extents(cr, str, extents)
	return extents.x_advance
end

--[[ opts: size, color, weight ('bold'|'normal'|'light'), align ('left'|'center'|'right'),
     shadow (default true), max_width (ellipsize) ]]
function G.text(cr, str, x, y, opts)
	opts = opts or {}
	str = tostring(str or '')
	local family = G.font
	local weight = CAIRO_FONT_WEIGHT_NORMAL
	if opts.weight == 'bold' then
		weight = CAIRO_FONT_WEIGHT_BOLD
	elseif opts.weight == 'light' then
		family = G.font_light
	end
	cairo_select_font_face(cr, family, CAIRO_FONT_SLANT_NORMAL, weight)
	cairo_set_font_size(cr, opts.size or 13)

	local w = text_width(cr, str)
	if opts.max_width and w > opts.max_width then
		-- trim whole UTF-8 characters until it fits
		while #str > 0 and text_width(cr, str .. '…') > opts.max_width do
			str = str:gsub('[%z\1-\127\194-\244][\128-\191]*$', '')
		end
		str = str .. '…'
		w = text_width(cr, str)
	end

	if opts.align == 'center' then
		x = x - w / 2
	elseif opts.align == 'right' then
		x = x - w
	end

	if opts.shadow ~= false then
		cairo_set_source_rgba(cr, 0, 0, 0, 0.30)
		cairo_move_to(cr, x, y + 1)
		cairo_show_text(cr, str)
	end
	G.rgba(cr, opts.color or G.theme.text)
	cairo_move_to(cr, x, y)
	cairo_show_text(cr, str)
	cairo_new_path(cr)
	return w
end

function G.measure(cr, str, size, weight)
	local family = (weight == 'light') and G.font_light or G.font
	cairo_select_font_face(cr, family, CAIRO_FONT_SLANT_NORMAL,
		weight == 'bold' and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
	cairo_set_font_size(cr, size)
	return text_width(cr, str)
end

---------------------------------------------------------------- gauges

-- glass ring gauge; frac 0..1
function G.ring(cr, cx, cy, r, width, frac, c1, c2)
	frac = G.clamp(frac or 0, 0, 1)
	c2 = c2 or c1
	local a0 = -math.pi / 2
	cairo_new_path(cr)

	-- recessed track
	cairo_set_line_width(cr, width)
	cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
	cairo_set_source_rgba(cr, 0, 0, 0, 0.18)
	cairo_stroke(cr)
	cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
	cairo_set_source_rgba(cr, 1, 1, 1, 0.10)
	cairo_stroke(cr)

	if frac > 0.002 then
		local a1 = a0 + frac * 2 * math.pi
		cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)

		-- colored glow under the arc
		cairo_set_line_width(cr, width + 6)
		cairo_arc(cr, cx, cy, r, a0, a1)
		G.rgba(cr, c1, 0.18)
		cairo_stroke(cr)

		cairo_set_line_width(cr, width)
		cairo_arc(cr, cx, cy, r, a0, a1)
		stroke_with(cr, linear(cx - r, cy - r, cx + r, cy + r, {
			{0, c1[1], c1[2], c1[3], 1},
			{1, c2[1], c2[2], c2[3], 1},
		}))

		-- specular line on the outer half of the arc
		cairo_set_line_width(cr, width * 0.28)
		cairo_arc(cr, cx, cy, r + width * 0.22, a0, a1)
		cairo_set_source_rgba(cr, 1, 1, 1, 0.45)
		cairo_stroke(cr)
		cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
	end
end

-- capsule progress bar; frac 0..1
function G.bar(cr, x, y, w, h, frac, c1, c2)
	frac = G.clamp(frac or 0, 0, 1)
	c2 = c2 or c1
	local r = h / 2

	G.rrect(cr, x, y, w, h, r)
	cairo_set_source_rgba(cr, 0, 0, 0, 0.20)
	cairo_fill_preserve(cr)
	cairo_set_source_rgba(cr, 1, 1, 1, 0.10)
	cairo_fill(cr)

	if frac > 0.002 then
		local fw = math.max(h, w * frac)
		G.rrect(cr, x, y, fw, h, r)
		fill_with(cr, linear(x, 0, x + w, 0, {
			{0, c1[1], c1[2], c1[3], 1},
			{1, c2[1], c2[2], c2[3], 1},
		}))
		-- gloss on the upper half
		G.rrect(cr, x + 1, y + 1, fw - 2, h / 2, r / 2)
		fill_with(cr, linear(0, y, 0, y + h / 2, {
			{0, 1, 1, 1, 0.55},
			{1, 1, 1, 1, 0.05},
		}))
	end

	G.rrect(cr, x + 0.5, y + 0.5, w - 1, h - 1, r - 0.5)
	cairo_set_line_width(cr, 1)
	stroke_with(cr, linear(0, y, 0, y + h, {
		{0, 0, 0, 0, 0.25},
		{1, 1, 1, 1, 0.25},
	}))
end

-- area sparkline; values oldest -> newest
function G.graph(cr, x, y, w, h, values, maxv, color, filled)
	local n = #values
	if n < 2 then return end
	maxv = math.max(maxv or 0, 1e-9)
	local step = w / (n - 1)

	local function pt(i)
		return x + (i - 1) * step, y + h - G.clamp(values[i] / maxv, 0, 1) * h
	end

	cairo_new_path(cr)
	cairo_move_to(cr, pt(1))
	for i = 2, n do
		local x0, y0 = pt(i - 1)
		local x1, y1 = pt(i)
		local mx = (x0 + x1) / 2
		cairo_curve_to(cr, mx, y0, mx, y1, x1, y1)
	end

	if filled then
		cairo_save(cr)
		cairo_line_to(cr, x + w, y + h)
		cairo_line_to(cr, x, y + h)
		cairo_close_path(cr)
		fill_with(cr, linear(0, y, 0, y + h, {
			{0, color[1], color[2], color[3], 0.50},
			{1, color[1], color[2], color[3], 0.02},
		}))
		cairo_restore(cr)
		-- redraw the line for the stroke
		cairo_move_to(cr, pt(1))
		for i = 2, n do
			local x0, y0 = pt(i - 1)
			local x1, y1 = pt(i)
			local mx = (x0 + x1) / 2
			cairo_curve_to(cr, mx, y0, mx, y1, x1, y1)
		end
	end

	cairo_set_line_width(cr, 1.6)
	cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
	G.rgba(cr, color)
	cairo_stroke(cr)
end

-- thin separator line
function G.divider(cr, x, y, w)
	cairo_rectangle(cr, x, y, w, 1)
	fill_with(cr, linear(x, 0, x + w, 0, {
		{0.0, 1, 1, 1, 0.0},
		{0.5, 1, 1, 1, 0.16},
		{1.0, 1, 1, 1, 0.0},
	}))
end

---------------------------------------------------------------- icons

local function cloud_path(cr, x, y, s)
	-- cloud centred on x, y with width ~ 2*s
	cairo_new_sub_path(cr)
	cairo_arc(cr, x - s * 0.45, y + s * 0.12, s * 0.42, 0, 2 * math.pi)
	cairo_new_sub_path(cr)
	cairo_arc(cr, x + s * 0.05, y - s * 0.12, s * 0.55, 0, 2 * math.pi)
	cairo_new_sub_path(cr)
	cairo_arc(cr, x + s * 0.55, y + s * 0.15, s * 0.38, 0, 2 * math.pi)
	G.rrect(cr, x - s * 0.85, y + s * 0.05, s * 1.75, s * 0.5, s * 0.25)
end

local function glass_fill(cr, top, bottom, y0, y1)
	cairo_set_fill_rule(cr, CAIRO_FILL_RULE_WINDING)
	fill_with(cr, linear(0, y0, 0, y1, {
		{0, top[1], top[2], top[3], top[4] or 1},
		{1, bottom[1], bottom[2], bottom[3], bottom[4] or 1},
	}))
end

local function sun(cr, x, y, s)
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
	cairo_set_line_width(cr, s * 0.12)
	cairo_set_source_rgba(cr, 1, 0.80, 0.30, 0.9)
	for i = 0, 7 do
		local a = i * math.pi / 4
		cairo_move_to(cr, x + math.cos(a) * s * 0.62, y + math.sin(a) * s * 0.62)
		cairo_line_to(cr, x + math.cos(a) * s * 0.82, y + math.sin(a) * s * 0.82)
	end
	cairo_stroke(cr)
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
	cairo_arc(cr, x, y, s * 0.45, 0, 2 * math.pi)
	glass_fill(cr, {1, 0.92, 0.55}, {1, 0.62, 0.18}, y - s * 0.45, y + s * 0.45)
	cairo_arc(cr, x - s * 0.12, y - s * 0.14, s * 0.2, 0, 2 * math.pi)
	cairo_set_source_rgba(cr, 1, 1, 1, 0.35)
	cairo_fill(cr)
end

local function moon(cr, x, y, s)
	cairo_save(cr)
	cairo_arc(cr, x, y, s * 0.5, 0, 2 * math.pi)
	cairo_new_sub_path(cr)
	cairo_arc_negative(cr, x + s * 0.28, y - s * 0.2, s * 0.42, 2 * math.pi, 0)
	cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD)
	fill_with(cr, linear(0, y - s * 0.5, 0, y + s * 0.5, {
		{0, 1, 0.98, 0.85, 1},
		{1, 0.85, 0.82, 1.0, 1},
	}))
	cairo_restore(cr)
end

local function cloud(cr, x, y, s, dark)
	cloud_path(cr, x, y, s)
	if dark then
		glass_fill(cr, {0.85, 0.88, 0.95}, {0.55, 0.60, 0.70}, y - s * 0.7, y + s * 0.6)
	else
		glass_fill(cr, {1, 1, 1}, {0.80, 0.86, 0.95}, y - s * 0.7, y + s * 0.6)
	end
end

-- kind: sun, moon, partly, partly_night, cloud, rain, snow, storm, fog
function G.weather_icon(cr, kind, x, y, s)
	cairo_save(cr)
	if kind == 'sun' then
		sun(cr, x, y, s)
	elseif kind == 'moon' then
		moon(cr, x, y, s)
	elseif kind == 'partly' or kind == 'partly_night' then
		if kind == 'partly' then sun(cr, x - s * 0.3, y - s * 0.3, s * 0.75) else moon(cr, x - s * 0.3, y - s * 0.32, s * 0.75) end
		cloud(cr, x + s * 0.12, y + s * 0.18, s * 0.72)
	elseif kind == 'rain' or kind == 'snow' or kind == 'storm' then
		cloud(cr, x, y - s * 0.18, s * 0.78, true)
		if kind == 'rain' then
			cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
			cairo_set_line_width(cr, s * 0.1)
			cairo_set_source_rgba(cr, 0.45, 0.75, 1.0, 0.95)
			for i = -1, 1 do
				cairo_move_to(cr, x + i * s * 0.32, y + s * 0.42)
				cairo_line_to(cr, x + i * s * 0.32 - s * 0.1, y + s * 0.7)
			end
			cairo_stroke(cr)
		elseif kind == 'snow' then
			cairo_set_source_rgba(cr, 1, 1, 1, 0.95)
			for i = -1, 1 do
				cairo_arc(cr, x + i * s * 0.32, y + s * 0.55 + (i % 2) * s * 0.12, s * 0.07, 0, 2 * math.pi)
				cairo_fill(cr)
			end
		else
			cairo_move_to(cr, x + s * 0.05, y + s * 0.3)
			cairo_line_to(cr, x - s * 0.18, y + s * 0.62)
			cairo_line_to(cr, x + s * 0.02, y + s * 0.6)
			cairo_line_to(cr, x - s * 0.1, y + s * 0.9)
			cairo_line_to(cr, x + s * 0.24, y + s * 0.5)
			cairo_line_to(cr, x + s * 0.04, y + s * 0.52)
			cairo_close_path(cr)
			cairo_set_source_rgba(cr, 1, 0.82, 0.25, 1)
			cairo_fill(cr)
		end
	elseif kind == 'fog' then
		cloud(cr, x, y - s * 0.2, s * 0.7, true)
		cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
		cairo_set_line_width(cr, s * 0.09)
		cairo_set_source_rgba(cr, 1, 1, 1, 0.7)
		for i = 0, 1 do
			cairo_move_to(cr, x - s * 0.6 + i * s * 0.15, y + s * 0.42 + i * s * 0.2)
			cairo_line_to(cr, x + s * 0.6 - i * s * 0.1, y + s * 0.42 + i * s * 0.2)
		end
		cairo_stroke(cr)
	else
		cloud(cr, x, y, s * 0.85)
	end
	cairo_restore(cr)
end

-- arrow centred on x, y; dir 'up' or 'down'
function G.arrow(cr, x, y, size, dir, color)
	local d = (dir == 'up') and -1 or 1
	cairo_save(cr)
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
	cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
	cairo_set_line_width(cr, size * 0.2)
	G.rgba(cr, color)
	cairo_move_to(cr, x, y - d * size * 0.5)
	cairo_line_to(cr, x, y + d * size * 0.5)
	cairo_move_to(cr, x - size * 0.38, y + d * size * 0.12)
	cairo_line_to(cr, x, y + d * size * 0.5)
	cairo_line_to(cr, x + size * 0.38, y + d * size * 0.12)
	cairo_stroke(cr)
	cairo_restore(cr)
end

-- simple music note glyph
function G.note_icon(cr, x, y, s)
	cairo_save(cr)
	cairo_set_line_width(cr, s * 0.1)
	cairo_set_source_rgba(cr, 1, 1, 1, 0.92)
	cairo_move_to(cr, x - s * 0.15, y + s * 0.3)
	cairo_line_to(cr, x - s * 0.15, y - s * 0.4)
	cairo_line_to(cr, x + s * 0.4, y - s * 0.55)
	cairo_line_to(cr, x + s * 0.4, y + s * 0.15)
	cairo_stroke(cr)
	cairo_arc(cr, x - s * 0.3, y + s * 0.32, s * 0.17, 0, 2 * math.pi)
	cairo_fill(cr)
	cairo_arc(cr, x + s * 0.25, y + s * 0.17, s * 0.17, 0, 2 * math.pi)
	cairo_fill(cr)
	cairo_restore(cr)
end

return G

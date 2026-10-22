# Liquid Glass widgets

Seven translucent "liquid glass" Conky widgets: frosted panels with a bright rim, specular sheen and soft shadow.

![Liquid Glass](Liquid%20Glass/Liquid%20Glass.jpg)

| Widget | Shows |
| --- | --- |
| Clock | Time, date and a strip of this week with today highlighted |
| Weather | Current conditions from [wttr.in](https://wttr.in) (no API key), feels-like, humidity, wind |
| System | CPU, memory and CPU temperature rings; memory used, load, uptime, battery |
| Now Playing | Title, artist and progress of the current track (needs `playerctl`) |
| Network | Live download/upload speeds with a history graph, Wi-Fi name, IP, totals |
| Storage | Free space on each disk and current disk read/write |
| Processes | Top 5 processes by CPU with memory use |

## Install

Conky Manager 3 installs this pack automatically. It shows up under **Widgets** as `~/.conky/Liquid Glass/...`, and as the **Liquid Glass** theme (which also sets the matching wallpaper).

Without Conky Manager, copy the `Liquid Glass` folder to `~/.conky/` and start a widget with `conky -c ~/.conky/Liquid\ Glass/Clock`. Requires conky 1.10+ built with Lua and Cairo (Debian/Ubuntu: `conky-all`).

## Settings

- `lua/widgets.lua`, top of the file: 12-hour clock, first day of the week, weather location and units, network interface.
- `lua/glass.lua`, `G.theme`: accent colors, text colors and the glass tint (raise the tint alpha if text is hard to read on a bright wallpaper).
- Position and size: `alignment`, `gap_x`, `gap_y`, `minimum_width` and `minimum_height` in each widget file, or use Edit Position and Look in Conky Manager. A smaller or larger size zooms the whole widget.

Widgets scale with the screen DPI. The Weather widget contacts wttr.in every 15 minutes, which sees your IP address; set a location in `widgets.lua` to avoid IP-based lookup.

To render the preview images with sample data instead of your own, start the widgets with `LIQUID_GLASS_DEMO=1`.

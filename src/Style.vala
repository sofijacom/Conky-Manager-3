/*
 * Style.vala
 *
 * Stylesheet for the main window: a gradient that changes with each page,
 * a translucent sidebar and glass cards (same design language as CleanMyLinux).
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

using TeeJee.Logging;

namespace Style {

	const string CSS = """
.cm {
  background-color: #2a1b47;
  background-image: linear-gradient(150deg, #4b2a7d 0%, #2a1b47 55%, #1a1230 100%);
  color: #ffffff;
}
.cm.page-overview { background-image: linear-gradient(150deg, #8a3b8f 0%, #4b2a7d 50%, #1d1338 100%); }
.cm.page-widgets  { background-image: linear-gradient(150deg, #1fa2ff 0%, #12728f 50%, #0f2a3d 100%); }
.cm.page-themes   { background-image: linear-gradient(150deg, #6a4cdb 0%, #3b2d8f 50%, #17143d 100%); }
.cm.page-import   { background-image: linear-gradient(150deg, #13a389 0%, #146a6e 50%, #0d2a3a 100%); }
.cm.page-settings { background-image: linear-gradient(150deg, #2f80ed 0%, #3a4fb5 50%, #1a1f4d 100%); }

.cm headerbar.cm-header { background-image: linear-gradient(90deg, #4b2a7d, #3a2163); }
.cm.page-overview headerbar.cm-header { background-image: linear-gradient(90deg, #8a3b8f, #4b2a7d); }
.cm.page-widgets headerbar.cm-header  { background-image: linear-gradient(90deg, #1fa2ff, #12728f); }
.cm.page-themes headerbar.cm-header   { background-image: linear-gradient(90deg, #6a4cdb, #3b2d8f); }
.cm.page-import headerbar.cm-header   { background-image: linear-gradient(90deg, #13a389, #146a6e); }
.cm.page-settings headerbar.cm-header { background-image: linear-gradient(90deg, #2f80ed, #3a4fb5); }

.cm * { color: inherit; }
.cm headerbar.cm-header,
.cm headerbar.cm-header:backdrop {
  background-color: transparent;
  border: none;
  box-shadow: none;
  min-height: 38px;
  color: rgba(255, 255, 255, 0.85);
}
headerbar.cm-header .title { color: rgba(255, 255, 255, 0.0); }
headerbar.cm-header button { color: rgba(255, 255, 255, 0.85); background: transparent; border: none; box-shadow: none; }
headerbar.cm-header button:hover { background-color: rgba(255, 255, 255, 0.12); }

/* Sidebar ------------------------------------------------------------ */
.sidebar {
  background-color: rgba(0, 0, 0, 0.22);
  border-right: 1px solid rgba(255, 255, 255, 0.06);
  padding: 0 10px 14px 10px;
}
.brand { font-size: 17px; font-weight: 800; letter-spacing: 0.3px; }
list.nav, list.nav row { background: transparent; }
list.nav row {
  padding: 9px 12px;
  border-radius: 10px;
  margin: 1px 0;
  color: rgba(255, 255, 255, 0.82);
}
list.nav row:hover { background-color: rgba(255, 255, 255, 0.08); }
list.nav row:selected {
  background-color: rgba(255, 255, 255, 0.18);
  color: #ffffff;
  box-shadow: inset 0 1px rgba(255, 255, 255, 0.12);
}
.nav-badge {
  background-color: rgba(126, 232, 161, 0.30);
  color: #ffffff;
  border-radius: 999px;
  padding: 1px 8px;
  font-size: 11px;
  font-weight: 800;
}
.nav-header {
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 1.2px;
  color: rgba(255, 255, 255, 0.45);
  padding: 14px 12px 4px 12px;
}
button.update-card {
  background-color: rgba(255, 255, 255, 0.14);
  background-image: none;
  border: 1px solid rgba(255, 255, 255, 0.22);
  border-radius: 12px;
  box-shadow: none;
  padding: 10px 12px;
}
button.update-card:hover { background-color: rgba(255, 255, 255, 0.22); }
.update-card-title { font-weight: 800; font-size: 13px; }
.update-card-detail { font-size: 11px; color: rgba(255, 255, 255, 0.72); }
.stats {
  background-color: rgba(0, 0, 0, 0.18);
  border-radius: 12px;
  padding: 12px;
}
.meter-title { font-size: 11px; font-weight: 700; color: rgba(255, 255, 255, 0.7); }
.meter-value { font-size: 11px; color: rgba(255, 255, 255, 0.6); }
.cm levelbar trough { background-color: rgba(255, 255, 255, 0.12); border: none; border-radius: 4px; min-height: 5px; }
.cm levelbar block.filled {
  background-color: #7ee8c1;
  background-image: linear-gradient(90deg, #5ee7df, #b490ca);
  border: none; border-radius: 4px; min-height: 5px;
}
.cm levelbar block.empty { background: transparent; border: none; }
.cm levelbar.hot block.filled { background-image: linear-gradient(90deg, #f6d365, #fd6e6a); }

/* Typography --------------------------------------------------------- */
.hero-icon { color: rgba(255, 255, 255, 0.92); -gtk-icon-shadow: 0 6px 24px rgba(0, 0, 0, 0.35); }
.hero-title { font-size: 30px; font-weight: 800; }
.hero-subtitle { font-size: 14px; color: rgba(255, 255, 255, 0.72); }
.section-label { font-size: 13px; font-weight: 700; color: rgba(255, 255, 255, 0.8); }
.dim { color: rgba(255, 255, 255, 0.6); font-size: 12px; }
.empty-title { font-size: 17px; font-weight: 700; }
.chip {
  background-color: rgba(255, 255, 255, 0.12);
  border-radius: 999px;
  padding: 3px 10px;
  font-size: 11px;
  font-weight: 700;
}
.chip.running { background-color: rgba(126, 232, 161, 0.28); }
.cm link, .cm link:visited { color: #9ad8ff; }

/* Buttons ------------------------------------------------------------ */
button.round-button {
  border-radius: 999px;
  padding: 0;
  min-width: 96px;
  min-height: 96px;
  background-color: rgba(255, 255, 255, 0.18);
  background-image: radial-gradient(circle at 50% 25%, rgba(255, 255, 255, 0.55), rgba(255, 255, 255, 0.12) 70%);
  border: 2px solid rgba(255, 255, 255, 0.55);
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.35), inset 0 1px rgba(255, 255, 255, 0.5);
  color: #ffffff;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.35);
  transition: all 150ms ease-out;
}
button.round-button:hover {
  background-image: radial-gradient(circle at 50% 25%, rgba(255, 255, 255, 0.7), rgba(255, 255, 255, 0.2) 70%);
  border-color: rgba(255, 255, 255, 0.85);
  box-shadow: 0 10px 36px rgba(0, 0, 0, 0.45), 0 0 0 6px rgba(255, 255, 255, 0.08);
}
button.round-button:active { background-image: radial-gradient(circle at 50% 70%, rgba(255, 255, 255, 0.45), rgba(255, 255, 255, 0.1) 70%); }
button.round-button:disabled { opacity: 0.45; background-color: rgba(255, 255, 255, 0.08); }
.round-main { font-size: 19px; font-weight: 800; }
.round-sub { font-size: 11.5px; color: rgba(255, 255, 255, 0.85); }

button.pill {
  border-radius: 999px;
  padding: 6px 18px;
  background-color: rgba(255, 255, 255, 0.92);
  background-image: none;
  color: #2a1b47;
  border: none;
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.25);
  font-weight: 700;
}
button.pill label, button.pill image { color: #2a1b47; }
button.pill:hover { background-color: #ffffff; }
button.pill.flat-pill {
  background-color: rgba(255, 255, 255, 0.12);
  color: #ffffff;
  box-shadow: none;
}
button.pill.flat-pill label, button.pill.flat-pill image { color: #ffffff; }
button.pill.flat-pill:hover { background-color: rgba(255, 255, 255, 0.22); }
button.pill.small { padding: 4px 12px; font-size: 12.5px; }
button.pill.danger { background-color: rgba(255, 90, 90, 0.35); }
button.pill.danger:hover { background-color: rgba(255, 90, 90, 0.55); }
button.icon-button {
  border-radius: 999px;
  padding: 6px;
  background: rgba(255, 255, 255, 0.10);
  border: none;
  box-shadow: none;
}
button.icon-button:hover { background: rgba(255, 255, 255, 0.22); }
button.icon-button.flat { background: transparent; }
button.icon-button.flat:hover { background: rgba(255, 255, 255, 0.16); }

radiobutton.tab, button.tab {
  border-radius: 999px;
  padding: 5px 14px;
  background: rgba(255, 255, 255, 0.08);
  background-image: none;
  border: none;
  box-shadow: none;
  color: rgba(255, 255, 255, 0.85);
  margin-right: 4px;
}
button.tab:hover { background: rgba(255, 255, 255, 0.16); }
button.tab:checked { background-color: rgba(255, 255, 255, 0.9); color: #2a1b47; }
button.tab:checked label { color: #2a1b47; }
.tab-count { font-weight: 700; margin-left: 6px; }

/* Cards -------------------------------------------------------------- */
.card {
  background-color: rgba(0, 0, 0, 0.22);
  border-radius: 14px;
  border: 1px solid rgba(255, 255, 255, 0.08);
}
.card list, .card viewport { background-color: transparent; }
.card list row { padding: 10px 14px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); }
.card list row:last-child { border-bottom: none; }
.card list row:hover { background-color: rgba(255, 255, 255, 0.05); }
.card list row:selected { background-color: rgba(255, 255, 255, 0.14); }
.row-title { font-weight: 700; font-size: 13.5px; }

.tile {
  background-color: rgba(0, 0, 0, 0.2);
  border-radius: 16px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  padding: 16px;
}
.tile-title { font-size: 12px; font-weight: 700; color: rgba(255, 255, 255, 0.7); letter-spacing: 1px; }
.tile-value { font-size: 24px; font-weight: 800; }
.tile-detail { font-size: 12.5px; color: rgba(255, 255, 255, 0.7); }

.cm flowbox, .cm flowbox flowboxchild { background: transparent; padding: 0; }
.cm flowbox flowboxchild:focus { outline: none; }
.gallery-card {
  background-color: rgba(0, 0, 0, 0.22);
  border-radius: 16px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  padding: 10px 10px 12px 10px;
  transition: all 150ms ease-out;
}
.gallery-card:hover {
  background-color: rgba(255, 255, 255, 0.08);
  border-color: rgba(255, 255, 255, 0.18);
}
.gallery-card.running { border-color: rgba(126, 232, 161, 0.55); }
.card-title { font-size: 14px; font-weight: 700; }
.card-detail { font-size: 11.5px; color: rgba(255, 255, 255, 0.6); }

.dropzone {
  background-color: rgba(0, 0, 0, 0.16);
  border-radius: 18px;
  border: 2px dashed rgba(255, 255, 255, 0.30);
  padding: 30px;
}
.dropzone.drag-hover { background-color: rgba(255, 255, 255, 0.12); border-color: rgba(255, 255, 255, 0.8); }

/* switch: reset the GTK theme's track art and on/off symbols, draw a plain pill */
.cm switch {
  min-width: 44px;
  min-height: 24px;
  padding: 2px;
  margin: 0;
  background-color: rgba(255, 255, 255, 0.18);
  background-image: none;
  border: 1px solid rgba(255, 255, 255, 0.22);
  border-radius: 999px;
  box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.25);
  outline: none;
  color: transparent;
  transition: background-color 150ms ease-out, border-color 150ms ease-out;
}
.cm switch:hover { background-color: rgba(255, 255, 255, 0.26); }
.cm switch:checked {
  background-color: #34c47c;
  border-color: #34c47c;
}
.cm switch:checked:hover { background-color: #3dd388; }
.cm switch:disabled { opacity: 0.5; }
.cm switch image, .cm switch:checked image {
  color: transparent;
  -gtk-icon-source: none;
  min-width: 0;
  min-height: 0;
  opacity: 0;
}
.cm switch slider {
  min-width: 22px;
  min-height: 22px;
  margin: 0;
  background-color: #ffffff;
  background-image: none;
  border: none;
  border-radius: 999px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.35);
  outline: none;
}

.cm entry, .cm spinbutton, .cm spinbutton entry {
  background-color: rgba(255, 255, 255, 0.12);
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.18);
  box-shadow: none;
}
.cm entry { border-radius: 999px; }
.cm spinbutton { border-radius: 10px; }
.cm spinbutton entry { border: none; background: transparent; }
.cm spinbutton button { background: transparent; border: none; box-shadow: none; color: #ffffff; }
.cm spinbutton button:hover { background: rgba(255, 255, 255, 0.14); }
.cm entry selection { background-color: rgba(255, 255, 255, 0.35); }
.cm combobox button, .cm combobox button.combo {
  background: rgba(255, 255, 255, 0.12);
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 10px;
  box-shadow: none;
  color: #ffffff;
}
.cm progressbar trough { background-color: rgba(255, 255, 255, 0.15); border: none; min-height: 6px; border-radius: 3px; }
.cm progressbar progress { background-image: linear-gradient(90deg, #5ee7df, #b490ca); border: none; min-height: 6px; border-radius: 3px; }
.cm spinner { color: #ffffff; }
.cm scrollbar { background: transparent; border: none; }
.cm scrollbar slider { background-color: rgba(255, 255, 255, 0.3); border: none; }

/* Menus attached to the window inherit its white text, so style them dark */
.cm menu, .cm .menu {
  background-color: #262a4a;
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 0;
  padding: 6px;
}
.cm menu menuitem {
  color: #ffffff;
  padding: 7px 14px;
  border-radius: 6px;
}
.cm menu menuitem:hover { background-color: rgba(255, 255, 255, 0.14); }
.cm menu menuitem label { color: #ffffff; }
.cm menu separator { background-color: rgba(255, 255, 255, 0.12); margin: 4px 6px; }

/* Dialogs (Edit Widget, Edit Theme, About, progress) ------------------ */
.cm.cm-dialog { background-image: linear-gradient(150deg, #3a4fb5 0%, #2a2f6e 60%, #1a1f4d 100%); }
.cm-dialog notebook, .cm-dialog notebook > header, .cm-dialog notebook > stack {
  background: transparent;
  border: none;
  box-shadow: none;
}
.cm-dialog notebook > header { padding: 4px 0 8px 0; }
.cm-dialog notebook > header tab {
  border-radius: 999px;
  padding: 4px 12px;
  margin: 0 4px 0 0;
  background: rgba(255, 255, 255, 0.08);
  border: none;
  box-shadow: none;
  min-height: 0;
}
.cm-dialog notebook > header tab:hover { background: rgba(255, 255, 255, 0.16); }
.cm-dialog notebook > header tab:checked { background: rgba(255, 255, 255, 0.9); }
.cm-dialog notebook > header tab:checked label { color: #2a1b47; }
.cm-dialog notebook > stack {
  background-color: rgba(0, 0, 0, 0.18);
  border-radius: 14px;
  border: 1px solid rgba(255, 255, 255, 0.08);
}
.cm-dialog button {
  background-color: rgba(255, 255, 255, 0.12);
  background-image: none;
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 10px;
  box-shadow: none;
  color: #ffffff;
  text-shadow: none;
  -gtk-icon-shadow: none;
}
.cm-dialog button:hover { background-color: rgba(255, 255, 255, 0.22); }
.cm-dialog button:disabled { opacity: 0.5; }
.cm-dialog button.suggested-action { background-color: rgba(255, 255, 255, 0.92); }
.cm-dialog button.suggested-action label { color: #2a1b47; }
.cm-dialog treeview.view, .cm-dialog scrolledwindow viewport { background-color: transparent; color: #ffffff; }
.cm-dialog treeview.view:selected { background-color: rgba(255, 255, 255, 0.18); }
.cm-dialog treeview.view header button {
  background: transparent;
  border: none;
  color: rgba(255, 255, 255, 0.6);
  font-weight: 700;
}
.cm-dialog scrolledwindow, .cm-dialog frame > border {
  border-radius: 12px;
  border-color: rgba(255, 255, 255, 0.12);
  background-color: rgba(0, 0, 0, 0.12);
}
.cm-dialog separator { background-color: rgba(255, 255, 255, 0.12); }
.cm-dialog textview text { background-color: rgba(0, 0, 0, 0.2); color: #ffffff; }
.cm-dialog checkbutton check, .cm-dialog radiobutton radio {
  background-color: rgba(255, 255, 255, 0.14);
  background-image: none;
  border: 1px solid rgba(255, 255, 255, 0.35);
  box-shadow: none;
  color: #ffffff;
}
.cm-dialog checkbutton check:checked, .cm-dialog radiobutton radio:checked { background-color: #34c47c; border-color: #34c47c; }
""";

	/* gives a dialog the main window's look */
	public void dialog(Gtk.Window win) {
		win.get_style_context().add_class("cm");
		win.get_style_context().add_class("cm-dialog");
	}

	public void install() {
		var provider = new Gtk.CssProvider();
		try {
			provider.load_from_data(CSS, -1);
		}
		catch (Error e) {
			log_error("CSS: " + e.message);
			return;
		}
		Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
			Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
	}

	/* small helpers shared by the pages */

	public Gtk.Label label(string text, string? css_class = null, float xalign = 0.0f) {
		var lbl = new Gtk.Label(text);
		lbl.xalign = xalign;
		if (css_class != null) {
			foreach (string c in css_class.split(" ")) {
				lbl.get_style_context().add_class(c);
			}
		}
		return lbl;
	}

	public Gtk.Image icon(string name, int size) {
		var img = new Gtk.Image.from_icon_name(name, Gtk.IconSize.BUTTON);
		img.pixel_size = size;
		return img;
	}

	public Gtk.Button pill(string text, string? icon_name = null, string extra_class = "") {
		var btn = new Gtk.Button();
		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		if (icon_name != null) {
			box.pack_start(icon(icon_name, 16), false, false, 0);
		}
		box.pack_start(new Gtk.Label(text), false, false, 0);
		box.halign = Gtk.Align.CENTER;
		btn.add(box);
		btn.get_style_context().add_class("pill");
		foreach (string c in extra_class.split(" ")) {
			if (c != "") {
				btn.get_style_context().add_class(c);
			}
		}
		return btn;
	}

	public void set_pill_text(Gtk.Button btn, string text) {
		var box = (Gtk.Box) btn.get_child();
		var last = box.get_children().last().data as Gtk.Label;
		if (last != null) {
			last.label = text;
		}
	}

	public Gtk.Button icon_button(string icon_name, string tooltip, bool flat = false) {
		var btn = new Gtk.Button();
		btn.add(icon(icon_name, 16));
		btn.tooltip_text = tooltip;
		btn.get_style_context().add_class("icon-button");
		if (flat) {
			btn.get_style_context().add_class("flat");
		}
		return btn;
	}

	public Gtk.Button round_button(string main_text, out Gtk.Label sub_label) {
		var btn = new Gtk.Button();
		btn.get_style_context().add_class("round-button");
		var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		box.valign = Gtk.Align.CENTER;
		box.pack_start(label(main_text, "round-main", 0.5f), false, false, 0);
		sub_label = label("", "round-sub", 0.5f);
		sub_label.no_show_all = true;
		box.pack_start(sub_label, false, false, 0);
		btn.add(box);
		btn.halign = Gtk.Align.CENTER;
		btn.valign = Gtk.Align.CENTER;
		return btn;
	}

	public void add_class(Gtk.Widget widget, string css_class) {
		widget.get_style_context().add_class(css_class);
	}
}

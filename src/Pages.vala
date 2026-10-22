/*
 * Pages.vala
 *
 * The pages shown in the main window: Overview, Widgets, Themes,
 * Add Widgets and Settings.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

using Gtk;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessManagement;
using TeeJee.GtkHelper;
using TeeJee.System;

/* Base page: a hero header (big icon, title, subtitle) above the content */
public abstract class Page : Box {
	public string page_id;
	public string title;
	public string nav_icon;
	public string? section;
	public Label nav_badge;
	protected MainWindow win;
	protected Label subtitle;
	protected Box hero_end;

	protected Page(MainWindow win, string page_id, string title, string nav_icon, string? section) {
		orientation = Orientation.VERTICAL;
		spacing = 16;
		this.win = win;
		this.page_id = page_id;
		this.title = title;
		this.nav_icon = nav_icon;
		this.section = section;
		margin_start = 28;
		margin_end = 28;
		margin_top = 6;
		margin_bottom = 22;
	}

	protected void add_hero(string icon_name, string hero_title) {
		var hero = new Box(Orientation.HORIZONTAL, 18);
		var img = Style.icon(icon_name, 64);
		Style.add_class(img, "hero-icon");
		hero.pack_start(img, false, false, 0);
		var texts = new Box(Orientation.VERTICAL, 2);
		texts.valign = Align.CENTER;
		texts.pack_start(Style.label(hero_title, "hero-title"), false, false, 0);
		subtitle = Style.label("", "hero-subtitle");
		subtitle.ellipsize = Pango.EllipsizeMode.END;
		texts.pack_start(subtitle, false, false, 0);
		hero.pack_start(texts, true, true, 0);
		hero_end = new Box(Orientation.HORIZONTAL, 8);
		hero_end.valign = Align.CENTER;
		hero.pack_end(hero_end, false, false, 0);
		pack_start(hero, false, false, 0);
	}

	public virtual void shown() {}
	public virtual void focus_search() {}

	protected void set_badge(int count) {
		if (nav_badge == null) {
			return; // not in the sidebar yet
		}
		nav_badge.label = count.to_string();
		nav_badge.visible = count > 0;
	}
}

/* helpers for describing widgets ------------------------------------- */

namespace Library {

	/* folder that groups a widget: "Liquid Glass" for ~/.conky/Liquid Glass/Clock */
	public string pack_name(ConkyConfigItem item) {
		var roots = new Gee.ArrayList<string>();
		roots.add(App.data_dir);
		roots.add_all(App.search_folders);
		foreach (string root in roots) {
			if (item.path.has_prefix(root + "/")) {
				string rel = item.path.substring(root.length + 1);
				int slash = rel.index_of("/");
				if (slash > 0) {
					return rel.substring(0, slash);
				}
				return Path.get_basename(root);
			}
		}
		return Path.get_basename(item.dir);
	}

	public string display_name(ConkyConfigItem item) {
		string name = item.base_name;
		foreach (string ext in new string[]{ ".cmtheme", ".conkyrc", ".conf", ".lua" }) {
			if (name.has_suffix(ext) && name.length > ext.length) {
				name = name.substring(0, name.length - ext.length);
			}
		}
		if (name.has_prefix(".")) {
			name = name.substring(1);
		}
		return name.replace("_", " ");
	}

	public bool theme_is_active(ConkyTheme th) {
		if (th.conkyrc_list.size == 0) {
			return false;
		}
		foreach (ConkyRC rc in th.conkyrc_list) {
			if (!rc.enabled) {
				return false;
			}
		}
		return true;
	}
}

/* Preview image, scaled to fit inside a rounded dark tile ------------- */

public class Thumb : Overlay {
	private DrawingArea area;
	private Box placeholder;
	private string path = "";
	private Gdk.Pixbuf? pix = null;
	private int w;
	private int h;

	private static Gee.ArrayQueue<Thumb> queue;
	private static uint queue_source = 0;

	public Thumb(int width, int height) {
		w = width;
		h = height;
		area = new DrawingArea();
		area.set_size_request(w, h);
		area.hexpand = true;
		area.draw.connect(on_draw);
		add(area);

		placeholder = new Box(Orientation.VERTICAL, 6);
		placeholder.halign = Align.CENTER;
		placeholder.valign = Align.CENTER;
		var img = Style.icon("image-x-generic-symbolic", 32);
		img.opacity = 0.45;
		placeholder.pack_start(img, false, false, 0);
		placeholder.pack_start(Style.label(_("No preview yet"), "dim", 0.5f), false, false, 0);
		placeholder.no_show_all = true;
		add_overlay(placeholder);
	}

	/* images load one per idle cycle so the gallery appears immediately */
	public void set_path(string image_path) {
		path = image_path;
		pix = null;
		placeholder.visible = (path == "" || !file_exists(path));
		if (!placeholder.visible) {
			if (queue == null) {
				queue = new Gee.ArrayQueue<Thumb>();
			}
			queue.offer(this);
			if (queue_source == 0) {
				queue_source = Idle.add(load_next, Priority.LOW);
			}
		}
		area.queue_draw();
	}

	private static bool load_next() {
		var thumb = queue.poll();
		if (thumb != null) {
			thumb.load();
		}
		if (queue.is_empty) {
			queue_source = 0;
			return false;
		}
		return true;
	}

	private void load() {
		int sf = get_scale_factor();
		int iw, ih;
		if (Gdk.Pixbuf.get_file_info(path, out iw, out ih) == null || iw <= 0 || ih <= 0) {
			placeholder.visible = true;
			return;
		}
		// load big enough for a wide card; drawing scales it down to fit
		double scale = double.min((double) (w * 1.6 * sf) / iw, (double) (h * 1.6 * sf) / ih);
		scale = double.min(scale, 2.0 * sf); // don't blow tiny previews up too far
		try {
			pix = new Gdk.Pixbuf.from_file_at_scale(path, int.max(1, (int) (iw * scale)), int.max(1, (int) (ih * scale)), true);
		}
		catch (Error e) {
			log_error(e.message);
			placeholder.visible = true;
		}
		area.queue_draw();
	}

	private bool on_draw(Cairo.Context cr) {
		int aw = area.get_allocated_width();
		int ah = area.get_allocated_height();
		double r = 12;
		cr.new_sub_path();
		cr.arc(aw - r, r, r, -Math.PI / 2, 0);
		cr.arc(aw - r, ah - r, r, 0, Math.PI / 2);
		cr.arc(r, ah - r, r, Math.PI / 2, Math.PI);
		cr.arc(r, r, r, Math.PI, 1.5 * Math.PI);
		cr.close_path();
		cr.clip();

		var bg = new Cairo.Pattern.linear(0, 0, 0, ah);
		bg.add_color_stop_rgba(0, 1, 1, 1, 0.10);
		bg.add_color_stop_rgba(1, 0, 0, 0, 0.25);
		cr.set_source(bg);
		cr.paint();

		if (pix != null) {
			int sf = get_scale_factor();
			// fit inside the tile with a small inset, never upscaling the loaded image
			double fit = double.min(double.min((aw - 16.0) * sf / pix.width, (ah - 16.0) * sf / pix.height), 1.0);
			double dw = pix.width * fit / sf;
			double dh = pix.height * fit / sf;
			cr.save();
			cr.translate(Math.floor((aw - dw) / 2), Math.floor((ah - dh) / 2));
			cr.scale(fit / sf, fit / sf);
			Gdk.cairo_set_source_pixbuf(cr, pix, 0, 0);
			cr.get_source().set_filter(Cairo.Filter.GOOD);
			cr.paint();
			cr.restore();
		}
		return false;
	}
}

/* A gallery card for a widget (switch) or a theme (Apply button) ------- */

public class GalleryCard : FlowBoxChild {
	public ConkyConfigItem item;
	public string pack;
	public string search_text;
	private MainWindow win;
	private Box frame;
	private Switch? toggle = null;
	private Button? apply_button = null;
	private Label? active_chip = null;
	private bool updating = false;

	public GalleryCard(MainWindow win, ConkyConfigItem item) {
		this.win = win;
		this.item = item;
		pack = Library.pack_name(item);
		string name = Library.display_name(item);
		search_text = (name + " " + pack + " " + item.path).down();

		frame = new Box(Orientation.VERTICAL, 10);
		Style.add_class(frame, "gallery-card");
		add(frame);

		var thumb = new Thumb(236, 148);
		thumb.set_path(item.image_path);
		frame.pack_start(thumb, false, false, 0);

		var row = new Box(Orientation.HORIZONTAL, 8);
		row.margin_start = 4;
		frame.pack_start(row, false, false, 0);

		var texts = new Box(Orientation.VERTICAL, 2);
		var title_label = Style.label(name, "card-title");
		title_label.ellipsize = Pango.EllipsizeMode.END;
		title_label.max_width_chars = 18;
		title_label.tooltip_text = item.path.replace(Environment.get_home_dir(), "~");
		texts.pack_start(title_label, false, false, 0);

		string detail = pack;
		if (item is ConkyTheme) {
			var th = (ConkyTheme) item;
			int n = th.conkyrc_list.size;
			detail = ngettext("%d widget", "%d widgets", n).printf(n);
			if (th.wallpaper_path != "") {
				detail += " · " + _("wallpaper");
			}
		}
		var detail_label = Style.label(detail, "card-detail");
		detail_label.ellipsize = Pango.EllipsizeMode.END;
		detail_label.max_width_chars = 22;
		texts.pack_start(detail_label, false, false, 0);
		row.pack_start(texts, true, true, 0);

		var more = new MenuButton();
		more.image = Style.icon("view-more-symbolic", 16);
		more.tooltip_text = _("More actions");
		more.valign = Align.CENTER;
		Style.add_class(more, "icon-button");
		Style.add_class(more, "flat");
		more.popup = build_menu();
		row.pack_end(more, false, false, 0);

		if (item is ConkyRC) {
			toggle = new Switch();
			toggle.valign = Align.CENTER;
			toggle.tooltip_text = _("Show on desktop");
			toggle.state_set.connect((state) => {
				if (!updating) {
					if (state) {
						win.start_widget((ConkyRC) item);
					}
					else {
						win.stop_widget((ConkyRC) item);
					}
				}
				return false;
			});
			row.pack_end(toggle, false, false, 0);
		}
		else {
			active_chip = Style.label(_("Active"), "chip running", 0.5f);
			active_chip.valign = Align.CENTER;
			active_chip.no_show_all = true;
			row.pack_end(active_chip, false, false, 0);
			apply_button = Style.pill(_("Apply"), null, "small");
			apply_button.valign = Align.CENTER;
			apply_button.tooltip_text = _("Stop other widgets, start this theme's widgets and set its wallpaper");
			apply_button.clicked.connect(() => win.apply_theme((ConkyTheme) item));
			row.pack_end(apply_button, false, false, 0);
		}

		update_state();
	}

	private Gtk.Menu build_menu() {
		var menu = new Gtk.Menu();
		if (item is ConkyRC) {
			var rc = (ConkyRC) item;
			add_item(menu, _("Edit Position and Look…"), () => win.edit_widget(rc));
			add_item(menu, _("Open Config in Text Editor"), () => xdg_open(rc.path));
			add_item(menu, _("Open Folder"), () => exo_open_folder(rc.dir));
			menu.append(new SeparatorMenuItem());
			add_item(menu, _("Generate Preview"), () => {
				var list = new Gee.ArrayList<ConkyRC>();
				list.add(rc);
				win.generate_previews(list);
			});
			add_item(menu, _("Run in Terminal (show errors)"), () => win.start_in_terminal(rc));
		}
		else {
			var th = (ConkyTheme) item;
			add_item(menu, _("Edit Theme…"), () => win.edit_theme(th));
			add_item(menu, _("Open Theme File in Text Editor"), () => xdg_open(th.path));
			add_item(menu, _("Open Folder"), () => exo_open_folder(th.dir));
		}
		menu.show_all();
		return menu;
	}

	private delegate void MenuAction();

	private void add_item(Gtk.Menu menu, string text, owned MenuAction action) {
		var mi = new Gtk.MenuItem.with_label(text);
		mi.activate.connect(() => action());
		menu.append(mi);
	}

	public bool is_running() {
		if (item is ConkyRC) {
			return item.enabled;
		}
		return Library.theme_is_active((ConkyTheme) item);
	}

	public void update_state() {
		bool running = is_running();
		if (running) {
			Style.add_class(frame, "running");
		}
		else {
			frame.get_style_context().remove_class("running");
		}
		if (toggle != null) {
			updating = true;
			toggle.active = running;
			toggle.state = running;
			updating = false;
		}
		if (active_chip != null) {
			active_chip.visible = running;
			apply_button.visible = !running;
		}
	}
}

/* Widgets and Themes pages -------------------------------------------- */

public class GalleryPage : Page {
	private bool themes;
	private SearchEntry search;
	private Box tabs;
	private RadioButton? first_tab = null;
	private Gee.HashMap<string, Label> tab_counts = new Gee.HashMap<string, Label>();
	private string filter_key = "all";
	private FlowBox flow;
	private Stack content;
	private Label empty_title;
	private Label empty_detail;
	private Button stop_all;
	private Gee.ArrayList<GalleryCard> cards = new Gee.ArrayList<GalleryCard>();

	public GalleryPage(MainWindow win, bool themes) {
		base(win, themes ? "themes" : "widgets", themes ? _("Themes") : _("Widgets"),
			themes ? "preferences-desktop-wallpaper-symbolic" : "view-app-grid-symbolic", _("Library"));
		this.themes = themes;

		add_hero(themes ? "preferences-desktop-wallpaper-symbolic" : "view-app-grid-symbolic", title);

		search = new SearchEntry();
		search.placeholder_text = themes ? _("Search themes") : _("Search widgets");
		search.width_chars = 22;
		search.search_changed.connect(() => {
			flow.invalidate_filter();
			update_empty();
		});
		hero_end.pack_start(search, false, false, 0);

		var bar = new Box(Orientation.HORIZONTAL, 0);
		tabs = new Box(Orientation.HORIZONTAL, 0);
		var tabs_scroll = new ScrolledWindow(null, null);
		tabs_scroll.vscrollbar_policy = PolicyType.NEVER;
		tabs_scroll.hscrollbar_policy = PolicyType.AUTOMATIC;
		tabs_scroll.add(tabs);
		bar.pack_start(tabs_scroll, true, true, 0);

		var actions = new Box(Orientation.HORIZONTAL, 8);
		actions.margin_start = 12;
		if (themes) {
			var new_theme = Style.pill(_("New Theme"), "list-add-symbolic", "small");
			new_theme.tooltip_text = _("Save the running widgets and current wallpaper as a theme");
			new_theme.clicked.connect(() => win.edit_theme(null));
			actions.pack_start(new_theme, false, false, 0);
		}
		else {
			stop_all = Style.pill(_("Stop All"), "media-playback-stop-symbolic", "small flat-pill");
			stop_all.get_child().show_all();
			stop_all.no_show_all = true;
			stop_all.clicked.connect(() => win.stop_all());
			actions.pack_start(stop_all, false, false, 0);
		}
		var refresh = Style.icon_button("view-refresh-symbolic", _("Rescan folders (F5)"));
		refresh.clicked.connect(() => win.rescan());
		actions.pack_start(refresh, false, false, 0);
		bar.pack_end(actions, false, false, 0);
		pack_start(bar, false, false, 0);

		flow = new FlowBox();
		flow.selection_mode = SelectionMode.NONE;
		flow.homogeneous = true;
		flow.column_spacing = 14;
		flow.row_spacing = 14;
		flow.min_children_per_line = 1;
		flow.max_children_per_line = 8;
		flow.valign = Align.START;
		flow.set_filter_func(filter);

		var scroll = new ScrolledWindow(null, null);
		scroll.hscrollbar_policy = PolicyType.NEVER;
		scroll.add(flow);

		var empty = new Box(Orientation.VERTICAL, 8);
		empty.valign = Align.CENTER;
		empty.halign = Align.CENTER;
		var empty_icon = Style.icon(nav_icon, 48);
		empty_icon.opacity = 0.5;
		empty.pack_start(empty_icon, false, false, 0);
		empty_title = Style.label("", "empty-title", 0.5f);
		empty_detail = Style.label("", "dim", 0.5f);
		empty_detail.wrap = true;
		empty_detail.max_width_chars = 50;
		empty_detail.justify = Justification.CENTER;
		empty.pack_start(empty_title, false, false, 0);
		empty.pack_start(empty_detail, false, false, 0);

		content = new Stack();
		content.add_named(scroll, "grid");
		content.add_named(empty, "empty");
		pack_start(content, true, true, 0);

		win.library_changed.connect(rebuild);
		win.widgets_changed.connect(update_state);
		rebuild();
	}

	private Gee.List<ConkyConfigItem> items() {
		var list = new Gee.ArrayList<ConkyConfigItem>();
		if (themes) {
			list.add_all(App.conkytheme_list);
		}
		else {
			list.add_all(App.conkyrc_list);
		}
		return list;
	}

	private void rebuild() {
		foreach (var card in cards) {
			flow.remove(card);
		}
		cards.clear();
		foreach (var item in items()) {
			var card = new GalleryCard(win, item);
			cards.add(card);
			flow.add(card);
		}
		flow.show_all();
		rebuild_tabs();
		update_state();
	}

	private void rebuild_tabs() {
		foreach (var child in tabs.get_children()) {
			tabs.remove(child);
		}
		tab_counts.clear();
		first_tab = null;

		var packs = new Gee.TreeMap<string, int>();
		foreach (var card in cards) {
			packs[card.pack] = (packs.has_key(card.pack) ? packs[card.pack] : 0) + 1;
		}

		add_tab("all", _("All"));
		add_tab("running", themes ? _("Active") : _("Running"));
		if (packs.size > 1) {
			foreach (var entry in packs.entries) {
				add_tab("pack:" + entry.key, entry.key);
			}
		}
		if (!tab_counts.has_key(filter_key)) {
			filter_key = "all";
		}
		foreach (var child in tabs.get_children()) {
			var tab = (RadioButton) child;
			if (tab.get_data<string>("key") == filter_key) {
				tab.active = true;
			}
		}
		tabs.show_all();
	}

	private void add_tab(string key, string text) {
		var tab = new RadioButton.from_widget(first_tab);
		if (first_tab == null) {
			first_tab = tab;
		}
		tab.set_mode(false);
		tab.set_data<string>("key", key);
		Style.add_class(tab, "tab");
		var box = new Box(Orientation.HORIZONTAL, 0);
		box.pack_start(new Label(text), false, false, 0);
		var count = Style.label("", "tab-count");
		box.pack_start(count, false, false, 0);
		tab.add(box);
		tab.toggled.connect(() => {
			if (tab.active) {
				filter_key = key;
				flow.invalidate_filter();
				update_empty();
			}
		});
		tab_counts[key] = count;
		tabs.pack_start(tab, false, false, 0);
	}

	private bool matches_tab(GalleryCard card, string key) {
		if (key == "running") {
			return card.is_running();
		}
		if (key.has_prefix("pack:")) {
			return card.pack == key.substring(5);
		}
		return true;
	}

	private bool filter(FlowBoxChild child) {
		var card = (GalleryCard) child;
		if (!matches_tab(card, filter_key)) {
			return false;
		}
		string q = search.text.strip().down();
		return q == "" || card.search_text.contains(q);
	}

	private void update_state() {
		int running = 0;
		foreach (var card in cards) {
			card.update_state();
			if (card.is_running()) {
				running++;
			}
		}
		foreach (var entry in tab_counts.entries) {
			int n = 0;
			foreach (var card in cards) {
				if (matches_tab(card, entry.key)) {
					n++;
				}
			}
			entry.value.label = n.to_string();
		}

		if (themes) {
			subtitle.label = cards.size == 0 ? _("No themes yet")
				: ngettext("%d theme", "%d themes", cards.size).printf(cards.size);
		}
		else {
			subtitle.label = ngettext("%d widget", "%d widgets", cards.size).printf(cards.size)
				+ " · " + ngettext("%d running", "%d running", running).printf(running);
			stop_all.visible = running > 0;
			set_badge(running);
		}
		flow.invalidate_filter();
		update_empty();
	}

	private void update_empty() {
		int visible = 0;
		foreach (var card in cards) {
			if (filter(card)) {
				visible++;
			}
		}
		if (visible > 0) {
			content.visible_child_name = "grid";
			return;
		}
		content.visible_child_name = "empty";
		if (win.scanning && cards.size == 0) {
			empty_title.label = _("Looking for widgets…");
			empty_detail.label = "";
		}
		else if (cards.size == 0) {
			empty_title.label = themes ? _("No themes yet") : _("No widgets found");
			empty_detail.label = themes
				? _("Turn on the widgets you like, then press New Theme to save them with your wallpaper.")
				: _("Import a theme pack in Add Widgets, or add a folder that has Conky configs in Settings.");
		}
		else if (filter_key == "running") {
			empty_title.label = themes ? _("No theme is active") : _("Nothing is running");
			empty_detail.label = themes ? _("Press Apply on a theme to use it.") : _("Flip the switch on a widget to show it on your desktop.");
		}
		else {
			empty_title.label = _("No matches");
			empty_detail.label = _("Try a different search.");
		}
	}

	public override void focus_search() {
		search.grab_focus();
	}
}

/* Overview ------------------------------------------------------------ */

public class OverviewPage : Page {
	private Label running_value;
	private Label running_detail;
	private Button running_button;
	private Label login_value;
	private Label login_detail;
	private Button login_button;
	private Label library_value;
	private Label library_detail;
	private ListBox running_list;
	private Box conky_missing;

	public OverviewPage(MainWindow win) {
		base(win, "overview", _("Overview"), "go-home-symbolic", null);
		add_hero("computer-symbolic", _("Your Desktop"));

		conky_missing = new Box(Orientation.HORIZONTAL, 12);
		Style.add_class(conky_missing, "tile");
		conky_missing.pack_start(Style.icon("dialog-warning-symbolic", 24), false, false, 0);
		var warn_texts = new Box(Orientation.VERTICAL, 2);
		warn_texts.pack_start(Style.label(_("Conky is not installed"), "row-title"), false, false, 0);
		var warn_detail = Style.label(_("Widgets can't be shown until it is. Install it with:") + "  sudo apt install conky-all", "dim");
		warn_detail.selectable = true;
		warn_texts.pack_start(warn_detail, false, false, 0);
		conky_missing.pack_start(warn_texts, true, true, 0);
		conky_missing.show_all();
		conky_missing.no_show_all = true;
		pack_start(conky_missing, false, false, 0);

		var tiles = new Box(Orientation.HORIZONTAL, 14);
		tiles.homogeneous = true;
		tiles.pack_start(tile(_("RUNNING"), out running_value, out running_detail, out running_button), true, true, 0);
		tiles.pack_start(tile(_("START AT LOGIN"), out login_value, out login_detail, out login_button), true, true, 0);
		Button browse;
		tiles.pack_start(tile(_("LIBRARY"), out library_value, out library_detail, out browse), true, true, 0);
		pack_start(tiles, false, false, 0);

		running_button.clicked.connect(() => {
			if (win.running_count() > 0) {
				win.stop_all();
			}
			else {
				win.show_page("widgets");
			}
		});
		login_button.clicked.connect(() => {
			App.autostart(!App.check_startup());
			App.update_startup_script();
			update_state();
		});
		Style.set_pill_text(browse, _("Browse"));
		browse.clicked.connect(() => win.show_page("widgets"));

		pack_start(Style.label(_("On your desktop now"), "section-label"), false, false, 0);

		running_list = new ListBox();
		running_list.selection_mode = SelectionMode.NONE;
		var empty = new Box(Orientation.VERTICAL, 6);
		empty.margin = 24;
		empty.pack_start(Style.label(_("No widgets are running"), "empty-title", 0.5f), false, false, 0);
		empty.pack_start(Style.label(_("Pick some in Widgets, or apply a theme."), "dim", 0.5f), false, false, 0);
		empty.show_all();
		running_list.set_placeholder(empty);
		var scroll = new ScrolledWindow(null, null);
		scroll.hscrollbar_policy = PolicyType.NEVER;
		scroll.add(running_list);
		Style.add_class(scroll, "card");
		pack_start(scroll, true, true, 0);

		win.widgets_changed.connect(update_state);
		win.library_changed.connect(update_state);
		update_state();
	}

	private Box tile(string heading, out Label value, out Label detail, out Button button) {
		var box = new Box(Orientation.VERTICAL, 6);
		box.valign = Align.FILL;
		Style.add_class(box, "tile");
		var heading_label = Style.label(heading, "tile-title");
		heading_label.single_line_mode = true;
		heading_label.ellipsize = Pango.EllipsizeMode.END;
		box.pack_start(heading_label, false, false, 0);
		value = Style.label("", "tile-value");
		box.pack_start(value, false, false, 0);
		detail = Style.label("", "tile-detail");
		detail.ellipsize = Pango.EllipsizeMode.END;
		box.pack_start(detail, true, true, 0);
		button = Style.pill("", null, "small flat-pill");
		button.halign = Align.START;
		button.margin_top = 6;
		box.pack_end(button, false, false, 0);
		return box;
	}

	public override void shown() {
		update_state();
	}

	private void update_state() {
		conky_missing.visible = Environment.find_program_in_path("conky") == null;

		var running = new Gee.ArrayList<ConkyRC>();
		foreach (ConkyRC rc in App.conkyrc_list) {
			if (rc.enabled) {
				running.add(rc);
			}
		}

		subtitle.label = running.size == 0 ? _("No widgets on your desktop")
			: ngettext("%d widget on your desktop", "%d widgets on your desktop", running.size).printf(running.size);

		running_value.label = ngettext("%d widget", "%d widgets", running.size).printf(running.size);
		var names = new Gee.ArrayList<string>();
		foreach (var rc in running) {
			names.add(Library.display_name(rc));
		}
		running_detail.label = names.size == 0 ? _("Nothing on your desktop") : string.joinv(", ", names.to_array());
		Style.set_pill_text(running_button, running.size > 0 ? _("Stop All") : _("Choose Widgets"));

		bool login = App.check_startup();
		login_value.label = login ? _("On") : _("Off");
		login_detail.label = login
			? ngettext("Starts %d second after you log in", "Starts %d seconds after you log in", App.startup_delay).printf(App.startup_delay)
			: _("Widgets stay off after you log in");
		Style.set_pill_text(login_button, login ? _("Turn Off") : _("Turn On"));

		var packs = new Gee.HashSet<string>();
		foreach (ConkyRC rc in App.conkyrc_list) {
			packs.add(Library.pack_name(rc));
		}
		library_value.label = ngettext("%d widget", "%d widgets", App.conkyrc_list.size).printf(App.conkyrc_list.size);
		library_detail.label = ngettext("%d theme", "%d themes", App.conkytheme_list.size).printf(App.conkytheme_list.size)
			+ " · " + ngettext("%d pack", "%d packs", packs.size).printf(packs.size);

		foreach (var child in running_list.get_children()) {
			running_list.remove(child);
		}
		foreach (var rc in running) {
			running_list.add(running_row(rc));
		}
		running_list.show_all();
	}

	private Widget running_row(ConkyRC rc) {
		var row = new Box(Orientation.HORIZONTAL, 12);
		var texts = new Box(Orientation.VERTICAL, 2);
		texts.pack_start(Style.label(Library.display_name(rc), "row-title"), false, false, 0);
		texts.pack_start(Style.label(Library.pack_name(rc), "dim"), false, false, 0);
		row.pack_start(texts, true, true, 0);
		var edit = Style.icon_button("document-edit-symbolic", _("Edit position and look"), true);
		edit.valign = Align.CENTER;
		edit.clicked.connect(() => win.edit_widget(rc));
		row.pack_start(edit, false, false, 0);
		var stop = Style.pill(_("Stop"), null, "small flat-pill");
		stop.valign = Align.CENTER;
		stop.clicked.connect(() => win.stop_widget(rc));
		row.pack_start(stop, false, false, 0);
		return row;
	}
}

/* Add Widgets --------------------------------------------------------- */

public class ImportPage : Page {
	private Box dropzone;
	private Label result;

	private const Gtk.TargetEntry[] targets = {
		{ "text/uri-list", 0, 0 }
	};

	public static bool is_archive(string path) {
		string p = path.down();
		foreach (string ext in new string[]{ ".7z", ".zip", ".tar", ".gz", ".tgz", ".bz2", ".xz" }) {
			if (p.has_suffix(ext)) {
				return true;
			}
		}
		return false;
	}

	public ImportPage(MainWindow win) {
		base(win, "import", _("Add Widgets"), "folder-download-symbolic", _("Get more"));
		add_hero("folder-download-symbolic", title);
		subtitle.label = _("Import Conky theme packs and widget archives you have downloaded");

		var drop_events = new EventBox();
		dropzone = new Box(Orientation.VERTICAL, 0);
		Style.add_class(dropzone, "dropzone");
		var inner = new Box(Orientation.VERTICAL, 10);
		inner.valign = Align.CENTER;
		inner.vexpand = true;
		dropzone.pack_start(inner, true, true, 0);
		var img = Style.icon("document-open-symbolic", 56);
		img.opacity = 0.8;
		inner.pack_start(img, false, false, 6);
		inner.pack_start(Style.label(_("Drop theme packs here"), "empty-title", 0.5f), false, false, 0);
		var formats = Style.label(_("Conky Manager packs (.cmtp.7z) and .7z, .zip, .tar.gz, .tar.xz or .tar.bz2 archives"), "dim", 0.5f);
		formats.wrap = true;
		formats.justify = Justification.CENTER;
		inner.pack_start(formats, false, false, 0);

		Label unused;
		var import_button = Style.round_button(_("Import…"), out unused);
		import_button.margin_top = 14;
		import_button.clicked.connect(choose_files);
		inner.pack_start(import_button, false, false, 0);

		result = Style.label("", "section-label", 0.5f);
		result.wrap = true;
		result.justify = Justification.CENTER;
		result.margin_top = 8;
		inner.pack_start(result, false, false, 0);
		drop_events.add(dropzone);
		pack_start(drop_events, true, true, 0);

		Gtk.drag_dest_set(drop_events, Gtk.DestDefaults.ALL, targets, Gdk.DragAction.COPY);
		drop_events.drag_motion.connect(() => {
			Style.add_class(dropzone, "drag-hover");
			return false;
		});
		drop_events.drag_leave.connect(() => dropzone.get_style_context().remove_class("drag-hover"));
		drop_events.drag_data_received.connect((ctx, x, y, data, info, time) => {
			dropzone.get_style_context().remove_class("drag-hover");
			var files = new Gee.ArrayList<string>();
			foreach (string uri in data.get_uris()) {
				try {
					string path = Filename.from_uri(uri);
					if (is_archive(path)) {
						files.add(path);
					}
				}
				catch (ConvertError e) {
					log_error(e.message);
				}
			}
			Gtk.drag_finish(ctx, files.size > 0, false, time);
			if (files.size > 0) {
				import(files.to_array());
			}
			else {
				result.label = _("Those files aren't archives %s can import.").printf(AppName);
			}
		});

		var find = new Box(Orientation.HORIZONTAL, 10);
		find.halign = Align.CENTER;
		find.pack_start(Style.label(_("Find more widgets:"), "dim"), false, false, 0);
		find.pack_start(new LinkButton.with_label("https://www.deviantart.com/search?q=conky", "DeviantArt"), false, false, 0);
		find.pack_start(new LinkButton.with_label("https://github.com/topics/conky", "GitHub"), false, false, 0);
		find.pack_start(new LinkButton.with_label("https://www.pling.com/s/Desktops/browse?cat=124", "Pling"), false, false, 0);
		pack_start(find, false, false, 0);
	}

	private void choose_files() {
		var dialog = new FileChooserDialog(_("Import Widgets"), win, FileChooserAction.OPEN,
			_("_Cancel"), ResponseType.CANCEL, _("_Import"), ResponseType.ACCEPT);
		dialog.select_multiple = true;
		dialog.local_only = true;
		var filter = new FileFilter();
		filter.set_filter_name(_("Theme packs and archives"));
		foreach (string p in new string[]{ "*.7z", "*.zip", "*.tar", "*.gz", "*.tgz", "*.bz2", "*.xz" }) {
			filter.add_pattern(p);
		}
		dialog.add_filter(filter);
		string[] files = {};
		if (dialog.run() == ResponseType.ACCEPT) {
			foreach (string f in dialog.get_filenames()) {
				files += f;
			}
		}
		dialog.destroy();
		if (files.length > 0) {
			import(files);
		}
	}

	public void import(string[] files) {
		int before = App.conkyrc_list.size;
		result.label = _("Importing…");
		gtk_do_events();
		int failed = win.import_files(files);
		ulong handler = 0;
		handler = win.library_changed.connect(() => {
			win.disconnect(handler);
			int added = App.conkyrc_list.size - before;
			string msg = ngettext("Imported %d file", "Imported %d files", files.length - failed).printf(files.length - failed);
			if (added > 0) {
				msg += " · " + ngettext("%d new widget", "%d new widgets", added).printf(added);
			}
			if (failed > 0) {
				msg += "\n" + ngettext("%d file could not be extracted", "%d files could not be extracted", failed).printf(failed);
			}
			result.label = msg;
		});
	}
}

/* Settings ------------------------------------------------------------ */

public class SettingsPage : Page {
	private Switch login_switch;
	private SpinButton delay;
	private ListBox folders;
	private bool loading = false;

	public SettingsPage(MainWindow win) {
		base(win, "settings", _("Settings"), "preferences-system-symbolic", _("App"));
		add_hero("preferences-system-symbolic", title);
		subtitle.label = _("Changes are saved right away");

		var scroll = new ScrolledWindow(null, null);
		scroll.hscrollbar_policy = PolicyType.NEVER;
		var body = new Box(Orientation.VERTICAL, 10);
		scroll.add(body);
		pack_start(scroll, true, true, 0);

		// startup
		body.pack_start(Style.label(_("Startup"), "section-label"), false, false, 0);
		var startup = card();
		login_switch = new Switch();
		login_switch.state_set.connect((state) => {
			if (!loading) {
				App.autostart(state);
				App.update_startup_script();
				win.widgets_changed();
			}
			return false;
		});
		startup.add(setting_row(_("Start widgets when you log in"),
			_("The widgets that are on when you log out come back at login"), login_switch));
		delay = new SpinButton.with_range(0, 120, 5);
		delay.value_changed.connect(() => {
			if (!loading) {
				App.startup_delay = (int) delay.value;
				App.save_app_config();
				App.update_startup_script();
				win.widgets_changed();
			}
		});
		var delay_box = new Box(Orientation.HORIZONTAL, 8);
		delay_box.pack_start(delay, false, false, 0);
		delay_box.pack_start(Style.label(_("seconds"), "dim"), false, false, 0);
		startup.add(setting_row(_("Delay before starting"), _("Gives the desktop time to finish loading first"), delay_box));
		body.pack_start(wrap(startup), false, false, 0);

		// folders
		var folders_head = new Box(Orientation.HORIZONTAL, 0);
		folders_head.margin_top = 10;
		folders_head.pack_start(Style.label(_("Widget folders"), "section-label"), false, false, 0);
		var add_folder = Style.pill(_("Add Folder…"), "list-add-symbolic", "small flat-pill");
		add_folder.clicked.connect(choose_folder);
		folders_head.pack_end(add_folder, false, false, 0);
		body.pack_start(folders_head, false, false, 0);
		folders = card();
		body.pack_start(wrap(folders), false, false, 0);

		// previews
		var previews_head = Style.label(_("Previews"), "section-label");
		previews_head.margin_top = 10;
		body.pack_start(previews_head, false, false, 0);
		var previews = card();
		var capture_bg = new Switch();
		capture_bg.active = App.capture_background;
		capture_bg.state_set.connect((state) => {
			App.capture_background = state;
			App.save_app_config();
			return false;
		});
		previews.add(setting_row(_("Include the desktop background"),
			_("Capture previews with your wallpaper behind the widget"), capture_bg));
		var format = new ComboBoxText();
		format.append("png", "PNG");
		format.append("jpg", "JPEG");
		format.active_id = App.generate_png ? "png" : "jpg";
		format.changed.connect(() => {
			App.generate_png = (format.active_id == "png");
			App.save_app_config();
		});
		previews.add(setting_row(_("Image format"), _("PNG keeps transparency, JPEG files are smaller"), format));
		var generate = Style.pill(_("Generate"), null, "small flat-pill");
		generate.clicked.connect(() => win.generate_previews(win.missing_previews()));
		previews.add(setting_row(_("Missing previews"), _("Capture a preview for every widget that has none"), generate));
		body.pack_start(wrap(previews), false, false, 0);

		load();
	}

	private ListBox card() {
		var list = new ListBox();
		list.selection_mode = SelectionMode.NONE;
		return list;
	}

	private Widget wrap(ListBox list) {
		var frame = new Box(Orientation.VERTICAL, 0);
		Style.add_class(frame, "card");
		frame.pack_start(list, false, false, 0);
		return frame;
	}

	private Widget setting_row(string title_text, string detail, Widget control) {
		var row = new Box(Orientation.HORIZONTAL, 12);
		var texts = new Box(Orientation.VERTICAL, 2);
		texts.pack_start(Style.label(title_text, "row-title"), false, false, 0);
		var d = Style.label(detail, "dim");
		d.wrap = true;
		texts.pack_start(d, false, false, 0);
		row.pack_start(texts, true, true, 0);
		control.valign = Align.CENTER;
		row.pack_end(control, false, false, 0);
		return row;
	}

	private void load() {
		loading = true;
		login_switch.active = App.check_startup();
		delay.value = App.startup_delay;
		loading = false;

		foreach (var child in folders.get_children()) {
			folders.remove(child);
		}
		folders.add(folder_row(App.data_dir, false));
		foreach (string path in App.search_folders) {
			folders.add(folder_row(path, true));
		}
		folders.show_all();
	}

	private Widget folder_row(string path, bool removable) {
		var row = new Box(Orientation.HORIZONTAL, 12);
		row.pack_start(Style.icon("folder-symbolic", 18), false, false, 0);
		var texts = new Box(Orientation.VERTICAL, 2);
		texts.pack_start(Style.label(path.replace(Environment.get_home_dir(), "~"), "row-title"), false, false, 0);
		texts.pack_start(Style.label(removable ? _("Scanned for widgets") : _("Default · imported widgets go here"), "dim"), false, false, 0);
		row.pack_start(texts, true, true, 0);
		var open = Style.icon_button("folder-open-symbolic", _("Open folder"), true);
		open.clicked.connect(() => exo_open_folder(path));
		row.pack_start(open, false, false, 0);
		if (removable) {
			var remove = Style.icon_button("list-remove-symbolic", _("Stop scanning this folder"), true);
			remove.clicked.connect(() => {
				App.search_folders.remove(path);
				App.save_app_config();
				load();
				win.rescan();
			});
			row.pack_start(remove, false, false, 0);
		}
		return row;
	}

	private void choose_folder() {
		var dialog = new FileChooserDialog(_("Add Widget Folder"), win, FileChooserAction.SELECT_FOLDER,
			_("_Cancel"), ResponseType.CANCEL, _("_Add"), ResponseType.ACCEPT);
		if (dialog.run() == ResponseType.ACCEPT) {
			string path = dialog.get_filename();
			if (path != App.data_dir && !App.search_folders.contains(path)) {
				App.search_folders.add(path);
				App.save_app_config();
				load();
				win.rescan();
			}
		}
		dialog.destroy();
	}

	public override void shown() {
		load();
	}
}

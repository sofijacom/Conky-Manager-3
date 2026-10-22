/*
 * MainWindow.vala
 *
 * Copyright 2015 Tony George <teejee2008@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 */

using Gtk;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessManagement;
using TeeJee.GtkHelper;
using TeeJee.System;

/* Sidebar meter: title, value text and a thin bar */
class Meter : Box {
	private Label value_label;
	private LevelBar bar;

	public Meter(string title) {
		Object(orientation: Orientation.VERTICAL, spacing: 3);
		var top = new Box(Orientation.HORIZONTAL, 0);
		top.pack_start(Style.label(title, "meter-title"), true, true, 0);
		value_label = Style.label("", "meter-value", 1.0f);
		top.pack_end(value_label, false, false, 0);
		pack_start(top, false, false, 0);
		bar = new LevelBar.for_interval(0, 1);
		bar.mode = LevelBarMode.CONTINUOUS;
		bar.remove_offset_value(LEVEL_BAR_OFFSET_LOW);
		bar.remove_offset_value(LEVEL_BAR_OFFSET_HIGH);
		bar.remove_offset_value("full");
		pack_start(bar, false, false, 0);
	}

	public void set(double fraction, string text, bool warn_when_high = true) {
		fraction = fraction.clamp(0, 1);
		bar.value = fraction;
		value_label.label = text;
		if (warn_when_high && fraction >= 0.85) {
			bar.get_style_context().add_class("hot");
		}
		else {
			bar.get_style_context().remove_class("hot");
		}
	}
}

public class MainWindow : Window {

	private Stack stack;
	private ListBox nav;
	private Spinner spinner;
	private Meter meter_running;
	private Meter meter_cpu;
	private Meter meter_memory;
	private Gee.ArrayList<Page> pages = new Gee.ArrayList<Page>();
	private string page_class = "";
	private int64 last_action = 0;
	private uint64 cpu_total_prev = 0;
	private uint64 cpu_idle_prev = 0;

	public bool scanning { get; private set; default = false; }

	/* emitted after a rescan (lists replaced) and when widgets start or stop */
	public signal void library_changed();
	public signal void widgets_changed();

	private const Gtk.TargetEntry[] targets = {
		{ "text/uri-list", 0, 0 }
	};

	public MainWindow() {
		title = AppName;
		window_position = WindowPosition.CENTER;
		set_default_size(int.max(App.window_width, 1000), int.max(App.window_height, 680));
		set_size_request(900, 600);
		icon = get_app_icon(64);
		get_style_context().add_class("cm");

		Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, targets, Gdk.DragAction.COPY);
		drag_data_received.connect(on_drag_data_received);

		init_header();

		var root = new Box(Orientation.HORIZONTAL, 0);
		add(root);
		root.pack_start(init_sidebar(), false, false, 0);

		stack = new Stack();
		stack.transition_type = StackTransitionType.CROSSFADE;
		stack.transition_duration = 180;
		root.pack_start(stack, true, true, 0);

		add_page(new OverviewPage(this));
		add_page(new GalleryPage(this, false));
		add_page(new GalleryPage(this, true));
		add_page(new ImportPage(this));
		add_page(new SettingsPage(this));

		nav.row_selected.connect((row) => {
			if (row != null) {
				show_page_widget(pages[row.get_index()]);
			}
		});

		key_press_event.connect(on_key_press);

		show_all();
		show_page("overview");
		update_stats();
		Timeout.add_seconds(2, () => {
			poll_running();
			update_stats();
			return true;
		});

		rescan();
	}

	/* header bar ------------------------------------------------------ */

	private void init_header() {
		var header = new HeaderBar();
		header.show_close_button = true;
		header.title = AppName;
		header.get_style_context().add_class("cm-header");
		set_titlebar(header);

		var menu = new Gtk.Menu();
		add_menu_item(menu, _("Generate Missing Previews"), () => generate_previews(missing_previews()));
		add_menu_item(menu, _("Regenerate All Previews"), () => generate_previews(App.conkyrc_list));
		menu.append(new SeparatorMenuItem());
		add_menu_item(menu, _("Open Widgets Folder"), () => exo_open_folder(App.data_dir));
		add_menu_item(menu, _("Rescan Folders"), () => rescan());
		add_menu_item(menu, _("Stop All Widgets"), () => stop_all());
		menu.append(new SeparatorMenuItem());
		add_menu_item(menu, _("About %s").printf(AppName), () => show_about());
		menu.show_all();

		var menu_button = new MenuButton();
		menu_button.popup = menu;
		menu_button.relief = ReliefStyle.NONE;
		menu_button.image = new Image.from_icon_name("open-menu-symbolic", IconSize.BUTTON);
		menu_button.tooltip_text = _("Menu");
		header.pack_end(menu_button);

		spinner = new Spinner();
		spinner.tooltip_text = _("Scanning for widgets…");
		spinner.no_show_all = true;
		header.pack_end(spinner);
	}

	private delegate void Action();

	private void add_menu_item(Gtk.Menu menu, string text, owned Action action) {
		var item = new Gtk.MenuItem.with_label(text);
		item.activate.connect(() => action());
		menu.append(item);
	}

	/* sidebar --------------------------------------------------------- */

	private Widget init_sidebar() {
		var sidebar = new Box(Orientation.VERTICAL, 0);
		Style.add_class(sidebar, "sidebar");
		sidebar.set_size_request(230, -1);

		var brand = new Box(Orientation.HORIZONTAL, 10);
		brand.margin_start = 8;
		brand.margin_top = 6;
		brand.margin_bottom = 14;
		var logo = new Image();
		var pix = get_app_icon(34 * scale_factor);
		if (pix != null) {
			logo.set_from_surface(Gdk.cairo_surface_create_from_pixbuf(pix, scale_factor, null));
		}
		brand.pack_start(logo, false, false, 0);
		brand.pack_start(Style.label(AppName, "brand"), false, false, 0);
		sidebar.pack_start(brand, false, false, 0);

		nav = new ListBox();
		nav.selection_mode = SelectionMode.SINGLE;
		Style.add_class(nav, "nav");
		nav.set_header_func((row, before) => {
			string? section = row.get_data<string?>("section");
			string? before_section = (before == null) ? null : before.get_data<string?>("section");
			if (section != null && section != before_section) {
				row.set_header(Style.label(section.up(), "nav-header"));
			}
			else {
				row.set_header(null);
			}
		});
		sidebar.pack_start(nav, true, true, 0);

		var stats = new Box(Orientation.VERTICAL, 10);
		Style.add_class(stats, "stats");
		meter_running = new Meter(_("Running widgets"));
		meter_cpu = new Meter(_("CPU"));
		meter_memory = new Meter(_("Memory"));
		stats.pack_start(meter_running, false, false, 0);
		stats.pack_start(meter_cpu, false, false, 0);
		stats.pack_start(meter_memory, false, false, 0);
		sidebar.pack_end(stats, false, false, 0);

		return sidebar;
	}

	private void add_page(Page page) {
		pages.add(page);
		stack.add_named(page, page.page_id);

		var row = new ListBoxRow();
		row.set_data<string?>("section", page.section);
		var box = new Box(Orientation.HORIZONTAL, 12);
		box.pack_start(Style.icon(page.nav_icon, 18), false, false, 0);
		box.pack_start(Style.label(page.title), false, false, 0);
		page.nav_badge = Style.label("", "nav-badge");
		page.nav_badge.no_show_all = true;
		box.pack_end(page.nav_badge, false, false, 0);
		row.add(box);
		nav.add(row);
	}

	public void show_page(string page_id) {
		for (int i = 0; i < pages.size; i++) {
			if (pages[i].page_id == page_id) {
				nav.select_row(nav.get_row_at_index(i));
				return;
			}
		}
	}

	private void show_page_widget(Page page) {
		stack.visible_child = page;
		var ctx = get_style_context();
		if (page_class != "") {
			ctx.remove_class(page_class);
		}
		page_class = "page-" + page.page_id;
		ctx.add_class(page_class);
		page.shown();
	}

	private Page? current_page() {
		return stack.visible_child as Page;
	}

	private bool on_key_press(Gdk.EventKey event) {
		bool ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
		if (ctrl && event.keyval == Gdk.Key.f) {
			var page = current_page();
			if (page != null) {
				page.focus_search();
			}
			return true;
		}
		if (event.keyval == Gdk.Key.F5) {
			rescan();
			return true;
		}
		return false;
	}

	/* status ---------------------------------------------------------- */

	public int running_count() {
		int n = 0;
		foreach (ConkyRC rc in App.conkyrc_list) {
			if (rc.enabled) {
				n++;
			}
		}
		return n;
	}

	/* picks up widgets started or stopped outside the app */
	private void poll_running() {
		if (scanning || (get_monotonic_time() - last_action) < 1500000) {
			return;
		}
		var running = get_running_conky_configs();
		bool changed = false;
		foreach (ConkyRC rc in App.conkyrc_list) {
			bool on = running.values.contains(rc.path);
			if (rc.enabled != on) {
				rc.enabled = on;
				changed = true;
			}
		}
		if (changed) {
			notify_state();
		}
	}

	private void notify_state() {
		int running = running_count();
		int total = App.conkyrc_list.size;
		meter_running.set(total > 0 ? (double) running / total : 0,
			"%d / %d".printf(running, total), false);
		widgets_changed();
	}

	private void update_stats() {
		// CPU: delta of the aggregate line in /proc/stat
		string? stat = read_file("/proc/stat");
		if (stat != null) {
			string[] f = stat.split("\n")[0].split(" ");
			uint64 total = 0;
			uint64 idle = 0;
			int col = 0;
			foreach (string v in f) {
				if (v == "" || v == "cpu") {
					continue;
				}
				uint64 n = uint64.parse(v);
				total += n;
				if (col == 3 || col == 4) {
					idle += n; // idle + iowait
				}
				col++;
			}
			if (cpu_total_prev > 0 && total > cpu_total_prev) {
				double usage = 1.0 - (double) (idle - cpu_idle_prev) / (total - cpu_total_prev);
				meter_cpu.set(usage, "%.0f%%".printf(usage * 100));
			}
			cpu_total_prev = total;
			cpu_idle_prev = idle;
		}

		string? meminfo = read_file("/proc/meminfo");
		if (meminfo != null) {
			double mem_total = 0;
			double mem_avail = 0;
			foreach (string line in meminfo.split("\n")) {
				if (line.has_prefix("MemTotal:")) {
					mem_total = double.parse(line.substring(9).strip().split(" ")[0]);
				}
				else if (line.has_prefix("MemAvailable:")) {
					mem_avail = double.parse(line.substring(13).strip().split(" ")[0]);
				}
			}
			if (mem_total > 0) {
				double used = mem_total - mem_avail;
				meter_memory.set(used / mem_total, "%.1f / %.1f GB".printf(used / 1048576.0, mem_total / 1048576.0));
			}
		}
	}

	/* actions shared by the pages ------------------------------------- */

	private void after_action() {
		last_action = get_monotonic_time();
		App.update_startup_script();
		notify_state();
	}

	public void start_widget(ConkyRC rc) {
		rc.start();
		after_action();
	}

	public void stop_widget(ConkyRC rc) {
		rc.stop();
		after_action();
	}

	public void start_in_terminal(ConkyRC rc) {
		rc.terminal_start();
		after_action();
	}

	public void apply_theme(ConkyTheme th) {
		gtk_set_busy(true, this);
		gtk_do_events();
		th.start();
		gtk_set_busy(false, this);
		after_action();
	}

	public void stop_all() {
		App.kill_all_conky();
		after_action();
	}

	public void rescan() {
		if (scanning) {
			return;
		}
		scanning = true;
		spinner.show();
		spinner.start();
		try {
			new Thread<void>.try("scan", () => {
				App.load_themes_and_widgets();
				Idle.add(() => {
					scanning = false;
					spinner.stop();
					spinner.hide();
					library_changed();
					notify_state();
					return false;
				});
			});
		}
		catch (Error e) {
			log_error(e.message);
			scanning = false;
		}
	}

	public void edit_widget(ConkyRC rc) {
		var dialog = new EditWidgetWindow(rc);
		Style.dialog(dialog);
		dialog.set_transient_for(this);
		dialog.show_all();
		dialog.run();
		dialog.destroy();
		after_action();
	}

	public void edit_theme(ConkyTheme? th) {
		App.refresh_conkyrc_status();
		var dialog = new EditThemeWindow(th);
		Style.dialog(dialog);
		dialog.set_transient_for(this);
		dialog.show_all();
		dialog.run();
		dialog.destroy();
		rescan();
	}

	public Gee.ArrayList<ConkyRC> missing_previews() {
		var list = new Gee.ArrayList<ConkyRC>();
		foreach (ConkyRC rc in App.conkyrc_list) {
			if (rc.image_path == "" || !file_exists(rc.image_path)) {
				list.add(rc);
			}
		}
		return list;
	}

	/* Captures a screenshot of each widget. Running widgets are stopped while
	 * this runs (each one is shown alone) and restarted afterwards. */
	public void generate_previews(Gee.List<ConkyRC> list) {
		if (list.size == 0) {
			gtk_messagebox(_("Previews"), _("Every widget already has a preview."), this);
			return;
		}

		var dialog = new Dialog();
		Style.dialog(dialog);
		dialog.title = _("Generating Previews");
		dialog.set_transient_for(this);
		dialog.modal = true;
		dialog.deletable = false;
		dialog.set_default_size(420, -1);
		var box = dialog.get_content_area();
		box.margin = 18;
		box.spacing = 10;
		var status = new Label("");
		status.xalign = 0;
		status.ellipsize = Pango.EllipsizeMode.MIDDLE;
		var bar = new ProgressBar();
		box.pack_start(status, false, false, 0);
		box.pack_start(bar, false, false, 0);
		bool cancelled = false;
		var cancel = (Button) dialog.add_button(_("Cancel"), ResponseType.CANCEL);
		cancel.clicked.connect(() => {
			cancelled = true;
			App.kill_all_conky();
		});
		dialog.show_all();

		var running = new Gee.ArrayList<ConkyRC>();
		foreach (ConkyRC rc in App.conkyrc_list) {
			if (rc.enabled) {
				running.add(rc);
			}
		}
		App.kill_all_conky();

		int done = 0;
		foreach (ConkyRC rc in list) {
			if (cancelled) {
				break;
			}
			status.label = _("Capturing %s (%d of %d)").printf(rc.name, done + 1, list.size);
			bar.fraction = (double) done / list.size;
			gtk_do_events();
			rc.generate_preview();
			done++;
		}

		foreach (ConkyRC rc in running) {
			rc.start();
		}
		dialog.destroy();
		after_action();
		library_changed();
	}

	/* returns the number of archives that failed */
	public int import_files(string[] files) {
		gtk_set_busy(true, this);
		gtk_do_events();
		int failed = 0;
		foreach (string file in files) {
			bool tar = file.has_suffix(".tar.7z") || file.has_suffix(".tar.bz2") || file.has_suffix(".tar.gz")
				|| file.has_suffix(".tgz") || file.has_suffix(".tar.xz") || file.has_suffix(".tar");
			if (!App.install_theme_pack(file, tar)) {
				failed++;
			}
		}
		gtk_set_busy(false, this);
		rescan();
		return failed;
	}

	private void on_drag_data_received(Gdk.DragContext context, int x, int y,
			SelectionData data, uint info, uint time) {
		var files = new Gee.ArrayList<string>();
		foreach (string uri in data.get_uris()) {
			try {
				string path = Filename.from_uri(uri);
				if (ImportPage.is_archive(path)) {
					files.add(path);
				}
			}
			catch (ConvertError e) {
				log_error(e.message);
			}
		}
		Gtk.drag_finish(context, files.size > 0, false, time);
		if (files.size > 0) {
			show_page("import");
			foreach (Page page in pages) {
				if (page is ImportPage) {
					((ImportPage) page).import(files.to_array());
				}
			}
		}
	}

	public void show_about() {
		var dialog = new Dialog();
		Style.dialog(dialog);
		dialog.title = _("About %s").printf(AppName);
		dialog.set_transient_for(this);
		dialog.modal = true;
		dialog.resizable = false;

		var box = dialog.get_content_area();
		box.margin = 24;
		box.spacing = 6;

		var logo = new Image();
		var pix = get_app_icon(96 * scale_factor);
		if (pix != null) {
			logo.set_from_surface(Gdk.cairo_surface_create_from_pixbuf(pix, scale_factor, null));
		}
		box.pack_start(logo, false, false, 0);
		box.pack_start(Style.label(AppName, "hero-title", 0.5f), false, false, 0);
		box.pack_start(Style.label(_("Version %s").printf(AppVersion), "hero-subtitle", 0.5f), false, false, 0);
		var about = Style.label(_("Browse, preview, start and style your Conky widgets."), null, 0.5f);
		about.margin_top = 8;
		box.pack_start(about, false, false, 0);
		var link = new LinkButton.with_label("https://github.com/thuutien/Conky-Manager-3", _("Project on GitHub"));
		box.pack_start(link, false, false, 0);

		// GPL-2.0 section 2(c): interactive versions keep a short copyright and no-warranty notice
		var legal = Style.label(_("Based on Conky Manager by Tony George and Scott Caudle.\nFree software under the GNU GPL v2 or later, with no warranty."), "dim", 0.5f);
		legal.justify = Justification.CENTER;
		legal.margin_top = 12;
		box.pack_start(legal, false, false, 0);

		dialog.add_button(_("Close"), ResponseType.CLOSE);
		dialog.show_all();
		dialog.run();
		dialog.destroy();
	}
}

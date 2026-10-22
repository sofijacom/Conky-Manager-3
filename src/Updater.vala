/*
 * Updater.vala
 *
 * Checks GitHub for new Conky Manager 3 releases and installs them.
 * The check and download run as the user (with curl); only the final install
 * of a .deb or tarball goes through pkexec. Downloads are verified against the
 * SHA-256 digest GitHub publishes for each release asset.
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
using TeeJee.System;

namespace Updater {

	const string REPO = "thuutien/Conky-Manager-3";
	const string API_LATEST = "https://api.github.com/repos/" + REPO + "/releases/latest";
	const string RELEASES_PAGE = "https://github.com/" + REPO + "/releases/latest";
	const string DOWNLOAD_PREFIX = "https://github.com/" + REPO + "/releases/download/";
	const string INSTALLED_BINARY = "/usr/bin/conky-manager3";

	public class Asset : Object {
		public string url;
		public string sha256;
		public int64 size;
	}

	public class Release : Object {
		public string version = "";
		public string url = RELEASES_PAGE;
		public string notes = "";
		public Gee.HashMap<string, Asset> assets = new Gee.HashMap<string, Asset>();
	}

	/* path of the running binary, recorded at startup (an upgrade replaces the file) */
	public string exe_path;

	public void init() {
		try {
			exe_path = FileUtils.read_link("/proc/self/exe");
		}
		catch (FileError e) {
			exe_path = INSTALLED_BINARY;
		}
	}

	/* ------------------------------------------------------------ versions */

	public int[] version_parts(string v) {
		int[] parts = {};
		string clean = v.has_prefix("v") || v.has_prefix("V") ? v.substring(1) : v;
		foreach (string p in clean.split(".")) {
			var digits = new StringBuilder();
			for (int i = 0; i < p.length && p[i].isdigit(); i++) {
				digits.append_c(p[i]);
			}
			parts += int.parse(digits.len > 0 ? digits.str : "0");
		}
		return parts;
	}

	public bool is_newer(string latest, string current = AppVersion) {
		int[] a = version_parts(latest);
		int[] b = version_parts(current);
		for (int i = 0; i < int.max(a.length, b.length); i++) {
			int x = i < a.length ? a[i] : 0;
			int y = i < b.length ? b[i] : 0;
			if (x != y) {
				return x > y;
			}
		}
		return false;
	}

	/* ------------------------------------------------------------ checking */

	async string run_capture(string[] argv, Cancellable? cancel = null) throws Error {
		var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
		string? out_text, err_text;
		yield proc.communicate_utf8_async(null, cancel, out out_text, out err_text);
		if (!proc.get_successful()) {
			string msg = (err_text ?? "").strip();
			throw new IOError.FAILED(msg != "" ? msg : _("Command failed"));
		}
		return out_text ?? "";
	}

	public async Release fetch_latest() throws Error {
		if (Environment.find_program_in_path("curl") == null) {
			throw new IOError.NOT_FOUND(_("curl is not installed"));
		}
		string json = yield run_capture({
			"curl", "-fsSL", "--max-time", "15",
			"-H", "Accept: application/vnd.github+json",
			"-A", "conky-manager3/" + AppVersion,
			API_LATEST
		});
		var parser = new Json.Parser();
		parser.load_from_data(json);
		var obj = parser.get_root().get_object();
		string tag = obj.has_member("tag_name") ? obj.get_string_member("tag_name") : "";
		if (tag == "") {
			throw new IOError.NOT_FOUND(_("No release found"));
		}
		var rel = new Release();
		rel.version = tag.has_prefix("v") ? tag.substring(1) : tag;
		if (obj.has_member("html_url")) {
			rel.url = obj.get_string_member("html_url");
		}
		if (obj.has_member("body") && !obj.get_null_member("body")) {
			rel.notes = obj.get_string_member("body");
		}
		if (obj.has_member("assets")) {
			foreach (var node in obj.get_array_member("assets").get_elements()) {
				var a = node.get_object();
				var asset = new Asset();
				asset.url = a.get_string_member("browser_download_url");
				asset.size = a.get_int_member("size");
				string digest = (a.has_member("digest") && !a.get_null_member("digest")) ? a.get_string_member("digest") : "";
				asset.sha256 = digest.has_prefix("sha256:") ? digest.substring(7).down() : "";
				rel.assets[a.get_string_member("name")] = asset;
			}
		}
		return rel;
	}

	/* ------------------------------------------------------------ installing */

	/* "deb", "tarball", "package" (another package manager) or "manual" (from source) */
	public string install_method() {
		if (exe_path != INSTALLED_BINARY) {
			return "manual";
		}
		string std_out, std_err;
		if (Environment.find_program_in_path("dpkg-query") != null) {
			execute_command_script_sync("dpkg-query -W -f='${Status}' conky-manager3", out std_out, out std_err);
			if ((std_out ?? "").strip().has_suffix(" installed")) {
				return "deb";
			}
		}
		foreach (string cmd in new string[]{ "pacman -Qq conky-manager3", "rpm -q conky-manager3" }) {
			string tool = cmd.split(" ")[0];
			if (Environment.find_program_in_path(tool) != null && execute_command_script_sync(cmd, out std_out, out std_err) == 0) {
				return "package";
			}
		}
		return "tarball";
	}

	string command_output(string cmd) {
		string std_out, std_err;
		execute_command_script_sync(cmd, out std_out, out std_err);
		return (std_out ?? "").strip();
	}

	/* the release file that matches this installation, or null */
	public string? asset_for(Release rel, string method) {
		string name = "";
		if (method == "deb") {
			name = "conky-manager3_%s_%s.deb".printf(rel.version, command_output("dpkg --print-architecture"));
		}
		else if (method == "tarball") {
			name = "conky-manager3-%s-%s.tar.gz".printf(rel.version, command_output("uname -m"));
		}
		return rel.assets.has_key(name) ? name : null;
	}

	string sha256_of(string path) throws Error {
		var checksum = new Checksum(ChecksumType.SHA256);
		var stream = File.new_for_path(path).read();
		uint8[] buf = new uint8[65536];
		ssize_t n;
		while ((n = stream.read(buf)) > 0) {
			checksum.update(buf, n);
		}
		stream.close();
		return checksum.get_string();
	}

	public delegate void Progress(double fraction);

	/* downloads the asset into dir and verifies it; returns the file path */
	public async string download(Release rel, string name, string dir, Progress progress) throws Error {
		var asset = rel.assets[name];
		if (!asset.url.has_prefix(DOWNLOAD_PREFIX)) {
			throw new IOError.INVALID_DATA(_("Unexpected download location: %s").printf(asset.url));
		}
		if (asset.sha256 == "") {
			throw new IOError.INVALID_DATA(_("GitHub did not publish a checksum for %s").printf(name));
		}
		string path = Path.build_filename(dir, name);
		var proc = new Subprocess.newv({ "curl", "-fsSL", "--max-time", "600", "-o", path, asset.url },
			SubprocessFlags.STDERR_PIPE);
		uint timer = Timeout.add(200, () => {
			var info = File.new_for_path(path);
			if (asset.size > 0 && info.query_exists()) {
				try {
					int64 done = info.query_info(FileAttribute.STANDARD_SIZE, 0).get_size();
					progress((double) done / asset.size);
				}
				catch (Error e) {}
			}
			return true;
		});
		try {
			yield proc.wait_check_async();
		}
		finally {
			Source.remove(timer);
		}
		progress(1.0);
		if (sha256_of(path) != asset.sha256) {
			FileUtils.unlink(path);
			throw new IOError.INVALID_DATA(_("Checksum mismatch for %s; the download was discarded").printf(name));
		}
		return path;
	}

	/* unpacks the tarball after checking it has no absolute or ".." paths; returns install.sh */
	async string unpack_tarball(string path, string dir) throws Error {
		string listing = yield run_capture({ "tar", "-tzf", path });
		foreach (string entry in listing.split("\n")) {
			if (entry == "") {
				continue;
			}
			if (entry.has_prefix("/") || entry == ".." || entry.has_prefix("../") || entry.contains("/../")) {
				throw new IOError.INVALID_DATA(_("Unsafe entry in archive: %s").printf(entry));
			}
		}
		yield run_capture({ "tar", "-xzf", path, "-C", dir, "--no-same-owner" });
		string top = Path.get_basename(path).replace(".tar.gz", "");
		// the folder is named without the architecture: conky-manager3-<version>
		int arch = top.last_index_of("-");
		string script = Path.build_filename(dir, top.substring(0, arch), "install.sh");
		if (!FileUtils.test(script, FileTest.IS_REGULAR)) {
			throw new IOError.NOT_FOUND(_("install.sh not found in the release archive"));
		}
		return script;
	}

	/* downloads, verifies and installs rel; throws with a readable message on failure */
	public async void install(Release rel, Progress progress) throws Error {
		string method = install_method();
		string? name = asset_for(rel, method);
		if (name == null) {
			throw new IOError.NOT_SUPPORTED(_("This release has no package for how Conky Manager 3 is installed here"));
		}
		if (Environment.find_program_in_path("pkexec") == null) {
			throw new IOError.NOT_FOUND(_("pkexec is not installed, so the update can't ask for your password"));
		}
		string dir = DirUtils.make_tmp("conky-manager3-update-XXXXXX");
		try {
			string path = yield download(rel, name, dir, progress);
			string[] argv;
			if (method == "deb") {
				argv = { "pkexec", "apt-get", "install", "-y", path };
			}
			else {
				string script = yield unpack_tarball(path, dir);
				argv = { "pkexec", "/bin/sh", script };
			}
			var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
			string? output;
			yield proc.communicate_utf8_async(null, null, out output, null);
			int status = proc.get_exit_status();
			if (status == 126 || status == 127) {
				throw new IOError.PERMISSION_DENIED(_("Authentication was cancelled"));
			}
			if (status != 0) {
				string[] lines = (output ?? "").strip().split("\n");
				throw new IOError.FAILED(lines.length > 0 && lines[lines.length - 1] != "" ? lines[lines.length - 1] : _("The installer failed"));
			}
		}
		finally {
			execute_command_sync("rm -rf '%s'".printf(dir));
		}
	}

	/* ------------------------------------------------------------ release notes */

	/* the small Markdown subset used in release notes, as Pango markup */
	public string notes_markup(string text) {
		var lines = new StringBuilder();
		try {
			var bold = new Regex("\\*\\*(.+?)\\*\\*");
			var code = new Regex("`([^`]+)`");
			var link = new Regex("!?\\[([^\\]]*)\\]\\([^)]+\\)");
			var bullet = new Regex("^(\\s*)[-*]\\s+");
			var heading = new Regex("^#+\\s+(.*)$");
			foreach (string raw in text.strip().split("\n")) {
				string line = Markup.escape_text(raw.chomp());
				if (raw.strip().has_prefix("![")) {
					continue; // images
				}
				line = bold.replace(line, -1, 0, "<b>\\1</b>");
				line = code.replace(line, -1, 0, "<tt>\\1</tt>");
				line = link.replace(line, -1, 0, "\\1");
				MatchInfo m;
				if (heading.match(line, 0, out m)) {
					line = "<b><big>%s</big></b>".printf(m.fetch(1));
				}
				else if (bullet.match(line, 0, out m)) {
					string indent = m.fetch(1).length > 0 ? "      " : "";
					line = indent + "•  " + bullet.replace(line, -1, 0, "");
				}
				lines.append(line).append("\n");
			}
		}
		catch (RegexError e) {
			return Markup.escape_text(text);
		}
		// skipped images leave gaps: keep at most one blank line in a row
		string result = lines.str.strip();
		while (result.contains("\n\n\n")) {
			result = result.replace("\n\n\n", "\n\n");
		}
		return result;
	}

	/* ------------------------------------------------------------ dialog */

	public class UpdateDialog : Dialog {
		private MainWindow win;
		private Release? release;
		private Image status_icon;
		private Spinner spinner;
		private Label title_label;
		private Label detail_label;
		private ScrolledWindow notes_scroll;
		private Label notes;
		private ProgressBar progress;
		private Button close_button;
		private Button action_button;
		private string mode = "";

		public UpdateDialog(MainWindow win, Release? release) {
			this.win = win;
			this.release = release;
			title = _("Software Update");
			set_transient_for(win);
			modal = true;
			resizable = false;
			set_default_size(560, -1);
			Style.dialog(this);

			close_button = (Button) add_button(_("Close"), ResponseType.CLOSE);
			action_button = (Button) add_button("", ResponseType.APPLY);
			action_button.get_style_context().add_class("suggested-action");
			response.connect(on_response);

			var area = get_content_area();
			area.spacing = 12;
			area.margin = 20;

			var head = new Box(Orientation.HORIZONTAL, 16);
			status_icon = Style.icon("software-update-available-symbolic", 48);
			spinner = new Spinner();
			spinner.set_size_request(48, 48);
			head.pack_start(status_icon, false, false, 0);
			head.pack_start(spinner, false, false, 0);
			var texts = new Box(Orientation.VERTICAL, 4);
			texts.valign = Align.CENTER;
			title_label = Style.label("", null);
			detail_label = Style.label("", "dim");
			detail_label.wrap = true;
			detail_label.max_width_chars = 52;
			texts.pack_start(title_label, false, false, 0);
			texts.pack_start(detail_label, false, false, 0);
			head.pack_start(texts, true, true, 0);
			area.pack_start(head, false, false, 0);

			notes = new Label("");
			notes.xalign = 0;
			notes.yalign = 0;
			notes.wrap = true;
			notes.max_width_chars = 60;
			notes.selectable = true;
			notes.margin = 12;
			notes_scroll = new ScrolledWindow(null, null);
			notes_scroll.hscrollbar_policy = PolicyType.NEVER;
			notes_scroll.min_content_height = 200;
			notes_scroll.max_content_height = 340;
			notes_scroll.propagate_natural_height = true;
			notes_scroll.add(notes);
			area.pack_start(notes_scroll, true, true, 0);

			progress = new ProgressBar();
			area.pack_start(progress, false, false, 0);
			area.show_all();

			if (release == null) {
				check.begin();
			}
			else {
				checked(release);
			}
		}

		private void show_state(string heading, string detail, bool busy = false, string? action = null,
				string? notes_text = null, bool show_progress = false) {
			title_label.set_markup("<b><big>%s</big></b>".printf(Markup.escape_text(heading)));
			detail_label.label = detail;
			spinner.visible = busy;
			status_icon.visible = !busy;
			if (busy) {
				spinner.start();
			}
			else {
				spinner.stop();
			}
			action_button.visible = action != null;
			if (action != null) {
				action_button.label = action;
			}
			notes_scroll.visible = notes_text != null && notes_text != "";
			if (notes_scroll.visible) {
				notes.set_markup(notes_markup(notes_text));
			}
			progress.visible = show_progress;
			close_button.sensitive = !busy;
			mode = action ?? "";
		}

		private async void check() {
			show_state(_("Checking for updates…"), "", true);
			try {
				checked(yield fetch_latest());
			}
			catch (Error e) {
				show_state(_("Couldn't check for updates"), e.message + ". " + _("Check your internet connection."),
					false, _("Try Again"));
			}
		}

		private void checked(Release rel) {
			release = rel;
			win.on_release_checked(rel);
			if (!is_newer(rel.version)) {
				show_state(_("You're up to date"), _("Version %s is the latest version of %s.").printf(AppVersion, AppName));
				return;
			}
			string method = install_method();
			bool can_install = asset_for(rel, method) != null;
			string detail = _("You have version %s.").printf(AppVersion);
			if (method == "manual") {
				detail += " " + _("You are running Conky Manager 3 from source. Update it with git pull, or install a package from the release page.");
			}
			else if (method == "package") {
				detail += " " + _("Conky Manager 3 was installed by your package manager. Update it there.");
			}
			else if (!can_install) {
				detail += " " + _("Download it from the release page.");
			}
			show_state(_("Version %s is available").printf(rel.version), detail, false,
				can_install ? _("Install %s").printf(rel.version) : _("Open Download Page"), rel.notes);
		}

		private async void do_install() {
			string hint = " " + _("You'll be asked for your password.");
			show_state(_("Installing version %s…").printf(release.version), _("Downloading…") + hint, true, null, null, true);
			progress.fraction = 0;
			try {
				yield install(release, (fraction) => {
					progress.fraction = fraction.clamp(0, 1);
					detail_label.label = (fraction < 1.0
						? _("Downloading… %d%%").printf((int) (fraction * 100))
						: _("Verifying and installing…")) + hint;
				});
				show_state(_("Updated to %s").printf(release.version),
					_("Restart Conky Manager 3 to start using the new version. Your widgets keep running."), false, _("Restart Now"));
			}
			catch (Error e) {
				show_state(_("Update failed"), e.message, false, _("Try Again"));
			}
		}

		private void on_response(int response_id) {
			if (response_id != ResponseType.APPLY) {
				destroy();
				return;
			}
			if (mode == _("Try Again")) {
				check.begin();
			}
			else if (mode == _("Open Download Page")) {
				xdg_open(release.url);
			}
			else if (mode == _("Restart Now")) {
				win.restart();
			}
			else {
				do_install.begin();
			}
		}
	}
}

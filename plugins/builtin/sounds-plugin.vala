namespace SoundsPlugin
{
    private const uint FADE_IN_TIME = 4000;
    private const uint FADE_OUT_MIN_TIME = 200;
    private const uint FADE_OUT_MAX_TIME = 10000;

    public struct Preset
    {
        public string value;
        public string name;
    }

    private const Preset[] SOUND_PRESTES = {
        { "clock.ogg", N_("Clock Ticking") },
        { "timer.ogg", N_("Timer Ticking") },
        { "birds.ogg", N_("Woodland Birds") },
        { "bell.ogg", N_("Bell") },
        { "loud-bell.ogg", N_("Loud Bell") },
    };

    private const GLib.SettingsBindFlags SETTINGS_BIND_FLAGS =
                                       GLib.SettingsBindFlags.DEFAULT |
                                       GLib.SettingsBindFlags.GET |
                                       GLib.SettingsBindFlags.SET;

    private void list_box_separator_func (Gtk.ListBoxRow  row,
                                          Gtk.ListBoxRow? before)
    {
        if (before != null) {
            var header = row.get_header ();

            if (header == null) {
                header = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
                header.show ();
                row.set_header (header);
            }
        }
    }

    [GtkTemplate (ui = "/org/gnome/pomodoro/ui/preferences-sound-page.ui")]
    public abstract class PreferencesSoundPage : Gtk.Box, Pomodoro.PreferencesPage
    {
        public double volume { get; set; }
        public string uri { get; set; }
        public string default_uri { get; set; default = ""; }

        public bool enabled {
            get {
                return this.sensitive;
            }
            set {
                this.sensitive = value;

                if (value) {
                    this.uri = this.get_selected_uri ();
                }
                else {
                    this.player.stop ();

                    this.uri = "";
                }
            }
        }

        [GtkChild]
        private Gtk.Adjustment volume_adjustment;
        [GtkChild]
        private Gtk.ListBox chooser_listbox;

        protected SoundPlayer player;

        private static const Gtk.TargetEntry[] target_entries = {};

        private static string file_chooser_current_folder_uri;
        private static string file_chooser_current_file_uri;
        private static int    file_chooser_width = 900;
        private static int    file_chooser_height = 700;

        private enum TargetType
        {
            TEXT_PLAIN,
            TEXT_URI_LIST
        }

        construct
        {
            this.chooser_listbox.set_header_func (list_box_separator_func);
            this.chooser_listbox.set_sort_func (chooser_listbox_sort_func);

            this.setup_player ();

            this.bind_property ("volume",
                                this.volume_adjustment,
                                "value",
                                GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);

            this.bind_property ("volume",
                                this.player,
                                "volume",
                                GLib.BindingFlags.SYNC_CREATE);

            this.notify["uri"].connect (this.on_uri_notify);

            /* Drag and drop */
            var target_list = new Gtk.TargetList (this.target_entries);
            target_list.add_uri_targets (TargetType.TEXT_URI_LIST);
            target_list.add_text_targets (TargetType.TEXT_PLAIN);

            Gtk.drag_dest_set (this.chooser_listbox,
                               Gtk.DestDefaults.ALL,
                               this.target_entries,
                               Gdk.DragAction.COPY);
            Gtk.drag_dest_set_target_list (this.chooser_listbox, target_list);
        }

        protected unowned Gtk.ListBoxRow get_row_by_uri (string uri)
        {
            unowned Gtk.ListBoxRow row = null;

            this.chooser_listbox.forall ((child) => {
                if (child.get_data<string> ("uri") == this.uri) {
                    row = child as Gtk.ListBoxRow;
                }
            });

            return row;
        }

        private string get_selected_uri ()
        {
            if (this.enabled)
            {
                var row = this.chooser_listbox.get_selected_row ();

                if (row != null) {
                    return row.get_data<string> ("uri");
                }

                return this.default_uri;
            }

            return "";
        }

        private static int chooser_listbox_sort_func (Gtk.ListBoxRow row1,
                                                      Gtk.ListBoxRow row2)
        {
            var is_preset1 = row1.get_data<bool> ("is-preset");
            var is_preset2 = row2.get_data<bool> ("is-preset");

            var label1 = row1.get_data<string> ("label");
            var label2 = row2.get_data<string> ("label");

            if (row1.selectable != row2.selectable) {
                return row1.selectable ? -1 : 1;
            }

            if (is_preset1 != is_preset2) {
                return is_preset1 ? -1 : 1;
            }

            return GLib.strcmp (label1, label2);
        }

        private Gtk.ListBoxRow create_row (string uri,
                                           string label,
                                           bool   is_preset=false)
        {
            var label_widget = new Gtk.Label (label);
            label_widget.halign = Gtk.Align.CENTER;

            var row = new Gtk.ListBoxRow ();
            row.add (label_widget);
            row.set_data<string> ("label", label);
            row.set_data<string> ("uri", uri);
            row.set_data<bool> ("is-preset", is_preset);
            row.show_all ();

            return row;
        }

        public void add_presets (Preset[] presets)
        {
            foreach (var preset in presets) {
                var row = this.create_row (preset.value,
                                           preset.name,
                                           true);

                this.chooser_listbox.insert (row, -1);
            }
        }

        private void on_uri_notify ()
        {
            var file = GLib.File.new_for_uri (this.uri);
            var row  = this.get_row_by_uri (this.uri);

            if (row == null && this.uri != "") {
                row = this.create_row (uri, file.get_basename ());
                this.chooser_listbox.insert (row, -1);
            }

            this.player.file = file;

            if (row != this.chooser_listbox.get_selected_row ()) {
                this.chooser_listbox.select_row (row);
            }

            if (this.uri != "" && !this.enabled) {
                this.enabled = true;
            }
            else if (this.uri == "" && this.enabled) {
                this.enabled = false;
            }
        }

        private void on_row_selected_internal (Gtk.ListBoxRow? row)
        {
            var uri = row != null ? row.get_data<string> ("uri") : "";

            if (this.uri != uri) {
                this.uri = uri;
            }

            if (uri != "") {
                this.player.play ();
            }
            else {
                this.player.stop ();
            }
        }

        [GtkCallback]
        private void on_row_selected (Gtk.ListBox     listbox,
                                      Gtk.ListBoxRow? row)
        {
            // if (this.get_mapped ()) {
            //     this.on_row_selected_internal (row);
            // }
        }

        [GtkCallback]
        private void on_row_activated (Gtk.ListBox    listbox,
                                       Gtk.ListBoxRow row)
        {
            if (row.name == "add") {
                this.open_file_chooser ();
            }
            else {
                this.on_row_selected_internal (row);
            }
        }

        [GtkCallback]
        private void on_drag_data_received (Gdk.DragContext   context,
                                            int               x,
                                            int               y,
                                            Gtk.SelectionData data,
                                            uint              type,
                                            uint              drag_time)
        {
            GLib.File file = null;

            if (context == null || data == null || data.get_length () < 0) {
                return;
            }

            switch (type)
            {
                case TargetType.TEXT_URI_LIST:
                    var uris = data.get_uris ();
                    if (uris != null) {
                        file = GLib.File.new_for_uri (uris[0]);
                    }
                    break;

                case TargetType.TEXT_PLAIN:
                    file = GLib.File.new_for_uri (data.get_text ());
                    break;

                default:
                    break;
            }

            if (file != null) {
                this.uri = file.get_uri ();
            }

            Gtk.drag_finish (context, true, false, drag_time);
        }

        public override void unmap ()
        {
            if (this.player is Fadeable) {
                (this.player as Fadeable).fade_out (FADE_OUT_MIN_TIME);
            }
            else {
                this.player.stop ();
            }

            base.unmap ();
        }

        private void open_file_chooser ()
        {
            var file_filter = new Gtk.FileFilter ();

            foreach (var mime_type in this.player.get_supported_mime_types ()) {
                file_filter.add_mime_type (mime_type);
            }

            var file_chooser = new Gtk.FileChooserDialog (_("Select Custom Sound"),
                                                          this.get_toplevel () as Gtk.Window,
                                                          Gtk.FileChooserAction.OPEN,
                                                          "_Cancel",
                                                          Gtk.ResponseType.CANCEL,
                                                          "_Select",
                                                          Gtk.ResponseType.OK);
            file_chooser.local_only = true;
            file_chooser.filter = file_filter;
            file_chooser.set_default_response (Gtk.ResponseType.OK);
            file_chooser.modal = true;
            file_chooser.destroy_with_parent = true;

            if (file_chooser_current_file_uri != null) {
                file_chooser.select_uri (file_chooser_current_file_uri);
            }
            else if (file_chooser_current_folder_uri != null) {
                file_chooser.set_current_folder_uri (file_chooser_current_folder_uri);
            }

            if (file_chooser_width > 0 && file_chooser_height > 0) {
                file_chooser.resize (file_chooser_width, file_chooser_height);
            }

            switch (file_chooser.run ())
            {
                case Gtk.ResponseType.OK:
                    this.uri = file_chooser.get_file ().get_uri ();
                    break;

                default:
                    break;
            }

            file_chooser_current_folder_uri = file_chooser.get_current_folder_uri ();
            file_chooser_current_file_uri = file_chooser.get_uri ();

            file_chooser.get_size (out file_chooser_width,
                                   out file_chooser_height);

            file_chooser.hide ();
        }

        public void configure_header_bar (Gtk.HeaderBar header_bar)
        {
            var toggle_button = new Gtk.Switch ();
            toggle_button.valign = Gtk.Align.CENTER;
            toggle_button.show ();

            this.bind_property ("enabled",
                                toggle_button,
                                "active",
                                GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);

            header_bar.pack_end (toggle_button);
        }

        protected virtual void setup_player ()
        {
            this.player = new SoundsPlugin.GStreamerPlayer ();
        }
    }

    /**
     * Preferences page for changing ticking sound.
     */
    public class PreferencesTickingSoundPage : PreferencesSoundPage
    {
        private static const Preset[] presets = {
            { "clock.ogg", N_("Clock Ticking") },
            { "timer.ogg", N_("Timer Ticking") },
            { "birds.ogg", N_("Woodland Birds") }
        };

        private GLib.Settings settings;

        construct
        {
            this.default_uri = "clock.ogg";

            this.settings = Pomodoro.get_settings ()
                                    .get_child ("preferences");

            this.settings.bind ("ticking-sound",
                                this,
                                "uri",
                                SETTINGS_BIND_FLAGS);

            this.settings.bind ("ticking-sound-volume",
                                this,
                                "volume",
                                SETTINGS_BIND_FLAGS);

            this.add_presets (presets);
        }

        protected override void setup_player ()
        {
            var player = SoundsPlugin.ApplicationExtension.instance.ticking_sound;

            if (player is SoundPlayerProxy) {
                player = (player as SoundPlayerProxy).player;
            }

            this.player = new SoundPlayerProxy (player);
        }
    }

    public class PreferencesPomodoroEndSoundPage : PreferencesSoundPage
    {
        private static const Preset[] presets = {
            { "bell.ogg", N_("Bell") },
            { "loud-bell.ogg", N_("Loud Bell") }
        };

        private GLib.Settings settings;

        construct
        {
            this.default_uri = "bell.ogg";

            this.settings = Pomodoro.get_settings ()
                                    .get_child ("preferences");

            this.settings.bind ("pomodoro-end-sound",
                                this,
                                "uri",
                                SETTINGS_BIND_FLAGS);

            this.settings.bind ("pomodoro-end-sound-volume",
                                this,
                                "volume",
                                SETTINGS_BIND_FLAGS);

            this.add_presets (presets);
        }

        protected override void setup_player ()
        {
            this.player = new SoundsPlugin.CanberraPlayer ();
        }
    }

    public class PreferencesPomodoroStartSoundPage : PreferencesSoundPage
    {
        private static const Preset[] presets = {
            { "bell.ogg", N_("Bell") },
            { "loud-bell.ogg", N_("Loud Bell") }
        };

        private GLib.Settings settings;

        construct
        {
            this.default_uri = "loud-bell.ogg";

            this.settings = Pomodoro.get_settings ()
                                    .get_child ("preferences");

            this.settings.bind ("pomodoro-start-sound",
                                this,
                                "uri",
                                SETTINGS_BIND_FLAGS);

            this.settings.bind ("pomodoro-start-sound-volume",
                                this,
                                "volume",
                                SETTINGS_BIND_FLAGS);

            this.add_presets (presets);
        }

        protected override void setup_player ()
        {
            this.player = new SoundsPlugin.CanberraPlayer ();
        }
    }

    public class PreferencesDialogExtension : Peas.ExtensionBase, Pomodoro.PreferencesDialogExtension
    {
        private static const string[] volume_icons = {
            "audio-volume-muted-symbolic",
            "audio-volume-high-symbolic",
            "audio-volume-low-symbolic",
            "audio-volume-medium-symbolic",
        };

        private Pomodoro.PreferencesDialog dialog;

        private GLib.Settings settings;
        private GLib.List<Gtk.ListBoxRow> rows;

        construct
        {
            this.settings = Pomodoro.get_settings ()
                                    .get_child ("preferences");

            this.dialog = Pomodoro.PreferencesDialog.get_default ();

            this.dialog.add_page ("ticking-sound",
                                  _("Ticking Sound"),
                                  typeof (SoundsPlugin.PreferencesTickingSoundPage));

            this.dialog.add_page ("end-of-break-sound",
                                  _("End of Break Sound"),
                                  typeof (SoundsPlugin.PreferencesPomodoroStartSoundPage));

            this.dialog.add_page ("start-of-break-sound",
                                  _("Start of Break Sound"),
                                  typeof (SoundsPlugin.PreferencesPomodoroEndSoundPage));

            this.setup_main_page ();
        }

        ~PreferencesDialogExtension ()
        {
            if (this.dialog != null) {
                this.dialog.remove_page ("ticking-sound");
                this.dialog.remove_page ("end-of-break-sound");
                this.dialog.remove_page ("start-of-break-sound");
            }

            foreach (var row in this.rows) {
                row.destroy ();
            }

            this.rows = null;
        }

        private static bool settings_sound_label_getter (GLib.Value   value,
                                                         GLib.Variant variant,
                                                         void*        user_data)
        {
            var uri = variant.get_string ();
            var label = _("Off");

            if (uri != "") {
                label = File.new_for_uri (uri).get_basename ();

                foreach (var preset in SOUND_PRESTES) {
                    if (preset.value == uri) {
                        label = preset.name;
                        break;
                    }
                }
            }

            value.set_string (label);

            return true;
        }

        private static bool settings_sound_toggled_getter (GLib.Value   value,
                                                           GLib.Variant variant,
                                                           void*        user_data)
        {
            value.set_boolean (variant.get_string () != "");

            return true;
        }

        private static bool settings_volume_icon_getter (GLib.Value   value,
                                                         GLib.Variant variant,
                                                         void*        user_data)
        {
            var volume = variant.get_double ();
            var num_icons = volume_icons.length;
            string icon_name;

            if (volume == 0.0) {
                icon_name = volume_icons[0];
            }
            else if (volume == 1.0) {
                icon_name = volume_icons[1];
            }
            else {
                var step = (1.0 - 0.0) / (num_icons - 2);
                var i = (uint) ((volume - 0.0) / step) + 2;

                assert (i < num_icons);

                icon_name = volume_icons[i];
            }

            value.set_string (icon_name);

            return true;
        }

        private Gtk.ListBoxRow create_row (string label,
                                           string name,
                                           string settings_key)
        {
            var name_label = new Gtk.Label (label);
            name_label.halign = Gtk.Align.START;
            name_label.valign = Gtk.Align.BASELINE;

            var value_label = new Gtk.Label (null);
            value_label.halign = Gtk.Align.END;
            value_label.margin_left = 30;
            value_label.get_style_context ().add_class ("dim-label");

            var volume_icon = new Gtk.Image ();
            volume_icon.icon_size = Gtk.IconSize.BUTTON;
            volume_icon.halign = Gtk.Align.END;
            volume_icon.margin_left = 10;
            volume_icon.get_style_context ().add_class ("dim-label");

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box.pack_start (name_label, true, true, 0);
            box.pack_start (value_label, false, true, 0);
            box.pack_start (volume_icon, false, true, 0);

            var row = new Gtk.ListBoxRow ();
            row.name = name;
            row.selectable = false;
            row.add (box);
            row.show_all ();

            this.settings.bind_with_mapping (settings_key,
                                             value_label,
                                             "label",
                                             GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET,
                                             (GLib.SettingsBindGetMappingShared) settings_sound_label_getter,
                                             null,
                                             null,
                                             null);

            this.settings.bind_with_mapping (settings_key,
                                             volume_icon,
                                             "visible",
                                             GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET,
                                             (GLib.SettingsBindGetMappingShared) settings_sound_toggled_getter,
                                             null,
                                             null,
                                             null);

            this.settings.bind_with_mapping (settings_key + "-volume",
                                             volume_icon,
                                             "icon-name",
                                             GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET,
                                             (GLib.SettingsBindGetMappingShared) settings_volume_icon_getter,
                                             null,
                                             null,
                                             null);

            return row;
        }

        private void setup_main_page ()
        {
            Gtk.ListBoxRow row;

            var main_page = this.dialog.get_page ("main") as Pomodoro.PreferencesMainPage;
            main_page.timer_listbox.row_activated.connect (this.on_row_activated);
            main_page.notifications_listbox.row_activated.connect (this.on_row_activated);

            row = this.create_row (_("Ticking sound"), "ticking-sound", "ticking-sound");
            main_page.lisboxrow_sizegroup.add_widget (row);
            main_page.timer_listbox.insert (row, -1);
            this.rows.prepend (row);

            row = this.create_row (_("Start of break sound"), "start-of-break-sound", "pomodoro-end-sound");
            main_page.lisboxrow_sizegroup.add_widget (row);
            main_page.notifications_listbox.insert (row, -1);
            this.rows.prepend (row);

            row = this.create_row (_("End of break sound"), "end-of-break-sound", "pomodoro-start-sound");
            main_page.lisboxrow_sizegroup.add_widget (row);
            main_page.notifications_listbox.insert (row, -1);
            this.rows.prepend (row);
        }

        private void on_row_activated (Gtk.ListBox    listbox,
                                       Gtk.ListBoxRow row)
        {
            switch (row.name)
            {
                case "ticking-sound":
                    this.dialog.set_page ("ticking-sound");
                    break;

                case "start-of-break-sound":
                    this.dialog.set_page ("start-of-break-sound");
                    break;

                case "end-of-break-sound":
                    this.dialog.set_page ("end-of-break-sound");
                    break;
            }
        }
    }

    public class ApplicationExtension : Peas.ExtensionBase, Pomodoro.ApplicationExtension
    {
        public static unowned ApplicationExtension instance;

        public SoundPlayer ticking_sound { get; private set; }
        public SoundPlayer pomodoro_start_sound { get; private set; }
        public SoundPlayer pomodoro_end_sound { get; private set; }

        private Pomodoro.Timer timer;
        private GLib.Settings  settings;
        private uint           fade_out_timeout_id;

        construct
        {
            unowned string[] args_unowned = null;

            ApplicationExtension.instance = this;

            Gst.init (ref args_unowned);

            this.timer = Pomodoro.Timer.get_default ();

            this.settings = Pomodoro.get_settings ().get_child ("preferences");

            this.setup_ticking_sound ();
            this.setup_pomodoro_end_sound ();
            this.setup_pomodoro_start_sound ();

            this.timer.state_changed.connect_after (this.on_timer_state_changed);
            this.timer.notify["is-paused"].connect (this.on_timer_is_paused_notify);
            this.timer.notify["state-duration"].connect (this.on_timer_state_duration_notify);

            this.update_ticking_sound ();
        }

        ~ApplicationExtension ()
        {
            this.timer.state_changed.disconnect (this.on_timer_state_changed);
        }

        /**
         * A settings getter for file.
         *
         * In settings file is represented as uri, in app as GLib.File.
         */
        private static bool settings_file_getter (GLib.Value   value,
                                                  GLib.Variant variant,
                                                  void*        user_data)
        {
            var uri = variant.get_string ();

            if (uri != "") {
                value.set_object (GLib.File.new_for_uri (uri));
            }
            else {
                value.reset ();
            }

            return true;
        }

        /**
         * A settings setter for file.
         *
         * In settings file is represented as uri, in app as GLib.File.
         */
        [CCode (has_target = false)]
        private static GLib.Variant settings_file_setter (GLib.Value       value,
                                                          GLib.VariantType expected_type,
                                                          void*            user_data)
        {
            var file = value.get_object () as GLib.File;

            return new GLib.Variant.string (file != null ? file.get_uri () : "");
        }

        private void setup_ticking_sound ()
        {
            try {
                var player = new SoundsPlugin.GStreamerPlayer ();
                player.repeat = true;

                this.ticking_sound = new SoundPlayerProxy (player);

                this.settings.bind_with_mapping ("ticking-sound",
                                                 player,
                                                 "file",
                                                 GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET,
                                                 (GLib.SettingsBindGetMappingShared) settings_file_getter,
                                                 (GLib.SettingsBindSetMappingShared) settings_file_setter,
                                                 null,
                                                 null);
                this.settings.bind ("ticking-sound-volume",
                                    player,
                                    "volume",
                                    GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET);
            }
            catch (SoundsPlugin.SoundPlayerError error) {
                GLib.critical ("Failed to setup player for \"timer-ticking\" sound");
            }
        }

        private void setup_pomodoro_end_sound ()
        {
            try {
                this.pomodoro_end_sound = new SoundsPlugin.CanberraPlayer ();

                this.settings.bind_with_mapping ("pomodoro-end-sound",
                                                 this.pomodoro_end_sound,
                                                 "file",
                                                 GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET,
                                                 (GLib.SettingsBindGetMappingShared) settings_file_getter,
                                                 (GLib.SettingsBindSetMappingShared) settings_file_setter,
                                                 null,
                                                 null);

                this.settings.bind ("pomodoro-end-sound-volume",
                                    this.pomodoro_end_sound,
                                    "volume",
                                    GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET);
            }
            catch (SoundsPlugin.SoundPlayerError error) {
                GLib.critical ("Failed to setup player for \"pomodoro-end\" sound");
            }
        }

        private void setup_pomodoro_start_sound ()
        {
            try {
                this.pomodoro_start_sound = new SoundsPlugin.CanberraPlayer ();

                this.settings.bind_with_mapping ("pomodoro-start-sound",
                                                 this.pomodoro_start_sound,
                                                 "file",
                                                 GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET,
                                                 (GLib.SettingsBindGetMappingShared) settings_file_getter,
                                                 (GLib.SettingsBindSetMappingShared) settings_file_setter,
                                                 null,
                                                 null);

                this.settings.bind ("pomodoro-start-sound-volume",
                                    this.pomodoro_start_sound,
                                    "volume",
                                    GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET);
            }
            catch (SoundsPlugin.SoundPlayerError error) {
                GLib.critical ("Failed to setup player for \"pomodoro-start\" sound");
            }
        }

        private void unschedule_fade_out ()
        {
            if (this.fade_out_timeout_id != 0) {
                GLib.Source.remove (this.fade_out_timeout_id);
                this.fade_out_timeout_id = 0;
            }
        }

        private bool on_fade_out_timeout ()
                     requires (this.timer != null)
        {
            this.fade_out_timeout_id = 0;

            var fade_duration = (uint)(this.timer.state.duration - this.timer.elapsed) * 1000;

            (this.ticking_sound as Fadeable).fade_out (fade_duration.clamp (FADE_OUT_MIN_TIME,
                                                                            FADE_OUT_MAX_TIME));

            return false;
        }

        /**
         * Manage fade-in and fade-out within current state.
         */
        private void schedule_fade_out ()
                     requires (this.timer != null)
        {
            this.unschedule_fade_out ();

            var remaining_time = (uint)(this.timer.state.duration - this.timer.elapsed) * 1000;

            if (remaining_time > FADE_OUT_MAX_TIME) {
                (this.ticking_sound as Fadeable).fade_in (FADE_IN_TIME);

                this.fade_out_timeout_id = GLib.Timeout.add (remaining_time - FADE_OUT_MAX_TIME,
                                                             this.on_fade_out_timeout);
            }
            else {
                this.on_fade_out_timeout ();
            }
        }

        private void update_ticking_sound ()
                     requires (this.timer != null)
        {
            if (this.timer.state is Pomodoro.PomodoroState && !this.timer.is_paused) {
                this.schedule_fade_out ();
            }
            else {
                this.unschedule_fade_out ();

                (this.ticking_sound as Fadeable).fade_out (FADE_OUT_MIN_TIME);
            }
        }

        private void on_timer_state_duration_notify ()
        {
            this.update_ticking_sound ();
        }

        private void on_timer_is_paused_notify ()
        {
            this.update_ticking_sound ();
        }

        private void on_timer_state_changed (Pomodoro.TimerState state,
                                             Pomodoro.TimerState previous_state)
        {
            this.update_ticking_sound ();

            if (previous_state.elapsed >= previous_state.duration)
            {
                if (state is Pomodoro.PomodoroState &&
                    previous_state is Pomodoro.BreakState)
                {
                    this.pomodoro_start_sound.play ();
                }

                if (state is Pomodoro.BreakState &&
                    previous_state is Pomodoro.PomodoroState)
                {
                    this.pomodoro_end_sound.play ();
                }
            }
        }
    }
}


[ModuleInit]
public void peas_register_types (GLib.TypeModule module)
{
    var object_module = module as Peas.ObjectModule;

    object_module.register_extension_type (typeof (Pomodoro.ApplicationExtension),
                                           typeof (SoundsPlugin.ApplicationExtension));

    object_module.register_extension_type (typeof (Pomodoro.PreferencesDialogExtension),
                                           typeof (SoundsPlugin.PreferencesDialogExtension));
}

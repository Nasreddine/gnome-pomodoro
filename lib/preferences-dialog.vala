/*
 * Copyright (c) 2013,2014 gnome-pomodoro contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 *
 */

using GLib;


namespace Pomodoro
{
    const double TIMER_SCALE_LOWER = 60.0;
    const double TIMER_SCALE_UPPER = 60.0 * 120.0;

    const double LONG_BREAK_INTERVAL_LOWER = 1.0;
    const double LONG_BREAK_INTERVAL_UPPER = 10.0;

    private const GLib.SettingsBindFlags SETTINGS_BIND_FLAGS =
                                       GLib.SettingsBindFlags.DEFAULT |
                                       GLib.SettingsBindFlags.GET |
                                       GLib.SettingsBindFlags.SET;

    /**
     * Mapping from settings to accelerator
     */
    private bool get_accelerator_mapping (GLib.Value   value,
                                          GLib.Variant variant,
                                          void*        user_data)
    {
        var accelerators = variant.get_strv ();

        foreach (var accelerator in accelerators)
        {
            value.set_string (accelerator);

            return true;
        }

        value.set_string ("");

        return true;
    }

    /**
     * Mapping from accelerator to settings
     */
    [CCode (has_target = false)]
    private GLib.Variant set_accelerator_mapping (GLib.Value       value,
                                                  GLib.VariantType expected_type,
                                                  void*            user_data)
    {
        var accelerator_name = value.get_string ();

        if (accelerator_name == "")
        {
            string[] strv = {};

            return new GLib.Variant.strv (strv);
        }
        else {
            string[] strv = { accelerator_name };

            return new GLib.Variant.strv (strv);
        }
    }

    /**
     * Mapping from settings to presence combobox
     */
    private static bool get_presence_status_mapping (GLib.Value   value,
                                                     GLib.Variant variant,
                                                     void*        user_data)
    {
        var status = string_to_presence_status (variant.get_string ());

        value.set_int ((int) status);

        //if (variant.is_of_type (GLib.VariantType.STRING))
        //{
        //    value.set_string (get_presence_status_label (status));
        //}
        //else {
        //    value.set_int ((int) status);
        //}

        return true;
    }

    /**
     * Mapping from settings to presence combobox
     */
    private static bool get_presence_status_label_mapping (GLib.Value   value,
                                                           GLib.Variant variant,
                                                           void*        user_data)
    {
        var status = string_to_presence_status (variant.get_string ());

        value.set_string (get_presence_status_label (status));

        return true;
    }

    /**
     * Mapping from presence combobox to settings
     */
    [CCode (has_target = false)]
    private static GLib.Variant set_presence_status_mapping (GLib.Value       value,
                                                             GLib.VariantType expected_type,
                                                             void*            user_data)
    {
        var status = (Pomodoro.PresenceStatus) value.get_int ();

        return new GLib.Variant.string (presence_status_to_string (status));
    }

    private string? get_presence_status_label (Pomodoro.PresenceStatus status)
    {
        switch (status)
        {
            case PresenceStatus.AVAILABLE:
                return _("Available");

            case PresenceStatus.BUSY:
                return _("Busy");

            case PresenceStatus.INVISIBLE:
                return _("Invisible");

            // case PresenceStatus.AWAY:
            //     return _("Away");

            case PresenceStatus.IDLE:
                return _("Idle");
        }

        return null;
    }

    [CCode (has_target = false)]
    private static Variant dummy_setter (GLib.Value       value,
                                         GLib.VariantType expected_type,
                                         void*            user_data)
    {
        return new Variant.string ("");
    }

    private static void list_box_separator_func (Gtk.ListBoxRow  row,
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

    public interface PreferencesDialogExtension : Peas.ExtensionBase
    {
    }

    public interface PreferencesPage : Gtk.Widget
    {
        public unowned Pomodoro.PreferencesDialog get_preferences_dialog ()
        {
            return this.get_toplevel () as Pomodoro.PreferencesDialog;
        }

        public virtual void configure_header_bar (Gtk.HeaderBar header_bar)
        {
        }
    }

    [GtkTemplate (ui = "/org/gnome/pomodoro/ui/preferences-keyboard-shortcut-page.ui")]
    public class PreferencesKeyboardShortcutPage : Gtk.Box, Gtk.Buildable, Pomodoro.PreferencesPage
    {
        private Pomodoro.Accelerator accelerator { get; set; }

        [GtkChild]
        private Gtk.Box preview_box;
        [GtkChild]
        private Gtk.Button disable_button;
        [GtkChild]
        private Gtk.Label error_label;

        private GLib.Settings settings;
        private ulong key_press_event_id = 0;
        private ulong key_release_event_id = 0;
        private ulong focus_out_event_id = 0;

        construct
        {
            this.accelerator = new Pomodoro.Accelerator ();
            this.accelerator.changed.connect (this.on_accelerator_changed);

            this.settings = Pomodoro.get_settings ()
                                    .get_child ("preferences");
            this.settings.delay ();

            this.settings.bind_with_mapping ("toggle-timer-key",
                                             this.accelerator,
                                             "name",
                                             SETTINGS_BIND_FLAGS,
                                             (GLib.SettingsBindGetMappingShared) get_accelerator_mapping,
                                             (GLib.SettingsBindSetMappingShared) set_accelerator_mapping,
                                             null,
                                             null);
            this.on_accelerator_changed ();
        }

        private bool validate_accelerator ()
        {
            var is_valid = false;

            try {
                this.accelerator.validate ();

                this.error_label.hide ();

                is_valid = true;
            }
            catch (Pomodoro.AcceleratorError error)
            {
                if (error is Pomodoro.AcceleratorError.TYPING_COLLISION)
                {
                    this.error_label.label = _("Using \"%s\" as shortcut will interfere with typing. Try adding another key, such as Control, Alt or Shift.").printf (this.accelerator.display_name);
                    this.error_label.show ();
                }
            }

            return is_valid;
        }

        private void update_preview ()
        {
            var index = 0;

            this.preview_box.forall ((child) => {
                child.destroy ();
            });

            foreach (var element in this.accelerator.get_keys ())
            {
                if (index > 0) {
                    this.preview_box.pack_start (new Gtk.Label ("+"),
                                                 false,
                                                 false, 
                                                 0);
                }

                var key_label = new Gtk.Label (element);
                key_label.valign = Gtk.Align.CENTER;
                key_label.get_style_context ().add_class ("key");

                this.preview_box.pack_start (key_label, false, false, 0);

                index++;
            }

            this.disable_button.sensitive = index > 0;

            this.preview_box.show_all ();
        }

        [GtkCallback]
        private void on_disable_clicked ()
        {
            this.accelerator.unset ();

            this.settings.apply ();
        }

        private void on_accelerator_changed ()
        {
            this.validate_accelerator ();
            this.update_preview ();
        }

        private bool on_key_press_event (Gdk.EventKey event)
        {
            switch (event.keyval)
            {
                case Gdk.Key.Tab:
                case Gdk.Key.space:
                case Gdk.Key.Return:
                    return base.key_press_event (event);

                case Gdk.Key.BackSpace:
                    if (!this.settings.has_unapplied) {
                        this.on_disable_clicked ();
                    }

                    return true;

                case Gdk.Key.Escape:
                    this.get_action_group ("win").activate_action ("back", null);

                    return true;
            }

            this.accelerator.set_keyval (event.keyval,
                                         event.state);

            return true;
        }

        private bool on_key_release_event (Gdk.EventKey event)
        {
            switch (event.keyval)
            {
                case Gdk.Key.Tab:
                case Gdk.Key.space:
                case Gdk.Key.Return:
                case Gdk.Key.BackSpace:
                    return true;
            }

            if (event.state == 0 || event.length == 0)
            {
                try {
                    this.accelerator.validate ();

                    this.settings.apply ();
                }
                catch (Pomodoro.AcceleratorError error)
                {
                    this.settings.revert ();
                }
            }

            return true;
        }

        private bool on_focus_out_event (Gdk.EventFocus event)
        {
            if (!this.visible) {
                return false;
            }

            this.settings.revert ();

            return true;
        }

        public override void map ()
        {
            base.map ();

            var toplevel = this.get_toplevel ();

            if (this.key_press_event_id == 0) {
                this.key_press_event_id = toplevel.key_press_event.connect (this.on_key_press_event);
            }

            if (this.key_release_event_id == 0) {
                this.key_release_event_id = toplevel.key_release_event.connect (this.on_key_release_event);
            }

            if (this.focus_out_event_id == 0) {
                this.focus_out_event_id = toplevel.focus_out_event.connect (this.on_focus_out_event);
            }
        }

        public override void unmap ()
        {
            base.unmap ();

            var toplevel = this.get_toplevel ();

            if (this.key_press_event_id != 0) {
                toplevel.key_press_event.disconnect (this.on_key_press_event);
                this.key_press_event_id = 0;
            }

            if (this.key_release_event_id != 0) {
                toplevel.key_release_event.disconnect (this.on_key_release_event);
                this.key_release_event_id = 0;
            }

            if (this.focus_out_event_id != 0) {
                toplevel.focus_out_event.disconnect (this.on_focus_out_event);
                this.focus_out_event_id != 0;
            }
        }
    }

    [GtkTemplate (ui = "/org/gnome/pomodoro/ui/preferences-presence-page.ui")]
    public abstract class PreferencesPresencePage : Gtk.ScrolledWindow, Gtk.Buildable, Pomodoro.PreferencesPage
    {
        /* TODO
        private Pomodoro.PreferencesSection section;

        construct
        {
            this.section = new Pomodoro.PreferencesSection (_("General"));
            this.section.show_all ();

            this.populate ();
        }

        private void populate ()
        {
            var empathy_section = new Pomodoro.PreferencesSection (_("Empathy"),
                                                                   new Gtk.Switch ());
            empathy_section.show_all ();

            var skype_section = new Pomodoro.PreferencesSection (_("Skype"),
                                                                 new Gtk.Switch ());
            skype_section.show_all ();

            this.box.pack_start (this.section);
            this.box.pack_start (empathy_section);
            this.box.pack_start (skype_section);
        }
        */
    }

    public class PreferencesPomodoroPresencePage : PreferencesPresencePage
    {
    }

    public class PreferencesBreakPresencePage : PreferencesPresencePage
    {
    }

    [GtkTemplate (ui = "/org/gnome/pomodoro/ui/preferences-plugins-page.ui")]
    public class PreferencesPluginsPage : Gtk.ScrolledWindow, Gtk.Buildable, Pomodoro.PreferencesPage
    {
        [GtkChild]
        private Gtk.ListBox plugins_listbox;

        private Peas.Engine engine;

        construct
        {
            this.engine = Peas.Engine.get_default ();

            this.plugins_listbox.set_header_func (Pomodoro.list_box_separator_func);

            this.populate ();
        }

        private Gtk.ListBoxRow create_row (Peas.PluginInfo plugin_info)
        {
            var name_label = new Gtk.Label (plugin_info.get_name ());
            name_label.get_style_context ().add_class ("pomodoro-plugin-name");
            name_label.halign = Gtk.Align.START;

            var description_label = new Gtk.Label (plugin_info.get_description ());
            description_label.get_style_context ().add_class ("dim-label");
            description_label.get_style_context ().add_class ("pomodoro-plugin-description");
            description_label.halign = Gtk.Align.START;

            var toggle = new Gtk.Switch ();
            toggle.valign = Gtk.Align.CENTER;
            toggle.active = plugin_info.is_loaded ();
            toggle.notify["active"].connect_after (() => {
                var is_loaded = false;

                if (toggle.active) {
                    is_loaded = this.engine.try_load_plugin (plugin_info);
                }
                else {
                    is_loaded = !this.engine.try_unload_plugin (plugin_info);
                }

                if (toggle.active != is_loaded) {
                    toggle.freeze_notify ();
                    toggle.active = is_loaded;
                    toggle.thaw_notify ();
                }
            });

            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            vbox.pack_start (name_label, false, false, 0);
            vbox.pack_start (description_label, false, false, 0);

            var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 30);
            hbox.pack_start (vbox, true, true, 0);
            hbox.pack_start (toggle, false, true, 0);

            var row = new Gtk.ListBoxRow ();
            row.activatable = false;
            row.add (hbox);
            row.show_all ();

            return row;
        }

        private void populate ()
        {
            foreach (var plugin_info in this.engine.get_plugin_list ())
            {
                if (plugin_info.is_hidden ()) {
                    continue;
                }

                var row = this.create_row (plugin_info);

                this.plugins_listbox.insert (row, -1);
            }
        }
    }

    [GtkTemplate (ui = "/org/gnome/pomodoro/ui/preferences-main-page.ui")]
    public class PreferencesMainPage : Gtk.ScrolledWindow, Gtk.Buildable, Pomodoro.PreferencesPage
    {
        [GtkChild]
        public Gtk.Box box;
        [GtkChild]
        public Gtk.ListBox timer_listbox;
        [GtkChild]
        public Gtk.ListBox notifications_listbox;
        [GtkChild]
        public Gtk.ListBox other_listbox;
        [GtkChild]
        public Gtk.SizeGroup lisboxrow_sizegroup;

        private GLib.Settings settings;
        private Pomodoro.Accelerator accelerator;

        construct
        {
            this.timer_listbox.set_header_func (Pomodoro.list_box_separator_func);
            this.notifications_listbox.set_header_func (Pomodoro.list_box_separator_func);
            this.other_listbox.set_header_func (Pomodoro.list_box_separator_func);
        }

        private unowned Widgets.LogScale setup_time_scale (Gtk.Builder builder,
                                                           string      grid_name,
                                                           string      label_name)
        {
            var adjustment = new Gtk.Adjustment (0.0,
                                                 TIMER_SCALE_LOWER,
                                                 TIMER_SCALE_UPPER,
                                                 60.0,
                                                 300.0,
                                                 0.0);

            var scale = new Widgets.LogScale (adjustment, 2.0);
            scale.show ();

            var grid = builder.get_object (grid_name) as Gtk.Grid;
            grid.attach (scale, 0, 1, 2, 1);

            var label = builder.get_object (label_name) as Gtk.Label;
            adjustment.value_changed.connect (() => {
                label.set_text (format_time ((long) adjustment.value));
            });

            adjustment.value_changed ();

            unowned Widgets.LogScale unowned_scale = scale;

            return unowned_scale;
        }

        private void setup_timer_section (Gtk.Builder builder)
        {
            var pomodoro_scale = this.setup_time_scale (builder,
                                                        "pomodoro_grid",
                                                        "pomodoro_label");
            var short_break_scale = this.setup_time_scale (builder,
                                                           "short_break_grid",
                                                           "short_break_label");
            var long_break_scale = this.setup_time_scale (builder,
                                                          "long_break_grid",
                                                          "long_break_label");
            var long_break_interval_spinbutton = builder.get_object ("long_break_interval_spinbutton")
                                                                     as Gtk.SpinButton;
            var accelerator_label = builder.get_object ("accelerator_label")
                                                        as Gtk.Label;
            var ticking_sound_label = builder.get_object ("ticking_sound_label")
                                                          as Gtk.Label;

            this.settings.bind ("pomodoro-duration",
                                pomodoro_scale.base_adjustment,
                                "value",
                                SETTINGS_BIND_FLAGS);
            this.settings.bind ("short-break-duration",
                                short_break_scale.base_adjustment,
                                "value",
                                SETTINGS_BIND_FLAGS);
            this.settings.bind ("long-break-duration",
                                long_break_scale.base_adjustment,
                                "value",
                                SETTINGS_BIND_FLAGS);
            this.settings.bind ("long-break-interval",
                                long_break_interval_spinbutton.adjustment,
                                "value",
                                SETTINGS_BIND_FLAGS);

            this.accelerator = new Pomodoro.Accelerator ();
            this.accelerator.changed.connect(() => {
                if (this.accelerator.display_name != "") {
                    accelerator_label.label = this.accelerator.display_name;
                }
                else {
                    accelerator_label.label = _("Off");
                }
            });
            this.settings.bind_with_mapping ("toggle-timer-key",
                                             this.accelerator,
                                             "name",
                                             SETTINGS_BIND_FLAGS,
                                             (GLib.SettingsBindGetMappingShared) get_accelerator_mapping,
                                             (GLib.SettingsBindSetMappingShared) set_accelerator_mapping,
                                             null,
                                             null);
        }

        private void setup_notifications_section (Gtk.Builder builder)
        {
            var screen_notifications_toggle = builder.get_object ("screen_notifications_toggle")
                                              as Gtk.Switch;

            var reminders_toggle = builder.get_object ("reminders_toggle") as Gtk.Switch;

            var pomodoro_end_sound_label = builder.get_object ("pomodoro_end_sound_label")
                                                               as Gtk.Label;
            var pomodoro_start_sound_label = builder.get_object ("pomodoro_start_sound_label")
                                                                 as Gtk.Label;

            this.settings.bind ("show-screen-notifications",
                                screen_notifications_toggle,
                                "active",
                                SETTINGS_BIND_FLAGS);

            this.settings.bind ("show-reminders",
                                reminders_toggle,
                                "active",
                                SETTINGS_BIND_FLAGS);
        }

        private void setup_other_section (Gtk.Builder builder)
        {
            var pomodoro_presence_label = builder.get_object ("pomodoro_presence_label")
                                                              as Gtk.Label;
            var break_presence_label = builder.get_object ("break_presence_label")
                                                           as Gtk.Label;

            this.settings.bind_with_mapping ("presence-during-pomodoro",
                                             pomodoro_presence_label,
                                             "label",
                                             GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET,
                                             (GLib.SettingsBindGetMappingShared) get_presence_status_label_mapping,
                                             (GLib.SettingsBindSetMappingShared) dummy_setter,
                                             null,
                                             null);

            this.settings.bind_with_mapping ("presence-during-break",
                                             break_presence_label,
                                             "label",
                                             GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET,
                                             (GLib.SettingsBindGetMappingShared) get_presence_status_label_mapping,
                                             (GLib.SettingsBindSetMappingShared) dummy_setter,
                                             null,
                                             null);
        }

        private void parser_finished (Gtk.Builder builder)
        {
            this.settings = Pomodoro.get_settings ()
                                    .get_child ("preferences");

            base.parser_finished (builder);

            this.setup_timer_section (builder);
            this.setup_notifications_section (builder);
            this.setup_other_section (builder);
        }

        [GtkCallback]
        private void on_row_activated (Gtk.ListBox    listbox,
                                       Gtk.ListBoxRow row)
        {
            var preferences_dialog = this.get_preferences_dialog ();

            switch (row.name)
            {
                case "keyboard-shortcut":
                    preferences_dialog.set_page ("keyboard-shortcut");
                    break;

                case "pomodoro-presence-status":
                    preferences_dialog.set_page ("presence-pomodoro");
                    break;

                case "break-presence-status":
                    preferences_dialog.set_page ("presence-break");
                    break;

                case "plugins":
                    preferences_dialog.set_page ("plugins");
                    break;

                default:
                    break;
            }
        }
    }

    [GtkTemplate (ui = "/org/gnome/pomodoro/ui/preferences.ui")]
    public class PreferencesDialog : Gtk.ApplicationWindow, Gtk.Buildable
    {
        private static const int FIXED_WIDTH = 600;
        private static const int FIXED_HEIGHT = 720;

        private static unowned Pomodoro.PreferencesDialog instance;

        private static const GLib.ActionEntry[] action_entries = {
            { "back", on_back_activate }
        };

        [GtkChild]
        private Gtk.HeaderBar header_bar;
        [GtkChild]
        private Gtk.Stack stack;
        [GtkChild]
        private Gtk.Button back_button;

        private GLib.HashTable<string, PageMeta?> pages;
        private GLib.List<string>                 history;
        private Peas.ExtensionSet                 extensions;

        private struct PageMeta
        {
            GLib.Type type;
            string    name;
            string    title;
        }

        construct
        {
            PreferencesDialog.instance = this;

            var geometry = Gdk.Geometry () {
                min_width = FIXED_WIDTH,
                max_width = FIXED_WIDTH,
                min_height = 300,
                max_height = 1500
            };
            var geometry_hints = Gdk.WindowHints.MAX_SIZE |
                                 Gdk.WindowHints.MIN_SIZE;
            this.set_geometry_hints (this,
                                     geometry,
                                     geometry_hints);

            this.pages = new GLib.HashTable<string, PageMeta?> (str_hash, str_equal);

            this.add_page ("main",
                           _("Preferences"),
                           typeof (Pomodoro.PreferencesMainPage));

            this.add_page ("plugins",
                          _("Plugins"),
                          typeof (Pomodoro.PreferencesPluginsPage));

            this.add_page ("keyboard-shortcut",
                          _("Keyboard Shortcut"),
                          typeof (Pomodoro.PreferencesKeyboardShortcutPage));

            this.add_page ("presence-pomodoro",
                           _("Presence During Pomodoro"),
                           typeof (Pomodoro.PreferencesPomodoroPresencePage));

            this.add_page ("presence-break",
                           _("Presence During Break"),
                           typeof (Pomodoro.PreferencesBreakPresencePage));

            this.add_action_entries (PreferencesDialog.action_entries, this);

            this.history_clear ();

            this.set_page ("main");

            /* let page be modified by extensions */
            this.extensions = new Peas.ExtensionSet (Peas.Engine.get_default (),
                                                     typeof (Pomodoro.PreferencesDialogExtension));

            this.stack.notify["visible-child"].connect (this.on_visible_child_notify);

            this.on_visible_child_notify ();
        }

        ~PreferencesDialog ()
        {
            PreferencesDialog.instance = this;
        }

        public static PreferencesDialog? get_default ()
        {
            return PreferencesDialog.instance;
        }

        public void parser_finished (Gtk.Builder builder)
        {
            base.parser_finished (builder);
        }

        public virtual signal void page_changed (Pomodoro.PreferencesPage page)
        {
            string name;
            string title;

            this.stack.child_get (page,
                                  "name", out name,
                                  "title", out title);
            this.history_push (name);

            this.header_bar.title = title;
            this.back_button.visible = this.history.length () > 1;

            this.header_bar.forall (
                (child) => {
                    if (child != this.back_button) {
                        this.header_bar.remove (child);
                    }
                });

            page.configure_header_bar (this.header_bar);
        }

        private void on_visible_child_notify ()
        {
            var page_height = 0;
            var header_bar_height = 0;

            var page = this.stack.visible_child as Pomodoro.PreferencesPage;

            this.page_changed (page);

            /* calculate window size */
            this.header_bar.get_preferred_height (null,
                                                  out header_bar_height);

            page.get_preferred_height_for_width (FIXED_WIDTH,
                                                 null,
                                                 out page_height);

            if (page is Gtk.ScrolledWindow) {
                var scrolled_window = page as Gtk.ScrolledWindow;
                scrolled_window.set_min_content_height (int.min (page_height, FIXED_HEIGHT));

                this.resize (FIXED_WIDTH, header_bar_height + FIXED_HEIGHT);
            }
            else {
                this.resize (FIXED_WIDTH, header_bar_height + page_height);
            }
        }

        private void on_back_activate (GLib.SimpleAction action,
                                       GLib.Variant?     parameter)
        {
            this.history_pop ();
        }

        public unowned Pomodoro.PreferencesPage? get_page (string name)
        {
            var page_widget = this.stack.get_child_by_name (name);

            if (page_widget != null) {
                return page_widget as Pomodoro.PreferencesPage;
            }

            if (this.pages.contains (name)) {
                var meta = this.pages.lookup (name);
                var page = Object.new (meta.type) as Pomodoro.PreferencesPage;

                this.stack.add_titled (page as Gtk.Widget,
                                       meta.name,
                                       meta.title);

                return page as Pomodoro.PreferencesPage;
            }

            return null;
        }

        private void history_clear ()
        {
            this.history = new GLib.List<string> ();
        }

        private void history_push (string name)
        {
            if (name == "main") {
                this.history_clear ();
            }
            else {
                unowned GLib.List<string> last = this.history.last ();
                string? last_name = null;

                /* ignore if last element is the same */
                if (last != null && last.data == name) {
                    return;
                }

                /* go back if previous element is the same */
                if (last != null && last.prev != null && last.prev.data == name) {
                    this.history_pop ();

                    return;
                }
            }

            this.history.append (name);
        }

        private string? history_pop ()
        {
            unowned GLib.List<string> last = this.history.last ();

            string? last_name = null;
            string  next_name = "main";

            if (last != null) {
                last_name = last.data.dup ();

                this.history.delete_link (last);
                last = this.history.last ();
            }

            if (last != null) {
                next_name = last.data.dup ();
            }

            this.set_page (next_name);

            return last_name;
        }

        public void add_page (string    name,
                              string    title,
                              GLib.Type type)
                    requires (type.is_a (typeof (Pomodoro.PreferencesPage)))
        {
            var meta = PageMeta () {
                name = name,
                title = title,
                type = type
            };

            this.pages.insert (name, meta);
        }

        public void remove_page (string name)
        {
            var child = this.stack.get_child_by_name (name);

            if (this.stack.get_visible_child_name () == name) {
                this.set_page ("main");
            }

            if (child != null) {
                this.stack.remove (child);
            }

            this.pages.remove (name);
        }

        public void set_page (string name)
        {
            var page = this.get_page (name);

            if (page != null) {
                this.stack.set_visible_child_name (name);
            }
            else {
                GLib.warning ("Could not change page to \"%s\"", name);
            }
        }
    }
}

namespace SoundsPlugin
{
    public errordomain SoundPlayerError
    {
        FAILED_TO_INITIALIZE
    }

    /**
     * Preset sounds are defined relative to data directory,
     * and used URIs are not particulary valid.
     */
    private string get_absolute_uri (string uri)
    {
        var scheme = GLib.Uri.parse_scheme (uri);

        if (scheme == null && uri != "")
        {
            var path = Path.build_filename (Config.PACKAGE_DATA_DIR,
                                            "sounds",
                                            uri);
            return GLib.Filename.to_uri (path);
        }

        return uri;
    }

    public interface SoundPlayer : GLib.Object
    {
        public abstract GLib.File? file { get; set; }

        public abstract double volume { get; set; }

        public abstract void play ();

        public abstract void stop ();

        public virtual string[] get_supported_mime_types ()
        {
            string[] mime_types = {
                "audio/*"
            };

            return mime_types;
        }
    }

    private interface Fadeable
    {
        public abstract void fade_in (uint duration);

        public abstract void fade_out (uint duration);
    }

    private class GStreamerPlayer : GLib.Object, SoundPlayer, Fadeable
    { 
        public GLib.File? file {
            get {
                return this._file;
            }
            set {
                this._file = value;

                var uri = get_absolute_uri (this._file != null ? this._file.get_uri () : "");

                if (uri == "") {
                    this.stop ();
                }
                else {
                    Gst.State state;
                    Gst.State pending_state;

                    this.pipeline.get_state (out state,
                                             out pending_state,
                                             Gst.CLOCK_TIME_NONE);

                    if (pending_state != Gst.State.VOID_PENDING) {
                        state = pending_state;
                    }

                    if (state == Gst.State.PLAYING || 
                        state == Gst.State.PAUSED)
                    {
                        this.is_about_to_finish = false;

                        this.pipeline.set_state (Gst.State.READY);
                        this.pipeline.uri = uri;
                        this.pipeline.set_state (state);
                    }
                }
            }
        }

        public double volume {
            get {
                return this.pipeline.volume;
            }
            set {
                this.pipeline.volume = value.clamp (0.0, 1.0);
            }
            default = 1.0;
        }

        public double volume_fade {
            get {
                return this.volume_filter.volume;
            }
            set {
                this.volume_filter.volume = value.clamp (0.0, 1.0);
            }
            default = 0.0;
        }

        public bool repeat { get; set; default = false; }

        private GLib.File _file;
        private dynamic Gst.Element pipeline;
        private dynamic Gst.Element volume_filter;
        private Pomodoro.Animation volume_animation;
        private bool is_about_to_finish = false;

        [Flags]
        private enum GstPlayFlags {
            VIDEO             = 0x00000001,
            AUDIO             = 0x00000002,
            TEXT              = 0x00000004,
            VIS               = 0x00000008,
            SOFT_VOLUME       = 0x00000010,
            NATIVE_AUDIO      = 0x00000020,
            NATIVE_VIDEO      = 0x00000040,
            DOWNLOAD          = 0x00000080,
            BUFFERING         = 0x00000100,
            DEINTERLACE       = 0x00000200,
            SOFT_COLORBALANCE = 0x00000400,
            FORCE_FILTERS     = 0x00000800
        }

        private const uint FADE_FRAMES_PER_SECOND = 20;

        public GStreamerPlayer () throws SoundPlayerError
        {
            dynamic Gst.Element pipeline = Gst.ElementFactory.make ("playbin", "player");
            dynamic Gst.Element volume_filter = Gst.ElementFactory.make ("volume", "volume");

            if (pipeline == null) {
                throw new SoundPlayerError.FAILED_TO_INITIALIZE ("Failed to initialize \"playbin\" element");
            }

            if (volume_filter == null) {
                throw new SoundPlayerError.FAILED_TO_INITIALIZE ("Failed to initialize \"volume\" element");
            }

            pipeline.flags = GstPlayFlags.AUDIO;
            pipeline.audio_filter = volume_filter;
            pipeline.about_to_finish.connect (this.on_about_to_finish);
            pipeline.get_bus ().add_watch (GLib.Priority.DEFAULT,
                                           this.on_bus_callback);

            pipeline.volume = 1.0;
            volume_filter.volume = 0.0;

            this.volume_filter = volume_filter;
            this.pipeline = pipeline;
        }

        ~GStreamerPlayer ()
        {
            if (this.pipeline != null) {
                this.pipeline.set_state (Gst.State.NULL);
            }
        }

        public void play ()
                    requires (this.pipeline != null)
        {
            this.fade_in (0);
        }

        public void stop ()
                    requires (this.pipeline != null)
        {
            this.fade_out (0);
        }

        public void fade_in (uint duration)
        {
            if (this.volume_animation != null) {
                this.volume_animation.stop ();
                this.volume_animation = null;
            }

            if (duration > 0) {
                this.volume_animation = new Pomodoro.Animation (Pomodoro.AnimationMode.EASE_OUT,
                                                                duration,
                                                                FADE_FRAMES_PER_SECOND);
                this.volume_animation.add_property (this,
                                                    "volume-fade",
                                                    1.0);
                this.volume_animation.start ();
            }
            else {
                this.volume_fade = 1.0;
            }

            var uri = get_absolute_uri (this.file != null ? this.file.get_uri () : "");

            if (uri != "") {
                this.pipeline.uri = uri;
                this.pipeline.set_state (Gst.State.PLAYING);
            }
        }

        public void fade_out (uint duration)
        {
            Gst.State state;
            Gst.State pending_state;

            if (this.volume_animation != null) {
                this.volume_animation.stop ();
                this.volume_animation = null;
            }

            this.pipeline.get_state (out state,
                                     out pending_state,
                                     Gst.CLOCK_TIME_NONE);

            if (pending_state != Gst.State.VOID_PENDING) {
                state = pending_state;
            }

            if (duration > 0 && state == Gst.State.PLAYING) {
                this.volume_animation = new Pomodoro.Animation (Pomodoro.AnimationMode.EASE_IN_OUT,
                                                                duration,
                                                                FADE_FRAMES_PER_SECOND);
                this.volume_animation.add_property (this,
                                                    "volume-fade",
                                                    0.0);
                this.volume_animation.complete.connect (() => {
                    this.stop ();
                });

                this.volume_animation.start ();
            }
            else {
                if (state != Gst.State.NULL && state != Gst.State.READY) {
                    this.pipeline.set_state (Gst.State.READY);
                }

                this.volume_fade = 0.0;
            }
        }

        private bool on_bus_callback (Gst.Bus     bus,
                                      Gst.Message message)
        {
            GLib.Error error;
            Gst.State state;
            Gst.State pending_state;

            this.pipeline.get_state (out state,
                                     out pending_state,
                                     Gst.CLOCK_TIME_NONE);

            switch (message.type)
            {
                case Gst.MessageType.EOS:
                    if (this.is_about_to_finish) {
                        this.is_about_to_finish = false;
                    }
                    else {
                        this.finished ();
                    }

                    if (pending_state != Gst.State.PLAYING) {
                        this.pipeline.set_state (Gst.State.READY);
                    }

                    break;

                case Gst.MessageType.ERROR:
                    if (this.is_about_to_finish) {
                        this.is_about_to_finish = false;
                    }

                    message.parse_error (out error, null);
                    GLib.critical (error.message);

                    this.pipeline.set_state (Gst.State.NULL);

                    this.finished ();
                    break;

                default:
                    break;
            }

            return true;
        }

        /**
         * Try emit "finished" signal before the end of stream.
         * If play gets called during then 
         */
        private void on_about_to_finish ()
        {
            this.is_about_to_finish = true;

            this.finished ();
        }

        public virtual signal void finished ()
        {
            string current_uri;

            if (this.repeat) {
                this.pipeline.get ("current-uri", out current_uri);

                if (current_uri != "") {
                    this.pipeline.set ("uri", current_uri);
                }
            }
        }
    }

    private class CanberraPlayer : GLib.Object, SoundPlayer
    {
        public GLib.File? file {
            get {
                return this._file;
            }
            set {
                this._file = value != null
                        ? File.new_for_uri (get_absolute_uri (value.get_uri ()))
                        : null;

                this.cache_file (this._file);
            }
        }

        public double volume { get; set; default = 1.0; }

        private GLib.File _file;
        private Canberra.Context context;
        private static uint next_event_id = 0;
        private string event_id;

        private static double amplitude_to_decibels (double amplitude)
        {
            return 20.0 * Math.log10 (amplitude);
        }

        public CanberraPlayer () throws SoundPlayerError
        {
            Canberra.Context context;

            this.event_id = "pomodoro-%u".printf (next_event_id++);

            /* Create context */
            var status = Canberra.Context.create (out context);
            var application = GLib.Application.get_default ();

            if (status != Canberra.SUCCESS) {
                throw new SoundPlayerError.FAILED_TO_INITIALIZE (
                        "Failed to initialize canberra context - %s".printf (Canberra.strerror (status)));
            }

            /* Set properties about application */
            status = context.change_props (
                    Canberra.PROP_APPLICATION_ID, application.application_id,
                    Canberra.PROP_APPLICATION_NAME, Config.PACKAGE_NAME,
                    Canberra.PROP_APPLICATION_ICON_NAME, Config.PACKAGE_NAME);

            if (status != Canberra.SUCCESS) {
                throw new SoundPlayerError.FAILED_TO_INITIALIZE (
                        "Failed to set context properties - %s".printf (Canberra.strerror (status)));
            }

            /* Connect to the sound system */
            status = context.open ();

            if (status != Canberra.SUCCESS) {
                throw new SoundPlayerError.FAILED_TO_INITIALIZE (
                        "Failed to open canberra context - %s".printf (Canberra.strerror (status)));
            }

            this.context = (owned) context;
        }

        ~CanberraPlayer ()
        {
            if (this.context != null) {
                this.stop ();
            }
        }

        private bool cache_file (GLib.File? file)
                     requires (this.context != null)
        {
            var file_path = file != null ? file.get_path () : null;

            if (file_path != null) {
                var status = this.context.cache
                            (Canberra.PROP_EVENT_ID, this.event_id,
                             Canberra.PROP_MEDIA_FILENAME, file_path);

                if (status == Canberra.SUCCESS) {
                    return true;
                }
                else {
                    GLib.warning ("Failed to cache file \"%s\": %s",
                                  file_path,
                                  Canberra.strerror (status));
                }
            }

            return false;
        }

        public void play ()
                    requires (this.context != null)
        {
            if (this.file != null && this.volume > 0.0)
            {
                if (this.context != null)
                {
                    Canberra.Proplist properties = null;

                    var status = Canberra.Proplist.create (out properties);
                    properties.sets (Canberra.PROP_EVENT_ID, this.event_id);
                    properties.sets (Canberra.PROP_MEDIA_FILENAME, this.file.get_path ());
                    properties.sets (Canberra.PROP_MEDIA_ROLE, "alarm");
                    properties.sets (Canberra.PROP_CANBERRA_VOLUME,
                                     amplitude_to_decibels (this.volume).to_string ());

                    status = this.context.play_full (0,
                                                     properties,
                                                     this.on_play_callback);

                    if (status != Canberra.SUCCESS) {
                        GLib.warning ("Couldn't play sound '%s' - %s",
                                      this.file.get_uri (),
                                      Canberra.strerror (status));
                    }
                }
                else {
                    GLib.warning ("Couldn't play sound '%s'",
                                  this.file.get_uri ());
                }
            }
        }

        public void stop ()
                    requires (this.context != null)
        {
            /* we dont need it for event sounds */
        }

        public string[] get_supported_mime_types ()
        {
            string[] mime_types = {
                "audio/x-vorbis+ogg",
                "audio/x-wav"
            };

            return mime_types;
        }

        private void on_play_callback (Canberra.Context context,
                                       uint32           id,
                                       int              code)
        {
        }
    }

    /**
     * A wrapper for regular SoundPlayer to allow it to be shared between more contexts.
     *
     * Used between main player and preferences dialog for the sound preview, so that sounds
     * wouldn't overlap and be in-sync.
     */
    private class SoundPlayerProxy : GLib.Object, SoundPlayer, Fadeable
    {
        public SoundPlayer player { get; construct set; }

        public GLib.File? file {
            get {
                return this.player.file;
            }
            set {
                this.player.file = value;
            }
        }

        public double volume {
            get {
                return this.player.volume;
            }
            set {
                this.player.volume = value;
            }
        }

        private bool is_playing {
            get {
                return this._is_playing;
            }
            set {
                if (this._is_playing != value)
                {
                    var refs = this.player.get_data<int> ("refs");

                    this.player.set_data<int> ("refs", refs + (value ? 1 : -1));

                    this._is_playing = value;
                }
            }
        }

        private bool _is_playing = false;

        public SoundPlayerProxy (SoundPlayer player)
        {
            player.notify["file"].connect (() => {
                this.notify_property ("file");
            });

            player.notify["volume"].connect (() => {
                this.notify_property ("volume");
            });

            this.player = player;
        }

        ~SoundPlayerProxy ()
        {
            this.stop ();
        }

        public void play ()
        {
            if (!this.is_playing)
            {
                this.is_playing = true;

                if (this.get_refs () == 1) {  /* TODO: we should unref once playback finishes */
                    this.player.play ();
                }
            }
        }

        public void stop ()
        {
            if (this.is_playing)
            {
                this.is_playing = false;

                if (this.get_refs () == 0) {
                    this.player.stop ();
                }
            }
        }

        public void fade_in (uint duration)
        {
            if (!(this.player is Fadeable))
            {
                this.play ();
            }
            else if (!this.is_playing)
            {
                this.is_playing = true;

                if (this.get_refs () == 1) {  /* TODO: we should unref once playback finishes */
                    (this.player as Fadeable).fade_in (duration);
                }
            }
        }

        public void fade_out (uint duration)
        {
            if (!(this.player is Fadeable))
            {
                this.stop ();
            }
            else if (this.is_playing)
            {
                this.is_playing = false;

                if (this.get_refs () == 0) {
                    (this.player as Fadeable).fade_out (duration);
                }
            }
        }

        public string[] get_supported_mime_types ()
        {
            return this.player.get_supported_mime_types ();
        }

        private int get_refs ()
        {
            return this.player.get_data<int> ("refs");
        }
    }
}

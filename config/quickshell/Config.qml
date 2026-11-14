// Shell settings, persisted to settings.json and watched live.
//
// Writes go through jq in a detached shell rather than from QML, so a partial
// write can never leave the file unparseable (jq builds a temp file and the
// rename is atomic). The FileView watch then picks the change straight back up,
// which is what makes the settings panel apply instantly.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: cfg

    readonly property string path: "/home/reouii/.config/quickshell/settings.json"
    property var raw: ({})

    property FileView file: FileView {
        path: cfg.path
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { cfg.raw = JSON.parse(text()) } catch (e) { /* keep last good settings */ }
        }
    }

    function get(k, d) {
        var v = raw ? raw[k] : undefined
        return (v === undefined || v === null) ? d : v
    }

    // ---- Colour ----
    readonly property string colorMode:   get("colorMode", "wallpaper")   // wallpaper | manual
    readonly property string sourceColor: get("sourceColor", "#88c0d0")
    readonly property string scheme:      get("scheme", "dark")           // dark | light
    readonly property real   vivid:       get("vivid", 1.0)
    // Degrees the third accent rotates from the source hue. Material's own
    // default of 60 turns an orange source green, so the default here is lower.
    readonly property real   harmony:     get("harmony", 30)

    // ---- Look ----
    readonly property real panelOpacity: get("panelOpacity", 1.0)
    readonly property real motion:       get("motion", 1.0)

    // ---- Type ----
    readonly property string fontDisplay: get("fontDisplay", "Red Hat Display")
    readonly property string fontBody:    get("fontBody",    "Red Hat Text")
    readonly property string fontMono:    get("fontMono",    "JetBrains Mono")
    readonly property real   fontScale:   get("fontScale",   1.0)

    // Night light colour temperature in Kelvin. 0 means off (no shift).
    readonly property int    nightTemp:   get("nightTemp", 0)

    // Applies a display+body pairing in one go.
    function setFontPair(display, body) {
        set("fontDisplay", display)
        set("fontBody", body)
    }

    // ---- Behaviour ----
    readonly property bool dnd:         get("dnd", false)
    readonly property int  batteryWarn: get("batteryWarn", 20)
    // ---- Bar items, each independently switchable ----
    readonly property bool showTray:       get("showTray", true)
    readonly property bool showTaskbar:    get("showTaskbar", true)
    readonly property bool showBattery:    get("showBattery", true)
    readonly property bool showStats:      get("showStats", true)
    readonly property bool showMedia:      get("showMedia", true)
    readonly property bool showVolume:     get("showVolume", true)
    readonly property bool showMic:        get("showMic", true)
    readonly property bool showClock:      get("showClock", true)
    readonly property bool showLayout:     get("showLayout", true)
    readonly property bool showPower:      get("showPower", true)
    readonly property bool showWorkspaces: get("showWorkspaces", true)
    readonly property bool showLauncher:   get("showLauncher", true)
    readonly property string musicDir:  get("musicDir", "")

    function shq(s) { return "'" + ("" + s).replace(/'/g, "'\\''") + "'" }

    // Merge one key into settings.json.
    function set(key, value) {
        var cmd =
            "f=" + shq(cfg.path) + "; mkdir -p \"$(dirname \"$f\")\"; " +
            "[ -s \"$f\" ] || echo '{}' > \"$f\"; " +
            "tmp=$(mktemp) && jq --arg k " + shq(key) +
            " --argjson v " + shq(JSON.stringify(value)) +
            " '.[$k]=$v' \"$f\" > \"$tmp\" && mv \"$tmp\" \"$f\""
        Quickshell.execDetached(["bash", "-c", cmd])
    }

    // Change the colour source and regenerate the scheme in one step.
    function setColorSource(mode, hex) {
        var script = "'" + "$HOME/.config/themes/bin/apply-colors.sh" + "'"
        var cmd = (mode === "manual")
            ? "$HOME/.config/themes/bin/apply-colors.sh --source " + shq(hex)
            : "$HOME/.config/themes/bin/apply-colors.sh --wallpaper"
        Quickshell.execDetached(["bash", "-c", cmd])
    }
}

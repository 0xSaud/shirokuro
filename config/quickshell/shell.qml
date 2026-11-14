//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Bluetooth

ShellRoot {
    id: root

    // Every colour in the shell comes from colors.json, which is regenerated
    // from the wallpaper. Nothing here hardcodes a hue.
    Config { id: cfg }
    Theme {
        id: tokens
        scheme: cfg.scheme
        panelOpacity: cfg.panelOpacity
        motion: cfg.motion
        fontDisplay: cfg.fontDisplay
        fontBody: cfg.fontBody
        fontMono: cfg.fontMono
        fontScale: cfg.fontScale
    }
    readonly property var th: tokens

    // Nerd Font glyphs are written as \uXXXX escapes throughout: pasted PUA
    // characters get silently stripped when this file is rewritten.
    readonly property string iconFont: tokens.icon
    readonly property string ramGlyph: String.fromCodePoint(0xf035b)

    // ---- Chosen GIF ----
    FileView {
        id: gifFile
        path: "/home/reouii/.config/quickshell/gif.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        JsonAdapter {
            id: gifState
            property string path: ""
            // Framing, so a wide or tall GIF can be positioned instead of
            // being centre-cropped and looking wrong.
            property real zoom: 1.0
            property real offsetX: 0.5
            property real offsetY: 0.5
        }
    }
    readonly property string gifPath: ("" + gifState.path).trim()
    readonly property bool   hasGif: gifPath.length > 0
    readonly property url    gifUrl: hasGif ? ("file://" + gifPath) : ""

    // ---- Panels ----
    property bool ccOpen: false
    property bool musicOpen: false
    function toggleCC()    { var v = !ccOpen;    ccOpen = v;    if (v) { musicOpen = false; refreshBri(); refreshPower() } }
    function toggleMusic() { var v = !musicOpen; musicOpen = v; if (v) ccOpen = false }

    // Ids differ from the IPC function names below on purpose — a handler
    // function called `launcher` would shadow an object with that id.
    Launcher  { id: appLauncher; th: root.th }
    PowerMenu {
        id: powerMenu
        th: root.th
        exec: function (c) { root.run(c) }
        lockCmd: cfg.get("locker", "hyprlock") === "quickshell"
                 ? "qs ipc call lock engage"
                 // Same path as sleep: hypridle switches to English, then locks.
                 : "loginctl lock-session"
    }

    // Current wallpaper, so the picker can mark which one is in use.
    FileView {
        id: wpState
        path: "/home/reouii/.config/themes/state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        JsonAdapter { id: wpJson; property string wallpaper: "" }
    }

    GifPicker {
        id: gifPicker
        th: root.th
        currentPath: root.gifPath
        curZoom: gifState.zoom; curOffX: gifState.offsetX; curOffY: gifState.offsetY
    }
    WallpaperPicker { id: wallPicker; th: root.th; currentPath: wpJson.wallpaper }
    FetchPicker     { id: fetchPicker; th: root.th }
    ColourPicker    { id: colourPicker; th: root.th; cfg: cfg }
    Settings        { id: settingsPanel; th: root.th; cfg: cfg }
    WifiPanel       { id: wifiPanel;     th: root.th }
    AudioPanel      { id: audioPanel;    th: root.th }
    BluetoothPanel  { id: btPanel;       th: root.th }
    WindowSwitcher  { id: winSwitcher;   th: root.th }
    Cheatsheet      { id: cheatsheet;    th: root.th }
    CalendarPanel   { id: calendarPanel; th: root.th }
    ClipboardPanel {
        id: clipPanel
        th: root.th
        pasteAddr: root.lastWinAddr
        pasteClass: root.lastWinClass
    }

    // The window that had focus before an overlay stole it, so the clipboard
    // panel knows where to paste back into.
    property string lastWinAddr: ""
    property string lastWinClass: ""
    readonly property bool anyOverlay:
        appLauncher.shown || powerMenu.shown || gifPicker.shown || wallPicker.shown
        || colourPicker.shown || settingsPanel.shown || wifiPanel.shown || clipPanel.shown
        || audioPanel.shown || btPanel.shown || winSwitcher.shown || cheatsheet.shown
        || calendarPanel.shown || fetchPicker.shown

    // ---- Screen recording (wf-recorder) ----
    property bool recording: false
    Process {
        running: true
        command: ["bash", "-c",
            "while true; do pgrep -x wf-recorder >/dev/null && echo 1 || echo 0; sleep 2; done"]
        stdout: SplitParser { onRead: function (l) { root.recording = (("" + l).trim() === "1") } }
    }
    function recStart(region) {
        var pick = region
            ? "-g \"$(slurp)\""
            : "-o \"$(hyprctl monitors -j | jq -r '.[]|select(.focused)|.name')\""
        root.run(
            "command -v wf-recorder >/dev/null || { " +
            "notify-send -u critical 'Recording' 'wf-recorder is not installed'; exit 0; }; " +
            "mkdir -p \"$HOME/Videos/Recordings\"; " +
            "f=\"$HOME/Videos/Recordings/rec-$(date +%Y%m%d-%H%M%S).mp4\"; " +
            "wf-recorder " + pick + " -f \"$f\" >/dev/null 2>&1; " +
            "[ -f \"$f\" ] && notify-send -a Recording 'Recording saved' \"$(basename \"$f\")\"")
    }
    function recStop() { root.run("pkill -INT -x wf-recorder") }

    // ---- Night light (hyprsunset) ----
    // hyprsunset holds the shift for as long as it runs, so "off" is simply
    // not running it rather than a second call.
    function setNight(k) {
        cfg.set("nightTemp", k)
        root.run("pkill -x hyprsunset 2>/dev/null; " +
                 (k > 0 ? "setsid hyprsunset -t " + k + " >/dev/null 2>&1 < /dev/null &" : "true"))
    }
    Component.onCompleted: {
        barHidden = cfg.get("barHidden", false)
        if (cfg.nightTemp > 0)
            root.run("pgrep -x hyprsunset >/dev/null || " +
                     "setsid hyprsunset -t " + cfg.nightTemp + " >/dev/null 2>&1 < /dev/null &")
    }

    // Every MPRIS player, minus the playerctld proxy (it mirrors another
    // player's identity and routing transport through it is unreliable).
    readonly property var players: {
        var out = []
        var list = Mpris.players ? Mpris.players.values : []
        for (var i = 0; i < list.length; i++) {
            var p = list[i]
            if (!p) continue
            if (("" + (p.dbusName || "")).toLowerCase().indexOf("playerctld") >= 0) continue
            out.push(p)
        }
        return out
    }

    Lock {
        id: lockScreen
        th: root.th
        wallpaper: wpJson.wallpaper
        userName: "reouii"
        gifPath: root.gifPath
        gifZoom: gifState.zoom
        gifOffX: gifState.offsetX
        gifOffY: gifState.offsetY
        trackTitle:   root.mp ? ("" + (root.mp.trackTitle  || "")) : ""
        trackArtist:  root.mp ? ("" + (root.mp.trackArtist || "")) : ""
        trackPlaying: !!(root.mp && root.mp.playbackState === MprisPlaybackState.Playing)
        batPct: root.hasBattery ? root.batPct : -1
        batCharging: root.batCharging
    }

    // Separate IPC target so `release` is reachable from a TTY if PAM ever
    // misbehaves. This is the documented way out of a bad lock.
    IpcHandler {
        target: "lock"
        // English first, so the password is never typed in Arabic by accident.
        function engage():  void {
            root.run("hyprctl switchxkblayout all 0")
            root.closeOverlays(); lockScreen.engage()
        }
        function release(): void { lockScreen.release() }
    }

    // Exactly one full-screen overlay at a time.
    function closeOverlays() {
        appLauncher.close(); powerMenu.close()
        gifPicker.close(); wallPicker.close(); colourPicker.close()
        settingsPanel.close(); wifiPanel.close(); clipPanel.close()
        audioPanel.close(); btPanel.close(); winSwitcher.close()
        cheatsheet.close(); calendarPanel.close(); fetchPicker.close()
    }
    function showOnly(panel) {
        var wasOpen = panel.shown
        closeOverlays()
        if (!wasOpen) panel.open()
    }
    function toggleLauncher() {
        powerMenu.close()
        if (appLauncher.shown) appLauncher.close(); else appLauncher.open()
    }
    function togglePower() {
        appLauncher.close()
        if (powerMenu.shown) powerMenu.close(); else powerMenu.open()
    }

    IpcHandler {
        target: "panels"
        function cc():       void { root.toggleCC() }
        function music():    void { root.toggleMusic() }
        function launcher():  void { root.toggleLauncher() }
        function power():     void { root.togglePower() }
        function gif():       void { root.showOnly(gifPicker) }
        function wallpaper(): void { root.showOnly(wallPicker) }
        function theme():     void { root.showOnly(colourPicker) }
        function settings():  void { root.showOnly(settingsPanel) }
        function wifi():      void { root.showOnly(wifiPanel) }
        function clipboard(): void { root.showOnly(clipPanel) }
        function audio():     void { root.showOnly(audioPanel) }
        function bluetooth(): void { root.showOnly(btPanel) }
        // Hide or show the bar. Saved in settings.json, so it stays hidden
        // across reloads and logins until toggled back.
        function bar():       void { root.barHidden = !root.barHidden; cfg.set("barHidden", root.barHidden) }
        function windows():   void { root.showOnly(winSwitcher) }
        function keys():      void { root.showOnly(cheatsheet) }
        function calendar():  void { root.showOnly(calendarPanel) }
        function fetch():     void { root.showOnly(fetchPicker) }
        function recordRegion(): void { root.recStart(true) }
        function recordScreen(): void { root.recStart(false) }
        function recordStop():   void { root.recStop() }
        function close():     void {
            root.ccOpen = false; root.musicOpen = false
            root.closeOverlays()
        }
    }

    // ---- System stats ----
    property string cpu:  "0"
    property string mem:  "0"
    property string disk: "?"
    property string temp: "0"
    Process {
        running: true
        command: ["bash", "/home/reouii/.config/themes/bin/sysinfo.sh"]
        stdout: SplitParser {
            onRead: function (line) {
                var p = ("" + line).trim().split("|")
                if (p.length >= 4) { root.cpu=p[0]; root.mem=p[1]; root.disk=p[2]; root.temp=p[3] }
            }
        }
    }

    function run(cmd) { Quickshell.execDetached(["bash", "-c", cmd]) }
    function fmt(s) {
        s = Math.max(0, Math.floor(s || 0))
        var m = Math.floor(s / 60); var ss = s % 60
        return m + ":" + (ss < 10 ? "0" + ss : "" + ss)
    }

    // ---- Battery ----
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: !!(bat && bat.isLaptopBattery)
    // UPower exposes percentage as 0..1 in some builds and 0..100 in others.
    readonly property int batPct: {
        if (!bat) return -1
        var p = bat.percentage
        if (p === undefined || p === null) return -1
        return Math.round(p <= 1.0 ? p * 100 : p)
    }
    readonly property bool batCharging:
        !!(bat && (bat.state === UPowerDeviceState.Charging
                   || bat.state === UPowerDeviceState.FullyCharged))
    readonly property bool batLow: hasBattery && !batCharging && batPct >= 0 && batPct <= cfg.batteryWarn
    function batIcon() {
        if (batCharging) return "\uf0e7"
        var p = batPct
        if (p >= 90) return "\uf240"
        if (p >= 65) return "\uf241"
        if (p >= 40) return "\uf242"
        if (p >= 15) return "\uf243"
        return "\uf244"
    }
    function batDetail() {
        if (!bat) return ""
        var secs = batCharging ? bat.timeToFull : bat.timeToEmpty
        if (!secs || secs <= 0) return batCharging ? "Charging" : ""
        var h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60)
        return (h > 0 ? h + "h " : "") + m + "m " + (batCharging ? "to full" : "left")
    }
    // Battery warning: ONE notification, with a sound, when the battery drops
    // to the chosen threshold. It does not repeat. Plugging in, or climbing
    // back above the threshold, re-arms it for next time.
    //
    // "Already warned" is kept across shell reloads, so editing the config while
    // the battery is low does not make it warn again. A timer checks as well as
    // the change handlers, so a session that starts with the battery already low
    // still gets its one warning.
    PersistentProperties {
        id: batState
        reloadableId: "batteryWarning"
        property bool warned: false
    }
    function batCheck() {
        if (!hasBattery || batPct < 0) return
        if (batCharging || batPct > cfg.batteryWarn) { batState.warned = false; return }
        if (batState.warned) return
        batState.warned = true
        var left = batDetail()
        root.run("notify-send -u critical -a Battery 'Battery low' " +
                 cfg.shq(batPct + "%" + (left.length ? ", about " + left : "") + ". Plug in the charger.") + "; " +
                 "pw-play /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null || " +
                 "canberra-gtk-play -i dialog-warning 2>/dev/null")
    }
    onBatPctChanged: batCheck()
    onBatChargingChanged: batCheck()
    onHasBatteryChanged: batCheck()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.batCheck() }
    // Shortly after start, once UPower has reported in.
    Timer { interval: 4000; running: true; onTriggered: root.batCheck() }

    // ---- Clock ----
    property string clockText: ""
    property string dateText: ""
    // The rail stacks these: hour, minute, weekday, day of month.
    property string clockH: ""
    property string clockM: ""
    property string clockDay: ""
    property string clockDate: ""
    property string clockLong: ""
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d = new Date()
            root.clockText = "\uf017 " + Qt.formatDateTime(d, "hh:mm AP  |  ddd dd MMM")
            root.dateText  = Qt.formatDateTime(d, "dddd, dd MMMM")
            root.clockH    = Qt.formatDateTime(d, "hh AP").split(" ")[0]
            root.clockM    = Qt.formatDateTime(d, "mm")
            root.clockDay  = Qt.formatDateTime(d, "ddd").toUpperCase()
            root.clockDate = Qt.formatDateTime(d, "dd")
            root.clockLong = Qt.formatDateTime(d, "ddd d MMM") + "  " + Qt.formatDateTime(d, "AP").toLowerCase()
        }
    }

    // ---- Keyboard layout ----
    property string kbLayout: "EN"
    function applyKb(s) { root.kbLayout = (("" + s).toLowerCase().indexOf("arab") >= 0) ? "AR" : "EN" }
    Process {
        running: true
        command: ["bash", "-c", "hyprctl devices -j | jq -r '[.keyboards[]|select(.main==true)][0].active_keymap'"]
        stdout: StdioCollector { id: kbOut; onStreamFinished: root.applyKb(kbOut.text) }
    }

    // ---- Tray de-duplication ----
    // Discord (and anything else that keeps a tray icon while its window is
    // open) would otherwise show up twice: once as a window, once in the tray.
    // SystemTrayItem exposes only `id`, never the owning process, so the map
    // from tray id to PID is built over D-Bus here and matched against the
    // window PIDs. Matching on the PID rather than the name is what makes this
    // safe: Discord's tray id is `discord_status_icon_1`, which no name-based
    // rule would tie to the window class `discord` without guessing.
    //
    // If any of this fails the map stays empty and every tray icon shows, which
    // is exactly the old behaviour.
    property var trayPid: ({})

    Process {
        id: trayLister
        running: true
        command: ["bash", "-c",
            "w=org.kde.StatusNotifierWatcher; " +
            "busctl --user call $w /StatusNotifierWatcher org.freedesktop.DBus.Properties " +
            "Get ss $w RegisteredStatusNotifierItems 2>/dev/null | grep -o '\"[^\"]*\"' | tr -d '\"' | " +
            "while read -r e; do " +
            "  b=${e%%/*}; p=/${e#*/}; [ \"$b\" = \"$e\" ] && p=/StatusNotifierItem; " +
            "  pid=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus " +
            "        org.freedesktop.DBus GetConnectionUnixProcessID s \"$b\" 2>/dev/null | awk '{print $2}'); " +
            "  [ -n \"$pid\" ] || continue; " +
            "  for i in org.kde.StatusNotifierItem org.freedesktop.StatusNotifierItem; do " +
            "    id=$(busctl --user call \"$b\" \"$p\" org.freedesktop.DBus.Properties Get ss $i Id 2>/dev/null " +
            "         | sed -n 's/^v s \"\\(.*\\)\"$/\\1/p'); " +
            "    [ -n \"$id\" ] && break; " +
            "  done; " +
            "  [ -n \"$id\" ] && printf '%s\\t%s\\n' \"$id\" \"$pid\"; " +
            "done"]
        stdout: StdioCollector {
            id: trayOut
            onStreamFinished: {
                var m = ({})
                var lines = ("" + trayOut.text).split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var f = lines[i].split("\t")
                    if (f.length < 2) continue
                    var pid = parseInt(f[1])
                    if (f[0].length > 0 && pid > 1) m[f[0]] = pid
                }
                root.trayPid = m
            }
        }
    }

    // Only the tray changing can change this map, and that is rare, so it is
    // not tied to the window refresh.
    readonly property int trayCount: SystemTray.items ? SystemTray.items.values.length : 0
    onTrayCountChanged: trayDebounce.restart()
    Timer {
        id: trayDebounce
        interval: 250
        onTriggered: {
            if (trayLister.running) { restart(); return }
            trayLister.running = true
        }
    }

    // True when this tray icon's process already owns a window in the taskbar.
    function trayIsDup(id) {
        if (!cfg.showTaskbar) return false
        var pid = root.trayPid["" + id]
        if (pid === undefined) return false
        for (var i = 0; i < root.winList.length; i++)
            if (parseInt(root.winList[i].pid) === pid) return true
        return false
    }
    function trayShownCount() {
        var items = SystemTray.items ? SystemTray.items.values : []
        var n = 0
        for (var i = 0; i < items.length; i++) if (!root.trayIsDup(items[i].id)) n++
        return n
    }

    // ---- Open windows (taskbar model) ----
    // hyprctl is the source rather than the wlr toplevel protocol because it
    // carries the PID, and the PID is what makes a real quit possible: closing
    // a window only asks politely, and apps like Discord answer by hiding in
    // the tray instead of exiting.
    //
    // The result is split in two on purpose. winList holds the structure and is
    // reassigned only when a window actually appears, vanishes or changes
    // workspace, so the icon Repeater keeps its delegates and does not drop
    // hover state. winMeta holds what churns - title, position - and is a plain
    // map lookup, so a terminal retitling itself every keystroke costs nothing.
    property var winList: []
    property var winMeta: ({})
    property string winSig: ""
    property string focusedAddr: ""

    // Hyprland emits addresses bare in events but prefixed in `clients -j`.
    function addrEq(a, b) {
        a = ("" + a).replace(/^0x/, "")
        b = ("" + b).replace(/^0x/, "")
        return a.length > 0 && a === b
    }

    Process {
        id: winLister
        running: true
        command: ["bash", "-c",
            "hyprctl clients -j | jq -r '.[] | select(.mapped==true) | select(.workspace.id > 0 or .workspace.name == \"special:bg\") | " +
            "[.address, (.pid|tostring), (.workspace.id|tostring), (.focusHistoryID|tostring), " +
            ".class, .title, ((.at[0] + .size[0] / 2)|floor|tostring), " +
            "((.at[1] + .size[1] / 2)|floor|tostring)] | @tsv'"]
        stdout: StdioCollector {
            id: winOut
            onStreamFinished: {
                var out = [], meta = ({}), sig = "", focus = ""
                var lines = ("" + winOut.text).split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var f = lines[i].split("\t")
                    if (f.length < 8) continue
                    if (("" + f[0]).length === 0) continue
                    var addr = f[0], ws = parseInt(f[2])
                    out.push({ addr: addr, pid: f[1], ws: ws, cls: f[4] })
                    meta[addr] = { title: f[5], cx: parseInt(f[6]), cy: parseInt(f[7]) }
                    sig += addr + ":" + ws + ":" + f[4] + ";"
                    if (parseInt(f[3]) === 0) focus = addr
                }
                root.winMeta = meta
                if (focus.length > 0) root.focusedAddr = focus
                if (sig !== root.winSig) {
                    // Workspace first, then address. Hyprland hands out
                    // addresses in creation order, so icons keep a stable spot
                    // instead of reshuffling under the cursor.
                    out.sort(function (a, b) {
                        var d = a.ws - b.ws
                        return d !== 0 ? d : a.addr.localeCompare(b.addr)
                    })
                    root.winSig = sig
                    root.winList = out
                }
            }
        }
    }

    // Hyprland fires several events for one window action; coalesce them so
    // dragging a window across workspaces doesn't spawn a dozen hyprctl calls.
    Timer {
        id: winDebounce
        interval: 120
        onTriggered: {
            // Setting running=true on a live Process is a no-op, so a refresh
            // arriving mid-query would be silently dropped. Come back instead.
            if (winLister.running) { restart(); return }
            winLister.running = true
        }
    }
    function refreshWins() { winDebounce.restart() }

    // A window's class is frequently NOT an icon-theme name, so looking it up
    // directly falls back to the generic executable glyph. Burp is the worst
    // case on this box: it reports class `install4j-burp-StartBurp` and its
    // .desktop names an absolute PNG path rather than a themed icon.
    //
    // StartupWMClass exists precisely to tie a window back to its launcher, so
    // match on that first, fall back to Quickshell's own heuristic lookup, and
    // only then guess from the class itself.
    function classIcon(cls) {
        var key = ("" + cls).trim()
        if (key.length === 0) return Quickshell.iconPath("application-x-executable")
        var lower = key.toLowerCase()
        var entry = null

        var apps = DesktopEntries.applications ? DesktopEntries.applications.values : []
        for (var i = 0; i < apps.length; i++) {
            var sc = "" + (apps[i].startupClass || "")
            if (sc.length > 0 && sc.toLowerCase() === lower) { entry = apps[i]; break }
        }
        if (!entry) {
            try { entry = DesktopEntries.heuristicLookup(key) } catch (e) { entry = null }
        }

        var name = entry ? ("" + (entry.icon || "")) : ""
        if (name.length === 0) name = lower
        // An entry may name a themed icon or point straight at a file.
        if (name.charAt(0) === "/") return "file://" + name
        return Quickshell.iconPath(name, "application-x-executable")
    }

    // Focus a window wherever it lives: focuswindow follows it onto its
    // workspace and monitor, then the cursor is warped onto it so the pointer
    // ends up where you are now looking. Drop the movecursor line to keep the
    // mouse still.
    function focusWin(w) {
        if (!w) return
        // A window hidden by SUPER+C (close-window.sh parks background apps
        // such as Spotify on special:bg) is brought back to this workspace.
        if (w.ws < 0 && Hyprland.focusedWorkspace)
            Hyprland.dispatch("movetoworkspace " + Hyprland.focusedWorkspace.id + ",address:" + w.addr)
        Hyprland.dispatch("focuswindow address:" + w.addr)
        // Geometry comes from winMeta rather than the list record so a window
        // that has been moved or resized since is still warped to accurately.
        var m = root.winMeta[w.addr]
        if (m && !isNaN(m.cx) && !isNaN(m.cy))
            Hyprland.dispatch("movecursor " + m.cx + " " + m.cy)
    }

    // Terminate the process behind a window for real. SIGTERM first so it can
    // save, SIGKILL three seconds later if it is still around. The PID is
    // checked as a number before it reaches the shell.
    function quitWin(w) {
        if (!w) return
        var pid = parseInt(w.pid)
        root.quitProc(pid, w.cls)
        root.refreshWins()
    }

    // Quit the app behind a tray icon. The PID comes from the D-Bus map built
    // for tray de-duplication; the icon id doubles as a name to match on.
    function quitTray(item) {
        if (!item) return
        var pid = root.trayPid["" + item.id]
        root.quitProc(pid === undefined ? 0 : pid, "" + item.id)
    }

    // Shared quit. Flatpak apps are handled first and by name: a sandboxed
    // app's window can report a PID from inside its own namespace (a small
    // number that means nothing out here), and killing one process of a
    // sandbox leaves the rest running. `flatpak kill` ends the whole instance.
    function quitProc(pid, name) {
        // Match strictly: the name must equal the Flatpak app id or its last
        // part (com.discordapp.Discord -> "discord"). A loose substring match
        // could end a different sandboxed app that merely shares a word.
        var key = ("" + name).toLowerCase().replace(/_status_icon_\d+$/, "").trim()
        var cmd = ""
        if (key.length >= 3)
            cmd += "app=$(flatpak ps --columns=application 2>/dev/null | awk -v n=" + cfg.shq(key) +
                   " '{a=tolower($1); k=split(a,p,\".\"); if (a==n || p[k]==n) {print $1; exit}}'); " +
                   "if [ -n \"$app\" ]; then flatpak kill \"$app\"; exit 0; fi; "
        pid = parseInt(pid)
        if (pid > 1)
            cmd += "kill -TERM " + pid + " 2>/dev/null; " +
                   "for i in 1 2 3; do sleep 1; kill -0 " + pid + " 2>/dev/null || exit 0; done; " +
                   "kill -KILL " + pid + " 2>/dev/null"
        if (cmd.length > 0) root.run(cmd)
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Anything that can add, remove, move or retitle a window makes the
            // taskbar stale.
            if (event.name === "openwindow"   || event.name === "closewindow"
             || event.name === "movewindow"   || event.name === "movewindowv2"
             || event.name === "windowtitle"  || event.name === "windowtitlev2"
             || event.name === "fullscreen" || event.name === "changefloatingmode"
             || event.name === "monitoradded" || event.name === "monitorremoved")
                root.refreshWins()

            // Focus moves far more often than the window set changes, so it
            // rides on its own property. Rebuilding the list here would tear
            // down the icon row on every alt-tab.
            if (event.name === "activewindowv2") {
                var fa = ("" + event.data).trim()
                if (fa.length > 0 && fa !== ",") root.focusedAddr = fa
            }

            if (event.name === "activelayout") {
                var d = "" + event.data; var i = d.indexOf(",")
                root.applyKb(i >= 0 ? d.substring(i + 1) : d)
            }
            // Remember the real window, never one of our own overlays, so the
            // clipboard panel can paste back into whatever you were using.
            else if (event.name === "activewindowv2" && !root.anyOverlay) {
                var a = ("" + event.data).trim()
                if (a.length > 0 && a !== "," ) root.lastWinAddr = a
            }
            else if (event.name === "activewindow" && !root.anyOverlay) {
                var s = "" + event.data
                var c = s.indexOf(",")
                root.lastWinClass = (c >= 0 ? s.substring(0, c) : s).trim()
            }
        }
    }

    // ---- Audio ----
    PwObjectTracker { objects: [ Pipewire.defaultAudioSink, Pipewire.defaultAudioSource ] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    function sinkVol()  { return sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0 }
    function sinkMuted(){ return sink && sink.audio ? sink.audio.muted : false }
    function srcVol()   { return source && source.audio ? Math.round(source.audio.volume * 100) : 0 }
    function srcMuted() { return source && source.audio ? source.audio.muted : false }
    function setSinkVol(v) { if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, v/100)) }
    function toggleMicMute() { if (source && source.audio) source.audio.muted = !source.audio.muted }
    function volIcon() {
        if (sinkMuted()) return "\uf026"
        var v = sinkVol()
        if (v <= 0) return "\uf026"
        if (v < 50) return "\uf027"
        return "\uf028"
    }

    // ---- Brightness ----
    property int  briPct: 50
    property int  briExt: 50
    property bool briSync: false
    property bool briHasExt: false
    readonly property string briScript: "~/.config/hypr/scripts/brightness.sh"
    Process {
        id: briState
        running: true
        command: ["bash","-c",
            "j=\"$HOME/.config/themes/brightness.json\"; " +
            "l=$(jq -r '.laptop // 50' \"$j\" 2>/dev/null); " +
            "e=$(jq -r '.external // 50' \"$j\" 2>/dev/null); " +
            "s=$(jq -r '.sync // false' \"$j\" 2>/dev/null); " +
            "x=$(hyprctl monitors -j 2>/dev/null | jq '[.[].name] | any(. != \"eDP-1\")'); " +
            "echo \"$l $e $s $x\"" ]
        stdout: StdioCollector { id: briStateOut
            onStreamFinished: {
                var p = ("" + briStateOut.text).trim().split(/\s+/)
                if (p.length >= 4) {
                    var l = parseInt(p[0]); if (!isNaN(l)) root.briPct = l
                    var e = parseInt(p[1]); if (!isNaN(e)) root.briExt = e
                    root.briSync   = (p[2] === "true")
                    root.briHasExt = (p[3] === "true")
                }
            }
        }
    }
    function refreshBri()    { briState.running = true }
    function setBriLaptop(v) { v = Math.round(v); root.briPct = v; root.run(root.briScript + " laptop "   + v) }
    function setBriExt(v)    { v = Math.round(v); root.briExt = v; root.run(root.briScript + " external " + v) }
    function setBriBoth(v)   { v = Math.round(v); root.briPct = v; root.briExt = v; root.run(root.briScript + " both " + v) }
    function toggleBriSync() { root.briSync = !root.briSync; if (root.briSync) root.briExt = root.briPct; root.run(root.briScript + " sync") }

    // ---- Bluetooth ----
    readonly property var btAdapter: Bluetooth.defaultAdapter
    function btOn() { return btAdapter ? btAdapter.enabled : false }
    function btToggle() { if (btAdapter) btAdapter.enabled = !btAdapter.enabled }

    // ---- Wi-Fi ----
    property string wifiSsid: ""
    Process {
        id: wifiRead
        running: true
        command: ["bash","-c","while true; do nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1==\"yes\"{print $2; found=1} END{if(!found)print \"\"}'; sleep 6; done"]
        stdout: SplitParser { onRead: function(l){ root.wifiSsid = ("" + l).trim() } }
    }

    // ---- Power profile ----
    property string powerProfile: ""
    Process {
        id: powerRead
        running: true
        command: ["bash","-c","$HOME/.config/themes/bin/power-profile.sh get"]
        stdout: StdioCollector { id: powerOut
            onStreamFinished: { var s = ("" + powerOut.text).trim(); if (s.length > 0) root.powerProfile = s }
        }
    }
    function refreshPower()     { powerRead.running = true }
    function setPowerProfile(p) { root.powerProfile = p; root.run("~/.config/themes/bin/power-profile.sh " + p) }

    // ---- Media ----
    // Set from the media panel to pin one player; empty means "whatever is playing".
    property string preferredPlayer: ""
    readonly property var mp: {
        var list = Mpris.players ? Mpris.players.values : []
        // Skip the playerctld proxy: it mirrors the real player's identity but
        // routing transport commands through it is unreliable.
        var real = []
        for (var i = 0; i < list.length; i++) {
            var pl = list[i]
            if (!pl) continue
            if (("" + (pl.dbusName || "")).toLowerCase().indexOf("playerctld") >= 0) continue
            real.push(pl)
        }
        if (real.length === 0) real = list
        // A pinned player wins, so the bar keeps following the tab you chose
        // even when another one starts making noise.
        if (root.preferredPlayer.length > 0) {
            for (var k = 0; k < real.length; k++)
                if (("" + real[k].dbusName) === root.preferredPlayer) return real[k]
        }
        for (var j = 0; j < real.length; j++)
            if (real[j].playbackState === MprisPlaybackState.Playing) return real[j]
        return real.length ? real[0] : null
    }
    // Per-app music volume: the PipeWire stream of the now-playing app ONLY.
    // No fallback by design, so it can never move the game's or system volume.
    readonly property var mpNode: {
        if (!root.mp) return null
        var want = ("" + (root.mp.identity || "")).toLowerCase()
        if (want.length === 0) return null
        var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i]
            if (!n || !n.isStream) continue
            var nm = ("" + (n.name || "")).toLowerCase()
            if (nm.length === 0) continue
            if (nm.indexOf(want) >= 0 || want.indexOf(nm) >= 0) return n
        }
        return null
    }
    PwObjectTracker { objects: root.mpNode ? [ root.mpNode ] : [] }
    property real mpPos: 0
    Timer {
        interval: 1000; running: root.musicOpen; repeat: true
        onTriggered: root.mpPos = (root.mp ? (root.mp.position || 0) : 0)
    }
    function mediaText() {
        if (!mp) return ""
        var t = (mp.trackTitle || "").substring(0, 24)
        if (t.length === 0) return ""
        return (mp.playbackState === MprisPlaybackState.Playing ? "\uf04b " : "\uf04c ") + t
    }
    function mpPrev() {
        if (!mp) return
        if (mp.canGoPrevious) mp.previous()
        else if (mp.canSeek)  mp.position = Math.max(0, (mp.position || 0) - 10)
    }
    function mpNext() {
        if (!mp) return
        if (mp.canGoNext)    mp.next()
        else if (mp.canSeek) mp.position = (mp.position || 0) + 10
    }
    function mpToggle() { if (mp) mp.togglePlaying() }

    // ---- Notifications ----
    ListModel { id: histModel }
    NotificationServer {
        id: notifServer
        keepOnReload: false
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: false
        onNotification: function (n) {
            n.tracked = true
            histModel.insert(0, {
                hSummary: ("" + (n.summary || "")),
                hBody:    ("" + (n.body || "")),
                hApp:     ("" + (n.appName || "app")),
                hTime:    Qt.formatDateTime(new Date(), "hh:mm AP")
            })
            while (histModel.count > 50) histModel.remove(50)
        }
    }

    // =====================================================================
    //  Bar building blocks
    // =====================================================================
    // "Ink" look: the bar is a strip of black lacquer across the top. Items on
    // it are bare glyphs and figures with no chip behind them; only the active
    // workspace carries colour, as a small red seal.
    readonly property int barH: 34
    property bool barHidden: false
    readonly property string sealPath: "file:///home/reouii/.config/quickshell/assets/seal.png"

    // Workspaces are numbered in kanji to match the blade in the wallpaper.
    // Set "kanjiWorkspaces": false in settings.json for plain digits.
    readonly property var kanji: ["\u3007", "\u4e00", "\u4e8c", "\u4e09", "\u56db", "\u4e94",
                                  "\u516d", "\u4e03", "\u516b", "\u4e5d", "\u5341",
                                  "\u5341\u4e00", "\u5341\u4e8c"]
    function wsLabel(ws) {
        if (!cfg.get("kanjiWorkspaces", true)) return "" + ws.name
        return (ws.id >= 0 && ws.id < kanji.length) ? kanji[ws.id] : "" + ws.name
    }

    component BarItem: Item {
        id: bi
        property string glyph: ""
        property string label: ""
        property color fg: root.th.onSurfaceVariant
        property var onClick: null
        property var onScrollUp: null
        property var onScrollDown: null
        readonly property bool interactive: onClick !== null || onScrollUp !== null
        implicitWidth: biRow.implicitWidth + 16
        implicitHeight: 24
        width: implicitWidth
        height: implicitHeight
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: root.th.surfaceContainerHigh
            opacity: (bi.interactive && biMa.containsMouse) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Row {
            id: biRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: bi.glyph.length > 0
                text: bi.glyph
                color: bi.fg
                font.family: root.iconFont
                font.pixelSize: root.th.fs(12)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: bi.label.length > 0
                text: bi.label
                color: bi.fg
                font.family: root.th.mono
                font.pixelSize: root.th.fs(11)
                font.weight: Font.Medium
            }
        }
        MouseArea {
            id: biMa
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: bi.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (bi.onClick) bi.onClick()
            onWheel: function (w) {
                if (w.angleDelta.y > 0 && bi.onScrollUp) bi.onScrollUp()
                else if (w.angleDelta.y < 0 && bi.onScrollDown) bi.onScrollDown()
            }
        }
    }

    // Thin upright stroke between groups.
    component BarSep: Item {
        width: 13
        height: 24
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Rectangle { anchors.centerIn: parent; width: 1; height: 12; color: root.th.outlineVariant }
    }

    // =====================================================================
    //  Panel building blocks
    // =====================================================================
    // Labels arrive as "POWER PROFILE"; they are shown as "Power profile".
    function sentence(s) {
        s = "" + s
        return s.length === 0 ? "" : s.charAt(0).toUpperCase() + s.slice(1).toLowerCase()
    }

    // Section title: a short red stroke, then the name in plain weight.
    component SectionHead: Item {
        id: sh
        property string label: ""
        property color tint: root.th.primary
        width: parent ? parent.width : 300
        implicitHeight: 30
        Rectangle {
            anchors.verticalCenter: shText.verticalCenter
            width: 10; height: 2
            color: root.th.primary
        }
        Text {
            id: shText
            x: 18
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5
            text: root.sentence(sh.label)
            color: root.th.onSurfaceVariant
            font.family: root.th.body
            font.pixelSize: root.th.fs(12)
            font.weight: Font.DemiBold
        }
    }

    // Toggle row. Monochrome: on is white-on-black reversed to a pale block.
    component Tile: Rectangle {
        id: tile
        property string label: ""
        property string sublabel: ""
        property bool active: false
        property color tint: root.th.primary
        property var onClick: null
        width: parent ? parent.width : 300
        implicitHeight: 52
        radius: root.th.r
        color: active ? root.th.surfaceText
                      : (tileMa.containsMouse ? root.th.surfaceContainerHighest : root.th.surfaceContainerHigh)
        Behavior on color { ColorAnimation { duration: 140 } }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            x: 14
            width: parent.width - 50
            spacing: 1
            Text { text: tile.label
                   color: tile.active ? root.th.surface : root.th.surfaceText
                   font.family: root.th.body; font.pixelSize: root.th.fs(13); font.weight: Font.DemiBold }
            Text { text: tile.sublabel; visible: text.length > 0
                   color: tile.active ? root.th.surfaceContainerHighest : root.th.outline
                   font.family: root.th.body; font.pixelSize: root.th.fs(10)
                   elide: Text.ElideRight; width: parent.width }
        }
        // State mark: red seal dot when on.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 14
            width: 8; height: 8; radius: 2
            color: tile.active ? root.th.primary : root.th.outlineVariant
        }
        MouseArea { id: tileMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (tile.onClick) tile.onClick() }
    }

    component SliderRow: Item {
        id: slRow
        property string label: ""
        property int pct: 0
        property color tint: root.th.primary
        property var onChange: null
        property bool rowEnabled: true
        width: parent ? parent.width : 300
        implicitHeight: 36
        opacity: rowEnabled ? 1 : 0.4

        Text {
            id: slLabel
            anchors.verticalCenter: parent.verticalCenter
            width: 66
            text: root.sentence(slRow.label)
            color: root.th.onSurfaceVariant
            font.family: root.th.body; font.pixelSize: root.th.fs(12)
        }
        Slider {
            id: sl
            anchors.verticalCenter: parent.verticalCenter
            x: slLabel.width + 6
            width: parent.width - x - 42
            // Explicit height: the custom background/handle set `height` but not
            // `implicitHeight`, so the Slider's own implicit size collapsed to
            // nothing. It still drew, but had no hit area.
            height: 26
            from: 0; to: 100
            value: slRow.pct
            enabled: slRow.rowEnabled
            onMoved: if (slRow.onChange) slRow.onChange(value)

            // A single brush stroke: white where filled, grey where not.
            background: Rectangle {
                x: sl.leftPadding
                y: sl.topPadding + sl.availableHeight / 2 - height / 2
                implicitWidth: 120
                implicitHeight: 3
                width: sl.availableWidth
                height: 3
                radius: 1.5
                color: root.th.outlineVariant
                Rectangle { width: sl.visualPosition * parent.width; height: parent.height
                            radius: 1.5; color: root.th.surfaceText }
            }
            handle: Rectangle {
                x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
                y: sl.topPadding + sl.availableHeight / 2 - height / 2
                implicitWidth: 12; implicitHeight: 12
                width: 12; height: 12; radius: 6
                color: sl.pressed ? root.th.primary : root.th.surfaceText
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            width: 36
            horizontalAlignment: Text.AlignRight
            text: slRow.pct
            color: root.th.surfaceText
            font.family: root.th.mono; font.pixelSize: root.th.fs(11)
        }
    }

    component SqBtn: Rectangle {
        id: sq
        property string icon: ""
        property color fg: root.th.onSurfaceVariant
        property color line: "transparent"
        property int glyphSize: 13
        property string glyphFont: root.th.body
        property var onClick: null
        implicitWidth: 30; implicitHeight: 30
        radius: root.th.rSmall
        color: sqMa.containsMouse ? root.th.surfaceText : root.th.surfaceContainerHigh
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { anchors.centerIn: parent; text: sq.icon
               color: sqMa.containsMouse ? root.th.surface : sq.fg
               font.family: sq.glyphFont; font.pixelSize: sq.glyphSize }
        MouseArea { id: sqMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (sq.onClick) sq.onClick() }
    }

    // Segmented choice. The chosen one is reversed: pale block, black text.
    component ProfileBtn: Rectangle {
        id: seg
        property string label: ""
        property string value: ""
        property color tint: root.th.primary
        property var onPick: null
        readonly property bool sel: seg.value.length > 0 && root.powerProfile === seg.value
        implicitHeight: 36
        radius: root.th.r
        color: seg.sel ? root.th.surfaceText
                       : (segMa.containsMouse ? root.th.surfaceContainerHighest : root.th.surfaceContainerHigh)
        Behavior on color { ColorAnimation { duration: 140 } }
        Text {
            anchors.centerIn: parent
            text: root.sentence(seg.label)
            color: seg.sel ? root.th.surface : root.th.onSurfaceVariant
            font.family: root.th.body; font.pixelSize: root.th.fs(11)
            font.weight: Font.DemiBold
        }
        MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (seg.onPick) seg.onPick() }
    }

    // =====================================================================
    //  Bar
    // =====================================================================
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: barWin
            property var modelData
            screen: modelData
            color: "transparent"
            anchors { top: true; left: true; right: true }
            implicitHeight: root.barH
            // SUPER+B. A hidden bar also gives its strip back to the windows.
            visible: !root.barHidden

            // Taskbar popup state. Both popups are declared once and re-anchored
            // to whichever icon they belong to, rather than one popup per window.
            //
            // Position is carried as a plain x offset, never as an Item
            // reference: PopupAnchor::onItemWindowChanged() in Quickshell 0.3.0
            // dereferences the item with no null check, so clearing anchor.item
            // on hover-out segfaults the whole shell. A rect against barWin has
            // no pointer to dangle.
            property var  tbHoverWin: null
            property real tbHoverX: 0
            property bool tbHoverOn: false
            property var  tbMenuWin: null
            property real tbMenuX: 0
            property bool tbMenuOn: false
            property bool tbMenuHover: false
            function closeTbMenu() { tbMenuOn = false; tbMenuHover = false }
            // Clicking into another window changes focus, which is the clearest
            // signal that the menu is no longer what the user is looking at.
            //
            // But focus_follows_mouse keeps emitting activewindow for up to
            // half a second after the pointer merely arrives at the bar, so a
            // straggler would otherwise close the menu the instant it opened.
            // Ignoring focus while the pointer is still on the menu's own icon
            // or inside the menu itself separates "user moved on" from that
            // settling noise, with no timing guess.
            Connections {
                target: root
                function onFocusedAddrChanged() {
                    if (!barWin.tbMenuOn) return
                    if (barWin.tbMenuHover) return
                    if (barWin.tbHoverOn && barWin.tbHoverWin && barWin.tbMenuWin
                        && barWin.tbHoverWin.addr === barWin.tbMenuWin.addr) return
                    barWin.closeTbMenu()
                }
            }
            // Keeps a popup on screen when its icon sits near the bar's edge.
            function tbClampX(centerX, w) {
                return Math.round(Math.max(6, Math.min(barWin.width - w - 6, centerX - w / 2)))
            }

            // ---- Surface: black lacquer with a hairline under it ----
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(root.th.ink.r, root.th.ink.g, root.th.ink.b,
                               Math.min(1.0, root.th.panelOpacity))
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1
                color: root.th.outlineVariant
            }

            // ---- Left: seal, workspaces, readings ----
            Row {
                anchors.left: parent.left; anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                spacing: 2

                // The seal is the launcher.
                Item {
                    visible: cfg.showLauncher
                    width: 30; height: 24
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: root.sealPath
                        sourceSize.width: 80; sourceSize.height: 80
                        smooth: true; mipmap: true
                        scale: sealMa.containsMouse ? 1.12 : 1.0
                        Behavior on scale { NumberAnimation { duration: root.th.tSnap; easing.type: Easing.OutQuint } }
                    }
                    MouseArea { id: sealMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleLauncher() }
                }

                BarSep { visible: cfg.showLauncher && cfg.showWorkspaces }

                Row {
                    visible: cfg.showWorkspaces
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: Hyprland.workspaces
                        Item {
                            id: wsBtn
                            property var ws: modelData
                            property bool isActive: Hyprland.focusedWorkspace
                                                    && Hyprland.focusedWorkspace.id === ws.id
                            // Show only the current desktop group: 1-10 on the home
                            // desktop, 11/12 on the END-key "other desktop".
                            visible: ws.id > 0
                                     && ((Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id >= 11)
                                         ? ws.id >= 11 : ws.id < 11)
                            width: 24; height: 24

                            // Active workspace: a small red seal behind the numeral.
                            Rectangle {
                                anchors.centerIn: parent
                                width: 20; height: 20; radius: 3
                                color: root.th.primary
                                opacity: wsBtn.isActive ? 1 : 0
                                scale: wsBtn.isActive ? 1 : 0.5
                                Behavior on opacity { NumberAnimation { duration: root.th.tSnap } }
                                Behavior on scale { NumberAnimation { duration: root.th.tSnap; easing.type: Easing.OutQuint } }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root.wsLabel(wsBtn.ws)
                                color: wsBtn.isActive ? root.th.primaryText
                                       : (wsMa.containsMouse ? root.th.surfaceText : root.th.outline)
                                font.family: root.th.body
                                font.pixelSize: root.th.fs(12)
                                font.weight: Font.Medium
                            }
                            MouseArea { id: wsMa; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Hyprland.dispatch("workspace " + wsBtn.ws.id) }
                        }
                    }
                }

                // Recording indicator; clicking it stops the capture.
                BarItem { visible: root.recording; glyph: "\uf111"; label: "REC"; fg: root.th.primary
                          onClick: function(){ root.recStop() } }

                BarSep { visible: cfg.showStats }
                BarItem { visible: cfg.showStats; glyph: "\uf2c9"; label: root.temp + "°" }
                BarItem { visible: cfg.showStats; glyph: "\uf2db"; label: root.cpu + "%" }
                BarItem { visible: cfg.showStats; glyph: root.ramGlyph; label: root.mem + "G" }
                BarItem { visible: cfg.showStats; glyph: "\uf0a0"; label: root.disk }
            }

            // ---- Centre: the time, set plain and large; date beside it ----
            Item {
                visible: cfg.showClock
                anchors.centerIn: parent
                width: clockRow.implicitWidth + 20
                height: 26
                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: root.th.surfaceContainerHigh
                    opacity: clockMa.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                Row {
                    id: clockRow
                    anchors.centerIn: parent
                    spacing: 10
                    Text { anchors.verticalCenter: parent.verticalCenter
                           text: root.clockH + ":" + root.clockM
                           color: root.th.surfaceText
                           font.family: root.th.display; font.pixelSize: root.th.fs(13)
                           font.weight: Font.Bold; font.letterSpacing: 0.5 }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter
                                width: 4; height: 4; radius: 1; color: root.th.primary }
                    Text { anchors.verticalCenter: parent.verticalCenter
                           text: root.clockLong
                           color: root.th.outline
                           font.family: root.th.body; font.pixelSize: root.th.fs(11) }
                }
                MouseArea { id: clockMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showOnly(calendarPanel) }
            }

            // ---- Right: media, windows, tray, controls ----
            Row {
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                spacing: 2

                BarItem { visible: cfg.showMedia && root.mediaText().length > 0
                          label: root.mediaText(); fg: root.th.tertiary
                          onClick: function(){ root.toggleMusic() } }

                // Taskbar: every open window, on every workspace and both
                // monitors. The system tray next to it only shows apps that
                // register a tray icon, which is a different and much smaller
                // set - nothing here depends on an app opting in.
                Item {
                    id: taskbar
                    visible: cfg.showTaskbar && root.winList.length > 0
                    height: 26
                    // Capped so a pile of windows clips at the left edge
                    // instead of shoving the controls off the bar.
                    width: Math.min(taskRow.implicitWidth, barWin.width * 0.30)
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true

                    Row {
                        id: taskRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Repeater {
                            model: root.winList
                            Item {
                                id: tbBtn
                                required property var modelData
                                width: 28
                                height: 26
                                readonly property bool isFocused: root.addrEq(modelData.addr, root.focusedAddr)
                                readonly property bool onThisWs:
                                    Hyprland.focusedWorkspace
                                    && Hyprland.focusedWorkspace.id === modelData.ws

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 4
                                    color: root.th.surfaceContainerHigh
                                    opacity: tbMa.containsMouse ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: -1
                                    implicitSize: 16
                                    source: root.classIcon(tbBtn.modelData.cls)
                                    // Focused is solid, elsewhere on this
                                    // workspace is near-solid, another
                                    // workspace or monitor fades back.
                                    opacity: tbBtn.isFocused ? 1.0 : (tbBtn.onThisWs ? 0.8 : 0.4)
                                    Behavior on opacity { NumberAnimation { duration: root.th.tSnap } }
                                }
                                // Red stroke under the focused window.
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: parent.height - 3
                                    height: 2; radius: 1
                                    width: tbBtn.isFocused ? 12 : 0
                                    color: root.th.primary
                                    Behavior on width {
                                        NumberAnimation { duration: root.th.tSnap; easing.type: Easing.OutQuint }
                                    }
                                }
                                MouseArea {
                                    id: tbMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: {
                                        barWin.tbHoverWin = tbBtn.modelData
                                        barWin.tbHoverX = tbBtn.mapToItem(null, tbBtn.width / 2, 0).x
                                        barWin.tbHoverOn = true
                                        // Moving onto a different icon dismisses
                                        // a menu left open by sliding sideways
                                        // out of the bar rather than into it.
                                        if (barWin.tbMenuOn && (!barWin.tbMenuWin
                                            || barWin.tbMenuWin.addr !== tbBtn.modelData.addr))
                                            barWin.closeTbMenu()
                                    }
                                    // Only the icon that owns the tooltip may
                                    // dismiss it, so crossing between two
                                    // adjacent icons doesn't blank it.
                                    onExited: if (barWin.tbHoverWin
                                                  && barWin.tbHoverWin.addr === tbBtn.modelData.addr)
                                        barWin.tbHoverOn = false
                                    onClicked: function (e) {
                                        if (e.button === Qt.RightButton) {
                                            barWin.tbMenuWin = tbBtn.modelData
                                            barWin.tbMenuX = tbBtn.mapToItem(null, tbBtn.width / 2, 0).x
                                            barWin.tbMenuOn = true
                                        } else {
                                            barWin.closeTbMenu()
                                            root.focusWin(tbBtn.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                BarSep { visible: taskbar.visible }

                // System tray. Hidden entirely once every item it holds is a
                // duplicate of a taskbar entry.
                Row {
                    visible: cfg.showTray && root.trayShownCount() > 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9
                    leftPadding: 6; rightPadding: 6
                    Repeater {
                        model: SystemTray.items
                        IconImage {
                            required property var modelData
                            // The app already has a window in the taskbar,
                            // so this icon would be a second copy of it.
                            // Row leaves no gap for an invisible child.
                            visible: !root.trayIsDup(modelData.id)
                            implicitSize: 15
                            source: modelData.icon
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function (e) {
                                    var it = parent.modelData
                                    if (e.button === Qt.LeftButton) { it.activate(); return }
                                    // Right click opens the app's own tray menu
                                    // (Quit, Open, ...). Without this an app that
                                    // hides in the tray, like Discord, has no
                                    // window on the bar and so no way to quit it.
                                    if (e.button === Qt.RightButton && it.hasMenu) {
                                        var pt = parent.mapToItem(null, 0, parent.height + 6)
                                        it.display(barWin, Math.round(pt.x), Math.round(pt.y))
                                        return
                                    }
                                    // Middle click, or no menu on offer: quit it
                                    // outright by the process that owns the icon.
                                    if (e.button === Qt.MiddleButton || !it.hasMenu) { root.quitTray(it); return }
                                    it.secondaryActivate()
                                }
                            }
                        }
                    }
                }

                BarItem {
                    visible: cfg.showBattery && root.hasBattery && root.batPct >= 0
                    glyph: root.batIcon(); label: "" + root.batPct
                    fg: root.batLow ? root.th.primary : root.th.onSurfaceVariant
                    onClick: function(){ root.toggleCC() }
                }
                BarItem { visible: cfg.showVolume
                          glyph: root.volIcon(); label: "" + root.sinkVol()
                          fg: root.sinkMuted() ? root.th.primary : root.th.onSurfaceVariant
                          onClick: function(){ root.showOnly(audioPanel) }
                          onScrollUp:   function(){ root.run("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+") }
                          onScrollDown: function(){ root.run("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") } }
                // Left click mutes the mic outright: the single most useful
                // thing to reach in a hurry. Scroll adjusts gain.
                BarItem { visible: cfg.showMic
                          glyph: root.srcMuted() ? "\uf131" : "\uf130"; label: "" + root.srcVol()
                          fg: root.srcMuted() ? root.th.primary : root.th.onSurfaceVariant
                          onClick: function(){ root.toggleMicMute() }
                          onScrollUp:   function(){ root.run("wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%+") }
                          onScrollDown: function(){ root.run("wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%-") } }
                BarItem { visible: cfg.showLayout; label: root.kbLayout
                          fg: root.kbLayout === "AR" ? root.th.surfaceText : root.th.onSurfaceVariant
                          onClick: function(){ root.run("hyprctl switchxkblayout all next") } }
                BarSep { visible: cfg.showPower }
                BarItem { visible: cfg.showPower; glyph: "\uf011"; fg: root.th.primary
                          onClick: function(){ root.togglePower() } }
            }

            // ---- Taskbar tooltip ----
            // The bar is 36px tall and clips its children, so anything that
            // hangs below it has to be its own surface.
            PopupWindow {
                id: tbTip
                anchor.window: barWin
                anchor.rect.x: barWin.tbClampX(barWin.tbHoverX, tbTip.width)
                anchor.rect.y: 0
                anchor.rect.width: tbTip.width
                anchor.rect.height: barWin.height
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
                // Suppressed while the menu is open so the two never stack.
                // The winMeta check drops it the moment its window goes away,
                // so quitting the last app can't leave a tooltip describing a
                // window that no longer exists.
                visible: barWin.tbHoverOn && !barWin.tbMenuOn && tipDelay.ready
                         && barWin.tbHoverWin !== null
                         && root.winMeta[barWin.tbHoverWin.addr] !== undefined
                color: "transparent"

                readonly property string tipCls: barWin.tbHoverWin ? barWin.tbHoverWin.cls : ""
                readonly property string tipTitle: {
                    if (!barWin.tbHoverWin) return ""
                    var m = root.winMeta[barWin.tbHoverWin.addr]
                    return m ? m.title : ""
                }

                // Width comes from measured text, not from the Column: binding
                // the popup to its content while the content is bound back to
                // the popup is a loop, and QML breaks it by collapsing to the
                // minimum, which elides every title.
                TextMetrics {
                    id: tipClsM
                    font.family: root.th.mono; font.pixelSize: root.th.fs(9)
                    font.letterSpacing: 1.0
                    text: tbTip.tipCls
                }
                TextMetrics {
                    id: tipTitleM
                    font.family: root.th.body; font.pixelSize: root.th.fs(12)
                    text: tbTip.tipTitle
                }
                implicitWidth: Math.min(380, Math.max(110, Math.ceil(
                    Math.max(tipClsM.width, tipTitleM.width)) + 26))
                // Top strip is transparent padding rather than an anchor
                // margin: anchor.rect is item-relative, and setting one field
                // of it collapses the rest to zero.
                implicitHeight: 4 + tipCol.implicitHeight + 18

                // A short delay keeps tooltips from strobing as the cursor
                // sweeps across the row.
                Timer {
                    id: tipDelay
                    property bool ready: false
                    interval: 400
                    onTriggered: ready = true
                }
                Connections {
                    target: barWin
                    function onTbHoverWinChanged() {
                        tipDelay.ready = false
                        if (barWin.tbHoverOn) tipDelay.restart()
                    }
                    function onTbHoverOnChanged() {
                        tipDelay.ready = false
                        if (barWin.tbHoverOn) tipDelay.restart(); else tipDelay.stop()
                    }
                }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.height - 4
                    radius: root.th.rSmall
                    color: root.th.raisedBg
                    border.width: 1
                    border.color: root.th.outlineVariant
                    Column {
                        id: tipCol
                        anchors.centerIn: parent
                        width: parent.width - 26
                        spacing: 1
                        Text {
                            width: parent.width
                            text: tbTip.tipCls
                            color: root.th.primary
                            font: tipClsM.font
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: tbTip.tipTitle
                            visible: text.length > 0
                            color: root.th.surfaceText
                            font: tipTitleM.font
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ---- Taskbar right-click menu ----
            PopupWindow {
                id: tbMenu
                anchor.window: barWin
                anchor.rect.x: barWin.tbClampX(barWin.tbMenuX, tbMenu.width)
                anchor.rect.y: 0
                anchor.rect.width: tbMenu.width
                anchor.rect.height: barWin.height
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
                // Closes itself if its window dies from somewhere else while
                // the menu is sitting open.
                visible: barWin.tbMenuOn && barWin.tbMenuWin !== null
                         && root.winMeta[barWin.tbMenuWin.addr] !== undefined
                color: "transparent"
                implicitWidth: 176
                // The top strip is deliberately transparent padding rather than
                // an anchor margin: a real gap would be a dead zone the cursor
                // has to cross, which would close the menu on the way in.
                implicitHeight: 8 + menuCard.implicitHeight

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: barWin.tbMenuHover = true
                    onExited: barWin.closeTbMenu()

                    Rectangle {
                        id: menuCard
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        implicitHeight: menuCol.implicitHeight + 12
                        radius: root.th.rSmall
                        color: root.th.raisedBg
                        border.width: 1
                        border.color: root.th.outlineVariant

                        Column {
                            id: menuCol
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 4

                            Text {
                                x: 12
                                width: parent.width - 24
                                text: barWin.tbMenuWin ? barWin.tbMenuWin.cls : ""
                                color: root.th.onSurfaceVariant
                                font.family: root.th.mono; font.pixelSize: root.th.fs(9)
                                font.letterSpacing: 1.0
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                x: 12; width: parent.width - 24; height: 1
                                color: root.th.outlineVariant
                            }
                            Rectangle {
                                x: 4
                                width: parent.width - 8
                                height: 30
                                radius: root.th.rSmall
                                color: quitMa.containsMouse ? root.th.errorContainer : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "  Quit"
                                    color: quitMa.containsMouse ? root.th.errorContainerText : root.th.error
                                    font.family: root.th.body; font.pixelSize: root.th.fs(12)
                                    font.weight: Font.Medium
                                }
                                MouseArea {
                                    id: quitMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.quitWin(barWin.tbMenuWin)
                                        barWin.closeTbMenu()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =====================================================================
    //  Notification popups
    // =====================================================================
    // Toasts drop from the middle of the bar, under the clock, as rounded
    // capsules: the app's initial in a disc, the message beside it, and a thin
    // line along the bottom that runs out as the toast's time does.
    PanelWindow {
        anchors { top: true }
        margins { top: 8 }
        implicitWidth: 480
        implicitHeight: Math.max(1, popupCol.implicitHeight)
        color: "transparent"
        exclusiveZone: 0
        visible: !cfg.dnd && notifServer.trackedNotifications.values.length > 0
        Column {
            id: popupCol
            width: parent.width
            spacing: 8
            Repeater {
                model: notifServer.trackedNotifications
                Rectangle {
                    id: toast
                    required property var modelData
                    // Compared as enum values. The old test turned the urgency
                    // into text and looked for the word "critical", but it prints
                    // as a number, so nothing was ever treated as critical.
                    readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                    // Urgent toasts (low battery, for one) get twice as long, then go.
                    readonly property int life: critical ? 10000
                        : (modelData.urgency === NotificationUrgency.Low ? 3000 : 5000)
                    readonly property string app: "" + (modelData.appName || "")
                    width: popupCol.width
                    implicitHeight: Math.max(56, msg.implicitHeight + 24)
                    height: implicitHeight
                    radius: 18
                    color: root.th.ink
                    border.width: 1
                    border.color: toast.critical ? root.th.primary : root.th.outlineVariant
                    clip: true

                    // Drop in from just above.
                    opacity: 0
                    transform: Translate { id: drop; y: -14 }
                    Component.onCompleted: { opacity = 1; drop.y = 0 }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on height { NumberAnimation { duration: 120 } }
                    NumberAnimation { target: drop; property: "y"; from: -14; to: 0
                                      duration: 260; easing.type: Easing.OutQuint; running: true }

                    // The app's initial.
                    Rectangle {
                        id: disc
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32; radius: 16
                        color: toast.critical ? root.th.primary : root.th.surfaceContainerHighest
                        Text {
                            anchors.centerIn: parent
                            text: toast.app.length > 0 ? toast.app.charAt(0).toUpperCase() : "•"
                            color: toast.critical ? root.th.primaryText : root.th.surfaceText
                            font.family: root.th.display; font.pixelSize: root.th.fs(13); font.weight: Font.Bold
                        }
                    }
                    Column {
                        id: msg
                        anchors { left: disc.right; right: parent.right; verticalCenter: parent.verticalCenter
                                  leftMargin: 12; rightMargin: 18 }
                        spacing: 1
                        Row {
                            width: parent.width
                            spacing: 8
                            Text { id: sumText
                                   width: Math.min(implicitWidth, parent.width - appText.width - 8)
                                   text: toast.modelData.summary || ""
                                   color: root.th.surfaceText; font.family: root.th.display
                                   font.pixelSize: root.th.fs(13); font.weight: Font.Bold
                                   elide: Text.ElideRight }
                            Text { id: appText
                                   anchors.baseline: sumText.baseline
                                   text: toast.app
                                   color: root.th.outline
                                   font.family: root.th.body; font.pixelSize: root.th.fs(9)
                                   visible: text.length > 0 }
                        }
                        Text { width: parent.width; text: toast.modelData.body || ""
                               color: root.th.onSurfaceVariant; font.family: root.th.body; font.pixelSize: root.th.fs(11)
                               wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                               visible: text.length > 0 }
                    }

                    // Time left.
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: 18
                        height: 2
                        radius: 1
                        color: toast.critical ? root.th.primary : root.th.outline
                        width: parent.width - 36
                        NumberAnimation on width { to: 0; duration: toast.life; running: true }
                    }

                    MouseArea { anchors.fill: parent; onClicked: toast.modelData.dismiss() }
                    Timer {
                        running: true
                        interval: toast.life
                        onTriggered: toast.modelData.dismiss()
                    }
                }
            }
        }
    }

    // =====================================================================
    //  Slide-in panel shell
    // =====================================================================
    // A black card that slides in from the right, under the bar.
    component SlidePanel: PanelWindow {
        id: win
        property bool shown: false
        default property alias content: inner.data
        property int panelWidth: 380
        anchors { top: true; bottom: true; right: true }
        margins { top: 10; bottom: 10; right: 10 }
        implicitWidth: panelWidth + 20
        color: "transparent"
        exclusiveZone: 0
        visible: shown || slideAnim.running

        // So content can stretch into whatever space is left over.
        readonly property int viewHeight: flick.height

        Rectangle {
            id: card
            width: win.panelWidth
            // Only as tall as its content, up to the full height available.
            height: Math.min(inner.implicitHeight + 40, parent.height)
            radius: root.th.rLarge
            color: Qt.rgba(root.th.ink.r, root.th.ink.g, root.th.ink.b,
                           Math.min(1.0, root.th.panelOpacity + 0.04))
            border.width: 1
            border.color: root.th.outlineVariant
            // Derived from panelWidth alone. Reading win.width here fed the
            // window's own width back into its content and produced a binding loop.
            x: win.shown ? 20 : (win.panelWidth + 40)
            opacity: win.shown ? 1 : 0
            Behavior on x       { NumberAnimation { id: slideAnim; duration: root.th.tPanel; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: root.th.tPanel; easing.type: Easing.OutQuint } }

            // Content scrolls when it outgrows the card.
            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                contentHeight: inner.implicitHeight + 40
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: inner
                    x: 20; y: 20
                    width: card.width - 40
                    spacing: 8
                }
            }

            // Scroll indicator, only while there is somewhere to scroll.
            Rectangle {
                visible: flick.interactive
                width: 3
                radius: 1.5
                color: root.th.outline
                opacity: flick.moving ? 0.9 : 0.35
                Behavior on opacity { NumberAnimation { duration: 200 } }
                x: card.width - 7
                height: Math.max(30, card.height * (flick.height / Math.max(1, flick.contentHeight)))
                y: (flick.contentY / Math.max(1, flick.contentHeight - flick.height))
                   * (card.height - height)
            }
        }
    }

    // =====================================================================
    //  Music panel
    // =====================================================================
    // A record deck along the bottom of the screen: the sleeve (cover art) on
    // the left with a black record sliding out from behind it and turning
    // while something plays, then the title, a long seek line and the
    // transport. It takes no keyboard focus and has no scrim, so it can stay
    // up while you work. SUPER+O opens and closes it.
    PanelWindow {
        id: musicPanel
        anchors { bottom: true }
        margins { bottom: 14 }
        implicitWidth: 820
        implicitHeight: 236
        color: "transparent"
        exclusiveZone: 0
        visible: root.musicOpen || deckAnim.running

        readonly property bool playing:
            !!(root.mp && root.mp.playbackState === MprisPlaybackState.Playing)
        readonly property bool hasArt: !!(root.mp && root.mp.trackArtUrl)

        Rectangle {
            id: deck
            width: 800
            height: 212
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.musicOpen ? 10 : musicPanel.implicitHeight + 10
            opacity: root.musicOpen ? 1 : 0
            Behavior on y       { NumberAnimation { id: deckAnim; duration: root.th.tPanel; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: root.th.tPanel; easing.type: Easing.OutQuint } }
            radius: root.th.rLarge + 4
            color: root.th.ink
            border.width: 1
            border.color: root.th.outlineVariant

            // ---- The record: slides out from behind the sleeve and turns ----
            Item {
                id: record
                width: 164; height: 164
                y: 24
                // Tucked mostly behind the sleeve when paused, drawn out when playing.
                x: musicPanel.playing ? 118 : 62
                Behavior on x { NumberAnimation { duration: root.th.tSlow; easing.type: Easing.OutQuint } }

                Item {
                    id: disc
                    anchors.fill: parent
                    RotationAnimation on rotation {
                        from: 0; to: 360
                        duration: 5200
                        loops: Animation.Infinite
                        running: musicPanel.playing && root.musicOpen
                    }
                    Rectangle { anchors.fill: parent; radius: width / 2; color: "#070707"
                                border.width: 1; border.color: root.th.outlineVariant }
                    // Grooves.
                    Repeater {
                        model: 6
                        Rectangle {
                            required property int index
                            anchors.centerIn: parent
                            width: 150 - index * 16; height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.07)
                        }
                    }
                    // A highlight wedge so the turning is visible on a black disc.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 6
                        width: 2; height: 44; radius: 1
                        color: Qt.rgba(1, 1, 1, 0.16)
                    }
                    // Red label with the seal at the centre.
                    Rectangle {
                        anchors.centerIn: parent
                        width: 56; height: 56; radius: 28
                        color: root.th.primary
                        Image {
                            anchors.centerIn: parent
                            width: 26; height: 26
                            source: root.sealPath
                            sourceSize.width: 104; sourceSize.height: 104
                            smooth: true; mipmap: true
                            opacity: 0.0
                        }
                        Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -12
                               text: "reouii"; color: root.th.primaryText
                               font.family: root.th.body; font.pixelSize: 7; font.weight: Font.Bold
                               font.letterSpacing: 0.6 }
                        Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 3.5
                                    color: root.th.ink }
                    }
                }
            }

            // ---- The sleeve: cover art, else the chosen GIF, else blank ----
            Rectangle {
                id: sleeve
                x: 24; y: 24
                width: 164; height: 164
                radius: root.th.r
                color: root.th.surfaceContainerHigh
                border.width: 1
                border.color: root.th.outlineVariant
                clip: true

                GifView {
                    anchors.fill: parent
                    th: root.th
                    source: (root.hasGif && root.musicOpen && !musicPanel.hasArt) ? root.gifUrl : ""
                    zoom: gifState.zoom
                    offsetX: gifState.offsetX
                    offsetY: gifState.offsetY
                    playing: root.musicOpen
                    visible: !musicPanel.hasArt && root.hasGif
                }
                Image {
                    anchors.fill: parent
                    source: musicPanel.hasArt ? root.mp.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: musicPanel.hasArt && status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !musicPanel.hasArt && !root.hasGif
                    text: "\uf001"
                    color: root.th.outlineVariant
                    font.family: root.iconFont; font.pixelSize: 44
                }
            }

            // ---- Right side: what is playing, and the controls ----
            Item {
                id: info
                x: 304
                y: 22
                width: deck.width - x - 24
                height: deck.height - 44

                // Source line: which player, or a switcher when there is a choice.
                Row {
                    id: sources
                    spacing: 6
                    height: 22
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 2; color: root.th.primary
                    }
                    Item { width: 4; height: 1 }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.players.length <= 1
                        text: root.mp ? ("" + (root.mp.identity || "Player")) : "Nothing playing"
                        color: root.th.outline
                        font.family: root.th.body; font.pixelSize: root.th.fs(10); font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: root.players.length > 1 ? root.players : []
                        Rectangle {
                            required property var modelData
                            readonly property bool sel:
                                !!(root.mp && ("" + root.mp.dbusName) === ("" + modelData.dbusName))
                            anchors.verticalCenter: parent.verticalCenter
                            height: 22
                            width: Math.min(130, plabel.implicitWidth + 18)
                            radius: root.th.rSmall
                            color: sel ? root.th.surfaceText : root.th.surfaceContainerHigh
                            Text {
                                id: plabel
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, 112)
                                text: "" + (modelData.identity || "player")
                                color: parent.sel ? root.th.surface : root.th.onSurfaceVariant
                                font.family: root.th.body; font.pixelSize: root.th.fs(9); font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                // Clicking the pinned one unpins, back to "whatever plays".
                                onClicked: {
                                    var n = "" + modelData.dbusName
                                    root.preferredPlayer = (root.preferredPlayer === n) ? "" : n
                                }
                            }
                        }
                    }
                }
                // Close.
                Rectangle {
                    anchors.right: parent.right
                    width: 24; height: 24; radius: root.th.rSmall
                    color: mcloseMa.containsMouse ? root.th.surfaceText : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"
                           color: mcloseMa.containsMouse ? root.th.surface : root.th.outline
                           font.family: root.th.body; font.pixelSize: root.th.fs(11) }
                    MouseArea { id: mcloseMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.musicOpen = false }
                }

                Text {
                    id: mTitle
                    y: 32
                    width: parent.width
                    text: root.mp ? (root.mp.trackTitle || "Nothing playing") : "Nothing playing"
                    color: root.th.surfaceText
                    font.family: root.th.display
                    font.pixelSize: root.th.fs(19); font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Text {
                    y: mTitle.y + mTitle.height + 1
                    width: parent.width
                    text: root.mp ? (root.mp.trackArtist || "") : ""
                    color: root.th.onSurfaceVariant
                    font.family: root.th.body; font.pixelSize: root.th.fs(12)
                    elide: Text.ElideRight
                }

                // Seek line with the times at either end.
                Text { id: tNow; y: 98; text: root.fmt(root.mpPos); color: root.th.outline
                       font.family: root.th.mono; font.pixelSize: root.th.fs(9) }
                Text { id: tEnd; y: 98; anchors.right: parent.right
                       text: root.fmt(root.mp ? root.mp.length : 0); color: root.th.outline
                       font.family: root.th.mono; font.pixelSize: root.th.fs(9) }
                Slider {
                    id: seek
                    y: 91
                    x: 42
                    width: parent.width - 84
                    height: 26
                    from: 0
                    to: (root.mp && root.mp.length > 0) ? root.mp.length : 1
                    value: root.mpPos
                    enabled: !!(root.mp && root.mp.canSeek)
                    onMoved: { if (root.mp && root.mp.canSeek) root.mp.position = value }
                    background: Rectangle {
                        x: seek.leftPadding
                        y: seek.topPadding + seek.availableHeight / 2 - height / 2
                        width: seek.availableWidth; height: 3; radius: 1.5
                        color: root.th.outlineVariant
                        Rectangle { width: seek.visualPosition * parent.width; height: parent.height
                                    radius: 1.5; color: root.th.surfaceText }
                    }
                    handle: Rectangle {
                        x: seek.leftPadding + seek.visualPosition * (seek.availableWidth - width)
                        y: seek.topPadding + seek.availableHeight / 2 - height / 2
                        width: 10; height: 10; radius: 5
                        color: seek.pressed ? root.th.primary : root.th.surfaceText
                        visible: seek.enabled
                    }
                }

                // Transport on the left, this app's own volume on the right.
                Row {
                    y: parent.height - 40
                    spacing: 14
                    Item {
                        width: 34; height: 40
                        Text { anchors.centerIn: parent; text: "\uf048"
                               color: prevMa.containsMouse ? root.th.surfaceText : root.th.onSurfaceVariant
                               font.family: root.iconFont; font.pixelSize: root.th.fs(14) }
                        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: root.mpPrev() }
                    }
                    Rectangle {
                        width: 40; height: 40; radius: 20
                        color: playMa.containsMouse ? root.th.primary : root.th.surfaceText
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { anchors.centerIn: parent
                               anchors.horizontalCenterOffset: musicPanel.playing ? 0 : 1
                               text: musicPanel.playing ? "\uf04c" : "\uf04b"
                               color: playMa.containsMouse ? root.th.primaryText : root.th.surface
                               font.family: root.iconFont; font.pixelSize: root.th.fs(13) }
                        MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: root.mpToggle() }
                    }
                    Item {
                        width: 34; height: 40
                        Text { anchors.centerIn: parent; text: "\uf051"
                               color: nextMa.containsMouse ? root.th.surfaceText : root.th.onSurfaceVariant
                               font.family: root.iconFont; font.pixelSize: root.th.fs(14) }
                        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: root.mpNext() }
                    }
                }

                // Volume of the playing app only; never the system volume.
                Item {
                    id: appVol
                    readonly property bool ok: !!(root.mpNode && root.mpNode.audio)
                    readonly property int pct: ok ? Math.round(root.mpNode.audio.volume * 100) : 0
                    anchors.right: parent.right
                    y: parent.height - 40
                    width: 190; height: 40
                    opacity: ok ? 1 : 0.35
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf028"
                           color: root.th.onSurfaceVariant
                           font.family: root.iconFont; font.pixelSize: root.th.fs(12) }
                    Slider {
                        id: av
                        anchors.verticalCenter: parent.verticalCenter
                        x: 24
                        width: parent.width - 24 - 34
                        height: 26
                        from: 0; to: 100
                        value: appVol.pct
                        enabled: appVol.ok
                        onMoved: if (appVol.ok) root.mpNode.audio.volume = Math.max(0, Math.min(1, value / 100))
                        background: Rectangle {
                            x: av.leftPadding
                            y: av.topPadding + av.availableHeight / 2 - height / 2
                            width: av.availableWidth; height: 3; radius: 1.5
                            color: root.th.outlineVariant
                            Rectangle { width: av.visualPosition * parent.width; height: parent.height
                                        radius: 1.5; color: root.th.surfaceText }
                        }
                        handle: Rectangle {
                            x: av.leftPadding + av.visualPosition * (av.availableWidth - width)
                            y: av.topPadding + av.availableHeight / 2 - height / 2
                            width: 10; height: 10; radius: 5
                            color: av.pressed ? root.th.primary : root.th.surfaceText
                        }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right
                           width: 30; horizontalAlignment: Text.AlignRight
                           text: appVol.ok ? appVol.pct : "–"
                           color: root.th.outline
                           font.family: root.th.mono; font.pixelSize: root.th.fs(9) }
                }
            }
        }
    }

    // =====================================================================
    //  Control Center
    // =====================================================================
    // A wide dashboard in the middle of the screen, laid out as a grid of
    // tiles rather than a tall list down one side: switches are icon tiles,
    // volume and brightness are upright bars you drag, and notifications sit
    // in their own tile. SUPER+N opens it; Esc or a click outside closes it.

    // One switch: icon on the left, name and state on the right.
    component Quick: Rectangle {
        id: q
        property string glyph: ""
        property string label: ""
        property string sub: ""
        property bool active: false
        property bool alert: false
        property var onClick: null
        radius: root.th.rLarge
        color: active ? root.th.surfaceText
                      : (qMa.containsMouse ? root.th.surfaceContainerHighest : root.th.surfaceContainerHigh)
        Behavior on color { ColorAnimation { duration: 140 } }

        Text {
            id: qGlyph
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            horizontalAlignment: Text.AlignHCenter
            text: q.glyph
            color: q.alert ? root.th.primary : (q.active ? root.th.surface : root.th.surfaceText)
            font.family: root.iconFont
            font.pixelSize: root.th.fs(17)
        }
        Column {
            x: 50
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 10
            spacing: 0
            Text { width: parent.width; text: q.label
                   color: q.active ? root.th.surface : root.th.surfaceText
                   font.family: root.th.body; font.pixelSize: root.th.fs(12); font.weight: Font.DemiBold
                   elide: Text.ElideRight }
            Text { width: parent.width; text: q.sub; visible: text.length > 0
                   color: q.active ? root.th.surfaceContainerHighest : root.th.outline
                   font.family: root.th.body; font.pixelSize: root.th.fs(9)
                   elide: Text.ElideRight }
        }
        MouseArea { id: qMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (q.onClick) q.onClick() }
    }

    // An upright bar: drag or scroll to set, figure on top, icon at the foot.
    component VBar: Item {
        id: vb
        property string glyph: ""
        property string label: ""
        property int pct: 0
        property bool muted: false
        property var onChange: null
        property var onIcon: null
        width: 46

        Text {
            id: vbPct
            anchors.horizontalCenter: parent.horizontalCenter
            text: vb.pct
            color: vb.muted ? root.th.primary : root.th.surfaceText
            font.family: root.th.display; font.pixelSize: root.th.fs(12); font.weight: Font.Bold
        }
        Rectangle {
            id: vbTrack
            anchors.horizontalCenter: parent.horizontalCenter
            y: vbPct.height + 6
            width: 34
            height: parent.height - y - 40
            radius: root.th.rLarge
            color: root.th.surfaceContainerHighest
            clip: true
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Math.max(0, Math.min(1, vb.pct / 100)) * parent.height
                color: vb.muted ? root.th.outline : root.th.surfaceText
                Behavior on height { NumberAnimation { duration: 90 } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeVerCursor
                function setFrom(my) {
                    var v = Math.round((1 - Math.max(0, Math.min(1, my / height))) * 100)
                    if (vb.onChange) vb.onChange(v)
                }
                onPressed: function (m) { setFrom(m.y) }
                onPositionChanged: function (m) { if (pressed) setFrom(m.y) }
                onWheel: function (w) {
                    var v = Math.max(0, Math.min(100, vb.pct + (w.angleDelta.y > 0 ? 5 : -5)))
                    if (vb.onChange) vb.onChange(v)
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: vbTrack.y + vbTrack.height + 6
            text: vb.glyph
            color: vb.muted ? root.th.primary : root.th.onSurfaceVariant
            font.family: root.iconFont; font.pixelSize: root.th.fs(13)
            MouseArea { anchors.fill: parent; anchors.margins: -6
                        cursorShape: vb.onIcon ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (vb.onIcon) vb.onIcon() }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: vb.label
            color: root.th.outline
            font.family: root.th.body; font.pixelSize: root.th.fs(9)
        }
    }

    // Small icon-over-word button for the foot of the dashboard.
    component FootBtn: Rectangle {
        id: fb
        property string glyph: ""
        property string label: ""
        property bool danger: false
        property var onClick: null
        height: 40
        radius: root.th.r
        color: fbMa.containsMouse ? root.th.surfaceText : root.th.surfaceContainerHigh
        Behavior on color { ColorAnimation { duration: 120 } }
        Row {
            anchors.centerIn: parent
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: fb.glyph
                   color: fbMa.containsMouse ? root.th.surface : (fb.danger ? root.th.primary : root.th.onSurfaceVariant)
                   font.family: root.iconFont; font.pixelSize: root.th.fs(12) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: fb.label
                   color: fbMa.containsMouse ? root.th.surface : root.th.onSurfaceVariant
                   font.family: root.th.body; font.pixelSize: root.th.fs(11); font.weight: Font.DemiBold }
        }
        MouseArea { id: fbMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (fb.onClick) fb.onClick() }
    }

    PanelWindow {
        id: ccPanel
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusiveZone: 0
        focusable: true
        visible: root.ccOpen || ccFade.running

        readonly property int pad: 16
        readonly property int gap: 10
        readonly property int innerW: 868
        readonly property int rowA: 148
        readonly property int rowB: 232
        readonly property int rowC: 40

        function shut() { root.ccOpen = false }
        function go(panel) { root.ccOpen = false; root.showOnly(panel) }

        Connections {
            target: root
            function onCcOpenChanged() { if (root.ccOpen) ccKeys.forceActiveFocus() }
        }

        Rectangle {
            anchors.fill: parent
            color: root.th.scrim
            opacity: root.ccOpen ? 0.75 : 0
            Behavior on opacity { NumberAnimation { id: ccFade; duration: root.th.tPanel; easing.type: Easing.OutQuint } }
            MouseArea { anchors.fill: parent; onClicked: ccPanel.shut() }
        }

        FocusScope {
            id: ccKeys
            anchors.fill: parent
            focus: root.ccOpen
            Keys.onPressed: function (e) {
                if (e.key === Qt.Key_Escape) { ccPanel.shut(); e.accepted = true }
            }

            Rectangle {
                id: dash
                width: ccPanel.innerW + ccPanel.pad * 2
                height: ccPanel.pad * 2 + ccPanel.rowA + ccPanel.rowB + ccPanel.rowC + ccPanel.gap * 2
                anchors.centerIn: parent
                radius: root.th.rLarge + 4
                color: root.th.ink
                border.width: 1
                border.color: root.th.outlineVariant

                opacity: root.ccOpen ? 1 : 0
                scale: root.ccOpen ? 1 : 0.97
                Behavior on opacity { NumberAnimation { duration: root.th.tPanel; easing.type: Easing.OutQuint } }
                Behavior on scale   { NumberAnimation { duration: root.th.tPanel; easing.type: Easing.OutQuint } }

                // Swallow clicks so the scrim's close handler doesn't fire through.
                MouseArea { anchors.fill: parent }

                // ============ Row A: who/when, and the switches ============
                Rectangle {
                    id: idTile
                    x: ccPanel.pad; y: ccPanel.pad
                    width: 270; height: ccPanel.rowA
                    radius: root.th.rLarge
                    color: root.th.surfaceContainerHigh
                    clip: true

                    GifView {
                        anchors.fill: parent
                        th: root.th
                        source: (root.hasGif && root.ccOpen) ? root.gifUrl : ""
                        zoom: gifState.zoom
                        offsetX: gifState.offsetX
                        offsetY: gifState.offsetY
                        playing: root.ccOpen
                        visible: root.hasGif
                        dim: 0.85
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: root.hasGif
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#30000000" }
                            GradientStop { position: 0.55; color: "#70000000" }
                            GradientStop { position: 1.0; color: "#E0000000" }
                        }
                    }
                    Column {
                        x: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 12
                        spacing: -2
                        Text { text: root.clockH + ":" + root.clockM
                               color: root.hasGif ? "#ffffff" : root.th.surfaceText
                               font.family: root.th.display; font.pixelSize: root.th.fs(30); font.weight: Font.Bold }
                        Text { text: root.dateText
                               color: root.hasGif ? "#e0e0e0" : root.th.onSurfaceVariant
                               font.family: root.th.body; font.pixelSize: root.th.fs(11) }
                    }
                    Row {
                        x: 16; y: 12
                        spacing: 8
                        Image { width: 20; height: 20; source: root.sealPath
                                sourceSize.width: 80; sourceSize.height: 80; smooth: true; mipmap: true }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "reouii"
                               color: root.hasGif ? "#ffffff" : root.th.surfaceText
                               font.family: root.th.body; font.pixelSize: root.th.fs(12); font.weight: Font.DemiBold }
                    }
                    Text {
                        visible: root.hasBattery && root.batPct >= 0
                        anchors.right: parent.right; anchors.rightMargin: 14
                        y: 14
                        text: root.batIcon() + "  " + root.batPct + "%"
                        color: root.batLow ? root.th.primary : (root.hasGif ? "#ffffff" : root.th.onSurfaceVariant)
                        font.family: root.th.mono; font.pixelSize: root.th.fs(11)
                    }
                }

                Grid {
                    id: quickGrid
                    x: idTile.x + idTile.width + ccPanel.gap
                    y: ccPanel.pad
                    width: ccPanel.innerW - idTile.width - ccPanel.gap
                    columns: 4
                    spacing: ccPanel.gap
                    readonly property real cw: (width - ccPanel.gap * 3) / 4
                    readonly property real ch: (ccPanel.rowA - ccPanel.gap) / 2

                    Quick { width: quickGrid.cw; height: quickGrid.ch
                            glyph: "\uf1eb"; label: "Wi-Fi"
                            sub: root.wifiSsid.length > 0 ? root.wifiSsid : "Off"
                            active: root.wifiSsid.length > 0
                            onClick: function(){ ccPanel.go(wifiPanel) } }
                    Quick { width: quickGrid.cw; height: quickGrid.ch
                            glyph: "\uf294"; label: "Bluetooth"
                            sub: root.btOn() ? "On" : "Off"
                            active: root.btOn()
                            onClick: function(){ ccPanel.go(btPanel) } }
                    Quick { width: quickGrid.cw; height: quickGrid.ch
                            glyph: cfg.dnd ? "\uf1f6" : "\uf0f3"; label: "Silent"
                            sub: cfg.dnd ? "Notifications hidden" : "Off"
                            active: cfg.dnd
                            onClick: function(){ cfg.set("dnd", !cfg.dnd) } }
                    Quick { width: quickGrid.cw; height: quickGrid.ch
                            glyph: root.srcMuted() ? "\uf131" : "\uf130"; label: "Mic"
                            sub: root.srcMuted() ? "Muted" : "Live " + root.srcVol() + "%"
                            active: !root.srcMuted()
                            onClick: function(){ root.toggleMicMute() } }
                    Quick { width: quickGrid.cw; height: quickGrid.ch
                            glyph: "\uf186"; label: "Night light"
                            sub: cfg.nightTemp > 0 ? cfg.nightTemp + " K" : "Off"
                            active: cfg.nightTemp > 0
                            // Steps through off, mild, warm, amber.
                            onClick: function(){
                                var s = [0, 5000, 4000, 3000]
                                var i = s.indexOf(cfg.nightTemp)
                                root.setNight(s[(i + 1) % s.length])
                            } }
                    Quick { width: quickGrid.cw; height: quickGrid.ch
                            glyph: "\uf111"; label: root.recording ? "Stop" : "Record"
                            sub: root.recording ? "Recording now" : "Pick an area"
                            active: root.recording; alert: root.recording
                            onClick: function(){ if (root.recording) root.recStop()
                                                 else { ccPanel.shut(); root.recStart(true) } } }
                    Quick { width: quickGrid.cw; height: quickGrid.ch
                            glyph: "\uf108"; label: "Full screen"
                            sub: "Record the monitor"
                            onClick: function(){ if (!root.recording) { ccPanel.shut(); root.recStart(false) } } }
                    Quick { width: quickGrid.cw; height: quickGrid.ch
                            glyph: "\uf11c"; label: "Shortcuts"
                            sub: "Key cheatsheet"
                            onClick: function(){ ccPanel.go(cheatsheet) } }
                }

                // ============ Row B: bars, power, notifications ============
                Rectangle {
                    id: barsTile
                    x: ccPanel.pad
                    y: ccPanel.pad + ccPanel.rowA + ccPanel.gap
                    width: 178; height: ccPanel.rowB
                    radius: root.th.rLarge
                    color: root.th.surfaceContainerHigh

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 14
                        height: parent.height - 28
                        spacing: root.briHasExt && !root.briSync ? 6 : 22

                        VBar { height: parent.height
                               glyph: root.volIcon(); label: "Volume"
                               pct: root.sinkVol(); muted: root.sinkMuted()
                               onChange: function(v){ root.setSinkVol(v) }
                               onIcon: function(){ if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted } }
                        VBar { height: parent.height
                               glyph: "\uf185"
                               label: (root.briHasExt && !root.briSync) ? "Laptop" : "Screen"
                               pct: root.briPct
                               onChange: function(v){ if (root.briHasExt && root.briSync) root.setBriBoth(v); else root.setBriLaptop(v) }
                               // With a second screen attached, the sun toggles "move together".
                               onIcon: root.briHasExt ? function(){ root.toggleBriSync() } : null }
                        VBar { height: parent.height
                               visible: root.briHasExt && !root.briSync
                               glyph: "\uf108"; label: "Monitor"
                               pct: root.briExt
                               onChange: function(v){ root.setBriExt(v) } }
                    }
                }

                Rectangle {
                    id: powerTile
                    x: barsTile.x + barsTile.width + ccPanel.gap
                    y: barsTile.y
                    width: 196; height: ccPanel.rowB
                    radius: root.th.rLarge
                    color: root.th.surfaceContainerHigh

                    Text { x: 14; y: 12; text: "Power"
                           color: root.th.outline
                           font.family: root.th.body; font.pixelSize: root.th.fs(10); font.weight: Font.DemiBold }
                    Column {
                        x: 10; y: 36
                        width: parent.width - 20
                        spacing: 6
                        Repeater {
                            model: [ { g: "\uf06c", l: "Eco",      n: "Longest battery", v: "eco" },
                                     { g: "\uf24e", l: "Balanced", n: "Everyday",        v: "balanced" },
                                     { g: "\uf0e7", l: "Turbo",    n: "Full speed",      v: "performance" } ]
                            Rectangle {
                                id: pRow
                                required property var modelData
                                readonly property bool on: root.powerProfile === modelData.v
                                width: parent.width
                                height: 56
                                radius: root.th.r
                                color: on ? root.th.surfaceText
                                          : (pMa.containsMouse ? root.th.surfaceContainerHighest : root.th.surfaceContainer)
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Text { x: 14; anchors.verticalCenter: parent.verticalCenter
                                       width: 20; horizontalAlignment: Text.AlignHCenter
                                       text: pRow.modelData.g
                                       color: pRow.on ? root.th.primary : root.th.onSurfaceVariant
                                       font.family: root.iconFont; font.pixelSize: root.th.fs(14) }
                                Column {
                                    x: 46; anchors.verticalCenter: parent.verticalCenter
                                    Text { text: pRow.modelData.l
                                           color: pRow.on ? root.th.surface : root.th.surfaceText
                                           font.family: root.th.body; font.pixelSize: root.th.fs(12); font.weight: Font.DemiBold }
                                    Text { text: pRow.modelData.n
                                           color: pRow.on ? root.th.surfaceContainerHighest : root.th.outline
                                           font.family: root.th.body; font.pixelSize: root.th.fs(9) }
                                }
                                MouseArea { id: pMa; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setPowerProfile(pRow.modelData.v) }
                            }
                        }
                    }
                }

                Rectangle {
                    id: notifTile
                    x: powerTile.x + powerTile.width + ccPanel.gap
                    y: barsTile.y
                    width: ccPanel.innerW - barsTile.width - powerTile.width - ccPanel.gap * 2
                    height: ccPanel.rowB
                    radius: root.th.rLarge
                    color: root.th.surfaceContainerHigh

                    Text { x: 14; y: 12
                           text: "Notifications" + (histModel.count > 0 ? "  " + histModel.count : "")
                           color: root.th.outline
                           font.family: root.th.body; font.pixelSize: root.th.fs(10); font.weight: Font.DemiBold }
                    Text {
                        visible: histModel.count > 0
                        anchors.right: parent.right; anchors.rightMargin: 14
                        y: 12
                        text: "Clear"
                        color: clearMa.containsMouse ? root.th.primary : root.th.onSurfaceVariant
                        font.family: root.th.body; font.pixelSize: root.th.fs(10); font.weight: Font.DemiBold
                        MouseArea { id: clearMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: histModel.clear() }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: histModel.count === 0
                        text: "Nothing new"
                        color: root.th.outline
                        font.family: root.th.body; font.pixelSize: root.th.fs(12)
                    }
                    ListView {
                        x: 10; y: 36
                        width: parent.width - 20
                        height: parent.height - 46
                        clip: true
                        spacing: 6
                        model: histModel
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            width: ListView.view.width
                            radius: root.th.r
                            color: root.th.surfaceContainer
                            implicitHeight: nc.implicitHeight + 14
                            height: implicitHeight
                            Rectangle { x: 8; y: 9; width: 2; height: parent.height - 18; color: root.th.primary }
                            Column {
                                id: nc
                                x: 18; y: 7
                                width: parent.width - 28
                                spacing: 1
                                Row {
                                    width: parent.width
                                    Text { text: model.hApp; color: root.th.outline
                                           font.family: root.th.body; font.pixelSize: root.th.fs(9)
                                           width: parent.width - 62; elide: Text.ElideRight }
                                    Text { text: model.hTime; color: root.th.outline
                                           font.family: root.th.mono; font.pixelSize: root.th.fs(9)
                                           width: 62; horizontalAlignment: Text.AlignRight }
                                }
                                Text { width: parent.width; text: model.hSummary; color: root.th.surfaceText
                                       font.family: root.th.body; font.pixelSize: root.th.fs(12); font.weight: Font.DemiBold
                                       wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                                Text { width: parent.width; text: model.hBody; color: root.th.onSurfaceVariant
                                       font.family: root.th.body; font.pixelSize: root.th.fs(11)
                                       wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                                       visible: text.length > 0 }
                            }
                        }
                    }
                }

                // ============ Row C: where to go next ============
                Row {
                    id: footRow
                    x: ccPanel.pad
                    y: barsTile.y + ccPanel.rowB + ccPanel.gap
                    width: ccPanel.innerW
                    spacing: ccPanel.gap
                    readonly property real bw: (width - ccPanel.gap * 6) / 7

                    FootBtn { width: footRow.bw; glyph: "\uf1fc"; label: "Colours"
                              onClick: function(){ ccPanel.go(colourPicker) } }
                    FootBtn { width: footRow.bw; glyph: "\uf03e"; label: "Wallpaper"
                              onClick: function(){ ccPanel.go(wallPicker) } }
                    FootBtn { width: footRow.bw; glyph: "\uf008"; label: "GIF"
                              onClick: function(){ ccPanel.go(gifPicker) } }
                    FootBtn { width: footRow.bw; glyph: "\uf120"; label: "Fastfetch"
                              onClick: function(){ ccPanel.go(fetchPicker) } }
                    FootBtn { width: footRow.bw; glyph: "\uf028"; label: "Sound"
                              onClick: function(){ ccPanel.go(audioPanel) } }
                    FootBtn { width: footRow.bw; glyph: "\uf013"; label: "Settings"
                              onClick: function(){ ccPanel.go(settingsPanel) } }
                    FootBtn { width: footRow.bw; glyph: "\uf011"; label: "Power"; danger: true
                              onClick: function(){ ccPanel.shut(); root.togglePower() } }
                }
            }
        }
    }
}

// Design tokens for the shell.
//
// Colours are a full Material 3 role set generated from the current wallpaper
// by ~/.config/themes/bin/gen-colors.py and written to colors.json. Changing the
// wallpaper rewrites that file; watchChanges below means the whole shell
// recolours live, with no restart and nothing to pick by hand.
//
// Using the real M3 roles (primary / secondary / tertiary + container pairs) is
// deliberate: a single accent is what made the first version read as one flat
// colour.
import QtQuick
import Quickshell.Io

QtObject {
    id: t

    // "dark" or "light" — driven by Config.
    property string scheme: "dark"
    // Multiplies every panel's background alpha. 1.0 = opaque.
    property real panelOpacity: 1.0
    // Scales every animation duration. 0 disables motion.
    property real motion: 1.0

    property var raw: ({})
    readonly property var c: (raw && raw[scheme]) ? raw[scheme] : ({})
    readonly property string sourceColor: raw && raw.source ? raw.source : "#88c0d0"
    readonly property bool isDark: scheme === "dark"

    property FileView file: FileView {
        path: "/home/reouii/.config/quickshell/colors.json"
        watchChanges: true
        blockLoading: true          // have colours on the very first frame
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { t.raw = JSON.parse(text()) } catch (e) { /* keep last good scheme */ }
        }
    }

    function role(name, fallback) {
        var v = c ? c[name] : undefined
        return (v !== undefined && v !== null && ("" + v).length > 0) ? v : fallback
    }

    // ---- Material 3 roles ----
    // NOTE: the "on<Role>" colours are declared as <role>Text, not their M3
    // names. QML silently DROPS the initialiser binding for a property called
    // `onX` when a sibling property `X` exists — `onSurface` alongside
    // `surface`, `onPrimary` alongside `primary`, and so on — so every one of
    // them read back as #000000 and every piece of text drawn in them was
    // black. onSurfaceVariant was the single survivor, because there is no
    // `surfaceVariant` property for it to collide with; it keeps its M3 name.
    // Do not rename these back, and do not add an `on`-prefixed property.
    readonly property color primary:                role("primary",            "#bad06c")
    readonly property color primaryText:            role("onPrimary",          "#293500")
    readonly property color primaryContainer:       role("primaryContainer",   "#3d4d00")
    readonly property color primaryContainerText:   role("onPrimaryContainer", "#d6ec86")

    readonly property color secondary:              role("secondary",            "#c5c9af")
    readonly property color secondaryText:          role("onSecondary",          "#2e3220")
    readonly property color secondaryContainer:     role("secondaryContainer",   "#444935")
    readonly property color secondaryContainerText: role("onSecondaryContainer", "#e1e5ca")

    readonly property color tertiary:               role("tertiary",            "#80d6c1")
    readonly property color tertiaryText:           role("onTertiary",          "#00382e")
    readonly property color tertiaryContainer:      role("tertiaryContainer",   "#005143")
    readonly property color tertiaryContainerText:  role("onTertiaryContainer", "#9cf2dd")

    readonly property color error:                  role("error",            "#ffb4ab")
    readonly property color errorText:              role("onError",          "#690005")
    readonly property color errorContainer:         role("errorContainer",   "#93000a")
    readonly property color errorContainerText:     role("onErrorContainer", "#ffdad6")

    readonly property color background:             role("background", "#131409")
    readonly property color backgroundText:         role("onBackground", "#e2e4d8")
    readonly property color surface:                role("surface", "#131409")
    readonly property color surfaceText:            role("onSurface", "#e2e4d8")
    readonly property color onSurfaceVariant:       role("onSurfaceVariant", "#c6c8b6")

    readonly property color surfaceContainerLowest:  role("surfaceContainerLowest",  "#0e0f06")
    readonly property color surfaceContainerLow:     role("surfaceContainerLow",     "#1b1d11")
    readonly property color surfaceContainer:        role("surfaceContainer",        "#1f2018")
    readonly property color surfaceContainerHigh:    role("surfaceContainerHigh",    "#292b22")
    readonly property color surfaceContainerHighest: role("surfaceContainerHighest", "#34362c")

    readonly property color outline:        role("outline",        "#8f937e")
    readonly property color outlineVariant: role("outlineVariant", "#44483a")
    readonly property color inverseSurface: role("inverseSurface", "#e2e4d8")
    readonly property color inversePrimary: role("inversePrimary", "#556500")

    // ---- Aliases used across the panels ----
    // Named by what they do rather than what colour they are, so a wallpaper
    // change never makes a name a lie (the old "brass" is exactly that trap).
    readonly property color ink:      surfaceContainerLowest
    readonly property color panel:    surfaceContainer
    readonly property color raised:   surfaceContainerHigh
    readonly property color hover:    surfaceContainerHighest
    readonly property color hairline: outlineVariant
    readonly property color spine:    outline
    readonly property color text:     surfaceText
    readonly property color dim:      onSurfaceVariant
    // Lowest-emphasis TEXT still has to be readable, so it uses the text role
    // rather than `outline`, which is Material's border colour and too dim to
    // read against a dark surface. Hierarchy comes from size and weight instead.
    readonly property color faint:    onSurfaceVariant
    readonly property color accent:   primary
    readonly property color accentDim: primaryContainer
    readonly property color signal:   error
    readonly property color scrim:    isDark ? Qt.rgba(0, 0, 0, 0.72)
                                             : Qt.rgba(surfaceText.r, surfaceText.g, surfaceText.b, 0.42)

    // ---- Paper-cut look ----
    // Every surface is a flat sheet with an ink outline and a hard, offset
    // shadow, like cut paper laid on a table. No blur, no rounding.
    readonly property color edge:   surfaceText                 // ink outline
    readonly property int   edgeW:  2
    readonly property color cutShadow: isDark ? Qt.rgba(0, 0, 0, 0.55)
                                              : Qt.rgba(surfaceText.r, surfaceText.g, surfaceText.b, 0.88)
    readonly property int   cut:    6                           // shadow offset, px
    // Accent for use ON an ink block (reverse print), whichever scheme is on.
    readonly property color accentOnInk: inversePrimary

    // ---- Rail ----
    // The rail is always ink, even on the paper (light) scheme: a dark spine
    // down the edge of the page. It takes its colours from the dark half of
    // the generated scheme so it never has to guess at contrast.
    readonly property var inkC: (raw && raw["dark"]) ? raw["dark"] : ({})
    function inkRole(name, fallback) {
        var v = inkC ? inkC[name] : undefined
        return (v !== undefined && v !== null && ("" + v).length > 0) ? v : fallback
    }
    readonly property color railBg:         inkRole("surfaceContainerLowest", "#140a06")
    readonly property color railText:       inkRole("onSurface",              "#efdfdb")
    readonly property color railDim:        inkRole("onSurfaceVariant",       "#ddc0b8")
    readonly property color railHover:      inkRole("surfaceContainerHigh",   "#322724")
    readonly property color railLine:       inkRole("outlineVariant",         "#59413b")
    readonly property color railAccent:     inkRole("primary",                "#dd694c")
    readonly property color railAccentText: inkRole("onPrimary",              "#351000")
    readonly property color railGold:       inkRole("tertiary",               "#caab54")
    readonly property color railError:      inkRole("error",                  "#ffb3b0")

    // Panel background honouring the opacity setting.
    readonly property color panelBg: Qt.rgba(panel.r, panel.g, panel.b, panelOpacity)
    readonly property color raisedBg: Qt.rgba(raised.r, raised.g, raised.b,
                                              Math.min(1.0, panelOpacity + 0.06))

    // ---- Type ----
    // Chosen in Settings; these are the fallbacks if nothing is set.
    property string fontDisplay: "Red Hat Display"
    property string fontBody:    "Red Hat Text"
    property string fontMono:    "JetBrains Mono"
    property real   fontScale:   1.0

    readonly property string display: fontDisplay
    readonly property string body:    fontBody
    readonly property string mono:    fontMono
    // Icon glyphs only (Nerd Font). Never used for prose, so it never changes.
    readonly property string icon:    "FiraCode Nerd Font Propo"

    // Panels size text through this so one setting scales the whole shell.
    function fs(px) { return Math.max(7, Math.round(px * fontScale)) }

    // ---- Metrics ----
    // "Ink" look: small, quiet radii. Enough to soften a card, never a pill
    // (rPill keeps its name because panels reference it).
    readonly property int rSmall: 4
    readonly property int r:      6
    readonly property int rLarge: 10
    readonly property int rPill:  6
    readonly property int pad:    18
    readonly property int gap:    10

    // ---- Motion ----
    readonly property int tSnap:  Math.round(110 * motion)
    readonly property int tPanel: Math.round(240 * motion)
    readonly property int tSlow:  Math.round(420 * motion)
}

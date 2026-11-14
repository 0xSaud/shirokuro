// A GIF rendered to a chosen crop rather than a blind centre crop.
//
// zoom 1.0 exactly covers the view; offsetX/offsetY are 0..1 and say which part
// of the overflow is visible (0.5 = centred). Wide or tall GIFs would otherwise
// have their subject cut out of frame, which is what made some of them look bad.
import QtQuick

Item {
    id: view

    property var  th
    property url  source: ""
    property real zoom: 1.0
    property real offsetX: 0.5
    property real offsetY: 0.5
    property bool playing: true
    property real dim: 1.0

    // Clearing source when hidden frees the decoded frames.
    readonly property bool active: ("" + source).length > 0
    // How much image sits outside the view, so a crop editor can turn a drag in
    // pixels into a change in offset.
    readonly property real overflowX: Math.max(1, img.width  - view.width)
    readonly property real overflowY: Math.max(1, img.height - view.height)
    readonly property bool ready: img.status === Image.Ready
    // zoom value that shows the whole GIF with nothing cropped off. Below 1.0,
    // since 1.0 is defined as "just covers the frame".
    readonly property real fitZoom: img.cover > 0 ? (img.contain / img.cover) : 1.0

    clip: true

    AnimatedImage {
        id: img
        source: view.source
        playing: view.playing
        cache: false
        asynchronous: true
        opacity: view.dim
        fillMode: Image.Stretch

        readonly property real natW: sourceSize.width  > 0 ? sourceSize.width  : 1
        readonly property real natH: sourceSize.height > 0 ? sourceSize.height : 1
        // Scale so the image at least covers the view, then apply the user's zoom.
        readonly property real cover: Math.max(view.width / natW, view.height / natH)
        readonly property real contain: Math.min(view.width / natW, view.height / natH)
        readonly property real s: cover * Math.max(0.2, view.zoom)

        width:  natW * s
        height: natH * s
        // Pan across whatever overflows the view.
        x: -(width  - view.width)  * Math.max(0, Math.min(1, view.offsetX))
        y: -(height - view.height) * Math.max(0, Math.min(1, view.offsetY))
    }
}

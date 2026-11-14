// Calendar.
//
// Layout: today on the left as a large date card, the month on the right as a
// grid of square cells. Left/Right change the month, Home returns to today.
import QtQuick
import Quickshell

Overlay {
    id: win

    // Offset in months from the current one, so "today" is always reachable.
    property int monthOffset: 0

    eyebrow: "CALENDAR"
    title: "Calendar"
    hint: "← → month  ·  home today"
    cardWidth: 800
    cardHeight: 500

    onOpened: monthOffset = 0
    onKeyPressed: function (e) {
        if (e.key === Qt.Key_Left)       { monthOffset -= 1; e.accepted = true }
        else if (e.key === Qt.Key_Right) { monthOffset += 1; e.accepted = true }
        else if (e.key === Qt.Key_Home)  { monthOffset = 0;  e.accepted = true }
    }

    // NOT `shown`: that is Overlay's visibility flag.
    readonly property date viewMonth: {
        var n = new Date()
        return new Date(n.getFullYear(), n.getMonth() + monthOffset, 1)
    }
    readonly property date today: new Date()

    readonly property int daysInMonth:
        new Date(viewMonth.getFullYear(), viewMonth.getMonth() + 1, 0).getDate()
    // Grid starts on Monday, which is how the week reads locally.
    readonly property int leadingBlanks: {
        var d = viewMonth.getDay()          // 0 = Sunday
        return (d + 6) % 7
    }

    function isToday(day) {
        return viewMonth.getFullYear() === today.getFullYear()
            && viewMonth.getMonth() === today.getMonth()
            && day === today.getDate()
    }
    function isWeekend(cellIndex) {
        var col = cellIndex % 7
        return col >= 5                  // Sat, Sun in a Monday-first grid
    }
    // Day of the year and days left in it, for the date card.
    readonly property int dayOfYear: {
        var s = new Date(today.getFullYear(), 0, 0)
        return Math.floor((today - s) / 86400000)
    }
    readonly property int daysInYear:
        ((today.getFullYear() % 4 === 0 && today.getFullYear() % 100 !== 0) || today.getFullYear() % 400 === 0) ? 366 : 365
    // ISO week number.
    readonly property int weekNo: {
        var d = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()))
        var n = d.getUTCDay() || 7
        d.setUTCDate(d.getUTCDate() + 4 - n)
        var y0 = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
        return Math.ceil((((d - y0) / 86400000) + 1) / 7)
    }

    Item {
        anchors.fill: parent

        // ================= today =================
        Rectangle {
            id: card
            x: 16; y: 16
            width: 250
            height: parent.height - 32
            radius: win.th.rLarge
            color: win.th.surfaceText

            Text {
                x: 22; y: 20
                text: Qt.formatDateTime(win.today, "dddd")
                color: win.th.surface
                font.family: win.th.body; font.pixelSize: win.th.fs(13); font.weight: Font.DemiBold
            }
            Text {
                id: bigDay
                x: 18; y: 34
                text: Qt.formatDateTime(win.today, "d")
                color: win.th.surface
                font.family: win.th.display; font.pixelSize: win.th.fs(104); font.weight: Font.Bold
            }
            Rectangle { x: 22; y: bigDay.y + bigDay.height + 2; width: 28; height: 3; color: win.th.primary }
            Text {
                x: 22; y: bigDay.y + bigDay.height + 16
                text: Qt.formatDateTime(win.today, "MMMM yyyy")
                color: win.th.surface
                font.family: win.th.display; font.pixelSize: win.th.fs(16); font.weight: Font.Bold
            }

            Column {
                x: 22
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                width: parent.width - 44
                spacing: 8
                Text { text: "Week " + win.weekNo + "   ·   day " + win.dayOfYear + " of " + win.daysInYear
                       color: win.th.surfaceContainerHighest
                       font.family: win.th.body; font.pixelSize: win.th.fs(10) }
                // The year so far.
                Rectangle {
                    width: parent.width; height: 4; radius: 2
                    color: win.th.outline
                    Rectangle { width: parent.width * win.dayOfYear / win.daysInYear; height: parent.height
                                radius: 2; color: win.th.surface }
                }
            }
        }

        // ================= month =================
        Tile {
            id: month
            th: win.th
            x: card.x + card.width + 10
            y: 16
            width: parent.width - x - 16
            height: parent.height - 32

            Text {
                id: mName
                text: Qt.formatDateTime(win.viewMonth, "MMMM")
                color: win.th.surfaceText
                font.family: win.th.display; font.pixelSize: win.th.fs(20); font.weight: Font.Bold
            }
            Text {
                anchors.left: mName.right
                anchors.leftMargin: 10
                anchors.baseline: mName.baseline
                text: Qt.formatDateTime(win.viewMonth, "yyyy")
                color: win.th.outline
                font.family: win.th.body; font.pixelSize: win.th.fs(13)
            }
            Row {
                anchors.right: parent.right
                spacing: 6
                Chip { th: win.th; label: "Today"; visible: win.monthOffset !== 0
                       onPick: function () { win.monthOffset = 0 } }
                Chip { th: win.th; width: 34; label: "‹"; onPick: function () { win.monthOffset -= 1 } }
                Chip { th: win.th; width: 34; label: "›"; onPick: function () { win.monthOffset += 1 } }
            }

            // Weekday initials.
            Row {
                id: dow
                y: 48
                width: parent.width
                Repeater {
                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    Text {
                        required property var modelData
                        required property int index
                        width: dow.width / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: win.th.outline
                        opacity: index >= 5 ? 0.6 : 1.0
                        font.family: win.th.body; font.pixelSize: win.th.fs(10); font.weight: Font.DemiBold
                    }
                }
            }

            Grid {
                id: grid
                y: dow.y + 24
                width: parent.width
                columns: 7
                spacing: 0
                readonly property real cw: width / 7
                readonly property real ch: Math.floor((month.bodyHeight - y) / 6)

                Repeater {
                    model: win.leadingBlanks + win.daysInMonth
                    Item {
                        id: cell
                        required property int index
                        readonly property bool blank: index < win.leadingBlanks
                        readonly property int day: index - win.leadingBlanks + 1
                        readonly property bool now: !blank && win.isToday(day)
                        width: grid.cw
                        height: grid.ch

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: win.th.r
                            visible: !cell.blank
                            color: cell.now ? win.th.surfaceText
                                 : (dayMa.containsMouse ? win.th.surfaceContainerHighest : win.th.surfaceContainer)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                x: 9; y: 6
                                text: cell.day
                                color: cell.now ? win.th.surface
                                     : (win.isWeekend(cell.index) ? win.th.outline : win.th.surfaceText)
                                font.family: win.th.display
                                font.pixelSize: win.th.fs(13)
                                font.weight: cell.now ? Font.Bold : Font.Medium
                            }
                            Rectangle {
                                visible: cell.now
                                anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.margins: 8
                                width: 6; height: 6; radius: 1.5
                                color: win.th.primary
                            }
                            MouseArea { id: dayMa; anchors.fill: parent; hoverEnabled: true }
                        }
                    }
                }
            }
        }
    }
}

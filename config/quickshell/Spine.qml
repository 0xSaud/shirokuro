// The shell's signature element: a hairline rule with a travelling tick that
// marks the active row or section. Every panel carries one, which is what makes
// the launcher, power menu, control center and music panel read as one family.
import QtQuick

Item {
    id: spine

    property color ruleColor: "#252C35"
    property color tickColor: "#C8A24C"
    property real  tickY: 0
    property real  tickHeight: 18
    property bool  tickVisible: true
    property int   moveDuration: 110

    implicitWidth: 9

    Rectangle {
        x: 4
        width: 1
        height: parent.height
        color: spine.ruleColor
    }

    Rectangle {
        x: 2
        width: 5
        radius: 1
        y: spine.tickY
        height: spine.tickHeight
        color: spine.tickColor
        visible: spine.tickVisible
        Behavior on y      { NumberAnimation { duration: spine.moveDuration; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: spine.moveDuration; easing.type: Easing.OutCubic } }
    }
}

import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Events

// One row in the agenda: time range, title, optional location/description,
// a repeat badge, and a delete action.
Item {
  id: eventItem

  required property var event
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property string fontFamily: Style.font.family
  property bool highlight: false
  property color highlightColor: Color.accent

  signal deleteRequested()
  signal editRequested()

  readonly property string repeatLabel: Events.eventRepeatLabel(event)

  width: parent ? parent.width : 0
  implicitHeight: row.implicitHeight

  Rectangle {
    visible: eventItem.highlight
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(eventItem.highlightColor, 0.18)
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: eventItem.editRequested()
  }

  Row {
    id: row
    width: parent.width
    leftPadding: Style.space(8)
    rightPadding: Style.space(8)
    topPadding: Style.space(2)
    bottomPadding: Style.space(2)
    spacing: Style.space(8)

    Text {
      id: timeText
      width: Style.space(104)
      textFormat: Text.PlainText
      text: Events.eventTimeRange(eventItem.event)
      color: eventItem.foreground
      font.family: eventItem.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Column {
      width: parent.width - row.leftPadding - row.rightPadding - timeText.width - deleteBtn.width - parent.spacing * 2
      spacing: Style.space(1)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: eventItem.event.title
        color: eventItem.foreground
        font.family: eventItem.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        visible: !!eventItem.event.location || !!eventItem.event.description
        text: [eventItem.event.location, eventItem.event.description].filter(function(x) { return !!x }).join(" · ")
        color: eventItem.dim
        font.family: eventItem.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        visible: eventItem.repeatLabel !== "" || Events.eventDaySpan(eventItem.event) > 1
        text: eventItem.repeatLabel !== ""
          ? eventItem.repeatLabel
          : "Until " + Events.shortDateKey(Events.eventLastDay(eventItem.event))
        color: Color.accent
        font.family: eventItem.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        visible: eventItem.event.reminderMins > 0
        text: "󰢌 Remind " + eventItem.event.reminderMins + "m before"
        color: Color.accent
        font.family: eventItem.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    PanelActionButton {
      id: deleteBtn
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅙"
      tooltipText: "Delete event"
      hoverColor: Color.urgent
      foreground: eventItem.foreground
      fontFamily: eventItem.fontFamily
      onClicked: eventItem.deleteRequested()
    }
  }
}
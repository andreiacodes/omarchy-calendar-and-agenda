import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Events

// One day column in the week agenda: a header plus its events.
Column {
  id: daySection

  required property var day
  property string sectionText: ""
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property string fontFamily: Style.font.family

  signal deleteRequested(var eventId)
  signal editRequested(var event)

  width: parent ? parent.width : 0
  spacing: Style.space(3)

  PanelSectionHeader {
    text: daySection.sectionText
    foreground: daySection.dim
    fontFamily: daySection.fontFamily
  }

  Repeater {
    model: daySection.day.events

    Item {
      required property var modelData
      width: parent ? parent.width : 0
      height: eventRow.implicitHeight

      EventItem {
        id: eventRow
        anchors.left: parent.left
        anchors.right: parent.right
        event: parent.modelData
        highlight: parent.modelData.isLive
        foreground: daySection.foreground
        dim: daySection.dim
        fontFamily: daySection.fontFamily
        onDeleteRequested: daySection.deleteRequested(parent.modelData.id)
        onEditRequested: daySection.editRequested(parent.modelData)
      }
    }
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    visible: daySection.day.events.length === 0
    text: "No events"
    color: daySection.dim
    font.family: daySection.fontFamily
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
  }
}
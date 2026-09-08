import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Events

// Modal form for creating a new calendar event: title, date, start/end time,
// location, description, and an optional repeat rule (none, daily, weekly,
// bi-weekly, or specific weekdays) with an optional end date.
Item {
  id: root

  property bool opened: false
  property string errorText: ""
  property string repeatVal: "none"
  property string reminderVal: "15"
  property string editingId: ""
  property var weekdaySel: [false, false, false, false, false, false, false]
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // Full content height the form needs to show every field without scrolling.
  readonly property real desiredContentHeight:
    column.implicitHeight + card.contentTopInset + card.contentBottomInset + Style.space(4)

  signal save(var eventData)
  signal cancel()

  visible: root.opened
  z: 20

  function open() {
    root.reset()
    root.opened = true
    Qt.callLater(function() { titleField.forceActiveFocus() })
  }

  function timeText(hhmm) {
    if (!hhmm || hhmm.length < 4) return ""
    return hhmm.slice(0, 2) + ":" + hhmm.slice(2, 4)
  }

  function openForEdit(event) {
    root.reset()
    if (!event) return
    root.editingId = event.id || ""
    titleField.text = event.title || ""
    locationField.text = event.location || ""
    descriptionField.text = event.description || ""
    startField.text = root.timeText(event.startHHMM)
    endField.text = root.timeText(event.endHHMM || event.startHHMM)
    dateField.text = event.date || event.startDate || ""
    endDateField.text = event.endDate || ""
    endRepeatField.text = event.repeatEnd || ""

    var repeat = String(event.repeat || "none")
    if (repeat === "daily" || repeat === "weekly" || repeat === "biweekly") {
      root.repeatVal = repeat
    } else if (repeat !== "none" && repeat !== "") {
      root.repeatVal = "custom"
      var sel = [false, false, false, false, false, false, false]
      var parts = repeat.split(",")
      for (var i = 0; i < parts.length; i++) {
        var w = parseInt(parts[i].trim(), 10)
        if (!isNaN(w) && w >= 1 && w <= 7) sel[w - 1] = true
      }
      root.weekdaySel = sel
    }

    root.errorText = ""

    var r = parseInt(event.reminderMins, 10)
    if (isNaN(r) || r <= 0) root.reminderVal = "none"
    else if (r === 5 || r === 15 || r === 30 || r === 60) root.reminderVal = String(r)
    else root.reminderVal = "15"

    root.opened = true
    Qt.callLater(function() { titleField.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.cancel()
  }

  function showError(msg) {
    root.errorText = msg
  }

  function reset() {
    titleField.text = ""
    locationField.text = ""
    descriptionField.text = ""
    dateField.text = Events.keyForDate(new Date())
    endDateField.text = ""
    startField.text = "09:00"
    endField.text = "10:00"
    endRepeatField.text = ""
    root.repeatVal = "none"
    root.reminderVal = "15"
    root.weekdaySel = [false, false, false, false, false, false, false]
    root.errorText = ""
    root.editingId = ""
  }

  function selectedWeekdays() {
    var out = []
    for (var i = 0; i < 7; i++) if (root.weekdaySel[i]) out.push(i + 1)
    return out.join(",")
  }

  function toggleWeekday(index) {
    var arr = root.weekdaySel.slice()
    arr[index] = !arr[index]
    root.weekdaySel = arr
  }

  function submit() {
    if (!titleField.text.trim()) { showError("Enter a title."); return }
    var dateKey = Events.parseDateKey(dateField.text)
    if (!dateKey) { showError("Enter a valid date (YYYY-MM-DD)."); return }
    var start = Events.parseTimeInput(startField.text)
    if (!start) { showError("Enter a valid start time (e.g. 09:00)."); return }
    var end = Events.parseTimeInput(endField.text) || start

    if (root.repeatVal === "custom") {
      var list = root.selectedWeekdays()
      if (!list) { showError("Pick at least one weekday for the repeat."); return }
      root.repeatVal = list
    }

    var endKey = ""
    if (root.repeatVal !== "none" && endRepeatField.text.trim() !== "") {
      endKey = Events.parseDateKey(endRepeatField.text)
      if (!endKey) { showError("Repeat end must be a valid date (YYYY-MM-DD)."); return }
    }

    var spanEnd = ""
    if (root.repeatVal === "none" && endDateField.text.trim() !== "") {
      spanEnd = Events.parseDateKey(endDateField.text)
      if (!spanEnd) { showError("End date must be a valid date (YYYY-MM-DD)."); return }
      if (spanEnd < dateKey) { showError("End date must not be before the start date."); return }
    }

    root.errorText = ""
    root.save({
      id: root.editingId,
      title: titleField.text,
      location: locationField.text,
      description: descriptionField.text,
      date: dateKey,
      endDate: spanEnd || "",
      startHHMM: start,
      endHHMM: end,
      repeat: root.repeatVal,
      day: Events.weekdayNum(Events.dateFromKey(dateKey)),
      repeatEnd: endKey || "",
      reminderMins: root.reminderVal === "none" ? 0 : parseInt(root.reminderVal, 10)
    })
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.7)

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  BorderSurface {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(32), Style.space(430))
    height: Math.min(root.desiredContentHeight, parent.height - Style.space(16))
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
    radius: Style.cornerRadius
    padding: Style.space(18)
    focus: true
    Keys.onEscapePressed: root.close()

    MouseArea {
      anchors.fill: parent
      onClicked: {}
    }

    Flickable {
      id: cardScroll
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset + Style.space(2)
      anchors.bottomMargin: card.contentBottomInset + Style.space(2)
      anchors.leftMargin: card.contentLeftInset
      anchors.rightMargin: card.contentRightInset
      clip: true
      contentWidth: width
      contentHeight: column.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: column
        width: cardScroll.width
        spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: root.editingId === "" ? "New Event" : "Edit Event"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          textFormat: Text.PlainText
          text: "TITLE *"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        TextField {
          id: titleField
          width: parent.width
          placeholderText: "Event title"
          foreground: root.foreground
          font.family: root.fontFamily
          Keys.onReturnPressed: root.submit()
          Keys.onEnterPressed: root.submit()
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          textFormat: Text.PlainText
          text: "DATE (YYYY-MM-DD)"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        TextField {
          id: dateField
          width: parent.width
          placeholderText: Events.keyForDate(new Date())
          foreground: root.foreground
          font.family: root.fontFamily
          inputMethodHints: Qt.ImhDate
          Keys.onReturnPressed: root.submit()
          Keys.onEnterPressed: root.submit()
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(10)

        Column {
          width: root.repeatVal === "none"
            ? (parent.width - parent.spacing * 2) / 3
            : (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap

          Text {
            textFormat: Text.PlainText
            text: "START TIME"
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          TextField {
            id: startField
            width: parent.width
            placeholderText: "09:00"
            foreground: root.foreground
            font.family: root.fontFamily
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
          }
        }

        Column {
          visible: root.repeatVal === "none"
          width: root.repeatVal === "none"
            ? (parent.width - parent.spacing * 2) / 3
            : 0
          spacing: Style.spacing.labelGap

          Text {
            textFormat: Text.PlainText
            text: "END DATE"
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          TextField {
            id: endDateField
            width: parent.width
            placeholderText: "YYYY-MM-DD"
            foreground: root.foreground
            font.family: root.fontFamily
            inputMethodHints: Qt.ImhDate
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
          }
        }

        Column {
          width: root.repeatVal === "none"
            ? (parent.width - parent.spacing * 2) / 3
            : (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap

          Text {
            textFormat: Text.PlainText
            text: "END TIME"
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          TextField {
            id: endField
            width: parent.width
            placeholderText: "10:00"
            foreground: root.foreground
            font.family: root.fontFamily
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          textFormat: Text.PlainText
          text: "LOCATION"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        TextField {
          id: locationField
          width: parent.width
          placeholderText: "Optional"
          foreground: root.foreground
          font.family: root.fontFamily
          Keys.onReturnPressed: root.submit()
          Keys.onEnterPressed: root.submit()
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          textFormat: Text.PlainText
          text: "DESCRIPTION"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Item {
          width: parent.width
          height: Math.max(Style.space(34),
            descriptionField.contentHeight + Style.spacing.inputPaddingY * 2 + Style.space(4))

          BorderSurface {
            anchors.fill: parent
            color: Style.controlFill(descriptionField.activeFocus, false, root.foreground, Color.accent)
            borderSpec: Border.controlSpec(
              descriptionField.activeFocus ? "focus" : "normal", root.foreground, Color.accent)
            radius: Style.cornerRadius
          }

          TextEdit {
            id: descriptionField
            anchors.fill: parent
            anchors.topMargin: Style.spacing.inputPaddingY + Style.space(2)
            anchors.bottomMargin: Style.spacing.inputPaddingY + Style.space(2)
            anchors.leftMargin: Style.spacing.controlPaddingX + Style.space(2)
            anchors.rightMargin: Style.spacing.controlPaddingX + Style.space(2)
            text: ""
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            selectByMouse: true
            color: root.foreground
            selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
            selectedTextColor: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()

            Text {
              anchors.fill: parent
              textFormat: Text.PlainText
              visible: descriptionField.text === ""
              text: "Optional"
              color: Qt.darker(root.foreground, 1.6)
              font.family: descriptionField.font.family
              font.pixelSize: descriptionField.font.pixelSize
            }
          }
        }
      }

      Dropdown {
        id: repeatDropdown
        width: parent.width
        label: "REPEAT"
        value: root.repeatVal
        options: [
          { value: "none", label: "None" },
          { value: "daily", label: "Daily" },
          { value: "weekly", label: "Weekly" },
          { value: "biweekly", label: "Bi-weekly" },
          { value: "custom", label: "Specific weekdays" }
        ]
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(v) { root.repeatVal = v }
      }

      Row {
        visible: root.repeatVal === "custom"
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: 7

          Button {
            required property int index
            text: Events.shortDayName(index + 1)
            selected: root.weekdaySel[index]
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleWeekday(index)
          }
        }
      }

      Column {
        visible: root.repeatVal !== "none"
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          textFormat: Text.PlainText
          text: "REPEAT ENDS ON (YYYY-MM-DD)"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        TextField {
          id: endRepeatField
          width: parent.width
          placeholderText: "Optional"
          foreground: root.foreground
          font.family: root.fontFamily
          Keys.onReturnPressed: root.submit()
          Keys.onEnterPressed: root.submit()
        }
      }

      Dropdown {
        id: reminderDropdown
        width: parent.width
        label: "REMINDER"
        value: root.reminderVal
        options: [
          { value: "none", label: "None" },
          { value: "5", label: "5 min before" },
          { value: "15", label: "15 min before" },
          { value: "30", label: "30 min before" },
          { value: "60", label: "1 hour before" }
        ]
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(v) { root.reminderVal = v }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: root.errorText !== ""
        text: root.errorText
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(10)

        Button {
          text: "Cancel"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.close()
        }

        Button {
          text: "Save"
          bordered: true
          focusable: true
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onClicked: root.submit()
        }
      }
    }
  }
  }
}
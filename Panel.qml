import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Events
import "SpawnGuard.js" as SpawnGuard

Panel {
  id: root
  moduleName: "io.github.andreiacodes.calendar"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(root.fg, 1.5)
  readonly property string fnt: bar ? bar.fontFamily : Style.font.family

  property date today: new Date()
  readonly property string todayKey: Events.keyForDate(root.today)
  property var weekEvents: []
  property int revision: 0
  property var dayEvents: root.dayEventsSource()

  // View state: "week" (7-day agenda) or "day" (single-day list).
  property string viewMode: "week"
  property bool viewDayFollowsToday: true
  property string viewDayPinnedKey: root.todayKey
  readonly property string viewDayKey: root.viewDayFollowsToday ? root.todayKey : root.viewDayPinnedKey
  readonly property string dayTitleText: ((root.viewDayKey === root.todayKey ? "Today · " : "")
    + Events.dayLabel(root.viewDayKey)).toUpperCase()

  property date viewMonth: new Date(root.today.getFullYear(), root.today.getMonth(), 1)
  property var monthGrid: root.monthGridSource()

  function switchView(mode) {
    root.viewMode = mode
    if (mode === "day") {
      root.viewDayFollowsToday = true
      root.viewDayPinnedKey = root.todayKey
    }
  }

  function navigateDay(delta) {
    root.viewDayPinnedKey = Events.addDays(root.viewDayKey, delta)
    root.viewDayFollowsToday = false
  }

  function goToday() {
    root.viewDayFollowsToday = true
  }

  function navigateMonth(delta) {
    var d = root.viewMonth
    root.viewMonth = new Date(d.getFullYear(), d.getMonth() + delta, 1)
  }

  function goCurrentMonth() {
    root.viewMonth = new Date(root.today.getFullYear(), root.today.getMonth(), 1)
  }

  function showDay(key) {
    root.switchView("day")
    root.viewDayFollowsToday = false
    root.viewDayPinnedKey = key
  }

  function monthGridSource() {
    root.revision
    return Events.getMonthGrid(root.viewMonth.getFullYear(), root.viewMonth.getMonth())
  }

  function refresh() {
    eventsFile.reload()
    root.recompute()
  }

  function recompute() {
    root.weekEvents = Events.getWeekEvents(root.todayKey)
    root.revision++
  }

  function dayEventsSource() {
    root.revision
    return Events.getEventsForDate(root.viewDayKey)
  }

  function syncFromFile(text) {
    Events.seedEvents(Events.parseStored(text))
    reminders.sync(Events.reminderPlan())
    obsidianSync.backfillStored(Events.storedEvents())
    root.recompute()
  }

  function deleteEventById(eventId) {
    var ev = null
    var all = Events.storedEvents()
    for (var i = 0; i < all.length; i++) {
      if (all[i].id === eventId) { ev = all[i]; break }
    }
    var res = Events.deleteEvent(eventId)
    if (res.ok) {
      if (ev) obsidianSync.removeEvent(ev.id, ev.date || ev.startDate)
      root.writeEvents(Events.eventsJson())
      reminders.sync(Events.reminderPlan())
      root.recompute()
      root.notifyChange()
    }
  }

  function editEvent(event) {
    formPanel.openForEdit(event)
  }

  // Manual resync: re-add any events the user removed from Obsidian notes.
  function refreshObsidian() {
    obsidianSync.refresh(Events.storedEvents())
  }

  // Manual import: pull in events found in the notes that the plugin lacks.
  function importObsidian() {
    obsidianSync.importFromNotes()
  }

  function writeEvents(json) {
    if (root.dirReady) {
      eventsFile.setText(json)
      return
    }
    root.pendingWrite = json
    mkdirProcess.command = ["mkdir", "-p", root.eventsDir]
    if (SpawnGuard.valid(mkdirProcess.command)) mkdirProcess.running = true
  }

  function updateToday() {
    var key = Events.keyForDate(new Date())
    if (key === root.todayKey) return
    root.today = new Date()
    root.refresh()
  }

  function open() {
    root.refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    if (formPanel.opened) formPanel.close()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function notifyChange() {
    if (root.hostWidget && typeof root.hostWidget.updateLabel === "function")
      root.hostWidget.updateLabel()
  }

  readonly property string eventsDir: Quickshell.env("HOME") + "/.config/omarchy/calendar"
  readonly property string eventsPath: root.eventsDir + "/events.json"
  property bool dirReady: false
  property string pendingWrite: ""

  FileView {
    id: eventsFile
    path: root.eventsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.syncFromFile(text())
    onLoadFailed: root.syncFromFile("")
  }

  Process {
    id: mkdirProcess
    clearEnvironment: true
    environment: SpawnGuard.envPinned(
      Quickshell.env("PATH") || "",
      Quickshell.env("HOME") || "",
      Quickshell.env("USER") || "",
      Quickshell.env("LANG") || "",
      Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
    command: ["mkdir", "-p", root.eventsDir]
    onExited: function(exitCode, exitStatus) {
      root.dirReady = true
      if (root.pendingWrite !== "") {
        var json = root.pendingWrite
        root.pendingWrite = ""
        eventsFile.setText(json)
      }
    }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.updateToday()
  }

  Timer {
    id: liveRefresh
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.recompute()
  }

  ReminderScheduler {
    id: reminders
  }

  ObsidianSync {
    id: obsidianSync
    onVaultReady: obsidianSync.backfillStored(Events.storedEvents())
    onEventsFound: function(list) {
      var added = Events.importEvents(list)
      if (added > 0) {
        root.writeEvents(Events.eventsJson())
        reminders.sync(Events.reminderPlan())
        root.recompute()
        root.notifyChange()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(
      formPanel.opened ? formPanel.desiredContentHeight : column.implicitHeight,
      formPanel.opened ? Style.space(760) : Style.space(540))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: formPanel.opened
      onMoveRequested: function(dx, dy) {
        if (dy === 0) return
        var max = Math.max(0, scroll.contentHeight - scroll.height)
        scroll.contentY = Math.max(0, Math.min(max, scroll.contentY + dy * Style.space(48)))
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: column
        width: scroll.width
        spacing: Style.space(14)

        // Header: title + obsidian controls + new-event button
        Item {
          width: parent.width
          implicitHeight: Math.max(titleText.implicitHeight, addButton.implicitHeight + Style.space(2))

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Agenda"
            color: root.fg
            font.family: root.fnt
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Button {
            id: importButton
            anchors.right: refreshButton.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: "⇩"
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fnt
            tooltipText: "Import events found in the Obsidian notes into the plugin."
            onClicked: root.importObsidian()
          }

          Button {
            id: refreshButton
            anchors.right: obsidianToggle.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: "⟳"
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fnt
            tooltipText: "Re-add events that are missing from the Obsidian daily notes."
            onClicked: root.refreshObsidian()
          }

          Button {
            id: obsidianToggle
            anchors.right: addButton.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: obsidianSync.obsidianSync ? "Obsidian: on" : "Obsidian: off"
            selected: obsidianSync.obsidianSync
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fnt
            tooltipText: "Mirror saved events into Obsidian daily notes. Off skips syncing new events."
            onClicked: obsidianSync.toggleSync()
          }

          Button {
            id: addButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "+ New Event"
            bordered: true
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fnt
            tooltipText: "Create a new event"
            onClicked: formPanel.open()
          }
        }

        // Week / Day view toggle
        Row {
          width: parent.width
          spacing: Style.space(6)

          Button {
            text: "Day"
            selected: root.viewMode === "day"
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            foreground: root.fg
            fontFamily: root.fnt
            onClicked: root.switchView("day")
          }

          Button {
            text: "Week"
            selected: root.viewMode === "week"
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            foreground: root.fg
            fontFamily: root.fnt
            onClicked: root.switchView("week")
          }

          Button {
            text: "Month"
            selected: root.viewMode === "month"
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            foreground: root.fg
            fontFamily: root.fnt
            onClicked: root.switchView("month")
          }
        }

        // Week view: today plus the next six days
        Item {
          width: parent.width
          height: root.viewMode === "week" ? weekColumn.implicitHeight : 0
          visible: root.viewMode === "week"

          Column {
            id: weekColumn
            width: parent.width
            spacing: Style.space(14)

            PanelSeparator {
              foreground: root.fg
              strength: 0.3
            }

            PanelSectionHeader {
              text: {
                var first = root.weekEvents[0]
                var last = root.weekEvents[root.weekEvents.length - 1]
                var range = (first && last)
                  ? Events.shortDateKey(first.key) + " – " + Events.shortDateKey(last.key)
                  : ""
                return ("This Week" + (range ? " · " + range : "")).toUpperCase()
              }
              foreground: root.dim
              fontFamily: root.fnt
            }

            Repeater {
              model: root.weekEvents

              Item {
                required property var modelData
                width: parent ? parent.width : 0
                height: dayColumn.implicitHeight

                Rectangle {
                  anchors.fill: parent
                  visible: parent.modelData.isToday && !parent.modelData.hasLive
                  radius: Style.cornerRadius
                  color: Util.alpha(Color.accent, 0.10)
                }

                WeekDaySection {
                  id: dayColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  day: parent.modelData
                  sectionText: parent.modelData.isToday
                    ? ("Today · " + Events.shortDateKey(parent.modelData.key)).toUpperCase()
                    : parent.modelData.label.toUpperCase()
                  foreground: root.fg
                  dim: root.dim
                  fontFamily: root.fnt
                  onDeleteRequested: function(eventId) { root.deleteEventById(eventId) }
                  onEditRequested: function(event) { root.editEvent(event) }
                }
              }
            }
          }
        }

        // Day view: every event on a single day, sorted by start time
        Item {
          width: parent.width
          height: root.viewMode === "day" ? dayColumn.implicitHeight : 0
          visible: root.viewMode === "day"

          Column {
            id: dayColumn
            width: parent.width
            spacing: Style.space(14)

            PanelSeparator {
              foreground: root.fg
              strength: 0.3
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                id: prevDay
                text: "‹"
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlGap * 2
                foreground: root.fg
                fontFamily: root.fnt
                tooltipText: "Previous day"
                onClicked: root.navigateDay(-1)
              }

              Button {
                width: parent.width - prevDay.width - nextDay.width - parent.spacing * 2
                text: root.dayTitleText
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlGap
                foreground: root.fg
                fontFamily: root.fnt
                tooltipText: "Jump back to today"
                onClicked: root.goToday()
              }

              Button {
                id: nextDay
                text: "›"
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlGap * 2
                foreground: root.fg
                fontFamily: root.fnt
                tooltipText: "Next day"
                onClicked: root.navigateDay(1)
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              visible: root.dayEvents.length > 0
              text: root.dayEvents.length + " event" + (root.dayEvents.length === 1 ? "" : "s")
              color: root.dim
              font.family: root.fnt
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.dayEvents

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
                  foreground: root.fg
                  dim: root.dim
                  fontFamily: root.fnt
                  onDeleteRequested: root.deleteEventById(parent.modelData.id)
                  onEditRequested: root.editEvent(parent.modelData)
                }
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              visible: root.dayEvents.length === 0
              text: "No events on this day"
              color: root.dim
              font.family: root.fnt
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }

        // Month view: a month grid with event dots on days that have events
        Item {
          id: monthView
          width: parent.width
          height: root.viewMode === "month" ? monthColumn.implicitHeight : 0
          visible: root.viewMode === "month"

          readonly property real cellW: (width - Style.space(2) * 6) / 7

          Column {
            id: monthColumn
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator {
              foreground: root.fg
              strength: 0.3
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                id: prevMonth
                text: "‹"
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlGap * 2
                foreground: root.fg
                fontFamily: root.fnt
                tooltipText: "Previous month"
                onClicked: root.navigateMonth(-1)
              }

              Button {
                width: parent.width - prevMonth.width - nextMonth.width - parent.spacing * 2
                text: Events.monthLabel(root.viewMonth.getFullYear(), root.viewMonth.getMonth()).toUpperCase()
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlGap
                foreground: root.fg
                fontFamily: root.fnt
                tooltipText: "Jump to current month"
                onClicked: root.goCurrentMonth()
              }

              Button {
                id: nextMonth
                text: "›"
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlGap * 2
                foreground: root.fg
                fontFamily: root.fnt
                tooltipText: "Next month"
                onClicked: root.navigateMonth(1)
              }
            }

            Row {
              width: parent.width

              Repeater {
                model: 7

                Text {
                  required property int index
                  width: monthView.cellW
                  textFormat: Text.PlainText
                  text: Events.shortDayName(index + 1).toUpperCase()
                  color: root.dim
                  font.family: root.fnt
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                }
              }
            }

            Grid {
              columns: 7
              width: parent.width
              columnSpacing: Style.space(2)
              rowSpacing: Style.space(2)

              Repeater {
                model: root.monthGrid

                Item {
                  required property var modelData
                  width: monthView.cellW
                  height: Style.space(36)

                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Style.space(3)
                    width: Style.space(22)
                    height: Style.space(22)
                    radius: height / 2
                    color: modelData.isToday ? Util.alpha(Color.accent, 0.22) : "transparent"
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Style.space(3)
                    width: Style.space(22)
                    height: Style.space(22)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    text: modelData.day
                    color: modelData.isToday ? Color.accent : (modelData.isThisMonth ? root.fg : root.dim)
                    font.family: root.fnt
                    font.pixelSize: Style.font.bodySmall
                    font.bold: modelData.isToday
                  }

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(27)
                    spacing: Style.space(2)
                    visible: modelData.eventCount > 0

                    Repeater {
                      model: modelData.dots

                      Rectangle {
                        width: Style.space(4)
                        height: Style.space(4)
                        radius: width / 2
                        color: Color.accent
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      visible: modelData.eventCount > 3
                      text: "+" + (modelData.eventCount - 3)
                      color: root.dim
                      font.family: root.fnt
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showDay(modelData.key)
                  }
                }
              }
            }
          }
        }
      }
    }

    EventFormPanel {
      id: formPanel
      anchors.fill: parent
      foreground: root.fg
      fontFamily: root.fnt
      onSave: function(ev) {
        var oldEvent = ev.id ? Events.findStoredById(ev.id) : null
        var res = ev.id ? Events.updateEvent(ev) : Events.addEvent(ev)
        if (res.ok) {
          root.writeEvents(Events.eventsJson())
          reminders.sync(Events.reminderPlan())
          var oldKey = oldEvent ? (oldEvent.date || oldEvent.startDate) : null
          obsidianSync.syncEvent(res.event, oldKey)
          formPanel.close()
          root.recompute()
          root.notifyChange()
        } else {
          formPanel.showError(res.reason || "Could not save this event.")
        }
      }
      onCancel: function() {
        formPanel.opened = false
      }
    }
  }
}
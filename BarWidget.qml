import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Events

// Calendar widget for the bar: shows the next/current event in the label and
// opens the agenda panel on click.
BarWidget {
  id: root
  moduleName: "io.github.andreiacodes.calendar"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.andreiacodes.calendar"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.togglePanel() }
  }

  // The bar label: "NOW: <event>" while an event is happening, then the next
  // event today, tomorrow's first event, or the first upcoming event.
  property string label: "Calendar"

  readonly property string eventsPath: Quickshell.env("HOME") + "/.config/omarchy/calendar/events.json"

  FileView {
    id: eventsFile
    path: root.eventsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      Events.seedEvents(Events.parseStored(text()))
      root.updateLabel()
    }
    onLoadFailed: {
      Events.seedEvents([])
      root.updateLabel()
    }
  }

  function updateLabel() {
    var now = new Date()
    var key = Events.keyForDate(now)
    var minNow = now.getHours() * 60 + now.getMinutes()

    var todayEvents = Events.getEventsForDate(key)
    for (var i = 0; i < todayEvents.length; i++) {
      var e = todayEvents[i]
      var s = Events.timeToMinutes(e.startHHMM)
      var en = Events.timeToMinutes(e.endHHMM || e.startHHMM)
      if (s >= 0 && minNow >= s && minNow <= en) {
        root.label = "NOW: " + (e.title || "")
        return
      }
      if (s >= 0 && minNow < s) {
        root.label = Events.formatTime(e.startHHMM) + " " + (e.title || "")
        return
      }
    }

    var tomorrowKey = Events.addDays(key, 1)
    var tomorrowEvents = Events.getEventsForDate(tomorrowKey)
    if (tomorrowEvents.length > 0) {
      root.label = "TOM: " + tomorrowEvents[0].title
      return
    }

    var nextKey = Events.nextEventKey(tomorrowKey, 60)
    if (nextKey) {
      var nextEvents = Events.getEventsForDate(nextKey)
      if (nextEvents.length > 0) {
        root.label = nextEvents[0].title + " · " + Events.shortDateKey(nextKey)
        return
      }
    }

    root.label = "Calendar"
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: eventsFile.reload()
  }

  Component.onCompleted: eventsFile.reload()

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    dimmed: root.label === "Calendar"
    tooltipText: "Calendar agenda — click to open"
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.togglePanel()
    }
  }
}
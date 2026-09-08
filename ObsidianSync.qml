import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Events
import "SpawnGuard.js" as SpawnGuard

// One-way: calendar -> Obsidian daily notes.
//
// After an event is saved, its line is written into the matching daily note
// (<vault>/Daily/YYYY-MM-DD.md), creating the note if it does not exist. A
// hidden marker comment (<!-- calendar:<id> -->) lets edits update the same
// line instead of duplicating it.
//
// Preferences are persisted to ~/.config/omarchy/calendar/settings.json. The
// vault path is auto-detected from ~/.config/obsidian/obsidian.json on first
// use, and can be overridden in the settings file.
//
// Note: QML JavaScript modules are per-document, so this file never reads the
// event list itself. Panel pushes real events in via backfillStored().
Item {
  id: root

  readonly property string settingsPath:
    Quickshell.env("HOME") + "/.config/omarchy/calendar/settings.json"
  readonly property string scriptPath:
    Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.andreiacodes.calendar/obsidian-sync.js"
  readonly property string importScriptPath:
    Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.andreiacodes.calendar/obsidian-import.js"

  property bool obsidianSync: true
  property string vaultPath: ""
  property string dailyFolder: "Daily"
  property string dailyFormat: "YYYY-MM-DD"
  property bool vaultDetecting: false
  property var pendingEvent: null
  property var pendingOldKey: null
  property var writeQueue: []
  property bool writeRunning: false

  readonly property var trustedEnv: SpawnGuard.envPinned(
    Quickshell.env("PATH") || "",
    Quickshell.env("HOME") || "",
    Quickshell.env("USER") || "",
    Quickshell.env("LANG") || "",
    Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")

  // Asks Panel to backfill now that the vault is known and writable.
  signal vaultReady()

  // Panel uses this to add events that exist in the notes but not locally.
  signal eventsFound(var list)

  // Scans the daily notes for the plugin's marker lines and reports the ones
  // the plugin does not have yet. Skips if the toggle is off or the vault is
  // unknown.
  function importFromNotes() {
    if (!root.obsidianSync) return
    if (root.vaultPath === "") return
    importProc.command = [
      "node", root.importScriptPath,
      "--vault", root.vaultPath,
      "--folder", root.sanitizeFolder(root.dailyFolder),
      "--format", String(root.dailyFormat).slice(0, 64)
    ]
    if (SpawnGuard.valid(importProc.command)) importProc.running = true
  }

  function loadSettings(text) {
    var obj = {}
    try { obj = JSON.parse(text) } catch (e) {}
    root.obsidianSync = obj.obsidianSync !== false
    var vp = String(obj.vaultPath || "")
    if (vp === "undefined") vp = ""
    root.vaultPath = vp
    root.dailyFolder = root.sanitizeFolder(String(obj.dailyFolder !== undefined ? obj.dailyFolder : "Daily"))
    root.dailyFormat = String(obj.dailyFormat || "YYYY-MM-DD").slice(0, 64)
    if (root.vaultPath !== "") {
      root.vaultReady()
      root.importFromNotes()
    }
  }

  function saveSettings() {
    settingsFile.setText(JSON.stringify({
      obsidianSync: root.obsidianSync,
      vaultPath: root.vaultPath,
      dailyFolder: root.dailyFolder,
      dailyFormat: root.dailyFormat
    }, null, 2))
  }

  function setSync(on) {
    root.obsidianSync = !!on
    root.saveSettings()
  }

  function toggleSync() {
    root.setSync(!root.obsidianSync)
  }

  // Writes every stored event into its daily note. Idempotent: the per-event
  // marker replaces the line instead of duplicating it. The list is supplied
  // by Panel (each QML doc gets its own JS module instance).
  function backfillStored(list) {
    if (!root.obsidianSync) return
    if (root.vaultPath === "") return
    if (!list) return
    for (var i = 0; i < list.length; i++) {
      root.queueWrite(list[i], list[i].date || list[i].startDate)
    }
  }

function detectVault() {
    if (root.vaultDetecting) return
    root.vaultDetecting = true
    detectProc.command = ["node", root.scriptPath, "--detect-vault"]
    if (SpawnGuard.valid(detectProc.command)) detectProc.running = true
    else root.vaultDetecting = false
  }

  // Called after an event is saved/edited. Skips if the toggle is off.
  // When the event moved to a different date, the line in the old daily note
  // is removed as well.
  function syncEvent(event, oldDateKey) {
    if (!root.obsidianSync) return
    if (!event || !event.title) return
    var dateKey = event.date || event.startDate
    if (!dateKey) return

    if (oldDateKey && oldDateKey !== dateKey) {
      root.removeEvent(event.id, oldDateKey)
    }

    if (root.vaultPath !== "") {
      root.queueWrite(event, dateKey)
      return
    }
    if (root.vaultDetecting) return
    root.pendingEvent = event
    root.pendingOldKey = oldDateKey
    root.detectVault()
  }

  // Manual resync from the toolbar button: re-add every stored event that is
  // missing from the daily notes (deletions aside — those lines stay gone
  // because the event itself no longer exists). Idempotent via the markers.
  function refresh(list) {
    if (!root.obsidianSync) return
    if (root.vaultPath === "") {
      root.pendingEvent = null
      root.detectVault()
      return
    }
    root.backfillStored(list)
  }

  // Removes the event's line from its daily note on delete. Skips if the
  // toggle is off or the vault is unknown yet.
  function removeEvent(id, dateKey) {
    if (!root.obsidianSync) return
    if (!id || !dateKey) return
    if (root.vaultPath === "") return
    root.writeQueue.push({ mode: "remove", id: id, dateKey: dateKey })
    if (!root.writeRunning) root.nextWrite()
  }

  // Writes run one at a time: a single Process can only run one command per
  // tick, so a burst of events would otherwise drop all but the last write.
  function queueWrite(event, dateKey) {
    root.writeQueue.push({ mode: "write", event: event, dateKey: dateKey })
    if (!root.writeRunning) root.nextWrite()
  }

  function nextWrite() {
    if (root.writeQueue.length === 0) {
      root.writeRunning = false
      return
    }
    root.writeRunning = true
    var w = root.writeQueue.shift()

    var vault = root.vaultPath.replace(/\/+$/, "")
    var folder = root.sanitizeFolder(root.dailyFolder)
    var name = root.formatDateKey(w.dateKey, root.dailyFormat)
      .replace(/[/\\:*?"<>|]/g, "-") // never allow separators in a note name
    var note = folder === ""
      ? vault + "/" + name + ".md"          // vault-root daily notes
      : vault + "/" + folder + "/" + name + ".md"

    if (w.mode === "remove") {
      var rid = String(w.id || "")
      if (!/^[A-Za-z0-9_-]{1,64}$/.test(rid)) {
        root.nextWrite()
        return
      }
      syncProc.command = [
        "node", root.scriptPath,
        "--vault", root.vaultPath,
        "--delete",
        "--note", note,
        "--id", rid
      ]
      if (SpawnGuard.valid(syncProc.command)) syncProc.running = true
      else root.nextWrite()
      return
    }

    var range = Events.eventTimeRange(w.event)
    var title = String(w.event.title || "").trim()
    if (title === "") { root.nextWrite(); return }
    title = title.slice(0, 200)
    var loc = String(w.event.location || "").trim().slice(0, 500)
    var desc = String(w.event.description || "").trim().replace(/\s+/g, " ").slice(0, 2000)

    var line = "- [ ] " + (range !== "" ? range + " " : "") + title
    if (loc !== "") line += " (" + loc + ")"
    if (desc !== "") line += " — " + desc

    syncProc.command = [
      "node", root.scriptPath,
      "--vault", root.vaultPath,
      "--note", note,
      "--id", String(w.event.id || ""),
      "--line", line
    ]
    if (SpawnGuard.valid(syncProc.command)) syncProc.running = true
    else root.nextWrite()
  }

  // Sanitizes a folder string to safe path segments (no "..", no separators
// beyond "/", only word chars/spaces/dashes/underscores). Kept in sync with
// the node scripts so a crafted daily-notes.json can never redirect writes.
  function sanitizeFolder(f) {
    var s = String(f || "")
      .replace(/^[/\\]+/, "")
      .replace(/[/\\]+$/, "")
      .replace(/[\\]/g, "/")
    var parts = s.split("/")
    var out = []
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i]
      if (p === "" || p === "." || p === "..") continue
      out.push(p.replace(/[^A-Za-z0-9 _-]/g, ""))
    }
    return out.join("/")
  }

  // Renders a YYYY-MM-DD key using Obsidian's Moment-style date format.
  // Supports YYYY/YY, MMMM/MMM/MM/M, dddd/ddd, DD/D, e, and [escaped] text.
  function formatDateKey(key, fmt) {
    if (!fmt) return key
    var y = parseInt(key.slice(0, 4), 10)
    var m = parseInt(key.slice(5, 7), 10)
    var d = parseInt(key.slice(8, 10), 10)
    var wd = new Date(Date.UTC(y, m - 1, d)).getUTCDay()
    var daysShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    var daysFull = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    var monthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var monthsFull = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    var pad2 = function(n) { return n < 10 ? "0" + n : "" + n }
    var tokens = [
      ["dddd", daysFull[wd]],
      ["ddd", daysShort[wd]],
      ["MMMM", monthsFull[m - 1]],
      ["MMM", monthsShort[m - 1]],
      ["YYYY", "" + y],
      ["YY", pad2(y % 100)],
      ["MM", pad2(m)],
      ["M", "" + m],
      ["DD", pad2(d)],
      ["D", "" + d],
      ["e", "" + wd]
    ]
    var out = ""
    var i = 0
    while (i < fmt.length) {
      var c = fmt.charAt(i)
      if (c === "[") {
        var end = fmt.indexOf("]", i + 1)
        if (end === -1) end = fmt.length
        for (var j = i + 1; j < end; j++) out += fmt.charAt(j)
        i = end + 1
        continue
      }
      var hit = ""
      for (var t = 0; t < tokens.length; t++) {
        if (fmt.indexOf(tokens[t][0], i) === i) {
          hit = tokens[t]
          break
        }
      }
      if (hit === "") { out += c; i++ }
      else { out += hit[1]; i += hit[0].length }
    }
    return out
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: {}
  }

  Process {
    id: syncProc
    // Process reuses the same object; a second start while one is already
    // running would abort the first. The queue guarantees one at a time, and
    // onStreamFinished pulls the next item.
    clearEnvironment: true
    environment: root.trustedEnv
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.nextWrite()
    }
  }

  Process {
    id: detectProc
    clearEnvironment: true
    environment: root.trustedEnv
    command: ["node", root.scriptPath, "--detect-vault"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.vaultDetecting = false
        var out = null
        try { out = JSON.parse(String(text).trim()) } catch (e) {}
        if (out && out.vault) {
          root.vaultPath = out.vault
          root.dailyFolder = root.sanitizeFolder(String(out.folder !== undefined ? out.folder : root.dailyFolder))
          root.dailyFormat = out.format ? String(out.format).slice(0, 64) : root.dailyFormat
          root.saveSettings()
          var ev = root.pendingEvent
          var oldKey = root.pendingOldKey
          root.pendingEvent = null
          root.pendingOldKey = null
          root.vaultReady()
          if (ev) root.syncEvent(ev, oldKey)
          root.importFromNotes()
        }
      }
    }
  }

  Process {
    id: importProc
    clearEnvironment: true
    environment: root.trustedEnv
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = []
        try { list = JSON.parse(String(text).trim()) } catch (e) {}
        if (list && list.length > 0) root.eventsFound(list)
      }
    }
  }

  // Try to learn the vault on startup even if the settings FileView hasn't
  // reported in yet; detection only runs when no path is stored.
  Component.onCompleted: {
    timerStartup.interval = 800
    timerStartup.repeat = false
    timerStartup.running = true
  }

  Timer {
    id: timerStartup
    onTriggered: {
      if (root.vaultPath === "") root.detectVault()
    }
  }
}
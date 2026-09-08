import QtQuick
import Quickshell
import Quickshell.Io
import "SpawnGuard.js" as SpawnGuard

// Manages Omarchy reminder timers for calendar events.
//
// Each plan item from Model.reminderPlan() becomes a transient systemd
// usertimer (`omarchy-reminder-<N>m-calendar-<id>-<yyyymmdd>`) that fires a
// desktop notification at event start minus the chosen lead. Units use the
// `omarchy-reminder-*.timer` glob, so they show up in the built-in reminder
// indicator and `omarchy reminder show`.
Item {
  id: root

  readonly property string reminderDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

  readonly property var trustedEnv: SpawnGuard.envPinned(
    Quickshell.env("PATH") || "",
    Quickshell.env("HOME") || "",
    Quickshell.env("USER") || "",
    Quickshell.env("LANG") || "",
    root.reminderDir)

  Component {
    id: procFactory
    Process {
      clearEnvironment: true
      environment: root.trustedEnv
    }
  }

  function spawn(args) {
    if (!SpawnGuard.valid(args)) return
    var p = procFactory.createObject(root, { command: args })
    p.running = true
  }

  // Reconciles the real timer set with the desired plan: drop every
  // calendar reminder (and its message file), then recreate the plan's.
  function sync(plan) {
    plan = plan || []

    spawn(["systemctl", "--user", "stop", "omarchy-reminder-*calendar-*.timer"])
    spawn(["systemctl", "--user", "reset-failed", "omarchy-reminder-*calendar-*.timer"])
    spawn(["bash", "-c",
      'rm -f "$1"/omarchy-reminder-*calendar-*.message 2>/dev/null; true',
      "bash", root.reminderDir])

    for (var i = 0; i < plan.length; i++) root.scheduleOne(plan[i])
    spawn(["omarchy-shell", "-q", "omarchy.indicators", "refresh"])
  }

  function scheduleOne(item) {
    if (!item || !item.unit || !item.onCalendar) return

    var msg = item.message || ""
    var unit = item.unit

    spawn(["bash", "-c",
      'mkdir -p "$3"; printf "%s" "$1" > "$3"/"$2".message',
      "bash", msg, unit, root.reminderDir])

    spawn(["systemd-run", "--user", "--quiet", "--collect",
      "--on-calendar=" + item.onCalendar,
      "--unit=" + unit,
      "--timer-property=Persistent=true",
      "bash", "-c",
      'omarchy-notification-send -g 󰢌 "Reminder" "$1"; rm -f "$3"/"$2".message; omarchy-shell -q omarchy.indicators refresh >/dev/null 2>&1 || true',
      "bash", msg, unit, root.reminderDir])
  }
}
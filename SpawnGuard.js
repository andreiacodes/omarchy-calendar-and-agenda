// Fail-closed gate for every external command this plugin runs.
//
// Threat model: note, vault and event content are untrusted data. Content
// must never be able to pick WHICH executable runs, smuggle control
// characters into an argument, or influence the child environment in a way
// that could wrap/redirect an executable (LD_PRELOAD, BASH_ENV, PATH, ...).
//
// Every spawn site must route its argv through valid() before executing it
// and must apply envPinned() so children start from a minimal trusted env.

var SYSTEM_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
var OMARCHY_BIN = "/usr/share/omarchy/bin"
var BARE_OK = ["bash", "node", "systemctl", "systemd-run", "mkdir",
  "omarchy-shell", "omarchy-notification-send"]

// True only if argv[0] is a bare allowed name or an absolute path, and no
// argument contains a newline or NUL byte.
function valid(argv) {
  if (!argv || argv.length === 0) return false
  var head = String(argv[0])
  if (head.charAt(0) !== "/" && BARE_OK.indexOf(head) === -1) return false
  for (var i = 0; i < argv.length; i++) {
    var a = String(argv[i])
    if (a.indexOf("\n") !== -1 || a.indexOf("\0") !== -1) return false
  }
  return true
}

// Builds the pinned child environment. Keeps only the handful of variables
// the spawned tools actually need and clears everything else, so no inherited
// LD_PRELOAD/LD_LIBRARY_PATH/BASH_ENV/etc. can affect (or impersonate) a
// child. System dirs come first so bare names can never resolve into a
// user-writable directory that an earlier PATH entry would have favoured.
function envPinned(sessionPath, home, user, lang, runtimeDir) {
  var pathStr = (SYSTEM_PATH + ":" + OMARCHY_BIN +
    (sessionPath ? ":" + sessionPath : ""))
  var seen = {}
  var parts = pathStr.split(":")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var d = parts[i]
    if (d === "" || seen[d]) continue
    seen[d] = true
    out.push(d)
  }
  return {
    "PATH": out.join(":"),
    "HOME": home || "/",
    "USER": user || "",
    "LANG": lang || "C.UTF-8",
    "XDG_RUNTIME_DIR": runtimeDir || "/tmp"
  }
}
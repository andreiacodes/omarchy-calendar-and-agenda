#!/usr/bin/env node
// Appends or replaces a calendar event line in an Obsidian daily note, or
// removes it (--delete).
//
// Security: nothing here ever evals or spawns a shell; content is data. Paths
// that would escape the vault, symlinked notes, malformed ids, and oversized
// lines are rejected so a crafted note or config on a synced device cannot
// make this write (or delete) files outside the chosen vault.
//
// usage:
//   node obsidian-sync.js --vault <vault> --name <note.md> --id <eventId> --line <line>
//   node obsidian-sync.js --vault <vault> --name <note.md> --id <eventId> --delete
//   node obsidian-sync.js --detect-vault            # print {vault,folder,format}
//
// The daily note filename is passed as `--name`; the folder under the vault
// is resolved here, fresh from Obsidian's daily-notes config, so entries
// always land in the "New file location" Obsidian is configured with (no
// folder configured -> vault root).
const fs = require("fs")
const path = require("path")

const args = process.argv.slice(2)
let vault = "", name = "", notePath = "", id = "", line = "", del = false
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--vault") vault = args[++i]
  else if (args[i] === "--name") name = args[++i]
  else if (args[i] === "--note") notePath = args[++i]
  else if (args[i] === "--id") id = args[++i]
  else if (args[i] === "--line") line = args[++i]
  else if (args[i] === "--delete") del = true
  else if (args[i] === "--detect-vault") return printVault()
}

function sanitizeFolder(f) {
  return String(f || "")
    .replace(/[\\]/g, "/")
    .split("/")
    .filter(function (s) { return s !== "" && s !== "." && s !== ".." })
    .map(function (s) { return s.replace(/[\x00-\x1f\x7f]/g, "") })
    .filter(function (s) { return s !== "" })
    .join("/")
}

function printVault() {
  const cfgPath = path.join(process.env.HOME || "", ".config/obsidian/obsidian.json")
  let v = ""
  try {
    const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"))
    const vaults = cfg.vaults || cfg
    for (const vv of Object.values(vaults)) {
      if (vv.open) { v = String(vv.path || ""); break }
    }
    if (!v) {
      const first = Object.values(vaults)[0]
      if (first) v = String(first.path || "")
    }
  } catch (e) { /* obsidian not configured yet -> fallback below */ }
  if (!v) v = fallbackVaultFromHome()
  if (!v) return
  const out = { vault: v, folder: "", format: "YYYY-MM-DD" }
  // Obsidian's daily-notes settings live in the vault itself, so Obsidian is
  // the source of truth: an empty folder means notes live at the vault root.
  try {
    const dn = JSON.parse(
      fs.readFileSync(path.join(v, ".obsidian/daily-notes.json"), "utf8"))
    if (typeof dn.folder === "string") out.folder = dn.folder.trim()
    if (typeof dn.format === "string" && dn.format.trim() !== "") {
      out.format = dn.format.trim()
    }
  } catch (e) {
    // No daily-notes config yet. Obsidian keeps notes at the vault root in
    // that case, so no folder is used — never invent one from a directory
    // that happens to exist (e.g. one this plugin once created).
  }
  out.folder = sanitizeFolder(out.folder)
  out.format = String(out.format).slice(0, 64)
  process.stdout.write(JSON.stringify(out))
}

// Obsidian marks a folder as a vault by keeping a `.obsidian` directory
// inside it. When `~/.config/obsidian/obsidian.json` is missing (Obsidian
// never wrote it) we fall back to that marker so the vault is found no
// matter where it lives — directly in the home folder, or in any top-level
// folder under it (e.g. ~/wiki, ~/Documents/wiki, ~/Notes, ...).
function fallbackVaultFromHome() {
  const home = process.env.HOME || ""
  if (home === "") return ""
  function isVault(dir) {
    try { return fs.existsSync(path.join(dir, ".obsidian")) } catch (e) { return false }
  }
  if (isVault(home)) return home
  try {
    const entries = fs.readdirSync(home, { withFileTypes: true })
    for (const e of entries) {
      if (!e.isDirectory()) continue
      if (e.name.charAt(0) === ".") continue
      const p = path.join(home, e.name)
      if (isVault(p)) return p
    }
  } catch (e) { /* no read access -> no vault */ }
  return ""
}

if (!vault || !id) process.exit(1)
// Back-compat: an older panel sends the full note path as `--note`. Only the
// bare filename is kept; the folder is always chosen below from Obsidian's
// own daily-notes config, never from anything on the command line.
if (!name) {
  if (!notePath) process.exit(1)
  name = path.basename(String(notePath).replace(/[\\]/g, "/"))
}
// `name` must be a bare filename: the folder is chosen below from Obsidian's
// own daily-notes config, never from anything on the command line.
if (/[\/\\]/.test(name)) process.exit(1)
const note = dailyNotePath(vault, name)

// Resolves a daily note's full path from Obsidian's daily-notes plugin config
// ("New file location"), read here at call time so a change to Obsidian's
// settings is picked up immediately. A missing or empty folder means Obsidian
// keeps daily notes at the vault root.
function dailyNotePath(v, noteName) {
  try {
    const dn = JSON.parse(
      fs.readFileSync(path.join(v, ".obsidian/daily-notes.json"), "utf8"))
    if (typeof dn.folder === "string" && dn.folder.trim() !== "") {
      return path.join(v, sanitizeFolder(dn.folder.trim()), noteName)
    }
  } catch (e) { /* no config -> notes live at the vault root */ }
  return path.join(v, noteName)
}

const marker = "<!-- calendar:" + id + " -->"

// Realpath of the nearest existing ancestor of `p` (walks up if needed).
function nearestExistingReal(p) {
  let cur = path.resolve(p)
  while (!fs.existsSync(cur)) {
    const up = path.dirname(cur)
    if (up === cur) return null
    cur = up
  }
  try { return fs.realpathSync(cur) } catch (e) { return null }
}

function insideVault(target) {
  const root = nearestExistingReal(vault)
  const targetDir = nearestExistingReal(path.dirname(target))
  if (!root || !targetDir) return false
  if (targetDir === root) return true
  return targetDir.startsWith(root + path.sep)
}

function guard() {
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) process.exit(1)
  if (line && line.length > 4000) process.exit(1)
  if (!/\.md$/i.test(note)) process.exit(1)
  if (!insideVault(note)) process.exit(1)
  try {
    if (fs.existsSync(note) && fs.lstatSync(note).isSymbolicLink()) process.exit(1)
  } catch (e) { process.exit(1) }
}

if (del) {
  guard()
  removeLine()
} else {
  if (!line) process.exit(1)
  guard()
  try { writeLine() } catch (e) { process.exit(1) }
}

function removeLine() {
  if (!fs.existsSync(note)) process.exit(0)
  try {
    const content = fs.readFileSync(note, "utf8")
    if (!content.includes(marker)) process.exit(0)
    const kept = content.split("\n").filter(function (l) { return !l.includes(marker) })
    const next = kept.join("\n").replace(/\n+$/, "")
    const heading = "# " + path.basename(note, ".md")
    // The note was created solely for the event: removing the event removes
    // the shell. Notes with any other content are kept, minus the line.
    if (next.trim() === "" || next.trim() === heading) {
      fs.unlinkSync(note)
    } else {
      fs.writeFileSync(note, next + "\n")
    }
  } catch (e) {
    process.exit(1)
  }
}

function writeLine() {
  const fullLine = line + " " + marker

  fs.mkdirSync(path.dirname(note), { recursive: true })

  let content = ""
  if (fs.existsSync(note)) content = fs.readFileSync(note, "utf8")

  const lines = content.split("\n")
  let replaced = false
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes(marker)) {
      lines[i] = fullLine
      replaced = true
      break
    }
  }

  if (!replaced) {
    // No heading is created for a new note; just append the event line.
    let joined = content.replace(/\n+$/, "")
    if (joined.length > 0) joined += "\n"
    fs.writeFileSync(note, joined + fullLine + "\n")
  } else {
    fs.writeFileSync(note, lines.join("\n"))
  }
}
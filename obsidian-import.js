#!/usr/bin/env node
// Reads calendar events back out of Obsidian daily notes. Only lines carrying
// the plugin's marker (<!-- calendar:<id> -->) are imported, so entries that
// belong to the plugin on a synced device are picked up. Prints JSON.
// usage:
//   node obsidian-import.js --vault <path> --folder <folder> --format <fmt>
const fs = require("fs")
const path = require("path")

const args = process.argv.slice(2)
let vault = "", folder = "Daily", format = "YYYY-MM-DD"
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--vault") vault = args[++i]
  else if (args[i] === "--folder") folder = args[++i]
  else if (args[i] === "--format") format = args[++i]
}

const MAX_FILES = 1000
const MAX_FILE_BYTES = 200 * 1024
const MAX_EVENTS = 1000
const MAX_TITLE = 200
const MAX_LOCATION = 500
const MAX_DESCRIPTION = 2000

function sanitizeFolder(f) {
  return String(f || "")
    .replace(/^[\/\\]+/, "")
    .replace(/[\/\\]+$/, "")
    .replace(/[\\]/g, "/")
    .split("/")
    .filter(function (s) { return s && s !== "." && s !== ".." })
    .map(function (s) { return s.replace(/[^A-Za-z0-9 _-]/g, "") })
    .join("/")
}

// The scan directory must resolve inside the vault itself.
function vaultDir(v) {
  if (!v) return null
  try { return fs.realpathSync(v) } catch (e) { return null }
}

const monthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const monthsFull = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

function pad2(n) { return n < 10 ? "0" + n : "" + n }
function lowercase(s) { return s.toLowerCase() }

function matchName(s, si, names) {
  for (let n = 0; n < names.length; n++) {
    const len = names[n].length
    if (s.substr(si, len).toLowerCase() === lowercase(names[n])) {
      return { len, idx: n }
    }
  }
  return null
}

// Reverse of the Moment-style format: turn a note filename into YYYY-MM-DD.
function parseFilename(name) {
  const s = name.replace(/\.md$/i, "")
  let y = 0, m = 0, d = 0, i = 0, si = 0
  const takeDigits = function (n) {
    const seg = s.substr(si, n)
    if (!/^\d+$/.test(seg)) return -1
    return parseInt(seg, 10)
  }
  while (i < format.length && si < s.length) {
    const c = format[i]
    if (c === "[") {
      const end = format.indexOf("]", i + 1)
      const lit = format.slice(i + 1, end === -1 ? format.length : end)
      if (s.substr(si, lit.length) !== lit) return ""
      si += lit.length
      i = (end === -1 ? format.length : end) + 1
      continue
    }
    const sub4 = format.substr(i, 4)
    const sub3 = format.substr(i, 3)
    const sub2 = format.substr(i, 2)
    if (sub4 === "YYYY") {
      const v = takeDigits(4); if (v < 0) return ""; y = v; si += 4; i += 4; continue
    }
    if (sub4 === "MMMM") {
      const mm = matchName(s, si, monthsFull); if (!mm) return ""; m = mm.idx + 1; si += mm.len; i += 4; continue
    }
    if (sub4 === "dddd") {
      while (si < s.length && /[A-Za-z]/.test(s[si])) si++
      i += 4; continue
    }
    if (sub3 === "MMM" && s.substr(si, 3).length === 3) {
      const mm = matchName(s, si, monthsShort); if (!mm) return ""; m = mm.idx + 1; si += mm.len; i += 3; continue
    }
    if (sub3 === "ddd") {
      while (si < s.length && /[A-Za-z]/.test(s[si])) si++
      i += 3; continue
    }
    if (sub2 === "YY" && c !== "M" && c !== "D") {
      const v = takeDigits(2); if (v < 0) return ""; y = 2000 + v; si += 2; i += 2; continue
    }
    if (sub2 === "MM" && s.substr(si, 2).length === 2 && /^\d\d$/.test(s.substr(si, 2))) {
      const v = takeDigits(2); m = v; si += 2; i += 2; continue
    }
    if (sub2 === "DD" && s.substr(si, 2).length === 2 && /^\d\d$/.test(s.substr(si, 2))) {
      const v = takeDigits(2); d = v; si += 2; i += 2; continue
    }
    if (c === "M") {
      let seg = s.substr(si, 2)
      if (seg.length === 2 && /^\d\d$/.test(seg)) { m = parseInt(seg, 10); si += 2 }
      else { const v = takeDigits(1); if (v < 1) return ""; m = v; si += 1 }
      i += 1; continue
    }
    if (c === "D") {
      let seg = s.substr(si, 2)
      if (seg.length === 2 && /^\d\d$/.test(seg)) { d = parseInt(seg, 10); si += 2 }
      else { const v = takeDigits(1); if (v < 1) return ""; d = v; si += 1 }
      i += 1; continue
    }
    if (c === "e") {
      if (si < s.length && /^\d$/.test(s[si])) si++
      i += 1; continue
    }
    if (s[si] !== c) return ""
    si++; i++
  }
  if (!y || !m || !d) return ""
  return pad2(y) + "-" + pad2(m) + "-" + pad2(d)
}

function parseLine(raw, id) {
  let base = String(raw || "")
  // Strip any trailing \r from Windows-synced notes.
  base = base.replace(/\r$/, "")
  base = base.replace(/<!--\s*calendar:[^>]*-->/g, "").trim()
  const cb = base.match(/^-\s*\[\s*\S*\s*\]\s*/)
  if (cb) base = base.slice(cb[0].length).trim()
  if (!base) return null

  let startHHMM = "", endHHMM = ""
  const tm = base.match(/^(\d{1,2}):(\d{2})\s*[/•–—-]\s*(\d{1,2}):(\d{2})\s*/)
  if (tm) {
    startHHMM = pad2(parseInt(tm[1], 10)) + tm[2]
    endHHMM = pad2(parseInt(tm[3], 10)) + tm[4]
    base = base.slice(tm[0].length).trim()
  }

  let description = ""
  const dIdx = base.indexOf(" — ")
  if (dIdx !== -1) {
    description = base.slice(dIdx + 3).trim()
    base = base.slice(0, dIdx).trim()
  }

  let location = ""
  const lm = base.match(/\(([^()]*)\)$/)
  if (lm) {
    location = lm[1].trim()
    base = base.replace(/\([^()]*\)\s*$/, "").trim()
  }

  const title = base
  if (!title) return null
  return {
    id: String(id).slice(0, 64),
    startHHMM: startHHMM,
    endHHMM: endHHMM,
    title: title.slice(0, MAX_TITLE),
    location: location.slice(0, MAX_LOCATION),
    description: description.slice(0, MAX_DESCRIPTION)
  }
}

folder = sanitizeFolder(folder)
const rootReal = vaultDir(vault)
const out = []
const dir = folder === "" ? vault : path.join(vault, folder)
let dirReal = null
try { dirReal = fs.realpathSync(dir) } catch (e) { dirReal = dir }
const rootSep = rootReal ? rootReal + path.sep : ""
if (!rootReal || !fs.existsSync(dir) ||
    (dirReal !== rootReal && !dirReal.startsWith(rootSep))) {
  process.stdout.write(JSON.stringify(out))
  process.exit(0)
}
let files = fs.readdirSync(dir).filter(function (f) { return /\.md$/i.test(f) })
files = files.slice(0, MAX_FILES)
for (const file of files) {
  if (out.length >= MAX_EVENTS) break
  const key = parseFilename(file)
  if (!key) continue
  const p = path.join(dir, file)
  let text = ""
  try {
    const st = fs.lstatSync(p)
    if (st.isSymbolicLink()) continue
    if (st.size > MAX_FILE_BYTES) continue
    text = fs.readFileSync(p, "utf8")
  } catch (e) { continue }
  const lines = text.split("\n")
  for (const raw of lines) {
    if (out.length >= MAX_EVENTS) break
    const m = raw.match(/<!--\s*calendar:\s*([A-Za-z0-9_-]{1,64})\s*-->/)
    if (!m) continue
    const ev = parseLine(raw, m[1])
    if (ev) {
      ev.date = key
      out.push(ev)
    }
  }
}
process.stdout.write(JSON.stringify(out))
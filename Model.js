// Events storage and management for the calendar widget.
// One-time events use `date`; repeating events use `startDate` + `repeat`
// (daily / weekly / bi-weekly / specific weekdays) with an optional end.
//
// File I/O happens in the QML layer (FileView + mkdir) — a Quickshell `File`
// type is not reachable from a JS import, so this module is pure JS:
// `seedEvents()` feeds it parsed JSON and the query helpers read the cache.

const DAY_SHORT = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const MONTH_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const MONTH_LONG = ["January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"]

const META = {
  created: "2026-01-01",
  description: "Events: date (YYYY-MM-DD) for one-time; startDate + repeat for recurring (none|daily|weekly|biweekly|weekday list like '1,3,5'); day 1-7 (Monday=1, Sunday=7); startHHMM/endHHMM in HHmm; repeatEnd optional",
  format: "date: YYYY-MM-DD, startDate: YYYY-MM-DD, repeat: none|daily|weekly|biweekly|weekday list '1,3,5', day: 1-7 (Monday-Sunday), startHHMM: HHmm format, endHHMM: HHmm format"
}

var events = []

function seedEvents(list) {
  events = Array.isArray(list) ? list : []
}

function storedEvents() {
  return events
}

function parseStored(text) {
  var data = ("" + (text || "")).trim()
  if (!data) return []
  try {
    var parsed = JSON.parse(data)
    return Array.isArray(parsed.events) ? parsed.events : []
  } catch (e) {
    return []
  }
}

function eventsJson() {
  return JSON.stringify({
    events: events,
    meta: META
  }, null, 2)
}

function dayName(dayNum) {
  var names = ["invalid", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
  return names[dayNum] || "Unknown"
}

function shortDayName(dayNum) {
  return DAY_SHORT[dayNum] || ""
}

function formatTime(hhmm) {
  if (!hhmm || hhmm.length < 4) return "--:--"
  var hour = parseInt(hhmm.slice(0, 2), 10)
  var minute = parseInt(hhmm.slice(2, 4), 10)
  if (isNaN(hour) || isNaN(minute)) return "--:--"
  return pad2(hour) + ":" + pad2(minute)
}

function timeToMinutes(hhmm) {
  if (!hhmm || hhmm.length < 4) return -1
  var h = parseInt(hhmm.slice(0, 2), 10)
  var m = parseInt(hhmm.slice(2, 4), 10)
  return isNaN(h) || isNaN(m) ? -1 : h * 60 + m
}

function pad2(n) {
  n = parseInt(n, 10)
  if (isNaN(n) || n < 0) return "00"
  return (n < 10 ? "0" : "") + n
}

function keyForDate(date) {
  if (!date || isNaN(date.getTime())) return ""
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function todayKey() {
  return keyForDate(new Date())
}

function dateFromKey(key) {
  if (!key) return null
  var m = String(key).match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return null
  var year = parseInt(m[1], 10)
  var month = parseInt(m[2], 10)
  var day = parseInt(m[3], 10)
  var date = new Date(year, month - 1, day)
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return null
  return date
}

function parseDateKey(text) {
  var date = dateFromKey(String(text || "").trim())
  return date ? keyForDate(date) : ""
}

function weekdayNum(date) {
  var d = date.getDay() // 0 Sun .. 6 Sat
  return d === 0 ? 7 : d
}

function addDays(key, n) {
  var date = dateFromKey(key)
  if (!date) return ""
  date.setDate(date.getDate() + n)
  return keyForDate(date)
}

function daysBetween(aKey, bKey) {
  var a = dateFromKey(aKey)
  var b = dateFromKey(bKey)
  if (!a || !b) return NaN
  return Math.round((b.getTime() - a.getTime()) / 86400000)
}

function parseTimeInput(text) {
  var t = String(text || "").trim().toLowerCase()
  if (!t) return ""
  var pm = false
  var am = false
  if (t.indexOf("pm") !== -1) { pm = true; t = t.replace(/pm/g, "").trim() }
  else if (t.indexOf("am") !== -1) { am = true; t = t.replace(/am/g, "").trim() }
  t = t.replace(/\s+/g, "")
  var m = t.match(/^(\d{1,2}):?(\d{2})$/)
  if (!m) return ""
  var h = parseInt(m[1], 10)
  var min = parseInt(m[2], 10)
  if (min < 0 || min > 59) return ""
  if (pm && h < 12) h += 12
  if (am && h === 12) h = 0
  if (h < 0 || h > 23) return ""
  return pad2(h) + pad2(min)
}

function shortDateKey(key) {
  var date = dateFromKey(key)
  if (!date) return ""
  return MONTH_SHORT[date.getMonth()] + " " + date.getDate()
}

function dayLabel(key) {
  var date = dateFromKey(key)
  if (!date) return ""
  return dayName(weekdayNum(date)) + ", " + MONTH_SHORT[date.getMonth()] + " " + date.getDate()
}

function eventTimeRange(event) {
  if (!event) return ""
  var start = formatTime(event.startHHMM)
  var end = formatTime(event.endHHMM || event.startHHMM)
  if (start === end) return start
  return (start || "--") + " – " + (end || "--")
}

function recurrenceDays(event) {
  // Weekday numbers (1=Mon..7=Sun) that `event` can land on.
  var repeat = String(event.repeat || "")
  if (repeat === "daily") return [1, 2, 3, 4, 5, 6, 7]

  var anchor = parseInt(event.day, 10)
  if (isNaN(anchor)) {
    var start = dateFromKey(event.startDate || event.date)
    anchor = start ? weekdayNum(start) : 0
  }

  if (repeat === "weekly" || repeat === "biweekly" || repeat === "") return anchor >= 1 && anchor <= 7 ? [anchor] : []

  // Otherwise treat repeat as a comma-separated weekday list, e.g. "1,3,5".
  var out = []
  var parts = String(repeat).split(",")
  for (var i = 0; i < parts.length; i++) {
    var w = parseInt(parts[i].trim(), 10)
    if (!isNaN(w) && w >= 1 && w <= 7 && out.indexOf(w) === -1) out.push(w)
  }
  return out
}

function eventOccursOn(event, key) {
  if (!event || !key) return false
  var repeat = String(event.repeat || "")

  // One-time event pinned to a specific date (also covers older one-offs that
  // carry `date` without a `repeat` field). A later `endDate` (or a start
  // time after the end time, i.e. crossing midnight) makes it span multiple
  // days; the event then shows on every covered day.
  if (event.date && (repeat === "" || repeat === "none")) {
    var last = eventLastDay(event)
    if (!last) return key === event.date
    return key >= event.date && key <= last
  }

  var days = recurrenceDays(event)
  if (days.length === 0) return false

  var date = dateFromKey(key)
  if (!date) return false
  if (days.indexOf(weekdayNum(date)) === -1) return false

  var start = event.startDate || event.date || ""
  if (start && key < start) return false
  var end = event.repeatEnd || ""
  if (end && key > end) return false

  if (repeat === "biweekly") {
    if (!start) return true
    var diff = daysBetween(start, key)
    if (isNaN(diff) || diff < 0) return false
    if (Math.floor(diff / 7) % 2 !== 0) return false
  }
  return true
}

function eventLastDay(event) {
  if (!event) return ""
  var repeat = String(event.repeat || "")
  if (event.date && (repeat === "" || repeat === "none")) {
    if (event.endDate) return event.endDate
    if (event.endHHMM && event.startHHMM
      && timeToMinutes(event.endHHMM) < timeToMinutes(event.startHHMM)) return addDays(event.date, 1)
    return event.date
  }
  return event.repeatEnd || ""
}

function eventDaySpan(event) {
  var last = eventLastDay(event)
  if (!last || !event.date) return 0
  var diff = daysBetween(event.date, last)
  if (isNaN(diff)) return 0
  return Math.max(1, diff + 1)
}

function eventRepeatLabel(event) {
  if (!event) return ""
  var repeat = String(event.repeat || "")
  if (event.date && (repeat === "" || repeat === "none")) return ""
  if (repeat === "daily") return "Repeats daily"
  if (repeat === "weekly") return "Repeats weekly"
  if (repeat === "biweekly") return "Repeats every 2 weeks"
  var days = recurrenceDays(event)
  if (days.length > 0 && repeat !== "daily") {
    var names = []
    for (var i = 0; i < days.length; i++) names.push(shortDayName(days[i]))
    var end = event.repeatEnd ? " until " + shortDateKey(event.repeatEnd) : ""
    return "Repeats " + names.join(", ") + end
  }
  return ""
}

function getEventsForDay(dayNum) {
  // Legacy weekday query (kept for compatibility). New code prefers
  // getEventsForDate() which understands one-time and repeating events.
  return events
    .filter(function(e) {
      return e.day !== null && e.day === dayNum
    })
    .sort(function(a, b) {
      return (a.startHHMM || "").localeCompare(b.startHHMM || "")
    })
}

function getEventsForDate(key) {
  return decorateLive(events
    .filter(function(e) { return eventOccursOn(e, key) })
    .sort(function(a, b) {
      return (a.startHHMM || "").localeCompare(b.startHHMM || "")
    }), true)
}

function nowHHMM() {
  var d = new Date()
  return pad2(d.getHours()) + pad2(d.getMinutes())
}

// True when the given time (empty = right now) falls inside the event's
// time window. An endHHMM earlier than startHHMM crosses midnight.
function eventIsLive(event, atHHMM) {
  if (!event || !event.startHHMM) return false
  var now = atHHMM || nowHHMM()
  var start = event.startHHMM
  var end = event.endHHMM || event.startHHMM
  if (end < start) return now >= start || now < end
  return now >= start && now < end
}

// Returns shallow copies of the given events with an `isLive` flag attached,
// so views can highlight whatever is happening right now. `singleLive` keeps
// at most the first (earliest-starting) live event flagged, so overlapping
// events don't all light up.
function decorateLive(list, singleLive) {
  var liveSeen = 0
  var out = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    var copy = {}
    for (var k in e) copy[k] = e[k]
    var live = eventIsLive(e)
    if (singleLive && live && liveSeen > 0) live = false
    if (live) liveSeen++
    copy.isLive = live
    out.push(copy)
  }
  return out
}

function nextEventKey(fromKey, limit) {
  var start = fromKey || todayKey()
  var max = typeof limit === "number" ? limit : 60
  for (var i = 0; i <= max; i++) {
    var key = addDays(start, i)
    if (getEventsForDate(key).length > 0) return key
  }
  return ""
}

function daysInMonth(year, month) {
  return new Date(year, month + 1, 0).getDate()
}

function monthLabel(year, month) {
  return MONTH_LONG[month] + " " + year
}

// Builds the 42-cell month grid (6 weeks) used by the month view. Each cell:
// { key, day, isThisMonth, isToday, eventCount, dots }.
function getMonthGrid(year, month) {
  var y = parseInt(year, 10)
  var m = parseInt(month, 10)
  if (isNaN(y) || isNaN(m)) return []
  var today = todayKey()

  var first = new Date(y, m, 1)
  var firstWd = weekdayNum(first)
  var numDays = daysInMonth(y, m)
  var prevDate = new Date(y, m - 1, 1)
  var py = prevDate.getFullYear()
  var pm = prevDate.getMonth()
  var prevLast = daysInMonth(py, pm)

  var out = []
  var lead = firstWd - 1
  for (var i = lead - 1; i >= 0; i--) {
    var d = prevLast - i
    out.push(monthCell(keyForDate(new Date(py, pm, d)), d, false, today))
  }
  for (var d2 = 1; d2 <= numDays; d2++) {
    out.push(monthCell(keyForDate(new Date(y, m, d2)), d2, true, today))
  }
  var nextDate = new Date(y, m + 1, 1)
  var ny = nextDate.getFullYear()
  var nm = nextDate.getMonth()
  var day = 1
  while (out.length < 42) {
    out.push(monthCell(keyForDate(new Date(ny, nm, day)), day, false, today))
    day++
  }
  return out
}

function monthCell(key, dayNum, isThisMonth, today) {
  var count = getEventsForDate(key).length
  return {
    key: key,
    day: dayNum,
    isThisMonth: isThisMonth,
    isToday: key === today,
    eventCount: count,
    dots: Math.min(count, 3)
  }
}

// Returns a 7-entry agenda starting at `startKey` (defaults to today). Each
// entry: { key, weekday, isToday, label, events }.
function getWeekEvents(startKey) {
  var start = startKey || todayKey()

  var out = []
  for (var i = 0; i < 7; i++) {
    var key = addDays(start, i)
    var dayEvents = decorateLive(events
      .filter(function(e) { return eventOccursOn(e, key) })
      .sort(function(a, b) {
        return (a.startHHMM || "").localeCompare(b.startHHMM || "")
      }), true)
    var liveCount = 0
    for (var j = 0; j < dayEvents.length; j++) {
      if (dayEvents[j].isLive) liveCount++
    }
    var date = dateFromKey(key)
    var wd = weekdayNum(date)
    out.push({
      key: key,
      weekday: wd,
      isToday: i === 0,
      hasLive: liveCount > 0,
      label: i === 0 ? dayName(wd) + " · Today" : dayName(wd) + " · " + shortDateKey(key),
      events: dayEvents
    })
  }
  return out
}

function generateEventId() {
  return Date.now().toString(36) + Math.random().toString(36).substr(2, 9)
}

function validateTime(hhmm) {
  if (!hhmm || typeof hhmm !== 'string' || hhmm.length < 4) return false
  var h = parseInt(hhmm.slice(0, 2), 10)
  var m = parseInt(hhmm.slice(2, 4), 10)
  return !isNaN(h) && !isNaN(m) && h >= 0 && h < 24 && m >= 0 && m < 60
}

// Validates and builds an event object. Returns { ok, reason, event }.
function buildEvent(eventData) {
  if (!eventData || !eventData.title || !eventData.title.trim()) {
    return { ok: false, reason: "Event title is required" }
  }

  var start = eventData.startHHMM || eventData.startTime || ""
  var end = eventData.endHHMM || eventData.endTime || start
  start = parseTimeInput(start)
  end = parseTimeInput(end) || start
  if (!validateTime(start)) return { ok: false, reason: "Invalid start time format" }
  if (!validateTime(end)) return { ok: false, reason: "Invalid end time format" }

  var repeat = String(eventData.repeat || "none")
  var dateKey = parseDateKey(eventData.date)
  var startKey = parseDateKey(eventData.startDate || eventData.date)
  var endKey = parseDateKey(eventData.repeatEnd)

  var newEvent = {
    id: generateEventId(),
    title: eventData.title.trim(),
    startHHMM: start,
    endHHMM: end,
    location: (eventData.location || "").trim(),
    description: (eventData.description || "").trim()
  }

  var mins = parseInt(eventData.reminderMins, 10)
  newEvent.reminderMins = isNaN(mins) ? 0 : Math.max(0, Math.min(mins, 1440))

  if (repeat === "none") {
    if (!dateKey) return { ok: false, reason: "Event date is required" }
    newEvent.date = dateKey
    newEvent.day = weekdayNum(dateFromKey(dateKey))
    var spanEndKey = parseDateKey(eventData.endDate)
    if (spanEndKey) {
      if (spanEndKey < dateKey) return { ok: false, reason: "End date must not be before the start date" }
      newEvent.endDate = spanEndKey
    }
  } else {
    if (!startKey) return { ok: false, reason: "A start date is required for repeating events" }
    if (endKey && endKey < startKey) return { ok: false, reason: "Repeat end date must be after the start date" }
    newEvent.repeat = repeat
    newEvent.startDate = startKey
    newEvent.day = parseInt(eventData.day, 10) || weekdayNum(dateFromKey(startKey))
    if (endKey) newEvent.repeatEnd = endKey
  }

  return { ok: true, event: newEvent }
}

// Appends to the in-memory list. Returns { ok, reason }. The caller persists
// the result with `eventsJson()`.
function addEvent(eventData) {
  var res = buildEvent(eventData)
  if (!res.ok) return { ok: false, reason: res.reason }
  events.push(res.event)
  return { ok: true }
}

// Replaces an existing event, keeping its id. Returns { ok, reason }.
function updateEvent(eventData) {
  if (!eventData || !eventData.id) return { ok: false, reason: "Missing event id" }
  var res = buildEvent(eventData)
  if (!res.ok) return { ok: false, reason: res.reason }
  res.event.id = eventData.id
  for (var i = 0; i < events.length; i++) {
    if (events[i].id === eventData.id) {
      events[i] = res.event
      return { ok: true }
    }
  }
  return { ok: false, reason: "Event not found" }
}

// Removes `eventId` from the in-memory list. Returns { ok }.
function deleteEvent(eventId) {
  for (var i = 0; i < events.length; i++) {
    if (events[i].id === eventId) {
      events.splice(i, 1)
      return { ok: true }
    }
  }
  console.log("Event not found:", eventId)
  return { ok: false }
}

function sanitizeUnit(id) {
  return String(id).replace(/[^a-zA-Z0-9_-]/g, "")
}

function fmtDateTime(epochSec) {
  var d = new Date(epochSec * 1000)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) +
    " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds())
}

function keyToEpochSec(key, hhmm) {
  var h = parseInt(hhmm.slice(0, 2), 10)
  var m = parseInt(hhmm.slice(2, 4), 10)
  if (isNaN(h) || isNaN(m)) return 0
  var y = parseInt(key.slice(0, 4), 10)
  var mo = parseInt(key.slice(5, 7), 10) - 1
  var d = parseInt(key.slice(8, 10), 10)
  if (isNaN(y) || isNaN(mo) || isNaN(d)) return 0
  return Math.floor(new Date(y, mo, d, h, m, 0).getTime() / 1000)
}

// Builds the omarchy reminder timers that should exist for the stored events.
// One-time events schedule a single timer; repeating events schedule the next
// REMINDER_HORIZON days of occurrences. Each fires `reminderMins` before the
// event's start time and integrates with `omarchy reminder` (same unit glob,
// same message-file convention).
function reminderPlan() {
  var now = Math.floor(Date.now() / 1000)
  var horizon = 15
  var out = []
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    var mins = e.reminderMins
    if (!(mins > 0)) continue
    if (!validateTime(e.startHHMM)) continue

    var occs = []
    if (e.repeat && e.repeat !== "none") {
      var startKey = todayKey()
      var limit = 400
      if (e.repeatEnd) {
        var span = daysBetween(startKey, e.repeatEnd)
        if (span < 0 || isNaN(span)) continue
        limit = Math.min(limit, span + 1)
      }
      for (var d = 0; d <= limit && occs.length < horizon; d++) {
        var key = addDays(startKey, d)
        if (!eventOccursOn(e, key)) continue
        var ep = keyToEpochSec(key, e.startHHMM)
        if (ep <= now) continue
        occs.push({ key: key, ep: ep })
      }
    } else {
      var k = e.date || e.startDate || ""
      if (k) {
        var ep2 = keyToEpochSec(k, e.startHHMM)
        if (ep2 !== 0 && ep2 > now) occs.push({ key: k, ep: ep2 })
      }
    }

    for (var j = 0; j < occs.length; j++) {
      var at = occs[j].ep - mins * 60
      if (at <= now) continue
      var doc = occs[j].key.replace(/-/g, "")
      out.push({
        id: e.id,
        leadMins: mins,
        onCalendar: fmtDateTime(at),
        message: e.title + " starts at " + formatTime(e.startHHMM),
        unit: "omarchy-reminder-" + mins + "m-calendar-" + sanitizeUnit(e.id) + "-" + doc
      })
    }
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    seedEvents: seedEvents,
    storedEvents: storedEvents,
    parseStored: parseStored,
    eventsJson: eventsJson,
    dayName: dayName,
    shortDayName: shortDayName,
    formatTime: formatTime,
    timeToMinutes: timeToMinutes,
    keyForDate: keyForDate,
    todayKey: todayKey,
    dateFromKey: dateFromKey,
    parseDateKey: parseDateKey,
    weekdayNum: weekdayNum,
    addDays: addDays,
    daysBetween: daysBetween,
    parseTimeInput: parseTimeInput,
    shortDateKey: shortDateKey,
    dayLabel: dayLabel,
    eventTimeRange: eventTimeRange,
    eventOccursOn: eventOccursOn,
    eventRepeatLabel: eventRepeatLabel,
    eventLastDay: eventLastDay,
    eventDaySpan: eventDaySpan,
    getEventsForDay: getEventsForDay,
    getEventsForDate: getEventsForDate,
    getMonthGrid: getMonthGrid,
    monthLabel: monthLabel,
    daysInMonth: daysInMonth,
    getWeekEvents: getWeekEvents,
    nextEventKey: nextEventKey,
    nowHHMM: nowHHMM,
    eventIsLive: eventIsLive,
    reminderPlan: reminderPlan,
    addEvent: addEvent,
    updateEvent: updateEvent,
    deleteEvent: deleteEvent
  }
}
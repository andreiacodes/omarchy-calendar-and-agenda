# Omarchy Calendar

A bar-widget plugin for [Omarchy](https://omarchy.org/): a mini calendar agenda
for your schedule.

## Features

- Week, Day, and Month views (Day | Week | Month toggle)
- Create / edit / delete events with a form
- Repeating events (daily, weekly, bi-weekly, specific weekdays)
- Multi-day events (including overnight ones, e.g. 23:00 → 02:00)
- Today highlighting in week view — when an event is happening right now, only
  that event's row is highlighted
- Omarchy reminders per event (default 15 minutes before start, or None /
  5 / 30 / 60 min) via the standard `omarchy reminder` timers
- Events are persisted to `~/.config/omarchy/calendar/events.json`

## Install

On the machine where the plugin should run:

```bash
omarchy plugin add https://github.com/andreiacodes/omarchy-calendar.git --enable
```

Then place the widget on the bar (adjust section as you like):

```bash
omarchy bar put org.omarchy.calendar --section right
```

The shell hot-reloads plugin code from
`~/.config/omarchy/plugins/org.omarchy.calendar/` — save a copy there if you
want to tweak anything locally.

## Note

The widget code itself contains no personal data; your events live in
`~/.config/omarchy/calendar/events.json`, which is not part of this repo.
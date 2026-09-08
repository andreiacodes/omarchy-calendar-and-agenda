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
- Per-event Omarchy reminders (None / 5 / 15 / 30 / 60 min before start) via
  the standard `omarchy reminder` timers
- Events are persisted to `~/.config/omarchy/calendar/events.json`

## Obsidian integration

Two-way sync between the calendar and your Obsidian daily notes
(`calendar → notes` on save, `notes → calendar` on import):

- Each event is written into the matching daily note as a checklist line hiding
  a marker comment (`<!-- calendar:<id> -->`):

      - [ ] <time> <name-of-the-event> <location> - <description> <!-- calendar:<id> -->

  `<time>` is only written when the event has start/end times (e.g.
  `09:00 – 12:00`); events without times omit it.

- The marker makes updates idempotent: saving an event again replaces its line
  instead of appending a duplicate. The marker is invisible in Obsidian
  preview mode.
- The sync is two-way:
  - Saving, editing, deleting, or moving an event updates the daily notes
    automatically
  - The **⟳** button (Obsidian header) re-adds any events that are no longer
    present in the notes
  - The **⇩** button imports events found in the notes that the plugin does
    not have yet
- Vault, daily folder, and date format are auto-detected from Obsidian's own
  configuration, or stored in `~/.config/omarchy/calendar/settings.json`:

      { "obsidianSync": true,
        "vaultPath": "/home/<you>/my-vault",
        "dailyFolder": "Daily",
        "dailyFormat": "YYYY-MM-DD" }

  Detection reads `~/.config/obsidian/obsidian.json` plus the vault's
  `.obsidian/daily-notes.json`, so whatever vault path you use in Obsidian is
  honoured and the folder / file-format choices made inside Obsidian are
  picked up on every machine. If Obsidian hasn't written its config yet, the
  plugin falls back to scanning the home folder for anything containing a
  `.obsidian` directory — so a vault kept directly in `~/`, or in any folder
  under it (`~/Notes`, `~/Documents`, …), is still found.

## Security

The plugin treats note, vault, and event content as untrusted data:

- All subprocesses exec their argv directly (Quickshell `Process` is
  QProcess); no shell is ever involved, so note text can never become a
  command line.
- Every spawn passes a fail-closed gate (`SpawnGuard.js`): the executable must
  be on an allow-list and no argument may contain a newline or NUL byte.
- Children run with a pinned, minimal environment — inherited `LD_PRELOAD`,
  `BASH_ENV`, and PATH overrides are cleared so execution cannot be redirected
  or wrapped.
- Obsidian writes are confined to the vault by canonical path checks (blocks
  `..` escapes and symlinked notes that point outside the vault); folder names
  taken from Obsidian config are sanitized.
- Import is sandboxed with file-count / file-size / event-count / field-length
  caps to prevent denial of service.
- Every widget label renders as plain text; imported Markdown/HTML is never
  interpreted.
- No privileged binary (`sudo`, `pkexec`, `su`, …) is ever invoked.

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
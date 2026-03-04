# Parsec - Damage Meter

> **Early Alpha** - Core functionality works, but not feature-complete and minimally tested. Expect bugs. Bug reports welcome via the Debug panel (copy-paste log).

A lightweight combat analysis addon for **TurtleWoW** (WoW 1.12.1), built on **SuperWoW** and **Nampower** for accurate combat data that vanilla addons can't provide.

## Requirements

- [SuperWoW](https://github.com/balakethelock/SuperWoW) - Extended combat log with source/target GUIDs, spell IDs, absorbs
- [Nampower](https://github.com/pepopo978/nampower) - Spell queue + SPELL_ENERGIZE events for mana/energy tracking
- WoW Client 1.12.1 (TurtleWoW)

**Both extensions are mandatory.** Without them, Parsec cannot identify combat event sources and will not function.

## Why Parsec?

Traditional vanilla damage meters (DPSMate, SW_Stats, KLHThreatMeter) are limited by the WoW 1.12 combat log, which only provides text strings without structured data. Parsec takes a different approach:

- **SuperWoW structured events** - Instead of regex-parsing combat log strings, Parsec uses SuperWoW's extended events that provide source GUID, target GUID, spell ID, and damage components as discrete values. This eliminates the fragile pattern matching that breaks on localized clients or unusual spell names.
- **Per-player DPS duration** - Most meters divide total damage by the global fight duration, inflating DPS for players who joined late or died early. Parsec tracks each player's first and last combat action and calculates DPS based on their individual activity window.
- **Multi-window views** - Open Damage, DPS, Healing, and HPS simultaneously in separate windows, each with independent segment selection (Overall vs. Current Fight). No tab-switching needed.
- **Pet-owner attribution** - Pet damage is automatically merged with the owner using GUID-based tracking, not name heuristics.
- **Modern UI** - Dark-themed options panel with sidebar navigation, custom bar textures, resizable/movable windows with persistent state across sessions.

## Features

- **Damage** and **DPS** tracking (per-player activity duration)
- **Healing** and **HPS** tracking (effective healing, overheal excluded)
- **Pet merge** - attribute pet damage/healing to owner via GUID
- **Multi-window** - open multiple views simultaneously
- **Segment support** - Overall vs. Current Fight per window
- **Window persistence** - positions, sizes, views and segments saved per character
- **Class colors** - standard WoW class coloring with hash-based fallback for unknown units
- **Custom bar textures** - Solid, Gradient, Striped, Glossy
- **Minimap button** with left/right/middle click actions
- **Options panel** with dark themed UI (sidebar navigation)
- **Debug panel** - message log (last 500 messages) with copy-paste for bug reports
- **Auto show/hide** windows on combat start/end
- **Lock windows** to prevent accidental moving

## Installation

1. Install **SuperWoW** and **Nampower** (see links above)
2. Copy the `Parsec` folder to `Interface\AddOns\`
3. Restart the WoW client

## Slash Commands

| Command | Description |
|---|---|
| `/parsec` | Toggle all windows |
| `/parsec show` / `hide` | Show or hide all windows |
| `/parsec reset` | Reset all combat data |
| `/parsec options` | Open options panel |
| `/parsec minimap` | Toggle minimap button |
| `/parsec debug` | Toggle debug mode |
| `/parsec pets` | Show pet-owner cache |
| `/parsec stats` | Show event statistics |
| `/parsec help` | List all commands |

## Options Panel

- **Bars** - Bar height, spacing, texture, pet merge toggle
- **Window** - Backdrop visibility, opacity, lock positions, reset actions
- **Automation** - Auto show/hide on combat, minimap button, track-all toggle
- **About** - Version info and command reference
- **Debug** - Message log buffer with Select All / Clear / Refresh

## Known Limitations (Alpha)

- Only tested in solo and small group content
- Raid (40-man) performance not yet validated
- No death log or damage breakdown by spell
- No report-to-chat functionality yet
- Threat tracking not implemented

## Architecture

```
Parsec/
  core/
    utils.lua         - Global namespace, class colors, print/debug with log buffer
    eventbus.lua      - Combat log parsing (SuperWoW structured events)
    combat-state.lua  - In-combat detection, segment management
    data-store.lua    - Player data aggregation, sorting, segments
    debug.lua         - Debug mode toggle, stats, event dump
    settings.lua      - Settings defaults, load/save/apply
    bootstrap.lua     - Initialization, slash commands, event wiring
  modules/
    damage.lua        - Damage event handlers
    healing.lua       - Healing event handlers
  ui/
    window.xml        - XML templates for window frames
    window.lua        - Window creation, resize, title bar, bar rendering
    minimap-button.lua- Draggable minimap icon
    options.lua       - Options panel (sidebar + lazy-built panels)
  textures/           - Custom TGA textures (bars, icons, window chrome)
```

## License

All rights reserved.

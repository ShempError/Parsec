# Parsec - Damage Meter

A lightweight combat analysis addon for **TurtleWoW** (WoW 1.12.1).

Requires **SuperWoW** + **Nampower** extensions.

## Features

- **Damage** tracking (total damage per player)
- **DPS** tracking (per-player activity duration, not global fight time)
- **Healing** tracking (effective healing, overheal excluded)
- **HPS** tracking (per-player activity duration)
- **Pet merge** - attribute pet damage/healing to owner
- **Multi-window** - open multiple views simultaneously (Damage + DPS, etc.)
- **Segment support** - Overall vs. Current Fight per window
- **Window persistence** - positions, sizes, views and segments saved per character
- **Class colors** - standard WoW class coloring with hash-based fallback
- **Custom bar textures** - Solid, Gradient, Striped, Glossy
- **Minimap button** with left/right/middle click actions
- **Options panel** with dark themed UI (sidebar navigation)
- **Debug panel** - message log with copy-paste support for troubleshooting
- **Auto show/hide** windows on combat start/end
- **Lock windows** to prevent accidental moving

## Installation

1. Copy the `Parsec` folder to `Interface\AddOns\`
2. Ensure **SuperWoW** and **Nampower** are installed
3. Restart the WoW client

## Slash Commands

| Command | Description |
|---|---|
| `/parsec` | Toggle all windows |
| `/parsec show` | Show all windows |
| `/parsec hide` | Hide all windows |
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
- **Debug** - Message log buffer (last 500 messages) with Select All / Clear / Refresh

## Architecture

```
Parsec/
  core/
    utils.lua         - Global namespace, class colors, print/debug with log buffer
    eventbus.lua      - Combat log parsing (CHAT_MSG_SPELL_*, SuperWoW events)
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
  tools/
    generate-textures.js - Node.js script to generate TGA texture files
```

## Requirements

- WoW Client 1.12.1 (TurtleWoW)
- SuperWoW (extended combat log events)
- Nampower (SPELL_ENERGIZE events)
- Lua 5.0

## License

All rights reserved.

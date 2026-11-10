# Halo

A tiny native macOS menu-bar app for highlighting things on screen while demoing in Teams or recording: glowing rainbow boxes, spotlight, arrows and pen strokes drawn over any app.

## Build

```sh
./build.sh && open Halo.app
```

Needs only the Swift toolchain (Xcode Command Line Tools), no Xcode project.

## Use

| Key | Action |
|---|---|
| ⌃⌥D | Start / stop drawing (stopping keeps drawings, click-through) |
| ⌃⌥X | Clear from anywhere |
| Drag | Draw with current tool |
| Click | Drop a ring marker |
| 1 2 3 4 | Box · Spotlight · Arrow · Pen |
| ⌫ / Z | Undo |
| C | Clear |
| T | Hide / show toolbar |
| Esc | Clear and exit |

The floating toolbar (drag it by the grip) and the menu-bar menu control colour, thickness, motion, glow, auto-fade and click ripples.

When screen sharing, share the whole screen so the overlay is included.

## Preview without screen recording

```sh
HALO_DEMO=1 HALO_RENDER=/tmp/halo.png ./Halo.app/Contents/MacOS/Halo
```

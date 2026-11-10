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
| Hold ⌃⌥D | Draw while held; release clears everything (no toolbar) |
| Tap ⌃⌥D | Toggle drawing mode with toolbar (stopping keeps drawings, click-through) |
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

## Icon

`icon/make-icon.swift` draws the icon. To regenerate:

```sh
swift icon/make-icon.swift
mkdir icon/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s icon/AppIcon.png --out icon/AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) icon/AppIcon.png --out icon/AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns icon/AppIcon.iconset -o icon/AppIcon.icns && rm -r icon/AppIcon.iconset
```

## Preview without screen recording

```sh
HALO_DEMO=1 HALO_RENDER=/tmp/halo.png ./Halo.app/Contents/MacOS/Halo
```

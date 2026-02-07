# MangoWC Keymode/Submap

A Noctalia bar widget that displays the current MangoWC keymode/submap.

## Features

- Shows the active keymode (submap) from MangoWC
- Hides itself when the keymode is `default`
- Supports custom text color

## Requirements

- `mmsg` (MangoWC IPC utility) available in `$PATH`

## Settings

You can customize these settings in Noctalia plugin settings:

- `textColor` (string): Custom text color (e.g. `#ffcc00`). Default: `#f4d24f`
- `maxTextLength` (number): Maximum characters to show (0 = no limit). Default: `30`

## Notes

This widget uses `mmsg -g` to read the current keymode and displays it if it is not `default`.

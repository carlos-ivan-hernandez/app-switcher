# App Switcher

A native macOS replacement for Cmd+Tab that shows open apps as a vertical list (icon + name).

## Build and run

```sh
./build.sh --run
```

On first launch, grant **Accessibility** access in System Settings → Privacy & Security → Accessibility.
The app picks it up within a second, no relaunch needed. Quit it from the menu bar icon.

Because the build is ad-hoc signed, macOS treats each rebuild as a new app: after rebuilding,
remove the old App Switcher entry from the Accessibility list and turn it on again.

## Modes

Pick a mode from the menu bar icon. The choice is remembered.

- **Classic**: hold Cmd, tap Tab to move, release Cmd to switch.
- **Search**: Cmd+Tab opens the list and it stays open. Type to filter, use the arrow
  keys to move, Enter to switch. Backspace edits the filter; Esc or clicking outside closes it.

## Keys (Classic mode)

| Key | Action |
| --- | --- |
| Cmd+Tab | Open / move down |
| Cmd+Shift+Tab | Move up |
| Arrow keys (Cmd held) | Move |
| Release Cmd, or Return | Switch to the selected app |
| Esc | Cancel |

You can also hover and click a row.

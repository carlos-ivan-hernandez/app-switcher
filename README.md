# App Switcher

A native macOS replacement for Cmd+Tab that shows open apps as a vertical list (icon + name).

## Build and run

```sh
./build.sh --run
```

On first launch, grant **Accessibility** access in System Settings → Privacy & Security → Accessibility.
The app picks it up within a second, no relaunch needed. Quit it from the menu bar icon.

The build is signed with a fixed identity (the bundle ID), so the permission survives rebuilds.

If it isn't working, the menu bar icon names the missing permission (Accessibility or
Input Monitoring) and links to its settings page. If App Switcher looks enabled but the menu
still says Accessibility is missing, the entry is from an older build: remove it with − and
add the app again, or run `tccutil reset Accessibility local.carlos.appswitcher`.

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

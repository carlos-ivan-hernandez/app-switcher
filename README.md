# App Switcher

A native macOS replacement for Cmd+Tab that shows open apps as a vertical list (icon + name)
or as a wheel of icons.

## Build

```sh
./build.sh
```

This makes `build/AppSwitcher.app`. Install it with App Installer
(`~/main/dev/repos/app-installer`), which copies it into `/Applications`, quitting and reopening
a copy that was running.

On first launch, grant **Accessibility** access in System Settings → Privacy & Security → Accessibility.
The app picks it up within a second, no relaunch needed.

The build is signed with a fixed identity (the bundle ID), so the permission survives rebuilds.

If it isn't working, the settings window names the missing permission (Accessibility or
Input Monitoring) and links to its settings page. If App Switcher looks enabled but the window
still says Accessibility is missing, the entry is from an older build: remove it with − and
add the app again, or run `tccutil reset Accessibility local.carlos.appswitcher`.

## Settings

Click the menu bar icon to open the settings window. It shows whether Cmd+Tab is active,
lets you pick the mode and appearance, and previews the switcher with the apps you have
open, drawn over your desktop wallpaper. Changes are remembered. Quit App Switcher from
this window too.

## Modes

- **Classic**: hold Cmd, tap Tab to move, release Cmd to switch.
- **Search**: Cmd+Tab opens the list and it stays open. Type to filter, use the arrow
  keys to move, Enter to switch. Backspace edits the filter; Esc or clicking outside closes it.
- **Wheel**: works like Classic, but the icons are arranged in a circle, going clockwise from
  the top, with the selected app's name in the middle. The wheel grows with the number of apps.

## Appearance

Applies to every mode:

- **Background**: **Blur**, **Liquid Glass**, **Clear Glass** (both need macOS 26 or later)
  or **Solid**. With Reduce Transparency on (Accessibility → Display), macOS draws glass and
  blur as solid colors.
- **Opacity**: fades the background from 100% down to 0%; icons and names stay fully visible.

## Keys (Classic and Wheel modes)

| Key | Action |
| --- | --- |
| Cmd+Tab | Open / move down |
| Cmd+Shift+Tab | Move up |
| Arrow keys (Cmd held) | Move |
| Release Cmd, or Return | Switch to the selected app |
| Esc | Cancel |

You can also hover over an app and click it.

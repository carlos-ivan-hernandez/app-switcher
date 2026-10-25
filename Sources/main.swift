import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon

// The menu bar isn't shown for an accessory app, but its shortcuts still work,
// so ⌘W closes the settings window.
let mainMenu = NSMenu()
let windowItem = NSMenuItem()
windowItem.submenu = NSMenu(title: "Window")
windowItem.submenu?.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
mainMenu.addItem(windowItem)
app.mainMenu = mainMenu

app.run()

# shafayet.notifications

A fork of the Omarchy first-party notification service with enhanced integration for the [shavanced.notification-center](https://github.com/shafayet/shavanced.notification-center) widget.

## Features

- **Notification daemon** — Handles Freedesktop notifications via D-Bus
- **Popup toasts** — On-screen notifications with actions, images, and app icons
- **Do Not Disturb** — Toggle DND via bar widget, IPC, or keybindings
- **Persistent history** — Notifications survive shell restarts and are stored on disk
- **History replay** — Show recent notifications as toasts (`showHistory` IPC)
- **Click-to-act** — Click toast to invoke default action or focus app window
- **Toast click sync** — Emits `notificationActedUpon` signal when toast is clicked, allowing bar widgets to update unread status

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  Applications   │────▶│  Notification    │────▶│  Popup toasts       │
│  (libnotify)    │     │  Server (QML)    │     │  (PanelWindow)      │
└─────────────────┘     └────────┬─────────┘     └─────────────────────┘
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
             ┌──────────┐ ┌──────────┐ ┌──────────┐
             │  Live    │ │ History  │ │ Settings │
             │  popups  │ │ (files)  │ │ (DND)    │
             └──────────┘ └──────────┘ └──────────┘
                    │
                    ▼
            ┌───────────────┐
            │ IPC handlers  │
            │ (showHistory, │
            │  clear, etc.) │
            └───────────────┘
```

## Integration with shavanced.notification-center

This service emits a `notificationActedUpon(int originalId)` signal when a toast is clicked (via `invokePopupDefault`). The [shavanced.notification-center](https://github.com/shafayet/shavanced.notification-center) widget connects to this signal to clear its "unread" state, changing the bar icon from "unread" (󱅫) to normal (󰂚) immediately when a notification is acted upon — without waiting for the popup to open.

## Installation

```bash
# Clone to your Omarchy plugins directory
git clone https://github.com/shafayet/shafayet.notifications ~/.config/omarchy/plugins/shafayet.notifications

# Enable the plugin
omarchy plugin enable shafayet.notifications

# Disable the original service (required — only one notification service can run)
omarchy plugin disable omarchy.notifications
```

## Configuration

The service stores its state in `~/.local/state/omarchy/`:
- `notifications.json` — DND preference
- `notifications/` — Live popup files (one per on-screen toast)
- `notifications/history/` — Archived notifications (newest 10)
- `notifications/images/` — Copied app icons and images

History limit is 10 entries (configurable via `historyLimit` property in Service.qml).

## IPC API

Available via `omarchy-ipc notifications <command>` or `qs ipc notifications <command>`:

| Command | Description |
|---------|-------------|
| `dndState` | Returns "on" or "off" |
| `toggleDnd` | Toggles DND, returns new state |
| `setDnd <on|off>` | Sets DND explicitly |
| `isDnd` | Alias for `dndState` |
| `showHistory` | Replays recent notifications as toasts |
| `clear` | Clears history directory (toasts on screen stay) |
| `dismissAll` | Dismisses all on-screen toasts |
| `dismissOne` | Dismisses the most recent toast |
| `invokeLast` | Invokes default action on most recent toast |
| `dismiss <summary>` | Dismisses toasts matching summary substring |

## Key Differences from omarchy.notifications

1. **Plugin ID**: `shafayet.notifications` (third-party) vs `omarchy.notifications` (first-party)
2. **Signal**: Adds `notificationActedUpon(originalId)` for bar widget sync
3. **Service lookup**: Consumers must use `shell.serviceFor("shafayet.notifications")` instead of `shell.firstPartyServiceFor("omarchy.notifications")`

## Development

```bash
# Link for live development
omarchy dev link shafayet.notifications

# Reload shell after changes
omarchy restart shell
```

## License

MIT — forked from Omarchy's notification service.
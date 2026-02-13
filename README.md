# Setup Launcher

An AutoHotkey v2 application manager that automates launching applications via shortcuts and navigates their menus with configurable key sequences.

## Overview

Setup Launcher is designed to automate repetitive application startup workflows. It launches applications through Windows shortcuts (.lnk files) and then sends customizable key sequences to navigate menus, click buttons, or perform any keyboard-driven setup tasks automatically.

## Features

### Core Functionality

- **Shortcut-Based Launching**: Launch any application via its .lnk shortcut file
- **Automatic Key Navigation**: Send configurable key sequences after launch (e.g., navigate to a specific menu, enter credentials, click buttons)
- **Window Title Detection**: Automatically detects and tracks application windows by title
- **Sequential Step Execution**: Execute navigation steps with delays or wait for specific window titles

### Automation Options

- **Auto-Start**: Mark setups to automatically launch when the script starts
- **Keep Active (Relaunch)**: Monitor windows and automatically relaunch if they close unexpectedly
- **Network Availability Check**: Wait for a specific host:port to be reachable before launching (useful for VPN-dependent apps)
- **Hide Windows**: Move application windows off-screen while keeping them alive via DWM thumbnails

### Refresh Cycle

- **Shared Refresh Timer**: A global timer that triggers refresh key sequences on all active setups
- **Configurable Interval**: Set refresh interval in seconds
- **Per-Setup Refresh Steps**: Each setup can have its own set of keys to send during refresh
- **Auto-Recovery**: If a refresh step fails (wrong screen, window unresponsive), the setup is automatically recovered

### User Interface

- **Main Dashboard**: ListView displaying all setups with status (Stopped, Running, Monitoring, Launching, etc.)
- **Setup Editor**: Tabbed interface for configuring General settings, Navigation Steps, and Refresh Steps
- **Floating Countdown**: Optional always-on-top countdown timer showing time until next refresh
- **Tray Menu**: Quick access to show window, run auto-start setups, or exit

## Installation

### Requirements

- Windows 10/11
- [AutoHotkey v2.0](https://www.autohotkey.com/) or later

### Setup

1. Download `SetupLauncher.ahk` and `SetupLauncher.ico`
2. Place both files in the same directory
3. Run `SetupLauncher.ahk` with AutoHotkey v2

Alternatively, compile the script to an executable using AutoHotkey's compiler.

## Usage

### Creating a Setup

1. Click **Add** to open the Setup Editor
2. Enter a **Name** for the setup
3. Click **Browse** to select the application's `.lnk` shortcut file
4. Enter the **Window Title** (or use **Detect** to auto-capture it)
5. Configure options:
   - **Auto-Start**: Launch this setup when the script starts
   - **Hide window**: Move the window off-screen after launch
   - **Keep Active**: Automatically relaunch if the window closes
   - **Wait for network**: Check host:port availability before launching
6. Add **Navigation Steps** (keys sent after launch)
7. Add **Refresh Steps** (keys sent on each refresh cycle)
8. Click **Save**

### Navigation Steps

Navigation steps are executed sequentially after the application window appears:

| Mode | Description |
|------|-------------|
| **Delay (ms)** | Wait for specified milliseconds before next step |
| **Wait for Window Title** | Pause until a window with the specified title appears |

Key syntax follows AutoHotkey conventions:
- `{Enter}`, `{Tab}`, `{Escape}`, `{F1}`-`{F12}` - Special keys
- `!x` - Alt+X
- `^x` - Ctrl+X
- `+x` - Shift+X
- `^+s` - Ctrl+Shift+S

### Refresh Cycle

The refresh cycle is a shared timer that sends configured key sequences to all running setups:

1. Set the **Refresh interval** (in seconds)
2. Click **Start Refresh** to begin the cycle
3. Each setup's **Refresh Steps** will be executed when the timer fires
4. Use **Show Display** to view a floating countdown timer

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+P` | Pause/Resume all automation |
| `Ctrl+Shift+S` | Stop all setups |
| `Ctrl+Shift+Q` | Close all setup windows |
| `Ctrl+Shift+Esc` | Exit application |

## Configuration

Settings are stored in `SetupLauncher.ini` in the same directory as the script.

### Global Settings

- `RefreshInterval` - Refresh cycle interval in seconds
- `AutoRefresh` - Start refresh automatically after all setups launch
- `GlobalAutoStart` - Run auto-start setups when script launches
- `AutoShowCountdown` - Show floating countdown when refresh starts
- `AutoHideCountdown` - Move countdown off-screen automatically

### Per-Setup Settings

- `Name` - Display name
- `ShortcutPath` - Path to .lnk file
- `WindowTitle` - Expected window title
- `AutoStart` - Launch on script start (0/1)
- `KeepActive` - Monitor and relaunch (0/1)
- `CheckInterval` - Monitoring interval in ms
- `CheckNet` - Wait for network (0/1)
- `NetAddress` / `NetPort` / `NetTimeout` / `NetRetryDelay` - Network check settings
- `HideWindow` - Hide window after launch (0/1)
- `StepCount` / `Step_N_Key` / `Step_N_Mode` / `Step_N_Value` - Navigation steps
- `RefreshStepCount` / `RefreshStep_N_*` - Refresh steps

## Technical Details

### Window Management

- Uses DWM (Desktop Window Manager) thumbnails to keep off-screen windows rendering
- Tracks windows by HWND for reliable identification
- Captures final window title after navigation for accurate monitoring

### Key Sending

- Uses `SendEvent` with key delays for reliable modifier key combinations
- Falls back to `ControlSend` when direct sending fails
- Temporarily blocks physical input during navigation to prevent interference

### Network Checking

- Uses Winsock2 to perform TCP port connectivity checks
- Non-blocking connect with select() for timeout handling

## License

This project is provided as-is for personal and educational use.

## Author

Created with AutoHotkey v2.0

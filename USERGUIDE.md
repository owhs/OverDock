# OverDock User Guide

Welcome to OverDock! This guide will help you set up and configure your custom taskbar.

## Installation

- **If using the executable:** Simply download and run `OverDock.exe`. All dependencies are included, and no installation is required!
- **If running from source:**
  1. Ensure you have **AutoHotkey v2** installed. You can download it from [autohotkey.com](https://www.autohotkey.com/).
  2. Clone or download this repository.
  3. Simply run `overdock.ahk`. OverDock will dynamically load itself and appear at the top or bottom of your screen.

## Interacting with OverDock

- **Settings Menu:** Double-click or Right-click any empty space on the OverDock bar to open the Settings GUI.
- **Plugins:** Hovering over plugins typically shows custom stylized tooltips. Left-clicking or Right-clicking will trigger plugin-specific actions (e.g., clicking the SysMon plugin opens Task Manager, clicking Media controls your player).
- **Overflow & Pagination:** If you have too many plugins for your screen width, OverDock will cleanly hide them. A navigation arrow will appear. Clicking it will paginate or slide the plugins into view. Look for the `PageBreakPlugin` to manually force a new page.
- **Hot Areas:** The absolute left and right edges (10 pixels wide) of the bar are invisible buttons. Clicking them can trigger actions like Start Menu, Task View, Show Desktop, or custom scripts.

## Configuration

Settings are stored in `OverDockConfig.ini`, but almost everything can be managed natively from the visual Settings menu. 

### Customizing the Theme
Through the Settings, you can configure:
- **Bar Height & Spacing:** Adjust the thickness of the bar and the padding between icons.
- **Colors:** Fully customizable HEX values for the background, text, icons, hover states, and dropdown menus. 
- **Font & Opacity:** Choose custom font styles and set transparent or solid backgrounds.

### Managing Plugins
In the Settings GUI, you can reorder your plugins:
- **Left, Center, Right align:** You can drag and drop plugins into three distinct alignment sections.
- Missing or misconfigured plugins will appear faded and offer visual warnings.

## Common Issues & Tips
- **Restarting:** If changes do not reflect immediately, or you manually edit the `OverDockConfig.ini`, you can reload the script by right-clicking the AHK tray icon and selecting "Reload".
- **Dynamic Updates:** The bar is "flick-free". This means adding/removing items or changing network speed string text widths will automatically slide other items into place perfectly.

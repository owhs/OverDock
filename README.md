# OverDock

**OverDock** is a high-performance, fully customizable taskbar and overlay dock built entirely in AutoHotkey v2. It provides a sleek, modern, and dynamic top or bottom bar that serves as a powerful replacement or enhancement to the default Windows taskbar. 

Designed with an advanced flexbox-like reflow engine, OverDock smoothly handles a vast array of plugins with flick-free animations, robust overflow management, and extensive theming capabilities.

## Key Features

- **Flick-Free Reflow Engine:** Dynamically calculates widths and smoothly slides or paginates plugins without lag or visual tearing.
- **Robust Plugin System:** Comes with over 20+ plugins including System Monitor, Bluetooth, WebNowPlaying Media, Weather, Todo lists, and more.
- **Advanced Theming:** Customize everything from font, background alpha, shadow offsets, custom colors, gradients, and hover effects.
- **Overflow & Pagination:** Manage crowded bars with native scrolling or pagination for overflowing plugins.
- **Hover & Tooltips:** Custom hook for native pointer feel, along with stylized tooltips and floating dropdown menus.
- **Hot Areas:** Configurable extreme left/right edges to trigger Windows actions (Start Menu, Task View, Desktop) or custom scripts.

## Core Tech Stack

- **AutoHotkey v2:** The primary engine driving the application.
- **Native GUI & GDI+:** Uses native AHK GUI controls and Windows APIs (e.g., DWM, GDI, IPHlpApi) for ultra-fast rendering.
- **Custom Object-Oriented Framework:** Built using heavily class-based AHK v2 features.

## Getting Started

Check out our documentation:
- [User Guide](USERGUIDE.md) - For installation, configuration, and daily use.
- [Developer Guide](DEVGUIDE.md) - For building custom plugins and modifying the core engine.

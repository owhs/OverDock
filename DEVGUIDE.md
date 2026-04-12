# OverDock Developer Guide

This guide describes the internal architecture of OverDock, explaining the flow, state management, and how to create custom plugins.

## Architecture & Flow

The main application logic runs in `overdock.ahk`. The core system is heavily Object-Oriented, built on AHK v2 classes. 

### 1. The Rendering Flow
1. **Initialization:** The script reads `OverDockConfig.ini` to fetch the Left, Center, and Right-ordered plugins. It instantiates them dynamically.
2. **Width Calculation:** The core `OverDockApp` constantly monitors geometry. It queries each active plugin by calling `Plugin.ReqWidth()`.
3. **Reflow & Overflow:** If an element's text changes (e.g., Network speed changes from "KB/s" to "MB/s"), `ReqWidth()` reports the new width. The parent app elegantly shifts all adjacent plugins to prevent overlapping or jumping.
4. **Rendering:** Once geometry is defined, the app calls `Plugin.Render(gui, align, x, h, w)`. The plugin then creates or updates its child Native GUI controls (Text, Pictures).

### 2. The Tick Engine
OverDock operates on fixed loops (Tick engines) to maintain tight control over system resource usage:
- `TickUpdate` (1000ms): Fires every second, calls `p.Update()` on visible plugins.
- `TickHover` (15ms): Checks mouse position for smooth custom UI hover states and tooltip rendering.

## Creating a Plugin

All plugins must extend the `OverDockPlugin` class. They should be saved in the `plugins/` directory named as `YourNamePlugin.ahk` and define a class `YourNamePlugin`.

### Basic Plugin Template

```autohotkey
#Include ../overdock.ahk

class MyCustomPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Displays a custom label"

    ; 1. Request Width
    ReqWidth() {
        ; Use MeasureTextWidth to safely calculate the UI space needed
        this.W := MeasureTextWidth("Hello World", "s10", Config.Theme.Font) + 20
        return super.ReqWidth()
    }

    ; 2. Render UI
    Render(gui, align, x, h, w) {
        ; Create a native AHK GUI control
        this.Lbl := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans c" Config.Theme.Text, "Hello World")
        
        ; Register built-in hover colors
        this.RegisterHover(this.Lbl.Hwnd, Config.Theme.Text, Config.Theme.IconHover)
        
        ; Attach events natively
        this.Lbl.OnEvent("Click", (*) => Run("notepad.exe"))
        
        ; Important: Register right-click config popups
        this.Lbl.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Lbl.Hwnd))
        
        return w
    }

    ; 3. Internal Updates (Fired on Tick)
    Update() {
        if HasProp(this, "Lbl") && this.Lbl.Hwnd {
            ; Periodically update the data
            ; this.Lbl.Value := "New Data"
        }
    }
}
```

## Plugin Settings & Configuration

Plugins often need their own configuration. OverDock provides an easy interface to inject your settings UI into the main visual flow.

By overriding `BuildCustomConfig` and `SaveCustomConfig`, you can automatically append settings to the plugin's context menu.

```autohotkey
    BuildCustomConfig(gui, yPos, drawWidth) {
        s := this.App.Scale
        
        ; Add UI elements
        gui.Add("Text", "x15 y" yPos " w" drawWidth " h20 BackgroundTrans cWhite", "My Settings")
        yPos += 25
        
        ; OverDock exposes helpful wrappers for consistent UI
        this.AddCheckbox(gui, 15, yPos, 150, 25, this, "MySettingVar", "Enable Feature X")
        
        ; Return the new computed Y position so the parent window sizes correctly
        return yPos + 35 
    }

    SaveCustomConfig() {
        ; Write to OverDockConfig.ini under your plugin's unique section
        this.SetConfig("MySettingVar", this.MySettingVar)
    }
```

## Helpful Methods & Tools
Inside your plugin, you have access to helpful parents:

- `this.App`: The parent `OverDockApp`. Helpful for checking `this.App.Scale` for DPI changes.
- `this.GetConfig("Key", Default)`: Fetches a value specifically scoped to your plugin from `OverDockConfig.ini`.
- `this.SetConfig("Key", Value)`: Saves a value to your scope.
- `this.RegisterHover(hwnd, defaultColorHex, hoverColorHex)`: A highly optimized, multi-threaded C++/AHK wrapper that ensures 60 FPS fade transitions without freezing the main thread.

#Include ../overdock.ahk
class ExplorerContextualPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Contextual controls for active windows."
    W := 80
    static ActiveClass := ""
    static ActivePath := ""

    ReqWidth() {
        if (ExplorerContextualPlugin.ActiveClass != "CabinetWClass" || !DirExist(ExplorerContextualPlugin.ActivePath))
            return 0
        return super.ReqWidth()
    }
    Render(gui, align, x, h, w) {
        if (w <= 0) w := Round(this.W * this.App.Scale)
            dw := w / 2

        gui.SetFont("s12 q5 c" Config.Theme.IconHover, Config.Theme.IconFont)
        this.Btn1 := this.AddCtrl(gui, "Text", "x" x " y0 w" dw " h" h " 0x200 Center BackgroundTrans", Chr(0xE756))
        this.RegisterHover(this.Btn1.Hwnd, Config.Theme.IconHover, Config.Theme.Icon)
        this.Btn1.OnEvent("Click", (*) => this.ExecuteContext(false))
        this.Btn1.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Btn1.Hwnd))

        gui.SetFont("s12 q5 c" StrReplace(Config.Theme.Icon, "#", ""), Config.Theme.IconFont)
        this.Btn2 := this.AddCtrl(gui, "Text", "x" (x + dw) " y0 w" dw " h" h " 0x200 Center BackgroundTrans", Chr(0xE756))
        this.RegisterHover(this.Btn2.Hwnd, StrReplace(Config.Theme.Icon, "#", ""), StrReplace(Config.Theme.Danger, "#", ""))
        this.Btn2.OnEvent("Click", (*) => this.ExecuteContext(true))
        this.Btn2.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Btn2.Hwnd))

        return w
    }
    MoveCtrls(x, w) {
        dw := w / 2
        this.Btn1.Move(x, , dw)
        this.Btn2.Move(x + dw, , dw)
    }

    Update() {
        if !HasProp(this, "Btn1")
            return
        try {
            hwnd := WinGetID("A")
            cls := WinGetClass(hwnd)
            title := WinGetTitle(hwnd)
            path := ""
            
            if (cls == "CabinetWClass") {
                if (HasProp(this, "LastHwnd") && this.LastHwnd == hwnd && HasProp(this, "LastTitle") && this.LastTitle == title && HasProp(this, "SavedPath")) {
                    path := this.SavedPath
                } else {
                    for window in ComObject("Shell.Application").Windows {
                        if (window.HWND == hwnd) {
                            path := window.Document.Folder.Self.Path
                            break
                        }
                    }
                    this.LastHwnd := hwnd
                    this.LastTitle := title
                    this.SavedPath := path
                }
            } else {
                cls := ""
                this.LastHwnd := ""
                this.LastTitle := ""
                this.SavedPath := ""
            }
            
            if (cls != ExplorerContextualPlugin.ActiveClass || path != ExplorerContextualPlugin.ActivePath) {
                ExplorerContextualPlugin.ActiveClass := cls
                ExplorerContextualPlugin.ActivePath := path
                this.App.Reflow()
            }
        } catch {
            if (ExplorerContextualPlugin.ActiveClass != "") {
                ExplorerContextualPlugin.ActiveClass := ""
                ExplorerContextualPlugin.ActivePath := ""
                this.LastHwnd := ""
                this.LastTitle := ""
                this.SavedPath := ""
                this.App.Reflow()
            }
        }
    }
    ExecuteContext(admin := false) {
        verb := admin ? "*RunAs " : ""
        if (ExplorerContextualPlugin.ActiveClass == "CabinetWClass") {
            path := ExplorerContextualPlugin.ActivePath
            if SubStr(path, -1) == ""
                path .= ""
            try {
                if (path != "")
                    Run(verb "wt.exe -d `"" path "`"")
                else
                    Run(verb "wt.exe")
            } catch {
                if (path != "")
                    Run(verb "cmd.exe /k cd /d `"" path "`"")
                else
                    Run(verb "cmd.exe")
            }
        }
    }
}
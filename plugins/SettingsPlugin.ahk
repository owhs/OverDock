#Include ../overdock.ahk
class SettingsPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Opens the overdock configuration settings."
    W := 40
    Render(gui, align, x, h, w) {
        if (w <= 0) w := Round(this.W * this.App.Scale)
            gui.SetFont("s13 q5 c" Config.Theme.Icon, Config.Theme.IconFont)
        this.Btn := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", Chr(0xE713))
        this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
        this.Btn.OnEvent("Click", (*) => OpenSettingsGUI())
        this.Btn.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Btn.Hwnd))
        return w
    }
    MoveCtrls(x, w) {
        this.Btn.Move(x, , w)
    }
}
#Include ../overdock.ahk
class UptimePlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Shows continuous system uptime."
    W := 60
    ReqWidth() {
        this.W := this.GetConfig("Width", 70)
        return super.ReqWidth()
    }
    BuildCustomConfig(gui, yP, dW) {
        s := this.App.Scale
        gui.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(80 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Width:")
        this.eW := gui.Add("Edit", "x" Round(100 * s) " y" yP " w" Round(50 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Number Center", this.W)
        return yP + Round(35 * s)
    }
    SaveCustomConfig() {
        this.SetConfig("Width", this.eW.Value)
    }
    Render(gui, align, x, h, w) {
        if (w <= 0) w := Round(this.W * this.App.Scale)
            gui.SetFont("s10 w500 q5 c" Config.Theme.Text, Config.Theme.Font)
        this.Lbl := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", "0h 0m")
        this.RegisterHover(this.Lbl.Hwnd, Config.Theme.Text, Config.Theme.IconHover)
        this.Lbl.OnEvent("Click", (*) => Run("taskmgr.exe /3"))
        this.Lbl.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Lbl.Hwnd))
        this.Update()
        return w
    }
    MoveCtrls(x, w) {
        this.Lbl.Move(x, , w)
    }
    Update() {
        tick := A_TickCount // 1000
        d := tick // 86400
        tick := Mod(tick, 86400)
        h := tick // 3600
        tick := Mod(tick, 3600)
        m := tick // 60

        str := ""
        if (d > 0)
            str .= d "d "
        str .= h "h " m "m"
        if (this.Lbl.Value != str)
            this.Lbl.Value := str
    }
}
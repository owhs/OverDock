#Include ../overdock.ahk
class PowerPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Shutdown, restart, and sleep controls."
    W := 40
    Render(gui, align, x, h, w) {
        if (w <= 0) w := Round(this.W * this.App.Scale)
            gui.SetFont("s13 q5 c" Config.Theme.Icon, Config.Theme.IconFont)
        this.Btn := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", Chr(0xE7E8))
        this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, StrReplace(Config.Theme.Danger, "#", ""))
        this.Btn.OnEvent("Click", (*) => this.ShowPowerMenu())
        this.Btn.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Btn.Hwnd))
        return w
    }
    MoveCtrls(x, w) {
        this.Btn.Move(x, , w)
    }
    ShowPowerMenu() {
        s := this.App.Scale
        ag := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" this.App.Gui.Hwnd)
        ag.IsDynamic := true
        ag.BackColor := Config.Theme.DropBg
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 19, "Int*", 1, "Int", 4)

        opts := [{ i: Chr(0xE713), t: "Lock", c: (*) => DllCall("user32\LockWorkStation") }, { i: Chr(0xE708), t: "Sleep", c: (*) => DllCall("PowrProf\SetSuspendState", "Int", 0, "Int", 0, "Int", 0) }, { i: Chr(0xE777), t: "Restart", c: (*) => Run("shutdown /r /t 0") }, { i: Chr(0xE7E8), t: "Shut Down", c: (*) => Run("shutdown /s /t 0") }
        ]

        yP := Round(5 * s), dW := Round(180 * s), rH := Round(35 * s)
        for item in opts {
            bg := ag.Add("Text", "x0 y" yP " w" dW " h" rH " BackgroundTrans", "")
            ag.SetFont("s" Round(13 * s) " q5 c" Config.Theme.IconHover, Config.Theme.IconFont)
            iL := ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(30 * s) " h" rH " 0x200 BackgroundTrans", item.i)
            ag.SetFont("s" Round(11 * s) " w500 q5 c" Config.Theme.DropText, Config.Theme.Font)
            tL := ag.Add("Text", "x" Round(45 * s) " y" yP " w" Round(120 * s) " h" rH " 0x200 BackgroundTrans", item.t)

            act := ((fn, *) => (this.App.ClosePopup(), fn())).Bind(item.c)
            bg.OnEvent("Click", act), iL.OnEvent("Click", act), tL.OnEvent("Click", act)

            hovC := item.t == "Shut Down" ? StrReplace(Config.Theme.Danger, "#", "") : Config.Theme.IconHover
            grp := [iL.Hwnd, tL.Hwnd]
            this.RegisterHover(bg.Hwnd, Config.Theme.DropText, hovC, grp)
            this.RegisterHover(iL.Hwnd, Config.Theme.DropText, hovC, grp)
            this.RegisterHover(tL.Hwnd, Config.Theme.DropText, hovC, grp)
            yP += rH
        }
        this.App.TogglePopup(ag, this.Btn.Hwnd, dW, yP + Round(5 * s))
    }
}
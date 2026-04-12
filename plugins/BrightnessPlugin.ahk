#Include ../overdock.ahk
class BrightnessPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Displays and sets monitor brightness."
    W := 40
    ReqWidth() {
        this.Supported := false
        try {
            for obj in ComObjGet("winmgmts:\\.\root\WMI").ExecQuery("SELECT * FROM WmiMonitorBrightness") {
                this.Supported := true
                this.Cur := obj.CurrentBrightness
            }
        }
        if !this.Supported
            return 0
        this.W := this.GetConfig("ShowPct", 0) ? 80 : 40
        return super.ReqWidth()
    }
    BuildCustomConfig(gui, yP, dW) {
        s := this.App.Scale
        this.ShowPct := this.GetConfig("ShowPct", 0)

        gui.SetFont("s" Round(13 * s) " q5 c" Config.Theme.IconHover, Config.Theme.IconFont)
        this.cbIcn := gui.Add("Text", "x" Round(15 * s) " y" yP " w" Round(20 * s) " h" Round(25 * s) " BackgroundTrans", this.ShowPct ? Chr(0xE73A) : Chr(0xE739))
        gui.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)
        this.cbTxt := gui.Add("Text", "x" Round(45 * s) " y" (yP + Round(3 * s)) " w" (dW - Round(60 * s)) " h" Round(20 * s) " BackgroundTrans", "Show % in Bar")

        act := (*) => (
            this.ShowPct := !this.ShowPct,
            this.cbIcn.Value := this.ShowPct ? Chr(0xE73A) : Chr(0xE739)
        )
        this.cbIcn.OnEvent("Click", act), this.cbTxt.OnEvent("Click", act)
        if IsSet(AppCursorMap)
            AppCursorMap[this.cbIcn.Hwnd] := 1, AppCursorMap[this.cbTxt.Hwnd] := 1

        return yP + Round(30 * s)
    }
    SaveCustomConfig() {
        this.SetConfig("ShowPct", this.ShowPct)
    }
    Render(gui, align, x, h, w) {
        s := this.App.Scale
        if (w <= 0) w := Round(this.W * s)
            showPct := this.GetConfig("ShowPct", 0)
        gui.SetFont("s13 q5 c" Config.Theme.Icon, Config.Theme.IconFont)
        this.Btn := this.AddCtrl(gui, "Text", "x" x " y0 w" Round((showPct ? 35 : this.W) * s) " h" h " 0x200 Center BackgroundTrans", Chr(0xE706))

        if (showPct) {
            gui.SetFont("s10 w500 q5 c" Config.Theme.Text, Config.Theme.Font)
            this.TxtPct := this.AddCtrl(gui, "Text", "x" (x + Round(35 * s)) " y0 w" Round(45 * s) " h" h " 0x200 Left BackgroundTrans", this.Cur "%")
            grp := [this.Btn.Hwnd, this.TxtPct.Hwnd]
            this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover, grp)
            this.RegisterHover(this.TxtPct.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp)
            this.TxtPct.OnEvent("Click", (*) => this.BtnClick())
            this.TxtPct.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.TxtPct.Hwnd))
        } else {
            this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
        }

        this.BuildSlider()
        this.Btn.OnEvent("Click", (*) => this.BtnClick())
        this.Btn.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Btn.Hwnd))
        return w
    }
    MoveCtrls(x, w) {
        s := this.App.Scale
        if HasProp(this, "TxtPct") {
            this.Btn.Move(x, , Round(35 * s))
            this.TxtPct.Move(x + Round(35 * s), , Max(0, w - Round(35 * s)))
        } else {
            this.Btn.Move(x, , w)
        }
    }
    BtnClick() {
        this.App.TogglePopup(this.SldGui, this.Btn.Hwnd, this.DW, this.DH)
    }
    BuildSlider() {
        s := this.App.Scale
        this.SldGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" this.App.Gui.Hwnd)
        this.SldGui.BackColor := Config.Theme.DropBg
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.SldGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.SldGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        this.DW := Round(250 * s), this.DH := Round(60 * s)
        this.SldGui.SetFont("s" Round(13 * s) " q5 c" Config.Theme.DropText, Config.Theme.IconFont)
        this.SldGui.Add("Text", "x" Round(15 * s) " y" Round(15 * s) " w" Round(30 * s) " h" Round(30 * s) " 0x200 BackgroundTrans", Chr(0xE706))
        this.SldGui.SetFont("s" Round(11 * s) " w500 q5 c" Config.Theme.DropText, Config.Theme.Font)
        this.Txt := this.SldGui.Add("Text", "x" Round(200 * s) " y" Round(15 * s) " w" Round(40 * s) " h" Round(30 * s) " 0x200 Right BackgroundTrans", this.Cur "%")

        this.CurVol := this.Cur
        sliderHex := StrReplace(Config.Theme.Slider, "#", "")
        this.SldBg := this.SldGui.Add("Text", "x" Round(45 * s) " y" Round(26 * s) " w" Round(150 * s) " h" Round(8 * s) " Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 5) " 0x0100", "")
        this.TrkFill := this.SldGui.Add("Text", "x" Round(45 * s) " y" Round(26 * s) " w" Round(1.5 * s * this.CurVol) " h" Round(8 * s) " Background" sliderHex " 0x0100", "")
        this.Hitbox := this.SldGui.Add("Text", "x" Round(45 * s) " y" Round(15 * s) " w" Round(150 * s) " h" Round(30 * s) " BackgroundTrans 0x0100", "")
        this.Hitbox.OnEvent("Click", (*) => "")

        this._fnOnSlideDown := ObjBindMethod(this, "OnSlideDown")
        OnMessage(0x0201, this._fnOnSlideDown)
    }
    Destroy() {
        if HasProp(this, "_fnOnSlideDown")
            OnMessage(0x0201, this._fnOnSlideDown, 0)
    }
    OnSlideDown(wParam, lParam, msg, hwnd) {
        try {
            if HasProp(this, "Hitbox") && (hwnd == this.Hitbox.Hwnd || hwnd == this.TrkFill.Hwnd || hwnd == this.SldBg.Hwnd) {
                CoordMode("Mouse", "Client")
                s := this.App.Scale
                baseX := Round(45 * s), maxW := Round(150 * s)
                while GetKeyState("LButton", "P") {
                    MouseGetPos(&mX)
                    relX := mX - baseX
                    relX := relX < 0 ? 0 : (relX > maxW ? maxW : relX)
                    this.CurVol := (relX / maxW) * 100
                    try {
                        for obj in ComObjGet("winmgmts:\\.\root\WMI").ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")
                            obj.WmiSetBrightness(1, this.CurVol)
                    }
                    this.ApplyVisuals()
                    Sleep(15)
                }
            }
        }
    }
    ApplyVisuals() {
        this.TrkFill.Move(, , Round(1.5 * this.App.Scale * this.CurVol))
        this.Txt.Value := Round(this.CurVol) "%"
        if HasProp(this, "TxtPct")
            this.TxtPct.Value := Round(this.CurVol) "%"
    }
}
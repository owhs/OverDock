#Include ../overdock.ahk
class BatteryPlugin extends OverDockPlugin {
    ReqWidth() {
        this.IsDesktop := true
        sps := Buffer(12, 0)
        ac := 0, pct := 255
        if DllCall("kernel32\GetSystemPowerStatus", "Ptr", sps) {
            ac := NumGet(sps, 0, "UChar")
            pct := NumGet(sps, 2, "UChar")
            if (pct != 255)
                this.IsDesktop := false
        }
        if this.IsDesktop
            return 0

        this.ShowPct := this.GetConfig("ShowPct", 1)
        this.ShowIcon := this.GetConfig("ShowIcon", 1)
        this.PctOnBatOnly := this.GetConfig("PctOnBatOnly", 0)

        this.IsVisPct := this.ShowPct
        if (this.ShowPct && this.PctOnBatOnly && ac == 1)
            this.IsVisPct := false

        if (!this.IsVisPct && !this.ShowIcon)
            return 0

        this.W := (this.IsVisPct ? 45 : 0) + (this.ShowIcon ? 25 : 0)
        return super.ReqWidth()
    }
    BuildCustomConfig(gui, yP, dW) {
        s := this.App.Scale
        this.AddCheckbox(gui, Round(15 * s), yP, dW - Round(30 * s), Round(25 * s), this, "ShowPct", "Show Percentage")
        yP += Round(30 * s)
        this.AddCheckbox(gui, Round(15 * s), yP, dW - Round(30 * s), Round(25 * s), this, "ShowIcon", "Show Battery Icon")
        yP += Round(30 * s)
        this.AddCheckbox(gui, Round(15 * s), yP, dW - Round(30 * s), Round(25 * s), this, "PctOnBatOnly", "Percent on Battery only")
        return yP + Round(30 * s)
    }
    SaveCustomConfig() {
        this.SetConfig("ShowPct", this.ShowPct)
        this.SetConfig("ShowIcon", this.ShowIcon)
        this.SetConfig("PctOnBatOnly", this.PctOnBatOnly)
    }
    Render(gui, align, x, h, w) {
        s := this.App.Scale
        if (w <= 0) w := Round(this.W * s)
            iconW := Round((this.ShowIcon ? 25 : 0) * s)
        txtW := w - iconW

        grp := []
        if (this.ShowPct) {
            gui.SetFont("s10 w500 q5 c" Config.Theme.Text, Config.Theme.Font)
            this.Txt := this.AddCtrl(gui, "Text", "x" x " y0 w" txtW " h" h " 0x200 Right BackgroundTrans", "100%")
            grp.Push(this.Txt.Hwnd)
        }
        if (this.ShowIcon) {
            gui.SetFont("s13 q5 c" Config.Theme.Icon, Config.Theme.IconFont)
            this.Icn := this.AddCtrl(gui, "Text", "x" (x + txtW) " y0 w" iconW " h" h " 0x200 Center BackgroundTrans", Chr(0xEBAA))
            grp.Push(this.Icn.Hwnd)
        }

        if (this.ShowPct)
            this.RegisterHover(this.Txt.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp)
        if (this.ShowIcon)
            this.RegisterHover(this.Icn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover, grp)

        act := (*) => Run("ms-settings:batterysaver")
        if (this.ShowPct) {
            this.Txt.OnEvent("Click", act)
            this.Txt.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Txt.Hwnd))
            if (!this.IsVisPct)
                this.Txt.Visible := false
        }
        if (this.ShowIcon) {
            this.Icn.OnEvent("Click", act)
            this.Icn.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Icn.Hwnd))
        }
        return w
    }
    MoveCtrls(x, w) {
        s := this.App.Scale
        iconW := Round((this.ShowIcon ? 25 : 0) * s)
        txtW := w - iconW
        if (HasProp(this, "Txt")) {
            this.Txt.Move(x, , txtW)
            this.Txt.Visible := (txtW > 0)
        }
        if (HasProp(this, "Icn")) {
            this.Icn.Move(x + txtW, , iconW)
            this.Icn.Visible := (iconW > 0)
        }
    }
    Update() {
        sps := Buffer(12, 0)
        if DllCall("kernel32\GetSystemPowerStatus", "Ptr", sps) {
            ac := NumGet(sps, 0, "UChar"), pct := NumGet(sps, 2, "UChar")
            if (pct != 255) {
                targetVisPct := this.ShowPct
                if (this.ShowPct && this.PctOnBatOnly && ac == 1)
                    targetVisPct := false

                if (HasProp(this, "IsVisPct") && targetVisPct != this.IsVisPct) {
                    this.IsVisPct := targetVisPct
                    this.App.needsReflow := true
                }

                if HasProp(this, "Txt") && this.Txt.Value != pct "%"
                    this.Txt.Value := pct "%"
                if HasProp(this, "Icn") {
                    if (ac == 1)
                        iV := Chr(0xEBB5)
                    else if (pct > 80)
                        iV := Chr(0xEBAA)
                    else if (pct > 50)
                        iV := Chr(0xEBA6)
                    else if (pct > 20)
                        iV := Chr(0xEBA2)
                    else
                        iV := Chr(0xEBA0)
                    if (this.Icn.Value != iV)
                        this.Icn.Value := iV
                }
            }
        }
    }
}
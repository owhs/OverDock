#Include ../overdock.ahk

class ClockPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Displays current date and time."
    BuildCustomConfig(gui, yP, dW) {
        s := this.App.Scale
        gui.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(80 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Format:")
        this.eFmt := gui.Add("Edit", "x" Round(100 * s) " y" yP " w" Round(120 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", this.GetConfig("Fmt", "ddd, MMM d  •  h:mm tt"))
        yP += Round(35 * s)

        this.AllCaps := this.GetConfig("AllCaps", 0)
        this.AddCheckbox(gui, Round(15 * s), yP, dW - Round(30 * s), Round(25 * s), this, "AllCaps", "Force All Caps")
        yP += Round(30 * s)

        return yP + Round(10 * s)
    }
    SaveCustomConfig() {
        this.SetConfig("Fmt", this.eFmt.Value)
        this.SetConfig("AllCaps", this.AllCaps)
    }
    ReqWidth() {
        template := FormatTime("20231230235959", this.GetConfig("Fmt", "ddd, MMM d  •  h:mm tt"))
        if (this.GetConfig("AllCaps", 0))
            template := StrUpper(template)
        this.W := MeasureTextWidth(template, "s" Config.General.ClockSize " w400 q5", Config.Theme.Font) + Round(20 * this.App.Scale)
        return super.ReqWidth()
    }
    Render(gui, align, x, h, w) {
        if (w <= 0) w := Round(this.W * this.App.Scale)
            cSize := Config.General.ClockSize
        gui.SetFont("s" cSize " w400 q5 c" Config.Theme.Text, Config.Theme.Font)
        this.Lbl := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", "00:00")
        this.RegisterHover(this.Lbl.Hwnd, Config.Theme.Text, Config.Theme.IconHover)
        this.Lbl.OnEvent("Click", (*) => this.ShowCalendar(0))
        this.Lbl.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Lbl.Hwnd))
        return w
    }
    MoveCtrls(x, w) {
        this.Lbl.Move(x, , w)
    }
    Update() {
        if HasProp(this, "Lbl") {
            v := FormatTime(, this.GetConfig("Fmt", "ddd, MMM d  •  h:mm tt"))
            if (this.GetConfig("AllCaps", 0))
                v := StrUpper(v)
            if (this.Lbl.Value != v)
                this.Lbl.Value := v
        }
    }

    ShowCalendar(navOffset := 0) {
        s := this.App.Scale
        if (navOffset == 0) {
            if (HasProp(this, "CalGui") && this.App.ActivePopup == this.CalGui) {
                this.App.ClosePopup()
                return
            }
            this.CalMonth := FormatTime(A_Now, "yyyyMM")
        } else {
            this.CalMonth := FormatTime(DateAdd(this.CalMonth "01", navOffset, "Days"), "yyyyMM")
        }

        calGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x08000000 +Owner" this.App.Gui.Hwnd)
        calGui.BackColor := Config.Theme.DropBg
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", calGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", calGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        calGui.SetFont("s" Round(14 * s) " w700 q5 c" Config.Theme.Text, Config.Theme.Font)
        calGui.Add("Text", "x" Round(10 * s) " y" Round(15 * s) " w" Round(200 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans", FormatTime(this.CalMonth "01", "MMMM yyyy"))

        calGui.SetFont("s" Round(12 * s) " q5 c" Config.Theme.Icon, Config.Theme.IconFont)
        bPrev := calGui.Add("Text", "x" Round(10 * s) " y" Round(15 * s) " w" Round(30 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans", Chr(0xE76B))
        bNext := calGui.Add("Text", "x" Round(180 * s) " y" Round(15 * s) " w" Round(30 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans", Chr(0xE76C))
        this.App.RegisterHover(bPrev.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
        this.App.RegisterHover(bNext.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)

        actPrev := (*) => this.ShowCalendar(-1)
        actNext := (*) => this.ShowCalendar(31)
        bPrev.OnEvent("Click", actPrev), bPrev.OnEvent("DoubleClick", actPrev)
        bNext.OnEvent("Click", actNext), bNext.OnEvent("DoubleClick", actNext)

        yOffset := Round(50 * s)
        calGui.SetFont("s" Round(10 * s) " w600 q5 c" Config.Theme.IconHover, Config.Theme.Font)
        days := ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        xOffset := Round(10 * s), dW := Round(30 * s)
        for day in days {
            calGui.Add("Text", "x" xOffset " y" yOffset " w" dW " h" dW " Center 0x200 BackgroundTrans", day)
            xOffset += dW
        }
        yOffset += dW

        curYear := FormatTime(this.CalMonth "01", "yyyy")
        curMonth := FormatTime(this.CalMonth "01", "MM")
        firstDayOfWeek := FormatTime(curYear curMonth "01", "WDay") - 1
        if (firstDayOfWeek == 0)
            firstDayOfWeek := 7

        daysInMonth := 31
        if (curMonth == "04" || curMonth == "06" || curMonth == "09" || curMonth == "11")
            daysInMonth := 30
        else if (curMonth == "02") {
            isLeap := (Mod(curYear, 4) == 0 && Mod(curYear, 100) != 0) || (Mod(curYear, 400) == 0)
            daysInMonth := isLeap ? 29 : 28
        }

        isCurrentMonth := (this.CalMonth == FormatTime(A_Now, "yyyyMM"))
        curDay := isCurrentMonth ? Integer(FormatTime(A_Now, "d")) : 0
        xOffset := Round(10 * s) + (firstDayOfWeek - 1) * dW
        dayCounter := 1

        calGui.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.Text, Config.Theme.Font)
        sliderHex := StrReplace(Config.Theme.Slider, "#", "")

        Loop 6 {
            while (xOffset < Round(220 * s) && dayCounter <= daysInMonth) {
                if (dayCounter == curDay) {
                    bgCtrl := calGui.Add("Text", "x" Round(xOffset + 2 * s) " y" Round(yOffset + 2 * s) " w" Round(26 * s) " h" Round(26 * s) " Background" sliderHex, "")
                    if (s == 1) {
                        hRgn := DllCall("CreateEllipticRgn", "Int", 0, "Int", 0, "Int", 26, "Int", 26, "Ptr")
                        DllCall("SetWindowRgn", "Ptr", bgCtrl.Hwnd, "Ptr", hRgn, "Int", 1)
                    }
                    calGui.SetFont("s" Round(10 * s) " w700 q5 cFFFFFF", Config.Theme.Font)
                } else {
                    calGui.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.Text, Config.Theme.Font)
                }

                calGui.Add("Text", "x" xOffset " y" yOffset " w" dW " h" dW " Center 0x200 BackgroundTrans", dayCounter)
                xOffset += dW
                dayCounter++
            }
            xOffset := Round(10 * s), yOffset += dW
            if (dayCounter > daysInMonth)
                break
        }

        totalH := yOffset + Round(10 * s), totalW := Round(220 * s)

        if (navOffset == 0) {
            this.CalGui := calGui
            this.App.TogglePopup(calGui, this.Lbl.Hwnd, totalW, totalH)
        } else {
            this.App.IgnoreClicksUntil := A_TickCount + 300
            oldGui := this.CalGui
            this.CalGui := calGui
            this.App.ActivePopup := calGui
            ControlGetPos(&cX, &cY, &cW, &cH, this.Lbl.Hwnd, this.App.Gui.Hwnd)
            dropX := this.App.MonX + cX + (cW / 2) - (totalW / 2)
            dropY := this.App.MonY + this.App.H + Round(5 * s)
            calGui.Show("x" dropX " y" dropY " w" totalW " h" totalH " NoActivate")
            if oldGui {
                global AppHoverMap
                for hwnd, ctrl in oldGui {
                    if AppHoverMap.Has(hwnd)
                        AppHoverMap.Delete(hwnd)
                }
                oldGui.Destroy()
            }
        }
        try Hotkey("Left", actPrev, "On")
        try Hotkey("Right", actNext, "On")
    }
}
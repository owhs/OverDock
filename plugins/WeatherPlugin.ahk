#Include ../overdock.ahk
class WeatherPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Displays local temperature and weather."
    W := 90
    ReqWidth() {
        this.ShowText := this.GetConfig("ShowText", 1)
        if (!this.ShowText) {
            this.W := 35
        } else {
            str := HasProp(this, "Txt") ? this.Txt.Value : "--°"
            tw := this.App.MeasureTextWidth(str "...", "s10 w500 q5", Config.Theme.Font)
            this.W := Round(35 + (tw / this.App.Scale) + 5)
        }
        return super.ReqWidth()
    }
    BuildCustomConfig(gui, yP, dW) {
        s := this.App.Scale
        this.Loc := this.GetConfig("Location", "")
        this.Unit := this.GetConfig("Unit", "C")

        gui.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)
        gui.Add("Text", "x" Round(15 * s) " y" (yP + Round(3 * s)) " w" Round(60 * s) " h" Round(20 * s) " BackgroundTrans", "Location:")

        gui.SetFont("s" Round(10 * s) " w400 q5 cWhite", Config.Theme.Font)
        this.eLoc := gui.Add("Edit", "x" Round(80 * s) " y" yP " w" Round(120 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), this.Loc)

        yP += Round(35 * s)

        gui.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)
        gui.Add("Text", "x" Round(15 * s) " y" (yP + Round(3 * s)) " w" Round(60 * s) " h" Round(20 * s) " BackgroundTrans", "Unit:")

        this.cbUnitIcn := gui.Add("Text", "x" Round(80 * s) " y" yP " w" Round(30 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25), this.Unit)
        act := (*) => (
            this.Unit := this.Unit == "C" ? "F" : "C",
            this.cbUnitIcn.Value := this.Unit
        )
        this.cbUnitIcn.OnEvent("Click", act)
        if IsSet(AppCursorMap)
            AppCursorMap[this.cbUnitIcn.Hwnd] := 1

        yP += Round(35 * s)

        this.AddCheckbox(gui, Round(15 * s), yP, Round(200 * s), Round(25 * s), this, "ShowText", "Show Temp Text")
        return yP + Round(30 * s)
    }
    SaveCustomConfig() {
        this.SetConfig("Location", this.eLoc.Value)
        this.SetConfig("Unit", this.Unit)
        this.SetConfig("ShowText", this.ShowText)
        this.LastFetch := 0
    }
    Render(gui, align, x, h, w) {
        s := this.App.Scale
        if (w <= 0) w := Round(this.W * s)
            showText := this.GetConfig("ShowText", 1)

        gui.SetFont("s13 q5 c" Config.Theme.Icon, Config.Theme.IconFont)
        this.Icn := this.AddCtrl(gui, "Text", "x" x " y0 w" Round(35 * s) " h" h " 0x200 Right BackgroundTrans", Chr(0xE706))

        if (showText) {
            gui.SetFont("s10 w500 q5 c" Config.Theme.Text, Config.Theme.Font)
            this.Txt := this.AddCtrl(gui, "Text", "x" (x + Round(40 * s)) " y0 w" Round(50 * s) " h" h " 0x200 Left BackgroundTrans", "--°")
            grp := [this.Icn.Hwnd, this.Txt.Hwnd]
            this.RegisterHover(this.Icn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover, grp)
            this.RegisterHover(this.Txt.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp)
            this.Txt.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Txt.Hwnd))
            this.Txt.OnEvent("Click", (*) => Run("https://wttr.in/" this.GetConfig("Location", "")))
        } else {
            this.RegisterHover(this.Icn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
        }

        this.Icn.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Icn.Hwnd))
        this.Icn.OnEvent("Click", (*) => Run("https://wttr.in/" this.GetConfig("Location", "")))
        this.LastFetch := 0
        this.Update()
        return w
    }
    MoveCtrls(x, w) {
        s := this.App.Scale
        if HasProp(this, "Txt") {
            this.Icn.Move(x, , Round(35 * s))
            this.Txt.Move(x + Round(40 * s), , Max(0, w - Round(40 * s)))
        } else {
            this.Icn.Move(x, , w)
        }
    }
    Update() {
        if (A_TickCount - this.LastFetch > 900000 || this.LastFetch == 0) {
            this.LastFetch := A_TickCount
            SetTimer(ObjBindMethod(this, "FetchWeather"), -10)
        }
    }
    FetchWeather() {
        try {
            loc := this.GetConfig("Location", "")
            unit := this.GetConfig("Unit", "C")
            uStr := unit == "F" ? "?u&format" : "?m&format"
            url := "https://wttr.in/" loc uStr "=%t|%C"

            this.HttpReq := ComObject("WinHttp.WinHttpRequest.5.1")
            this.HttpReq.Open("GET", url, true)
            this.HttpReq.Send()
            this.CheckTimer := ObjBindMethod(this, "CheckWeather")
            SetTimer(this.CheckTimer, 100)
        } catch {
        }
    }
    CheckWeather() {
        try {
            if (this.HttpReq.WaitForResponse(0)) {
                SetTimer(this.CheckTimer, 0)
                if (this.HttpReq.Status == 200) {
                    arr := this.HttpReq.ResponseBody
                    pData := NumGet(ComObjValue(arr) + 8 + A_PtrSize, "Ptr")
                    len := arr.MaxIndex() + 1
                    resp := StrGet(pData, len, "UTF-8")

                    parts := StrSplit(resp, "|")
                    if (parts.Length >= 2) {
                        temp := Trim(RegExReplace(parts[1], "[+CF\s]", ""))
                        cond := parts[2]
                        if HasProp(this, "Txt") {
                            if (this.Txt.Value != temp) {
                                this.Txt.Value := temp
                                tw := this.App.MeasureTextWidth(temp "...", "s10 w500 q5", Config.Theme.Font)
                                nW := Round(35 + (tw / this.App.Scale) + 5)
                                if (nW != this.W) {
                                    this.W := nW
                                    this.App.Reflow()
                                }
                            }
                        }

                        iconStr := Chr(0xE706) ; Sun
                        if InStr(cond, "Cloud") || InStr(cond, "Overcast") || InStr(cond, "Partly")
                            iconStr := Chr(0xE753) ; Cloud
                        else if InStr(cond, "Rain") || InStr(cond, "Drizzle") || InStr(cond, "Mist") || InStr(cond, "Fog")
                            iconStr := Chr(0xEE4B) ; Rain
                        else if InStr(cond, "Snow") || InStr(cond, "Ice")
                            iconStr := Chr(0xE814) ; Snow

                        this.Icn.Value := iconStr
                    }
                }
            }
        } catch {
            try SetTimer(this.CheckTimer, 0)
        }
    }
    Destroy() {
        if HasProp(this, "CheckTimer")
            try SetTimer(this.CheckTimer, 0)
    }
}
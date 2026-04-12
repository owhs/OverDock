#Include ../overdock.ahk
class PageBreakPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Splits bar logically into multiple pages."
    IsPageBreak := true
    W := 1 ; Dummy width

    Render(gui, align, x, h, w) {
        return w
    }

    MoveCtrls(x, w) {
    }

    ShowSettings() {
        s := this.App.Scale
        ag := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale")
        ag.BackColor := Config.Theme.DropBg
        ag.MarginX := 0, ag.MarginY := 0
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 19, "Int*", 1, "Int", 4)

        W := Round(300 * s)
        ag.SetFont("s" Round(12 * s) " w600 q5 c" Config.Theme.Text, Config.Theme.Font)
        ag.Add("Text", "x" Round(15 * s) " y" Round(15 * s) " w" (W - Round(30 * s)) " h" Round(25 * s) " BackgroundTrans", this.Name " Settings")

        yP := Round(45 * s)
        ag.SetFont("s" Round(10 * s) " w500 q5 c" Config.Theme.Text, Config.Theme.Font)

        modeVal := this.GetConfig("OverflowMode", Config.General.OverflowMode)
        alignVal := this.GetConfig("OverflowAlign", Config.General.OverflowAlign)

        ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(120 * s) " BackgroundTrans", "Overflow Mode:")
        mBg := ag.Add("Text", "x" Round(110 * s) " y" (yP - Round(3 * s)) " w" Round(140 * s) " h" Round(25 * s) " Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")
        ag.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)
        mTxt := ag.Add("Text", "x" Round(110 * s) " y" yP " w" Round(140 * s) " BackgroundTrans Center", modeVal)
        yP += Round(40 * s)

        ag.SetFont("s" Round(10 * s) " w500 q5 c" Config.Theme.Text, Config.Theme.Font)
        ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(120 * s) " BackgroundTrans", "Button Align:")
        aBg := ag.Add("Text", "x" Round(110 * s) " y" (yP - Round(3 * s)) " w" Round(140 * s) " h" Round(25 * s) " Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")
        ag.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)
        aTxt := ag.Add("Text", "x" Round(110 * s) " y" yP " w" Round(140 * s) " BackgroundTrans Center", alignVal)
        yP += Round(40 * s)

        actM := (*) => (
            v := this.GetConfig("OverflowMode", Config.General.OverflowMode) == "Popup" ? "Pagination" : "Popup",
            this.SetConfig("OverflowMode", v),
            mTxt.Value := v
        )
        mBg.OnEvent("Click", actM), mTxt.OnEvent("Click", actM)

        actA := (*) => (
            v := this.GetConfig("OverflowAlign", Config.General.OverflowAlign) == "Left" ? "Right" : "Left",
            this.SetConfig("OverflowAlign", v),
            aTxt.Value := v
        )
        aBg.OnEvent("Click", actA), aTxt.OnEvent("Click", actA)

        this.App.RegisterHover(mBg.Hwnd, BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25))
        this.App.RegisterHover(aBg.Hwnd, BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25))
        AppCursorMap[mBg.Hwnd] := 1, AppCursorMap[mTxt.Hwnd] := 1
        AppCursorMap[aBg.Hwnd] := 1, AppCursorMap[aTxt.Hwnd] := 1

        yP += Round(30 * s)
        ag.SetFont("s" Round(10 * s) " w600 q5 cWhite", Config.Theme.Font)
        botBtn := ag.Add("Text", "x" Round(15 * s) " y" yP " w" (W - Round(30 * s)) " h" Round(28 * s) " 0x200 Center Background" StrReplace(Config.Theme.IconHover, "#", ""), "Save / Close")
        this.App.RegisterHover(botBtn.Hwnd, "FFFFFF", "E0E0E0")
        AppCursorMap[botBtn.Hwnd] := 1
        botBtn.OnEvent("Click", (*) => (ag.Destroy(), ApplyDynamicSettings()))

        MouseGetPos(&mX, &mY)
        this.App.TogglePopup(ag, this.App.Gui.Hwnd, W, yP + Round(45 * s), mX - Round(W / 2), mY + Round(10 * s), true)
    }

    Update() {
    }
}
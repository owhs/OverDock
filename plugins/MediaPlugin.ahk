#Include ../overdock.ahk
class MediaPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Controls current media playback."
    ReqWidth() {
        this.ShowOnlyWhenPlaying := this.GetConfig("ShowOnlyWhenPlaying", 0)
        if (this.ShowOnlyWhenPlaying) {
            if (this.GetPlayingAudioWindows().Length == 0)
                return 0
        }

        this.ShowFwdBack := this.GetConfig("ShowFwdBack", 1)
        this.ShowStreamsBtn := this.GetConfig("ShowStreamsBtn", 1)
        this.W := (this.ShowFwdBack ? 140 : 70) - (this.ShowStreamsBtn ? 0 : 35)
        return super.ReqWidth()
    }
    BuildCustomConfig(gui, yP, dW) {
        s := this.App.Scale
        this.ShowFwdBack := this.GetConfig("ShowFwdBack", 1)
        this.ShowStreamsBtn := this.GetConfig("ShowStreamsBtn", 1)
        this.ShowOnlyWhenPlaying := this.GetConfig("ShowOnlyWhenPlaying", 0)

        this.AddCheckbox(gui, Round(15 * s), yP, Round(200 * s), Round(25 * s), this, "ShowFwdBack", "Show Fwd/Back Controls")
        yP += Round(35 * s)
        this.AddCheckbox(gui, Round(15 * s), yP, Round(200 * s), Round(25 * s), this, "ShowStreamsBtn", "Show Audio Streams Button")
        yP += Round(35 * s)
        this.AddCheckbox(gui, Round(15 * s), yP, Round(200 * s), Round(25 * s), this, "ShowOnlyWhenPlaying", "Auto-hide when not playing")

        return yP + Round(30 * s)
    }
    SaveCustomConfig() {
        this.SetConfig("ShowFwdBack", this.ShowFwdBack)
        this.SetConfig("ShowStreamsBtn", this.ShowStreamsBtn)
        this.SetConfig("ShowOnlyWhenPlaying", this.ShowOnlyWhenPlaying)
    }
    Render(gui, align, x, h, w) {
        s := this.App.Scale
        if (w <= 0) w := Round(this.W * s)
            iW := Round(35 * s)
        gui.SetFont("s13 q5 c" Config.Theme.Icon, Config.Theme.IconFont)

        cx := x
        if (this.ShowFwdBack) {
            this.B1 := this.AddCtrl(gui, "Text", "x" cx " y0 w" iW " h" h " 0x200 Center BackgroundTrans", Chr(0xE892))
            this.RegisterHover(this.B1.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
            this.B1.OnEvent("Click", (*) => Send("{Media_Prev}"))
            this.B1.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.B1.Hwnd))
            cx += iW
        }

        this.B2 := this.AddCtrl(gui, "Text", "x" cx " y0 w" iW " h" h " 0x200 Center BackgroundTrans", Chr(0xE768))
        this.RegisterHover(this.B2.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
        this.B2.OnEvent("Click", (*) => Send("{Media_Play_Pause}"))
        this.B2.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.B2.Hwnd))
        cx += iW

        if (this.ShowFwdBack) {
            this.B3 := this.AddCtrl(gui, "Text", "x" cx " y0 w" iW " h" h " 0x200 Center BackgroundTrans", Chr(0xE893))
            this.RegisterHover(this.B3.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
            this.B3.OnEvent("Click", (*) => Send("{Media_Next}"))
            this.B3.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.B3.Hwnd))
            cx += iW
        }

        this.ShowOnlyWhenPlaying := this.GetConfig("ShowOnlyWhenPlaying", 0)

        this.ShowStreamsBtn := this.GetConfig("ShowStreamsBtn", 1)
        if (this.ShowStreamsBtn) {
            this.B4 := this.AddCtrl(gui, "Text", "x" cx " y0 w" iW " h" h " 0x200 Center BackgroundTrans", Chr(0xE9D9))
            this.RegisterHover(this.B4.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
            this.B4.OnEvent("Click", (*) => this.ShowAudioSessions())
            this.B4.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.B4.Hwnd))
        }

        this.W := (this.ShowFwdBack ? 140 : 70) - (this.ShowStreamsBtn ? 0 : 35)
        w := Round(this.W * s)
        return w
    }
    MoveCtrls(x, w) {
        s := this.App.Scale, iW := Round(35 * s), cx := x
        if this.ShowFwdBack {
            this.B1.Move(cx, , iW), cx += iW
        }
        this.B2.Move(cx, , iW), cx += iW
        if this.ShowFwdBack {
            this.B3.Move(cx, , iW), cx += iW
        }
        if HasProp(this, "B4")
            this.B4.Move(cx, , iW)
    }

    Update() {
        playing := this.GetPlayingAudioWindows().Length > 0
        iconStr := playing ? Chr(0xE769) : Chr(0xE768)
        if (this.B2.Value != iconStr)
            this.B2.Value := iconStr

        this.ShowOnlyWhenPlaying := this.GetConfig("ShowOnlyWhenPlaying", 0)
        if (HasProp(this, "LastPlaying") && this.LastPlaying != playing) {
            if (this.ShowOnlyWhenPlaying)
                this.App.needsReflow := true
        }
        this.LastPlaying := playing
    }

    ShowAudioSessions() {
        s := this.App.Scale
        ag := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" this.App.Gui.Hwnd)
        ag.IsDynamic := true
        ag.BackColor := Config.Theme.DropBg
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        yP := Round(10 * s), dW := Round(260 * s), rH := Round(35 * s)

        ag.SetFont("s" Round(11 * s) " w600 q5 c" Config.Theme.DropText, Config.Theme.Font)
        ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(230 * s) " h" Round(25 * s) " BackgroundTrans", "Active Audio Streams:")
        yP += Round(35 * s)

        sessions := this.GetPlayingAudioWindows()

        if (sessions.Length == 0) {
            ag.SetFont("s" Round(10 * s) " w400 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.Font)
            ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(230 * s) " h" rH " 0x200 BackgroundTrans", "No audio playing right now.")
            yP += rH
        } else {
            for app in sessions {
                bg := ag.Add("Text", "x0 y" yP " w" dW " h" rH " BackgroundTrans", "")
                ag.SetFont("s" Round(13 * s) " q5 c" Config.Theme.IconHover, Config.Theme.IconFont)
                iL := ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(30 * s) " h" rH " 0x200 BackgroundTrans", Chr(0xE93C))

                ag.SetFont("s" Round(11 * s) " w400 q5 c" Config.Theme.DropText, Config.Theme.Font)
                tL := ag.Add("Text", "x" Round(45 * s) " y" yP " w" Round(200 * s) " h" rH " 0x200 BackgroundTrans", app.Title ? app.Title : app.Name)


                act := ObjBindMethod(this, "ActivateAudioSession", app.Hwnd, app.PID)
                bg.OnEvent("Click", act), tL.OnEvent("Click", act), iL.OnEvent("Click", act)

                grp := [iL.Hwnd, tL.Hwnd]
                this.RegisterHover(bg.Hwnd, Config.Theme.DropText, Config.Theme.IconHover, grp)
                this.RegisterHover(iL.Hwnd, Config.Theme.DropText, Config.Theme.IconHover, grp)
                this.RegisterHover(tL.Hwnd, Config.Theme.DropText, Config.Theme.IconHover, grp)
                yP += rH
            }
        }
        this.App.TogglePopup(ag, this.B4.Hwnd, dW, yP + Round(10 * s))
    }

    ActivateAudioSession(hw, pid, *) {
        this.App.ClosePopup()
        try {
            if (hw) {
                WinShow(hw)
                WinActivate(hw)
            } else {
                WinShow("ahk_pid " pid)
                WinActivate("ahk_pid " pid)
            }
        }
    }

    GetPlayingAudioWindows() {
        sessions := []
        try {
            IMMDeviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
            ComCall(4, IMMDeviceEnumerator, "UInt", 0, "UInt", 1, "Ptr*", &IMMDevice := 0)
            if !IMMDevice
                return sessions
            IID_IAudioSessionManager2 := Buffer(16)
            DllCall("ole32\CLSIDFromString", "WStr", "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}", "Ptr", IID_IAudioSessionManager2)
            ComCall(3, IMMDevice, "Ptr", IID_IAudioSessionManager2, "UInt", 23, "Ptr", 0, "Ptr*", &IAudioSessionManager2 := 0)
            ComCall(5, IAudioSessionManager2, "Ptr*", &IAudioSessionEnumerator := 0)
            ComCall(3, IAudioSessionEnumerator, "Int*", &count := 0)

            Loop count {
                ComCall(4, IAudioSessionEnumerator, "Int", A_Index - 1, "Ptr*", &IAudioSessionControl := 0)
                ComCall(3, IAudioSessionControl, "Int*", &state := 0)

                if (state == 1) {
                    IAudioSessionControl2 := ComObjQuery(IAudioSessionControl, "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}")
                    IAudioMeter := ComObjQuery(IAudioSessionControl, "{C02216F6-8C67-4B5B-9D00-D008E73E0064}")
                    peak := 0.0
                    if IAudioMeter {
                        ComCall(3, IAudioMeter, "Float*", &peak)
                    }

                    if (IAudioSessionControl2 && peak > 0.0001) {
                        ComCall(14, IAudioSessionControl2, "UInt*", &pid := 0)
                        if (pid && pid != DllCall("GetCurrentProcessId")) {
                            try {
                                name := ProcessGetName(pid)
                                if (name && name != "audiodg.exe" && name != "System" && name != "FxSound.exe") {
                                    hw := 0, title := ""
                                    for id in WinGetList("ahk_pid " pid) {
                                        if (WinGetStyle(id) & 0x10000000 && WinGetTitle(id) != "") {
                                            hw := id, title := WinGetTitle(id)
                                            break
                                        }
                                    }
                                    sessions.Push({ PID: pid, Name: name, Title: title, Hwnd: hw })
                                }
                            }
                        }
                    }
                }
                if (IAudioSessionControl)
                    ObjRelease(IAudioSessionControl)
            }
            if (IAudioSessionEnumerator)
                ObjRelease(IAudioSessionEnumerator)
            if (IAudioSessionManager2)
                ObjRelease(IAudioSessionManager2)
            if (IMMDevice)
                ObjRelease(IMMDevice)
        }

        unique := Map(), res := []
        for s in sessions {
            if !unique.Has(s.PID) {
                unique[s.PID] := 1
                res.Push(s)
            }
        }
        return res
    }
}
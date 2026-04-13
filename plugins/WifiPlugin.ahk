#Include ../overdock.ahk
class WifiPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Monitor wireless connection status."
    W := 40
    ReqWidth() {
        this.ShowSSID := this.GetConfig("ShowSSID", 1)
        if (!this.ShowSSID) {
            this.W := 35
        } else {
            str := HasProp(this, "Txt") ? this.Txt.Value : "Connected"
            tw := this.App.MeasureTextWidth(str "...", "s10 w500 q5", Config.Theme.Font)
            this.W := Round(35 + (tw / this.App.Scale) + 5)
        }
        return super.ReqWidth()
    }
    BuildCustomConfig(gui, yP, dW) {
        s := this.App.Scale
        this.ShowSSID := this.GetConfig("ShowSSID", 1)
        this.AdpForce := this.GetConfig("AdpForce", "")

        gui.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)
        gui.Add("Text", "x" Round(15 * s) " y" (yP + Round(3 * s)) " w" Round(80 * s) " h" Round(20 * s) " BackgroundTrans", "Adapter:")

        comps := ["Auto"]
        try {
            for obj in ComObjGet("winmgmts:\\.\root\CIMV2").ExecQuery("SELECT * FROM Win32_NetworkAdapter WHERE NetConnectionID IS NOT NULL")
                comps.Push(obj.NetConnectionID)
        }

        cbList := []
        idx := 1
        for i, v in comps {
            cbList.Push(v)
            if (v == this.AdpForce)
                idx := i
        }

        this.AdpDropText := gui.Add("Text", "x" Round(85 * s) " y" yP " w" Round(150 * s) " h" Round(25 * s) " 0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10), " " (this.AdpForce == "" ? "Auto" : this.AdpForce))

        actDrop := (*) => this.App.BuildDropdown(gui, this.AdpDropText, this.AdpDropText, comps)
        this.AdpDropText.OnEvent("Click", actDrop)
        if IsSet(AppCursorMap)
            AppCursorMap[this.AdpDropText.Hwnd] := 1

        yP += Round(35 * s)

        gui.SetFont("s" Round(13 * s) " q5 c" Config.Theme.IconHover, Config.Theme.IconFont)
        this.cbSSIDIcn := gui.Add("Text", "x" Round(15 * s) " y" yP " w" Round(20 * s) " h" Round(25 * s) " BackgroundTrans", this.ShowSSID ? Chr(0xE73A) : Chr(0xE739))
        gui.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)
        this.cbSSIDTxt := gui.Add("Text", "x" Round(45 * s) " y" (yP + Round(3 * s)) " w" (dW - Round(60 * s)) " h" Round(20 * s) " BackgroundTrans", "Show SSID / Network")

        act := (*) => (
            this.ShowSSID := !this.ShowSSID,
            this.cbSSIDIcn.Value := this.ShowSSID ? Chr(0xE73A) : Chr(0xE739)
        )
        this.cbSSIDIcn.OnEvent("Click", act), this.cbSSIDTxt.OnEvent("Click", act)
        if IsSet(AppCursorMap)
            AppCursorMap[this.cbSSIDIcn.Hwnd] := 1, AppCursorMap[this.cbSSIDTxt.Hwnd] := 1

        return yP + Round(30 * s)
    }
    SaveCustomConfig() {
        this.SetConfig("ShowSSID", this.ShowSSID)
        this.SetConfig("AdpForce", this.AdpDropText.Value == " Auto" ? "" : Trim(this.AdpDropText.Value))
    }
    Render(gui, align, x, h, w) {
        s := this.App.Scale
        if (w <= 0) w := Round(this.W * s)
            gui.SetFont("s13 q5 c" Config.Theme.Icon, Config.Theme.IconFont)

        if (this.ShowSSID) {
            this.Btn := this.AddCtrl(gui, "Text", "x" x " y0 w" Round(35 * s) " h" h " 0x200 Right BackgroundTrans", Chr(0xE701))
            gui.SetFont("s10 w500 q5 c" Config.Theme.Text, Config.Theme.Font)
            str := HasProp(this, "CurSSID") ? this.CurSSID : "Wi-Fi"
            tw := this.App.MeasureTextWidth(str "...", "s10 w500 q5", Config.Theme.Font)
            this.Txt := this.AddCtrl(gui, "Text", "x" (x + Round(40 * s)) " y0 w" tw " h" h " 0x200 Left BackgroundTrans", str)

            grp := [this.Btn.Hwnd, this.Txt.Hwnd]
            this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover, grp)
            this.RegisterHover(this.Txt.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp)
            this.Txt.OnEvent("Click", (*) => this.ShowWifiList())
            this.Txt.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Txt.Hwnd))
        } else {
            this.Btn := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", Chr(0xE701))
            this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
        }

        this.Btn.OnEvent("Click", (*) => this.ShowWifiList())
        this.Btn.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Btn.Hwnd))
        this.Update()
        return w
    }
    MoveCtrls(x, w) {
        s := this.App.Scale
        if HasProp(this, "Txt") {
            try this.Btn.Move(x, , Round(35 * s))
            try {
                tw := this.App.MeasureTextWidth(this.Txt.Value "...", "s10 w500 q5", Config.Theme.Font)
                this.Txt.Move(x + Round(40 * s), , tw)
            }
        } else {
            if HasProp(this, "Btn")
                try this.Btn.Move(x, , w)
        }
    }
    ShowWifiList() {
        s := this.App.Scale
        this.DropGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" this.App.Gui.Hwnd)
        this.DropGui.BackColor := Config.Theme.DropBg
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.DropGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.DropGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        this.DropGui.SetFont("s" Round(11 * s) " w600 q5 c" Config.Theme.DropText, Config.Theme.Font)
        this.DropGui.Add("Text", "x" Round(15 * s) " y" Round(10 * s) " w" Round(180 * s) " h" Round(25 * s) " BackgroundTrans", "Network Adapters")

        yP := Round(45 * s)
        hasAdapters := false
        try {
            for obj in ComObjGet("winmgmts:\\.\root\CIMV2").ExecQuery("SELECT * FROM Win32_NetworkAdapter WHERE NetConnectionID IS NOT NULL") {
                hasAdapters := true
                status := obj.NetConnectionStatus
                stateStr := (status == 2) ? "Connected" : (status == 0 ? "Disconnected" : "Disabled/Unknown")
                cCol := (status == 2) ? "c4CAF50" : "c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40)

                this.DropGui.SetFont("s" Round(10 * s) " w600 q5 cWhite", Config.Theme.Font)
                bg := this.DropGui.Add("Text", "x" Round(10 * s) " y" yP " w" Round(210 * s) " h" Round(45 * s) " BackgroundTrans 0x0100", "")
                this.DropGui.Add("Text", "x" Round(15 * s) " y" Round(yP + 5 * s) " w" Round(180 * s) " h" Round(20 * s) " BackgroundTrans", obj.NetConnectionID)

                this.DropGui.SetFont("s" Round(9 * s) " w400 q5 " cCol, Config.Theme.Font)
                this.DropGui.Add("Text", "x" Round(15 * s) " y" Round(yP + 23 * s) " w" Round(180 * s) " h" Round(20 * s) " BackgroundTrans", stateStr " - " obj.Name)

                bg.OnEvent("Click", (*) => Run("ms-settings:network"))
                this.App.RegisterHover(bg.Hwnd, Config.Theme.DropBg, BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15))
                yP += Round(50 * s)
            }
        }

        if (!hasAdapters) {
            this.DropGui.SetFont("s" Round(10 * s) " w600 q5 cWhite", Config.Theme.Font)
            this.DropGui.Add("Text", "x" Round(15 * s) " y" yP " w" Round(180 * s) " h" Round(20 * s) " BackgroundTrans", "No Adapters Found")
            yP += Round(30 * s)
        }

        this.DropGui.SetFont("s" Round(10 * s) " w600 q5 cWhite", Config.Theme.Font)
        btn := this.DropGui.Add("Text", "x" Round(15 * s) " y" yP " w" Round(200 * s) " h" Round(30 * s) " 0x200 Center Background" Config.Theme.Slider, "Open Network Settings")
        this.App.RegisterHover(btn.Hwnd, "FFFFFF", "E0E0E0")
        btn.OnEvent("Click", (*) => Run("ms-settings:network"))

        this.App.TogglePopup(this.DropGui, this.Btn.Hwnd, Round(230 * s), yP + Round(40 * s))
    }
    Update() {
        connected := DllCall("wininet\InternetGetConnectedState", "UInt*", &flags := 0, "UInt", 0)
        iconStr := Chr(0xEB55)
        ssidStr := "Disconnected"

        forced := this.GetConfig("AdpForce", "")

        if (connected) {
            iconStr := (flags & 0x02) ? Chr(0xE839) : Chr(0xE701)
            ssidStr := (flags & 0x02) ? "Ethernet" : "Connected"

            if (forced) {
                ssidStr := forced
                iconStr := (flags & 0x02) ? Chr(0xE839) : Chr(0xE701)
            } else {
                try {
                    if !DllCall("GetModuleHandleW", "Str", "wlanapi.dll", "Ptr")
                        DllCall("LoadLibrary", "Str", "wlanapi.dll")
                    hClient := 0, negVersion := 0
                    if !DllCall("Wlanapi\WlanOpenHandle", "UInt", 2, "Ptr", 0, "UInt*", &negVersion, "Ptr*", &hClient) {
                        pInterfaceList := 0
                        if !DllCall("Wlanapi\WlanEnumInterfaces", "Ptr", hClient, "Ptr", 0, "Ptr*", &pInterfaceList) {
                            if (NumGet(pInterfaceList, 0, "UInt") > 0) {
                                pInterfaceInfo := pInterfaceList + 8
                                state := NumGet(pInterfaceInfo, 528, "UInt")
                                if (state == 1) {
                                    pConnectionAttributes := 0, size := 0
                                    if !DllCall("Wlanapi\WlanQueryInterface", "Ptr", hClient, "Ptr", pInterfaceInfo, "UInt", 7, "Ptr", 0, "UInt*", &size, "Ptr*", &pConnectionAttributes, "Ptr", 0) {
                                        ssidLen := NumGet(pConnectionAttributes, 520, "UInt")
                                        ssidStr := StrGet(pConnectionAttributes + 524, ssidLen, "CP0")
                                        signal := NumGet(pConnectionAttributes, 576, "UInt")
                                        DllCall("Wlanapi\WlanFreeMemory", "Ptr", pConnectionAttributes)

                                        if (signal >= 80)
                                            iconStr := Chr(0xE701)
                                        else if (signal >= 50)
                                            iconStr := Chr(0xE873)
                                        else
                                            iconStr := Chr(0xE874)
                                    }
                                }
                            }
                            DllCall("Wlanapi\WlanFreeMemory", "Ptr", pInterfaceList)
                        }
                        DllCall("Wlanapi\WlanCloseHandle", "Ptr", hClient, "Ptr", 0)
                    }
                }
            }
        }

        if (this.Btn.Value != iconStr)
            this.Btn.Value := iconStr
        if (this.ShowSSID && HasProp(this, "Txt")) {
            if (StrLen(ssidStr) > 14)
                ssidStr := SubStr(ssidStr, 1, 12) ".."
            if (this.Txt.Value != ssidStr) {
                this.Txt.Value := ssidStr
                tw := this.App.MeasureTextWidth(ssidStr "...", "s10 w500 q5", Config.Theme.Font)
                nW := Round(35 + (tw / this.App.Scale) + 5)
                if (this.W != nW) {
                    this.W := nW
                    this.App.Reflow()
                }
            }
        }
    }
}
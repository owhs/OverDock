#Include ../overdock.ahk

class BluetoothPlugin extends OverDockPlugin {
    W := 40

    ReqWidth() {
        return super.ReqWidth()
    }

    Render(gui, align, x, h, w) {
        s := this.App.Scale
        if (w <= 0) w := Round(this.W * s)
            gui.SetFont("s13 q5 c" Config.Theme.Icon, Config.Theme.IconFont)
        this.Btn := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", Chr(0xE702))
        this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)

        this.Btn.OnEvent("Click", (*) => this.ShowPopup())
        return w
    }

    MoveCtrls(x, w) {
        this.Btn.Move(x, , w)
    }

    LoadDevices() {
        connList := []
        offList := []
        try {
            is64 := (A_PtrSize == 8)
            btSearchParams := Buffer(is64 ? 40 : 32, 0)
            NumPut("UInt", btSearchParams.Size, btSearchParams, 0)
            NumPut("Int", 1, btSearchParams, 4)
            NumPut("Int", 1, btSearchParams, 8)
            NumPut("Int", 0, btSearchParams, 12)
            NumPut("Int", 1, btSearchParams, 16)
            NumPut("Int", 0, btSearchParams, 20)
            NumPut("UChar", 2, btSearchParams, 24)
            NumPut("Ptr", 0, btSearchParams, is64 ? 32 : 28)

            btDeviceInfo := Buffer(560, 0)
            NumPut("UInt", 560, btDeviceInfo, 0)

            hFind := DllCall("bthprops.cpl\BluetoothFindFirstDevice", "Ptr", btSearchParams.Ptr, "Ptr", btDeviceInfo.Ptr, "Ptr")
            if (hFind) {
                Loop {
                    offName := is64 ? 64 : 60
                    offConn := is64 ? 20 : 16

                    name := StrGet(btDeviceInfo.Ptr + offName, 248, "UTF-16")
                    fConnected := NumGet(btDeviceInfo, offConn, "Int")

                    if (name != "") {
                        icn := "E702"
                        if InStr(name, "Mouse") || InStr(name, "MX")
                            icn := "E962"
                        else if InStr(name, "Headphone") || InStr(name, "WH-") || InStr(name, "Earbud") || InStr(name, "JBL") || InStr(name, "TWS") || InStr(name, "Shokz")
                            icn := "E7F6"
                        else if InStr(name, "Phone") || RegExMatch(name, "i)(Pixel|Galaxy|moto|iphone)")
                            icn := "E8EA"
                        else if InStr(name, "Speaker") || InStr(name, "Soundbar")
                            icn := "E7F5"
                        else if InStr(name, "Keyboard")
                            icn := "E765"

                        bStat := fConnected ? 1 : 0
                        devObj := { Name: name, Type: icn, State: bStat }

                        if (bStat)
                            connList.Push(devObj)
                        else
                            offList.Push(devObj)
                    }

                    if !DllCall("bthprops.cpl\BluetoothFindNextDevice", "Ptr", hFind, "Ptr", btDeviceInfo.Ptr)
                        break
                }
                DllCall("bthprops.cpl\BluetoothFindDeviceClose", "Ptr", hFind)
            }
        }

        this.Devices := []
        for dev in connList
            this.Devices.Push(dev)
        for dev in offList
            this.Devices.Push(dev)

        if (this.Devices.Length == 0) {
            this.Devices := [{ Name: "No devices found", Type: "E702", State: 0 }]
        }
    }

    ShowPopup() {
        s := this.App.Scale
        this.DropGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" this.App.Gui.Hwnd)
        this.DropGui.BackColor := Config.Theme.DropBg
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.DropGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.DropGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        PW := Round(250 * s)

        this.DropGui.SetFont("s" Round(12 * s) " w600 q5 c" Config.Theme.IconHover, Config.Theme.IconFont)
        this.DropGui.Add("Text", "x" Round(15 * s) " y" Round(15 * s) " w" Round(20 * s) " h" Round(25 * s) " BackgroundTrans", Chr(0xE702))

        this.DropGui.SetFont("s" Round(11 * s) " w600 q5 c" Config.Theme.DropText, Config.Theme.Font)
        this.DropGui.Add("Text", "x" Round(40 * s) " y" Round(15 * s) " w" Round(150 * s) " h" Round(25 * s) " BackgroundTrans", "Manage devices")

        this.DropGui.Add("Text", "x" Round(15 * s) " y" Round(45 * s) " w" (PW - Round(30 * s)) " h1 0x0100 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25), "")

        yP := Round(55 * s)

        this.LoadDevices()

        ; Optional SexyList integration for scrolling large device lists
        if (HasProp(this, "SList") && this.SList) {
            try this.SList.Destroy()
        }

        renderRow := ObjBindMethod(this, "RenderDevRow")
        this.SList := SexyList(this.DropGui, 0, yP, PW, Round(240 * s), this.Devices, renderRow, (*) => 0)
        this.SList.RowH := Round(40 * s)
        try this.SList.Outer.BackColor := Config.Theme.DropBg
        try this.SList.Inner.BackColor := Config.Theme.DropBg
        this.SList.Render()

        this.DropGui.OnEvent("Close", (*) => (HasProp(this, "SList") ? this.SList.Destroy() : 0))
        this.DropGui.OnEvent("Escape", (*) => (HasProp(this, "SList") ? this.SList.Destroy() : 0))

        yP += Round(250 * s)
        this.App.TogglePopup(this.DropGui, this.Btn.Hwnd, PW, yP)
    }

    RenderDevRow(listObj, dev, idx, yP, w, bg) {
        s := this.App.Scale
        g := listObj.Inner
        pw := HasProp(this, "PW") ? this.PW : Round(250 * s)

        bg.Opt("BackgroundTrans 0x0100")

        g.SetFont("s" Round(14 * s) " q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 50), Config.Theme.IconFont)
        g.Add("Text", "x" Round(15 * s) " y" (yP + Round(10 * s)) " w" Round(20 * s) " h" Round(20 * s) " BackgroundTrans Center", Chr("0x" dev.Type))

        fntC := dev.State ? "cWhite" : "c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 50)
        g.SetFont("s" Round(10 * s) " w500 q5 " fntC, Config.Theme.Font)
        tTxt := g.Add("Text", "x" Round(45 * s) " y" (yP + Round(10 * s)) " w" Round(130 * s) " h" Round(20 * s) " BackgroundTrans", dev.Name)

        togBgCol := dev.State ? BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25) : BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25)
        togKnobX := dev.State ? Round(209 * s) : Round(191 * s)

        togBg := g.Add("Text", "x" Round(190 * s) " y" (yP + Round(8 * s)) " w" Round(36 * s) " h" Round(22 * s) " Background" togBgCol " 0x0100", "")
        togBgIn := g.Add("Text", "x" Round(192 * s) " y" (yP + Round(10 * s)) " w" Round(32 * s) " h" Round(18 * s) " Background" (dev.State ? togBgCol : "1e1e1e") " 0x0100", "")
        togKnob := g.Add("Text", "x" togKnobX " y" (yP + Round(10 * s)) " w" Round(18 * s) " h" Round(18 * s) " Background" (dev.State ? "White" : BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40)) " 0x0100", "")

        ; Intentionally bypassing click events per user request because toggle logic requires deep private Windows Bluetooth API hooks.

        if IsSet(TopBar)
            TopBar.RegisterHover(bg.Hwnd, Config.Theme.DropBg, BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15))
        if IsSet(AppCursorMap) {
            AppCursorMap[bg.Hwnd] := 1
        }
    }
}
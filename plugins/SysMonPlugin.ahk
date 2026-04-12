#Include ../overdock.ahk

class SysMonPlugin extends OverDockPlugin {
    static Version := "2.0"
    static Description := "System Resource Monitor (CPU, RAM, Disk, Net, Temps)"

    ReqWidth() {
        this.ShowCPU := this.GetConfig("ShowCPU", 1)
        this.ShowRAM := this.GetConfig("ShowRAM", 1)
        this.ShowDisk := this.GetConfig("ShowDisk", 1)
        this.ShowNet := this.GetConfig("ShowNet", 1)
        this.ShowTotalNet := this.GetConfig("ShowTotalNet", 0)
        this.ShowTemps := this.GetConfig("ShowTemps", 1)

        this.ShowIcons := this.GetConfig("ShowIcons", 1)
        this.SplitDisplay := this.GetConfig("SplitDisplay", 1)
        this.TickerMode := this.GetConfig("TickerMode", 0)
        this.TrackLifetimeNet := this.GetConfig("TrackLifetimeNet", 0)
        this.LifetimeRxGB := Float(this.GetConfig("LifetimeRxGB", 0.0))
        this.LifetimeTxGB := Float(this.GetConfig("LifetimeTxGB", 0.0))

        iCpu := this.ShowIcons ? Chr(0x1F4BB) " CPU: " : "CPU: "
        iRam := this.ShowIcons ? Chr(0x1F9E0) " RAM: " : "RAM: "
        iDisk := this.ShowIcons ? Chr(0x1F4BE) " Disk: " : "Disk: "
        iNet := this.ShowIcons ? Chr(0x2B07) " Net: " : "Net: "
        iTemp := this.ShowIcons ? Chr(0x1F321) " Temp: " : "Temp: "

        wArr := []
        if (this.ShowCPU)
            wArr.Push(iCpu "100%")
        if (this.ShowRAM) {
            rMode := this.GetConfig("RAMMode", 1)
            if (rMode == 1)
                wArr.Push(iRam "100%")
            else if (rMode == 2)
                wArr.Push(iRam "128.0G")
            else
                wArr.Push(iRam "128.0G (100%)")
        }
        if (this.ShowDisk)
            wArr.Push(iDisk "999.9M/s")
        if (this.ShowNet || this.ShowTotalNet) {
            netStr := ""
            if (this.ShowNet)
                netStr .= iNet "999.9M/s"
            if (this.ShowTotalNet)
                netStr .= (netStr ? "  " : "") "(999.9 TB)"
            wArr.Push(netStr)
        }
        if (this.ShowTemps) {
            wArr.Push(iTemp "GPU 99° CPU 99°")
        }

        fullTemplate := ""
        longestItem := ""
        for i, it in wArr {
            if (StrLen(it) > StrLen(longestItem))
                longestItem := it
            fullTemplate .= it
            if (i < wArr.Length)
                fullTemplate .= this.SplitDisplay ? "  |  " : "  "
        }

        if (this.TickerMode) {
            this.W := MeasureTextWidth(longestItem, "s10 w500 q5", Config.Theme.Font) + Round(20 * this.App.Scale)
        } else {
            this.W := MeasureTextWidth(fullTemplate, "s10 w500 q5", Config.Theme.Font) + Round(20 * this.App.Scale)
        }

        this.LastDataTick := 0
        this.LastTickerTick := A_TickCount
        this.TickerIndex := 1

        if (!HasProp(this, "LastNetTick")) {
            this.LastCpuIdle := 0, this.LastCpuTotal := 0
            this.LastDiskRead := 0, this.LastDiskWrite := 0, this.LastDiskTick := 0
            this.LastNetRx := 0, this.LastNetTx := 0, this.LastNetTick := 0
            this.LastNetSaveTick := A_TickCount
        }

        return super.ReqWidth()
    }

    BuildCustomConfig(gui, yP, dW) {
        s := this.App.Scale

        gui.SetFont("bold")
        gui.Add("Text", "x" Round(15 * s) " y" yP " w" dW " h" Round(20 * s) " BackgroundTrans c" Config.Theme.Text, "Visibility Options")
        gui.SetFont("norm")
        yP += Round(25 * s)

        cw := (dW - Round(30 * s)) / 2
        this.AddCheckbox(gui, Round(15 * s), yP, cw, Round(25 * s), this, "ShowCPU", "CPU")
        this.AddCheckbox(gui, Round(15 * s) + cw, yP, cw, Round(25 * s), this, "ShowRAM", "RAM")
        yP += Round(30 * s)
        this.AddCheckbox(gui, Round(15 * s), yP, cw, Round(25 * s), this, "ShowDisk", "Disk I/O")
        this.AddCheckbox(gui, Round(15 * s) + cw, yP, cw, Round(25 * s), this, "ShowNet", "Net Speed")
        yP += Round(30 * s)
        this.AddCheckbox(gui, Round(15 * s), yP, cw, Round(25 * s), this, "ShowTotalNet", "Total Net")
        this.AddCheckbox(gui, Round(15 * s) + cw, yP, cw, Round(25 * s), this, "ShowTemps", "Temps")
        yP += Round(30 * s)

        this.AddCheckbox(gui, Round(15 * s), yP, cw, Round(25 * s), this, "TrackLifetimeNet", "Lifetime Net")
        rstBtn := gui.Add("Text", "x" Round(15 * s + cw) " y" yP " w" (cw - Round(15 * s)) " h" Round(22 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " c" Config.Theme.Text, "Reset Memory")
        this.RegisterHover(rstBtn.Hwnd, BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25))
        rstBtn.OnEvent("Click", ObjBindMethod(this, "ResetLifetimeData", rstBtn))
        AppCursorMap[rstBtn.Hwnd] := 1
        yP += Round(35 * s)

        gui.Add("Text", "x" Round(15 * s) " y" Round(yP) " w" (dW - Round(30 * s)) " h" Round(1 * s) " Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 20), "")
        yP += Round(15 * s)

        gui.SetFont("bold")
        gui.Add("Text", "x" Round(15 * s) " y" yP " w" dW " h" Round(20 * s) " BackgroundTrans c" Config.Theme.Text, "Presentation")
        gui.SetFont("norm")
        yP += Round(25 * s)

        this.AddCheckbox(gui, Round(15 * s), yP, cw, Round(25 * s), this, "ShowIcons", "Icons")
        this.AddCheckbox(gui, Round(15 * s) + cw, yP, cw, Round(25 * s), this, "SplitDisplay", "Use ' | '")
        yP += Round(30 * s)
        this.AddCheckbox(gui, Round(15 * s), yP, cw, Round(25 * s), this, "TickerMode", "Ticker")
        yP += Round(35 * s)

        gui.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(90 * s) " h" Round(25 * s) " 0x200 BackgroundTrans c" Config.Theme.Text, "RAM Format:")
        RAMOptions := ["Percentage", "Total GB", "Both"]
        this.RAMModeVal := this.GetConfig("RAMMode", 1)
        rBg := gui.Add("Text", "x" Round(105 * s) " y" yP " w" Round(110 * s) " h" Round(25 * s) " Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")
        this.rTxt := gui.Add("Text", "x" Round(110 * s) " y" Round(yP + 3 * s) " w" Round(80 * s) " h" Round(20 * s) " BackgroundTrans c" Config.Theme.Text, RAMOptions[this.RAMModeVal])
        rArr := gui.Add("Text", "x" Round(195 * s) " y" Round(yP + 3 * s) " w" Round(15 * s) " h" Round(20 * s) " BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " Center", Chr(0x2304))

        act := ObjBindMethod(this.App, "BuildDropdown", gui, rBg, this.rTxt, RAMOptions, this, "RAMModeVal")
        rBg.OnEvent("Click", act), this.rTxt.OnEvent("Click", act), rArr.OnEvent("Click", act)
        AppCursorMap[rBg.Hwnd] := 1, AppCursorMap[this.rTxt.Hwnd] := 1, AppCursorMap[rArr.Hwnd] := 1

        yP += Round(35 * s)

        gui.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(90 * s) " h" Round(25 * s) " 0x200 BackgroundTrans c" Config.Theme.Text, "Update Freq:")
        SpeedOptions := ["500 ms", "1000 ms", "2000 ms", "5000 ms"]
        this.SpeedIdx := this.GetConfig("UpdateSpeedIdx", 2)
        sBg := gui.Add("Text", "x" Round(105 * s) " y" yP " w" Round(110 * s) " h" Round(25 * s) " Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")
        this.sTxt := gui.Add("Text", "x" Round(110 * s) " y" Round(yP + 3 * s) " w" Round(80 * s) " h" Round(20 * s) " BackgroundTrans c" Config.Theme.Text, SpeedOptions[this.SpeedIdx])
        sArr := gui.Add("Text", "x" Round(195 * s) " y" Round(yP + 3 * s) " w" Round(15 * s) " h" Round(20 * s) " BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " Center", Chr(0x2304))

        act2 := ObjBindMethod(this.App, "BuildDropdown", gui, sBg, this.sTxt, SpeedOptions, this, "SpeedIdx")
        sBg.OnEvent("Click", act2), this.sTxt.OnEvent("Click", act2), sArr.OnEvent("Click", act2)
        AppCursorMap[sBg.Hwnd] := 1, AppCursorMap[this.sTxt.Hwnd] := 1, AppCursorMap[sArr.Hwnd] := 1

        yP += Round(35 * s)

        gui.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(90 * s) " h" Round(25 * s) " 0x200 BackgroundTrans c" Config.Theme.Text, "Ticker Speed:")
        TickSpeedOpts := ["2 Secs", "3 Secs", "5 Secs", "10 Secs"]
        this.TickSpeedIdx := this.GetConfig("TickerSpeedIdx", 2)
        tBg := gui.Add("Text", "x" Round(105 * s) " y" yP " w" Round(110 * s) " h" Round(25 * s) " Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")
        this.tTxt := gui.Add("Text", "x" Round(110 * s) " y" Round(yP + 3 * s) " w" Round(80 * s) " h" Round(20 * s) " BackgroundTrans c" Config.Theme.Text, TickSpeedOpts[this.TickSpeedIdx])
        tArr := gui.Add("Text", "x" Round(195 * s) " y" Round(yP + 3 * s) " w" Round(15 * s) " h" Round(20 * s) " BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " Center", Chr(0x2304))

        act3 := ObjBindMethod(this.App, "BuildDropdown", gui, tBg, this.tTxt, TickSpeedOpts, this, "TickSpeedIdx")
        tBg.OnEvent("Click", act3), this.tTxt.OnEvent("Click", act3), tArr.OnEvent("Click", act3)
        AppCursorMap[tBg.Hwnd] := 1, AppCursorMap[this.tTxt.Hwnd] := 1, AppCursorMap[tArr.Hwnd] := 1

        return yP + Round(35 * s)
    }

    SaveCustomConfig() {
        this.SetConfig("ShowCPU", this.ShowCPU)
        this.SetConfig("ShowRAM", this.ShowRAM)
        this.SetConfig("ShowDisk", this.ShowDisk)
        this.SetConfig("ShowNet", this.ShowNet)
        this.SetConfig("ShowTotalNet", this.ShowTotalNet)
        this.SetConfig("ShowTemps", this.ShowTemps)

        this.SetConfig("ShowIcons", this.ShowIcons)
        this.SetConfig("SplitDisplay", this.SplitDisplay)
        this.SetConfig("TickerMode", this.TickerMode)
        this.SetConfig("TrackLifetimeNet", this.TrackLifetimeNet)

        this.SetConfig("RAMMode", this.RAMModeVal)
        this.SetConfig("UpdateSpeedIdx", this.SpeedIdx)
        this.SetConfig("TickerSpeedIdx", this.TickSpeedIdx)
    }

    ResetLifetimeData(btn, *) {
        this.LifetimeRxGB := 0.0
        this.LifetimeTxGB := 0.0
        this.SetConfig("LifetimeRxGB", 0.0)
        this.SetConfig("LifetimeTxGB", 0.0)
        btn.Value := "Cleared!"
        SetTimer(() => (btn.Value := "Reset Memory"), -1500)
    }

    Render(gui, align, x, h, w) {
        if (w <= 0) w := Round(this.W * this.App.Scale)
            gui.SetFont("s10 w500 q5 c" Config.Theme.Text, Config.Theme.Font)
        this.Lbl := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", "SysMon")
        this.RegisterHover(this.Lbl.Hwnd, Config.Theme.Text, Config.Theme.IconHover)
        this.Lbl.OnEvent("Click", (*) => Run("taskmgr.exe"))
        this.Lbl.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.Lbl.Hwnd))
        this.Update()
        return w
    }

    MoveCtrls(x, w) {
        if HasProp(this, "Lbl") && this.Lbl.Hwnd
            this.Lbl.Move(x, , w)
    }

    GetUpdateSpeedMs() {
        opts := [500, 1000, 2000, 5000]
        idx := this.GetConfig("UpdateSpeedIdx", 2)
        return (idx > 0 && idx <= opts.Length) ? opts[idx] : 1000
    }

    GetTickerSpeedMs() {
        opts := [2000, 3000, 5000, 10000]
        idx := this.GetConfig("TickerSpeedIdx", 2)
        return (idx > 0 && idx <= opts.Length) ? opts[idx] : 3000
    }

    GetCPU() {
        DllCall("GetSystemTimes", "Int64P", &id := 0, "Int64P", &kr := 0, "Int64P", &us := 0)
        tot := kr + us
        cpuLoad := 0
        if (HasProp(this, "LastCpuTotal") && this.LastCpuTotal > 0) {
            if (tot - this.LastCpuTotal != 0)
                cpuLoad := Round(100 - (id - this.LastCpuIdle) * 100 / (tot - this.LastCpuTotal))
        }
        this.LastCpuIdle := id, this.LastCpuTotal := tot
        return { Load: cpuLoad }
    }

    GetRAM() {
        m := Buffer(64, 0)
        NumPut("UInt", 64, m, 0)
        if DllCall("Kernel32.dll\GlobalMemoryStatusEx", "Ptr", m) {
            total := NumGet(m, 8, "UInt64") / 1073741824
            avail := NumGet(m, 16, "UInt64") / 1073741824
            used := total - avail
            percent := NumGet(m, 4, "UInt")
            return { TotalGB: Round(total, 1), AvailGB: Round(avail, 1), UsedGB: Round(used, 1), Pct: percent }
        }
        return { TotalGB: 0, AvailGB: 0, UsedGB: 0, Pct: 0 }
    }

    GetDisk() {
        read := 0, write := 0
        SysDrive := SubStr(A_WinDir, 1, 2)
        hDevice := DllCall("CreateFile", "Str", "\\." SysDrive, "UInt", 0, "UInt", 3, "Ptr", 0, "UInt", 3, "UInt", 0, "Ptr", 0, "Ptr")
        if (hDevice != -1) {
            dp := Buffer(128, 0)
            if DllCall("DeviceIoControl", "Ptr", hDevice, "UInt", 0x70020, "Ptr", 0, "UInt", 0, "Ptr", dp, "UInt", 128, "UInt*", &ret := 0, "Ptr", 0) {
                read += NumGet(dp, 0, "Int64")
                write += NumGet(dp, 8, "Int64")
            }
            DllCall("CloseHandle", "Ptr", hDevice)
        }

        tick := A_TickCount
        rRate := 0, wRate := 0
        if (HasProp(this, "LastDiskTick") && this.LastDiskTick > 0) {
            dt := (tick - this.LastDiskTick) / 1000.0
            if (dt > 0) {
                rRate := (read - this.LastDiskRead) / dt
                if (rRate < 0)
                    rRate := ((0xFFFFFFFFFFFFFFFF - this.LastDiskRead) + read) / dt
                wRate := (write - this.LastDiskWrite) / dt
                if (wRate < 0)
                    wRate := ((0xFFFFFFFFFFFFFFFF - this.LastDiskWrite) + write) / dt
            }
        }
        this.LastDiskRead := read, this.LastDiskWrite := write, this.LastDiskTick := tick
        return { ReadBps: rRate, WriteBps: wRate, TotalBps: rRate + wRate }
    }

    GetNet() {
        size := 0
        DllCall("Iphlpapi\GetIfTable", "Ptr", 0, "UInt*", &size, "Int", 0)
        buf := Buffer(size, 0)
        rx := 0, tx := 0
        if (DllCall("Iphlpapi\GetIfTable", "Ptr", buf, "UInt*", &size, "Int", 0) == 0) {
            entries := NumGet(buf, 0, "UInt"), offset := 4
            Loop entries {
                type := NumGet(buf, offset + 516, "UInt")
                if (type == 6 || type == 71) {
                    rx += NumGet(buf, offset + 552, "UInt")
                    tx += NumGet(buf, offset + 576, "UInt")
                }
                offset += 860
            }
        }

        tick := A_TickCount
        rxRate := 0, txRate := 0
        if (HasProp(this, "LastNetTick") && this.LastNetTick > 0) {
            dt := (tick - this.LastNetTick) / 1000.0
            if (dt > 0) {
                rxRate := (rx - this.LastNetRx) / dt
                if (rxRate < 0)
                    rxRate := ((0xFFFFFFFF - this.LastNetRx) + rx) / dt
                txRate := (tx - this.LastNetTx) / dt
                if (txRate < 0)
                    txRate := ((0xFFFFFFFF - this.LastNetTx) + tx) / dt
            }
        }

        if (this.TrackLifetimeNet && this.LastNetTick > 0) {
            deltaRx := rx - this.LastNetRx
            if (deltaRx < 0) deltaRx := (0xFFFFFFFF - this.LastNetRx) + rx
                this.LifetimeRxGB += (deltaRx / 1073741824)

            deltaTx := tx - this.LastNetTx
            if (deltaTx < 0) deltaTx := (0xFFFFFFFF - this.LastNetTx) + tx
                this.LifetimeTxGB += (deltaTx / 1073741824)

            if (tick - this.LastNetSaveTick > 60000) {
                this.SetConfig("LifetimeRxGB", this.LifetimeRxGB)
                this.SetConfig("LifetimeTxGB", this.LifetimeTxGB)
                this.LastNetSaveTick := tick
            }
        }

        this.LastNetRx := rx, this.LastNetTx := tx, this.LastNetTick := tick

        targetRxGB := this.TrackLifetimeNet ? this.LifetimeRxGB : (rx / 1073741824)
        targetTxGB := this.TrackLifetimeNet ? this.LifetimeTxGB : (tx / 1073741824)

        rxStr := (targetRxGB >= 1000) ? Round(targetRxGB / 1024, 2) " TB" : Round(targetRxGB, 2) " GB"
        txStr := (targetTxGB >= 1000) ? Round(targetTxGB / 1024, 2) " TB" : Round(targetTxGB, 2) " GB"

        return { RxBps: rxRate, TxBps: txRate, TotalRxGB: targetRxGB, TotalRxStr: rxStr, TotalTxGB: targetTxGB, TotalTxStr: txStr }
    }

    FetchData() {
        if (this.ShowCPU)
            this.DataCPU := this.GetCPU()
        if (this.ShowRAM)
            this.DataRAM := this.GetRAM()
        if (this.ShowDisk)
            this.DataDisk := this.GetDisk()
        if (this.ShowNet || this.ShowTotalNet)
            this.DataNet := this.GetNet()
        if (this.ShowTemps)
            this.DataTemps := HardwareTemp.GetAll()
    }

    Update() {
        if !HasProp(this, "Lbl") || !this.Lbl.Hwnd
            return

        tick := A_TickCount
        if (tick - this.LastDataTick >= this.GetUpdateSpeedMs()) {
            this.FetchData()
            this.LastDataTick := tick
        }

        this.RefreshDisplay(tick)
    }

    FormatItems() {
        items := []
        iCpu := this.ShowIcons ? Chr(0x1F4BB) " CPU: " : "CPU: "
        iRam := this.ShowIcons ? Chr(0x1F9E0) " RAM: " : "RAM: "
        iDisk := this.ShowIcons ? Chr(0x1F4BE) " Disk: " : "Disk: "
        iNet := this.ShowIcons ? Chr(0x2B07) " Net: " : "Net: "
        iTemp := this.ShowIcons ? Chr(0x1F321) " Temp: " : "Temp: "

        if (this.ShowCPU && HasProp(this, "DataCPU")) {
            items.Push(iCpu . this.DataCPU.Load "%")
        }

        if (this.ShowRAM && HasProp(this, "DataRAM")) {
            rMode := this.GetConfig("RAMMode", 1)
            if (rMode == 1)
                items.Push(iRam . this.DataRAM.Pct "%")
            else if (rMode == 2)
                items.Push(iRam . this.DataRAM.UsedGB "G")
            else
                items.Push(iRam . this.DataRAM.UsedGB "G (" this.DataRAM.Pct "%)")
        }

        if (this.ShowDisk && HasProp(this, "DataDisk")) {
            spd := Round(this.DataDisk.TotalBps / 1048576, 1)
            items.Push(iDisk . spd "M/s")
        }

        if ((this.ShowNet || this.ShowTotalNet) && HasProp(this, "DataNet")) {
            netStr := ""
            if (this.ShowNet) {
                rate := this.DataNet.RxBps
                if (rate > 1048576)
                    netStr .= iNet . Round(rate / 1048576, 1) "M/s"
                else if (rate > 1024)
                    netStr .= iNet . Round(rate / 1024) "K/s"
                else
                    netStr .= iNet . Round(rate) "B/s"
            }
            if (this.ShowTotalNet) {
                if (netStr != "")
                    netStr .= "  "
                netStr .= "(" this.DataNet.TotalRxStr ")"
            }
            items.Push(Trim(netStr))
        }

        if (this.ShowTemps && HasProp(this, "DataTemps")) {
            if (this.DataTemps.Length > 0) {
                types := Map()
                for sensor in this.DataTemps {
                    sT := (sensor.Type == "System") ? "CPU" : sensor.Type
                    if !types.Has(sT)
                        types[sT] := []
                    types[sT].Push(sensor.Temp)
                }
                tStr := iTemp
                typeCnt := 0
                for tType, tArr in types {
                    maxT := 0
                    for v in tArr
                        if (v > maxT)
                            maxT := v
                    if typeCnt > 0
                        tStr .= " "
                    tStr .= tType " " Round(maxT) "°"
                    typeCnt++
                }
                if (typeCnt > 0)
                    items.Push(Trim(tStr))
            }
        }

        return items
    }

    RefreshDisplay(tick) {
        items := this.FormatItems()
        if (items.Length == 0) {
            this.Lbl.Value := ""
            return
        }

        if (this.TickerMode) {
            if (tick - this.LastTickerTick >= this.GetTickerSpeedMs()) {
                this.TickerIndex++
                this.LastTickerTick := tick
            }
            if (this.TickerIndex > items.Length || this.TickerIndex < 1)
                this.TickerIndex := 1
            this.Lbl.Value := items[this.TickerIndex]
        } else {
            sep := this.SplitDisplay ? "   |   " : "   "
            str := ""
            for i, item in items {
                str .= item
                if (i < items.Length)
                    str .= sep
            }
            this.Lbl.Value := Trim(str)
        }
    }
}

class HardwareTemp {
    Static GetAll() {
        allTemps := []
        for t in this.GetGPU()
            allTemps.Push(t)
        for t in this.GetCPU()
            allTemps.Push(t)
        return allTemps
    }

    Static GetGPU() {
        temps := []
        seen := Map()
        try {
            if !(hGdi32 := DllCall("LoadLibrary", "Str", "gdi32.dll", "Ptr"))
                return temps

            ptrSize := A_PtrSize
            EnumSize := (ptrSize == 8) ? 16 : 8
            EnumAdapters := Buffer(EnumSize, 0)

            if (DllCall("gdi32\D3DKMTEnumAdapters2", "Ptr", EnumAdapters, "UInt") == 0) {
                NumAdapters := NumGet(EnumAdapters, 0, "UInt")

                if (NumAdapters > 0) {
                    AdapterStride := 20
                    AdaptersArray := Buffer(NumAdapters * AdapterStride, 0)
                    NumPut("Ptr", AdaptersArray.Ptr, EnumAdapters, (ptrSize == 8) ? 8 : 4)

                    if (DllCall("gdi32\D3DKMTEnumAdapters2", "Ptr", EnumAdapters, "UInt") == 0) {
                        Loop NumAdapters {
                            offset := (A_Index - 1) * AdapterStride
                            hAdapter := NumGet(AdaptersArray, offset, "UInt")

                            qaSize := (ptrSize == 8) ? 24 : 16
                            QueryInfo := Buffer(qaSize, 0)

                            NumPut("UInt", hAdapter, QueryInfo, 0)
                            NumPut("UInt", 34, QueryInfo, 4)

                            RegInfo := Buffer(4160, 0)
                            NumPut("Ptr", RegInfo.Ptr, QueryInfo, 8)
                            NumPut("UInt", RegInfo.Size, QueryInfo, (ptrSize == 8) ? 16 : 12)

                            gpuName := "Unknown GPU"
                            if (DllCall("gdi32\D3DKMTQueryAdapterInfo", "Ptr", QueryInfo, "UInt") == 0) {
                                parsedName := StrGet(RegInfo.Ptr, 260, "UTF-16")
                                if (parsedName != "")
                                    gpuName := parsedName
                            }

                            if (gpuName == "Microsoft Basic Render Driver" || InStr(gpuName, "Basic Display"))
                                continue

                            NumPut("UInt", 62, QueryInfo, 4)
                            PerfData := Buffer(64, 0)
                            NumPut("Ptr", PerfData.Ptr, QueryInfo, 8)
                            NumPut("UInt", PerfData.Size, QueryInfo, (ptrSize == 8) ? 16 : 12)

                            if (DllCall("gdi32\D3DKMTQueryAdapterInfo", "Ptr", QueryInfo, "UInt") == 0) {
                                tempDeciCelsius := NumGet(PerfData, 56, "UInt")

                                if (tempDeciCelsius > 0 && tempDeciCelsius < 2000) {
                                    tempC := Round(tempDeciCelsius / 10.0, 1)
                                    if !seen.Has(gpuName) {
                                        seen[gpuName] := true
                                        temps.Push({ Type: "GPU", Name: gpuName, Temp: tempC })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return temps
    }

    Static GetCPU() {
        temps := []
        seen := Map()

        try {
            wmi := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
            query := wmi.ExecQuery("SELECT Name, Temperature, HighPrecisionTemperature FROM Win32_PerfFormattedData_Counters_ThermalZoneInformation")

            for obj in query {
                name := obj.Name
                tempK := 0
                try tempK := obj.HighPrecisionTemperature

                if (tempK && tempK > 0 && tempK != 2732) {
                    celsius := Round((tempK - 2732) / 10.0, 1)
                    if (celsius > -50 && celsius < 200) {
                        temps.Push({ Type: "System", Name: "Thermal Zone (" name ")", Temp: celsius })
                        seen[name] := true
                    }
                } else {
                    try temp := obj.Temperature
                    if (temp && temp > 0 && temp != 273) {
                        celsius := Round(temp - 273.15, 1)
                        if (celsius > -50 && celsius < 200) {
                            temps.Push({ Type: "System", Name: "Thermal Zone (" name ")", Temp: celsius })
                            seen[name] := true
                        }
                    }
                }
            }
        }

        return temps
    }
}
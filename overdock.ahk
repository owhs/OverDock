#Requires AutoHotkey v2.0
#SingleInstance Force

if (A_ScriptName != "overdock_loader.ahk") {
    loaderPath := A_Temp "\overdock\overdock_loader.ahk"
    try FileDelete(loaderPath)

    if A_IsCompiled {
        FileInstall("C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe", A_Temp "\overdock\OverDockRuntime.exe", 1)
        FileInstall("overdock.ahk", A_Temp "\overdock\overdock_core.ahk", 1)
    }

    code := "#Requires AutoHotkey v2.0`n#SingleInstance Force`n"
    code .= "SetWorkingDir `"" A_ScriptDir "`"`n"

    if A_IsCompiled
        code .= "#Include `"" A_Temp "\overdock\overdock_core.ahk`"`n"
    else
        code .= "#Include `"" A_ScriptFullPath "`"`n"

    try DirCreate(A_Temp "\overdock\OverDockRuntimePlugins")
    Loop Files, A_ScriptDir "\plugins\*.ahk" {
        pluginText := FileRead(A_LoopFilePath)
        pluginText := RegExReplace(pluginText, "im)^[ \t]*#Include\s+(?:\.\.[/\\])?overdock\.ahk\s*[\r\n]*", "")
        shadowPath := A_Temp "\overdock\OverDockRuntimePlugins\" A_LoopFileName
        try FileDelete(shadowPath)
        FileAppend(pluginText, shadowPath)
        code .= "#Include `"" shadowPath "`"`n"
    }
    try DirCreate(A_Temp "\overdock\OverDockRuntimePlugins\lib")
    Loop Files, A_ScriptDir "\plugins\lib\*.ahk" {
        pluginText := FileRead(A_LoopFilePath)
        shadowPath := A_Temp "\overdock\OverDockRuntimePlugins\lib\" A_LoopFileName
        try FileDelete(shadowPath)
        FileAppend(pluginText, shadowPath)
    }

    FileAppend(code, loaderPath)

    if A_IsCompiled {
        Run('"' A_Temp '\overdock\OverDockRuntime.exe" "' loaderPath '"')
    } else {
        Run('"' A_AhkPath '" "' loaderPath '"')
    }
    ExitApp()
}

global IniFile := A_WorkingDir "\OverDockConfig.ini"
global AppHoverMap := Map()
global AppCursorMap := Map()

BlendHex(c1, c2, factor) {
    c1 := StrReplace(c1, "#", "")
    c2 := StrReplace(c2, "#", "")

    ; Sanity checks and 3-digit hex scaling
    if (StrLen(c1) == 3)
        c1 := SubStr(c1, 1, 1) SubStr(c1, 1, 1) SubStr(c1, 2, 1) SubStr(c1, 2, 1) SubStr(c1, 3, 1) SubStr(c1, 3, 1)
    if (StrLen(c2) == 3)
        c2 := SubStr(c2, 1, 1) SubStr(c2, 1, 1) SubStr(c2, 2, 1) SubStr(c2, 2, 1) SubStr(c2, 3, 1) SubStr(c2, 3, 1)
    if (StrLen(c1) != 6)
        c1 := "000000"
    if (StrLen(c2) != 6)
        c2 := "000000"

    factor := Max(0, Min(100, factor)) / 100

    r1 := Integer("0x" SubStr(c1, 1, 2)), g1 := Integer("0x" SubStr(c1, 3, 2)), b1 := Integer("0x" SubStr(c1, 5, 2))
    r2 := Integer("0x" SubStr(c2, 1, 2)), g2 := Integer("0x" SubStr(c2, 3, 2)), b2 := Integer("0x" SubStr(c2, 5, 2))

    r := Round(r1 * (1 - factor) + r2 * factor)
    g := Round(g1 * (1 - factor) + g2 * factor)
    b := Round(b1 * (1 - factor) + b2 * factor)

    hexString := Format("{:02X}{:02X}{:02X}", r, g, b)
    return hexString
}

; Load Configuration from INI
global Config := LoadConfig()

; ==============================================================================
; 1. PLUGIN REGISTRY WORKFLOW
; ==============================================================================
global LeftPlugins := []
global CenterPlugins := []
global RightPlugins := []

InitializePlugins() {
    global LeftPlugins, CenterPlugins, RightPlugins, Config
    LeftPlugins := []
    CenterPlugins := []
    RightPlugins := []

    if Config.Plugins.HasProp("LeftOrder") {
        for pName in Config.Plugins.LeftOrder {
            oName := pName
            realName := InStr(oName, "-") ? StrSplit(oName, "-")[1] : oName
            clsName := realName "Plugin"
            if IsSet(%clsName%) {
                pI := %clsName%()
                pI.Name := oName "Plugin"
                LeftPlugins.Push(pI)
            }
        }
    }

    if Config.Plugins.HasProp("CenterOrder") {
        for pName in Config.Plugins.CenterOrder {
            oName := pName
            realName := InStr(oName, "-") ? StrSplit(oName, "-")[1] : oName
            clsName := realName "Plugin"
            if IsSet(%clsName%) {
                pI := %clsName%()
                pI.Name := oName "Plugin"
                CenterPlugins.Push(pI)
            }
        }
    }

    if Config.Plugins.HasProp("RightOrder") {
        for pName in Config.Plugins.RightOrder {
            oName := pName
            realName := InStr(oName, "-") ? StrSplit(oName, "-")[1] : oName
            clsName := realName "Plugin"
            if IsSet(%clsName%) {
                pI := %clsName%()
                pI.Name := oName "Plugin"
                RightPlugins.Push(pI)
            }
        }
    }
}
InitializePlugins()

; Hook Windows cursor for native 'pointer' hover feel
OnMessage(0x0020, WM_SETCURSOR)
WM_SETCURSOR(wParam, lParam, msg, hwnd) {
    if AppHoverMap.Has(wParam) || AppCursorMap.Has(wParam) {
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Int", 32649, "Ptr"))
        return 1
    }
}

global CustomTooltipMap := Map()
global CustomTooltipGui := ""

RegisterCustomTooltip(hwnd, title, version, desc) {
    global CustomTooltipMap
    CustomTooltipMap[hwnd] := { Title: title, Version: version, Desc: desc }
}

UpdateCustomTooltip() {
    static lastCtrl := 0
    static hoverStart := 0
    CoordMode("Mouse", "Screen")
    try {
        MouseGetPos(&mX, &mY, &mWin, &mCtrl, 2)

        if (mCtrl != lastCtrl) {
            lastCtrl := mCtrl
            hoverStart := A_TickCount
            if (IsObject(CustomTooltipGui)) {
                CustomTooltipGui.Destroy()
                CustomTooltipGui := ""
            }
            return
        }

        if (mCtrl && CustomTooltipMap.Has(mCtrl) && !IsObject(CustomTooltipGui)) {
            if ((A_TickCount - hoverStart) >= 300) {
                info := CustomTooltipMap[mCtrl]
                global CustomTooltipGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x08000000 +E0x00080020 +Owner" mWin)
                try WinSetTransparent(255, CustomTooltipGui.Hwnd)
                CustomTooltipGui.BackColor := Config.Theme.DropBg
                try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", CustomTooltipGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
                try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", CustomTooltipGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)
                CustomTooltipGui.MarginX := 12, CustomTooltipGui.MarginY := 10

                CustomTooltipGui.SetFont("s10 w600 q5 c" Config.Theme.IconHover, Config.Theme.Font)
                CustomTooltipGui.Add("Text", "xm ym BackgroundTrans c" Config.Theme.IconHover, info.Title "   v" info.Version)

                CustomTooltipGui.SetFont("s9 w400 q5 cWhite", Config.Theme.Font)
                CustomTooltipGui.Add("Text", "xm y+5 w220 BackgroundTrans cWhite", info.Desc)

                CustomTooltipGui.Show("x" (mX + 15) " y" (mY + 15) " NoActivate AutoSize")
            }
        }
    } catch {
        lastCtrl := 0
        hoverStart := 0
        if (IsObject(CustomTooltipGui)) {
            CustomTooltipGui.Destroy()
            CustomTooltipGui := ""
        }
    }
}
SetTimer(UpdateCustomTooltip, 50)

global TopBar := OverDockApp()

; ==============================================================================
; 2. THE HOTBAR ENGINE (Now Features Flick-Free Reflow Engine!)
; ==============================================================================
class OverDockApp {
    __New() {
        this.Scale := A_ScreenDPI / 96
        this.H := Round(Config.General.Height * this.Scale)

        MonitorGet(MonitorGetPrimary(), &ML, &MT, &MR, &MB)
        this.MonX := ML, this.MonY := MT, this.W := MR - ML

        this.Gui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x02000000")
        this.Gui.BackColor := Config.Theme.BarBg
        ;if (Config.Theme.HasProp("UseMica") && Config.Theme.UseMica == "1")
        ;    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.Gui.Hwnd, "Int", 38, "Int*", 2, "Int", 4)
        if (Config.Theme.HasProp("BarAlpha") && Config.Theme.BarAlpha != "255")
            WinSetTransparent(Config.Theme.BarAlpha, this.Gui.Hwnd)

        this.Gui.MarginX := 0, this.Gui.MarginY := 0

        ; FAILSAFE: Right click or Double Click the empty bar to open Settings!
        this.Gui.OnEvent("ContextMenu", (gui, ctrl, *) => (!ctrl ? OpenSettingsGUI() : ""))
        OnMessage(0x0203, ObjBindMethod(this, "OnDoubleClick"))

        this.ActivePopup := ""
        this.ActiveTrigger := 0

        this.RenderPlugins()
        this.ReserveSpace()

        this.fnTickUpdate := ObjBindMethod(this, "TickUpdate")
        this.fnTickHover := ObjBindMethod(this, "TickHover")
        this.fnCheckFullscreen := ObjBindMethod(this, "CheckFullscreen")
        this.fnRestoreSpace := ObjBindMethod(this, "RestoreSpace")

        SetTimer(this.fnTickUpdate, 1000)
        SetTimer(this.fnTickHover, 15)
        SetTimer(this.fnCheckFullscreen, 200)
        OnExit(this.fnRestoreSpace)
    }

    OnDoubleClick(wParam, lParam, msg, hwnd) {
        if (hwnd == this.Gui.Hwnd)
            OpenSettingsGUI()
    }

    Destroy() {
        if HasProp(this, "fnRestoreSpace") {
            this.RestoreSpace()
            OnExit(this.fnRestoreSpace, 0)
        }

        SetTimer(this.fnTickUpdate, 0)
        SetTimer(this.fnTickHover, 0)
        SetTimer(this.fnCheckFullscreen, 0)
        this.ClosePopup()

        for group in [LeftPlugins, CenterPlugins, RightPlugins]
            for p in group
                if HasMethod(p, "Destroy")
                    p.Destroy()

        this.Gui.Destroy()
    }

    ApplyUpdate() {
        this.IsRendered := false
        SetTimer(this.fnTickUpdate, 0)
        SetTimer(this.fnTickHover, 0)
        SetTimer(this.fnCheckFullscreen, 0)
        this.ClosePopup()

        if HasProp(this, "OflLeftGui") && this.OflLeftGui
            try this.OflLeftGui.Destroy()
        if HasProp(this, "OflRightGui") && this.OflRightGui
            try this.OflRightGui.Destroy()
        if HasProp(this, "OflCenterGui") && this.OflCenterGui
            try this.OflCenterGui.Destroy()

        for group in [LeftPlugins, CenterPlugins, RightPlugins]
            for p in group
                if HasMethod(p, "Destroy")
                    p.Destroy()

        try {
            for ctrlHwnd in WinGetControlsHwnd(this.Gui.Hwnd)
                DllCall("DestroyWindow", "Ptr", ctrlHwnd)
        }

        for prop in ["OflLeftBtn", "OflLeftDbgBox", "OflRightBtn", "OflRightDbgBox", "OflCenterBtn", "OflCenterDbgBox"]
            if HasProp(this, prop)
                this.DeleteProp(prop)

        this.ActivePopup := ""
        this.ActiveSubPopup := ""
        this.ActiveDropdown := ""
        this.ActiveTrigger := 0

        global AppHoverMap, AppCursorMap
        toRemH := []
        for hwnd in AppHoverMap
            if (!DllCall("IsWindow", "Ptr", hwnd) || DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") == this.Gui.Hwnd)
                toRemH.Push(hwnd)
        for h in toRemH
            AppHoverMap.Delete(h)

        toRemC := []
        for hwnd in AppCursorMap
            if (!DllCall("IsWindow", "Ptr", hwnd) || DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") == this.Gui.Hwnd)
                toRemC.Push(hwnd)
        for h in toRemC
            AppCursorMap.Delete(h)

        newH := Round(Config.General.Height * this.Scale)
        newAutoHide := (Config.General.HasProp("AutoHide") && Config.General.AutoHide) ? 1 : 0
        lastAutoHide := HasProp(this, "LastAutoHideValue") ? this.LastAutoHideValue : 0

        if (newH != this.H || lastAutoHide != newAutoHide) {
            this.H := newH
            this.RestoreSpace()
            this.ReserveSpace()
        }
        this.LastAutoHideValue := newAutoHide

        InitializePlugins()
        this.Gui.BackColor := Config.Theme.BarBg
        if (Config.Theme.HasProp("BarAlpha") && Config.Theme.BarAlpha != "255")
            WinSetTransparent(Config.Theme.BarAlpha, this.Gui.Hwnd)
        else
            WinSetTransparent(255, this.Gui.Hwnd)

        this.RenderPlugins()

        SetTimer(this.fnTickUpdate, 1000)
        SetTimer(this.fnTickHover, 15)
        SetTimer(this.fnCheckFullscreen, 200)
    }


    EvalOverflowMode(plugins, &outMode, &outAlign) {
        outMode := (Config.General.OverflowMode == "Pagination")
        outAlign := (Config.General.OverflowAlign == "Left")
        for p in plugins {
            if (HasProp(p, "IsPageBreak") && p.IsPageBreak) {
                outMode := (p.GetConfig("OverflowMode", Config.General.OverflowMode) == "Pagination")
                outAlign := (p.GetConfig("OverflowAlign", Config.General.OverflowAlign) == "Left")
                break
            }
        }
    }

    ; The Flick-free sliding layout updater. Shifts icons natively based on dynamic widths!
    Reflow() {
        if (!HasProp(this, "IsRendered") || !this.IsRendered)
            return

        s := this.Scale
        space := Round(Number(Config.General.Spacing) * s)
        modePaged := (Config.General.OverflowMode == "Pagination")

        this.EvalOverflowMode(LeftPlugins, &modePaged, &alignOuter)

        cX := Round(10 * s)
        hasLeftOfl := HasProp(this, "OflLeftBtn")
        if (hasLeftOfl && alignOuter) {
            this.OflLeftBtn.Move(cX, , Round(35 * s))
            if HasProp(this, "OflLeftDbgBox")
                this.OflLeftDbgBox.Move(cX, , Round(35 * s))
            cX += Round(35 * s) + space
        }
        for p in LeftPlugins {
            if (HasProp(p, "IsPageBreak") && p.IsPageBreak)
                continue
            w := p.ReqWidth()
            if (!p.IsOverflow && w > 0) {
                p.SetVisible(true)
                pL := Round(p.PadL * s), pR := Round(p.PadR * s)
                if HasMethod(p, "MoveCtrls")
                    p.MoveCtrls(cX + pL, Max(0, w - pL - pR))
                if HasProp(p, "DbgBox")
                    p.DbgBox.Move(cX + pL, , Max(0, w - pL - pR))
                cX += w + space
            } else {
                if (w == 0 || modePaged)
                    p.SetVisible(false)
            }
        }
        if (hasLeftOfl && !alignOuter) {
            this.OflLeftBtn.Move(cX, , Round(35 * s))
            if HasProp(this, "OflLeftDbgBox")
                this.OflLeftDbgBox.Move(cX, , Round(35 * s))
        }

        this.EvalOverflowMode(RightPlugins, &modePaged, &alignOuter)
        cX := this.W - Round(10 * s)
        hasRightOfl := HasProp(this, "OflRightBtn")
        if (hasRightOfl && !alignOuter) {
            cX -= Round(35 * s)
            this.OflRightBtn.Move(cX, , Round(35 * s))
            if HasProp(this, "OflRightDbgBox")
                this.OflRightDbgBox.Move(cX, , Round(35 * s))
            cX -= space
        }
        for p in RightPlugins {
            if (HasProp(p, "IsPageBreak") && p.IsPageBreak)
                continue
            w := p.ReqWidth()
            if (!p.IsOverflow && w > 0) {
                p.SetVisible(true)
                cX -= w
                pL := Round(p.PadL * s), pR := Round(p.PadR * s)
                if HasMethod(p, "MoveCtrls")
                    p.MoveCtrls(cX + pL, Max(0, w - pL - pR))
                if HasProp(p, "DbgBox")
                    p.DbgBox.Move(cX + pL, , Max(0, w - pL - pR))
                cX -= space
            } else {
                if (w == 0 || modePaged)
                    p.SetVisible(false)
            }
        }
        if (hasRightOfl && alignOuter) {
            cX -= Round(35 * s)
            this.OflRightBtn.Move(cX, , Round(35 * s))
            if HasProp(this, "OflRightDbgBox")
                this.OflRightDbgBox.Move(cX, , Round(35 * s))
        }

        hasCenterOfl := HasProp(this, "OflCenterBtn")
        this.EvalOverflowMode(CenterPlugins, &modePaged, &alignOuter)
        activeCW := this.CenterPagesW[Min(this.CenterPage, this.CenterPagesW.Length)]
        CenX := (this.W / 2) - (activeCW / 2)
        cX := CenX

        for p in CenterPlugins {
            if (HasProp(p, "IsPageBreak") && p.IsPageBreak)
                continue
            w := p.ReqWidth()
            if (!p.IsOverflow && w > 0) {
                p.SetVisible(true)
                pL := Round(p.PadL * s), pR := Round(p.PadR * s)
                if HasMethod(p, "MoveCtrls")
                    p.MoveCtrls(cX + pL, Max(0, w - pL - pR))
                if HasProp(p, "DbgBox")
                    p.DbgBox.Move(cX + pL, , Max(0, w - pL - pR))
                cX += w + space
            } else {
                if (w == 0 || modePaged)
                    p.SetVisible(false)
            }
        }
        if (hasCenterOfl) {
            btnX := alignOuter ? (this.W / 2) - (activeCW / 2) - Round(35 * s) - Round(10 * s) : (this.W / 2) + (activeCW / 2) + Round(10 * s)
            this.OflCenterBtn.Move(btnX, , Round(35 * s))
        }

        for group in [LeftPlugins, CenterPlugins, RightPlugins] {
            for p in group {
                if (!HasProp(p, "IsOverflow") || !p.IsOverflow) {
                    if HasMethod(p, "SyncShadows")
                        p.SyncShadows()
                }
            }
        }

        DllCall("RedrawWindow", "Ptr", this.Gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185) ; RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW
    }
    MeasureTextWidth(textStr, fontOpt, fontName) {
        dummyGui := Gui()
        dummyGui.SetFont(fontOpt, fontName)
        tc := dummyGui.Add("Text", , textStr)
        ControlGetPos(, , &w, , tc.Hwnd)
        dummyGui.Destroy()
        return w
    }

    ExecuteHotareaAction(actionContext) {
        propAct := actionContext "Action"
        propCust := actionContext "Custom"
        if !Config.General.HasProp(propAct)
            return
        act := Config.General.%propAct%
        cust := Config.General.%propCust%
        if (act == "Show Desktop")
            Send("#d")
        else if (act == "Task View")
            Send("#{Tab}")
        else if (act == "Start Menu")
            Send("{LWin}")
        else if (act == "Custom" && cust != "") {
            try Run(cust)
        }
    }

    RenderPlugins() {
        s := this.Scale
        this.LeftHotareaBtn := this.Gui.Add("Text", "x0 y0 w10 h" this.H " BackgroundTrans", "")
        this.LeftHotareaBtn.OnEvent("Click", (*) => this.ExecuteHotareaAction("LeftHotarea"))
        AppCursorMap[this.LeftHotareaBtn.Hwnd] := 1
        if (Config.General.HasProp("HighlightEdges") && Config.General.HighlightEdges) {
            this.RegisterHover(this.LeftHotareaBtn.Hwnd, "Trans", StrReplace(Config.Theme.IconHover, "#", ""))
            AppHoverMap[this.LeftHotareaBtn.Hwnd].IsBg := 1
        }

        this.RightHotareaBtn := this.Gui.Add("Text", "x" (this.W - 10) " y0 w10 h" this.H " BackgroundTrans", "")
        this.RightHotareaBtn.OnEvent("Click", (*) => this.ExecuteHotareaAction("RightHotarea"))
        AppCursorMap[this.RightHotareaBtn.Hwnd] := 1
        if (Config.General.HasProp("HighlightEdges") && Config.General.HighlightEdges) {
            this.RegisterHover(this.RightHotareaBtn.Hwnd, "Trans", StrReplace(Config.Theme.IconHover, "#", ""))
            AppHoverMap[this.RightHotareaBtn.Hwnd].IsBg := 1
        }

        space := Round(Number(Config.General.Spacing) * s)
        this.EvalOverflowMode(CenterPlugins, &modePaged, &alignOuter)

        this.CenterPagesW := [0]
        curCPg := 1
        for p in CenterPlugins {
            p.App := this
            w := p.ReqWidth()
            if (HasProp(p, "IsPageBreak") && p.IsPageBreak && w > 0) {
                curCPg++
                this.CenterPagesW.Push(0)
                continue
            }
            if (w > 0)
                this.CenterPagesW[curCPg] += w + space
        }
        for i, val in this.CenterPagesW {
            if (val > 0)
                this.CenterPagesW[i] -= space
        }
        if (!HasProp(this, "CenterPage"))
            this.CenterPage := 1

        activeCW := this.CenterPagesW[Min(this.CenterPage, this.CenterPagesW.Length)]
        CenX := (this.W / 2) - (activeCW / 2)
        LeftMax := CenX - Round(40 * s)
        RightMin := CenX + activeCW + Round(40 * s)
        olW := Round(35 * s)

        this.OflLeftGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x02000000 +Owner" this.Gui.Hwnd)
        this.OflLeftGui.BackColor := Config.Theme.BarBg
        ;if (Config.Theme.HasProp("UseMica") && Config.Theme.UseMica == "1")
        ;    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.OflLeftGui.Hwnd, "Int", 38, "Int*", 2, "Int", 4)
        if (Config.Theme.HasProp("BarAlpha") && Config.Theme.BarAlpha != "255")
            WinSetTransparent(Config.Theme.BarAlpha, this.OflLeftGui.Hwnd)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.OflLeftGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)

        this.OflRightGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x02000000 +Owner" this.Gui.Hwnd)
        this.OflRightGui.BackColor := Config.Theme.BarBg
        ;if (Config.Theme.HasProp("UseMica") && Config.Theme.UseMica == "1")
        ;    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.OflRightGui.Hwnd, "Int", 38, "Int*", 2, "Int", 4)
        if (Config.Theme.HasProp("BarAlpha") && Config.Theme.BarAlpha != "255")
            WinSetTransparent(Config.Theme.BarAlpha, this.OflRightGui.Hwnd)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.OflRightGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)

        this.OflCenterGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x02000000 +Owner" this.Gui.Hwnd)
        this.OflCenterGui.BackColor := Config.Theme.BarBg
        if (Config.Theme.HasProp("BarAlpha") && Config.Theme.BarAlpha != "255")
            WinSetTransparent(Config.Theme.BarAlpha, this.OflCenterGui.Hwnd)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.OflCenterGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)

        this.EvalOverflowMode(LeftPlugins, &modePaged, &alignOuter)
        if (!HasProp(this, "LeftPage"))
            this.LeftPage := 1
        if (!HasProp(this, "RightPage"))
            this.RightPage := 1

        this.LeftOflPlugins := []
        this.LeftOflTot := 0
        reqW := 0, hasLeftOfl := false
        for p in LeftPlugins {
            p.App := this
            w := p.ReqWidth()
            if (HasProp(p, "IsPageBreak") && p.IsPageBreak && w > 0) {
                hasLeftOfl := true
                break
            }
            if (w > 0) {
                reqW += w + space
                if (Round(10 * s) + reqW > LeftMax) {
                    hasLeftOfl := true
                    break
                }
            }
        }
        cX := Round(10 * s)
        if (hasLeftOfl && alignOuter)
            cX += olW + space

        currentPage := 1
        forceOverflow := false
        for p in LeftPlugins {
            p.App := this
            w := p.ReqWidth()
            if (w == 0) {
                p.IsOverflow := false
                p.Page := 1
                if !(HasProp(p, "IsPageBreak") && p.IsPageBreak) {
                    p.Render(this.Gui, "Left", cX, this.H, 0)
                    p.SetVisible(false)
                }
                continue
            }

            if (HasProp(p, "IsPageBreak") && p.IsPageBreak) {
                if (modePaged) {
                    currentPage++
                    cX := Round(10 * s) + (alignOuter ? (olW + space) : 0)
                } else {
                    forceOverflow := true
                }
                p.IsOverflow := false
                p.Page := 1
                continue
            }

            pL := Round(p.PadL * s), pR := Round(p.PadR * s)
            edgeLimit := LeftMax - ((hasLeftOfl && !alignOuter) ? olW : 0)
            if (cX + w > edgeLimit || forceOverflow) {
                if (modePaged) {
                    currentPage++
                    cX := Round(10 * s) + (alignOuter ? (olW + space) : 0)
                } else {
                    p.IsOverflow := true
                    p.Page := 1
                    this.LeftOflPlugins.Push(p)
                    continue
                }
            }
            p.Page := currentPage

            p.IsOverflow := modePaged ? (p.Page != this.LeftPage) : false
            if (!modePaged && Config.General.VisualDebug)
                p.DbgBox := this.Gui.Add("Text", "x" (cX + pL) " y0 w" Max(0, w - pL - pR) " h" this.H " 0x12 BackgroundTrans E0x20", "")
            else if (modePaged && Config.General.VisualDebug)
                p.DbgBox := this.Gui.Add("Text", "x" (cX + pL) " y0 w" Max(0, w - pL - pR) " h" this.H " 0x12 BackgroundTrans E0x20", "")
            p.Render(this.Gui, "Left", cX + pL, this.H, Max(0, w - pL - pR))
            if (p.IsOverflow)
                p.SetVisible(false)
            cX += w + space
        }
        this.LeftTotalPages := currentPage

        if (!modePaged && this.LeftOflPlugins.Length > 0) {
            this.LeftOflTot := Round(10 * s)
            for p in this.LeftOflPlugins {
                w := p.ReqWidth()
                pL := Round(p.PadL * s), pR := Round(p.PadR * s)
                if (Config.General.VisualDebug)
                    p.DbgBox := this.OflLeftGui.Add("Text", "x" (this.LeftOflTot + pL) " y0 w" Max(0, w - pL - pR) " h" this.H " 0x12 BackgroundTrans E0x20", "")
                p.Render(this.OflLeftGui, "Left", this.LeftOflTot + pL, this.H, Max(0, w - pL - pR))
                this.LeftOflTot += w + space
            }
            if (this.LeftOflPlugins.Length > 0)
                this.LeftOflTot += Round(10 * s) - space
        }
        if (hasLeftOfl) {
            btnX := alignOuter ? Round(10 * s) : cX
            this.Gui.SetFont("s" Round(13 * s) " q5 c" Config.Theme.Icon, Config.Theme.IconFont)
            iconStr := modePaged ? Chr(0xE76C) : Chr(0xE712)
            if (modePaged && this.LeftPage >= this.LeftTotalPages)
                iconStr := Chr(0xE76B)
            this.OflLeftBtn := this.Gui.Add("Text", "x" btnX " y0 w" olW " h" this.H " 0x200 Center BackgroundTrans", iconStr)
            if (Config.General.VisualDebug)
                this.OflLeftDbgBox := this.Gui.Add("Text", "x" btnX " y0 w" olW " h" this.H " 0x12 BackgroundTrans E0x20", "")
            this.RegisterHover(this.OflLeftBtn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
            if (modePaged)
                this.OflLeftBtn.OnEvent("Click", (*) => this.ToggleLeftPage())
            else
                this.OflLeftBtn.OnEvent("Click", (*) => this.TogglePopup(this.OflLeftGui, this.OflLeftBtn.Hwnd, this.LeftOflTot, this.H))
            this.OflLeftBtn.OnEvent("ContextMenu", (*) => this.OpenPageBreakSettings("Left"))
        }

        this.EvalOverflowMode(RightPlugins, &modePaged, &alignOuter)
        this.RightOflPlugins := []
        this.RightOflTot := 0
        reqW := 0, hasRightOfl := false
        for p in RightPlugins {
            p.App := this
            w := p.ReqWidth()
            if (HasProp(p, "IsPageBreak") && p.IsPageBreak && w > 0) {
                hasRightOfl := true
                break
            }
            if (w > 0) {
                reqW += w + space
                if (this.W - Round(10 * s) - reqW < RightMin) {
                    hasRightOfl := true
                    break
                }
            }
        }
        cX := this.W - Round(10 * s)
        if (hasRightOfl && alignOuter)
            cX -= olW + space

        currentPage := 1
        forceOverflow := false
        for p in RightPlugins {
            p.App := this
            w := p.ReqWidth()
            if (w == 0) {
                p.IsOverflow := false
                p.Page := 1
                if !(HasProp(p, "IsPageBreak") && p.IsPageBreak) {
                    p.Render(this.Gui, "Right", cX, this.H, 0)
                    p.SetVisible(false)
                }
                continue
            }

            if (HasProp(p, "IsPageBreak") && p.IsPageBreak) {
                if (modePaged) {
                    currentPage++
                    cX := this.W - Round(10 * s) - (alignOuter ? (olW + space) : 0)
                } else {
                    forceOverflow := true
                }
                p.IsOverflow := false
                p.Page := 1
                continue
            }

            pL := Round(p.PadL * s), pR := Round(p.PadR * s)
            edgeLimit := RightMin + ((hasRightOfl && !alignOuter) ? olW : 0)
            if (cX - w < edgeLimit || forceOverflow) {
                if (modePaged) {
                    currentPage++
                    cX := this.W - Round(10 * s) - (alignOuter ? (olW + space) : 0)
                } else {
                    p.IsOverflow := true
                    p.Page := 1
                    this.RightOflPlugins.Push(p)
                    continue
                }
            }
            p.Page := currentPage

            p.IsOverflow := modePaged ? (p.Page != this.RightPage) : false
            if (modePaged) {
                if (Config.General.VisualDebug)
                    p.DbgBox := this.Gui.Add("Text", "x" (cX - w + pL) " y0 w" Max(0, w - pL - pR) " h" this.H " 0x12 BackgroundTrans E0x20", "")
                p.Render(this.Gui, "Right", cX - w + pL, this.H, Max(0, w - pL - pR))
            } else {
                cX -= w
                if (Config.General.VisualDebug)
                    p.DbgBox := this.Gui.Add("Text", "x" (cX + pL) " y0 w" Max(0, w - pL - pR) " h" this.H " 0x12 BackgroundTrans E0x20", "")
                p.Render(this.Gui, "Right", cX + pL, this.H, Max(0, w - pL - pR))
                cX -= space
                continue
            }
            if (p.IsOverflow)
                p.SetVisible(false)
            cX -= w + space
        }
        this.RightTotalPages := currentPage

        if (!modePaged && this.RightOflPlugins.Length > 0) {
            this.RightOflTot := Round(10 * s)
            for p in this.RightOflPlugins
                this.RightOflTot += p.ReqWidth() + space
            this.RightOflTot += Round(10 * s) - space

            rOflX := this.RightOflTot - Round(10 * s)
            for p in this.RightOflPlugins {
                w := p.ReqWidth()
                pL := Round(p.PadL * s), pR := Round(p.PadR * s)
                rOflX -= w
                if (Config.General.VisualDebug)
                    p.DbgBox := this.OflRightGui.Add("Text", "x" (rOflX + pL) " y0 w" Max(0, w - pL - pR) " h" this.H " 0x12 BackgroundTrans E0x20", "")
                p.Render(this.OflRightGui, "Right", rOflX + pL, this.H, Max(0, w - pL - pR))
                rOflX -= space
            }
        }
        if (hasRightOfl) {
            btnX := alignOuter ? (this.W - Round(10 * s) - olW) : cX
            this.Gui.SetFont("s" Round(13 * s) " q5 c" Config.Theme.Icon, Config.Theme.IconFont)
            iconStr := modePaged ? Chr(0xE76B) : Chr(0xE712)
            if (modePaged && this.RightPage >= this.RightTotalPages)
                iconStr := Chr(0xE76C)
            this.OflRightBtn := this.Gui.Add("Text", "x" btnX " y0 w" olW " h" this.H " 0x200 Center BackgroundTrans", iconStr)
            if (Config.General.VisualDebug)
                this.OflRightDbgBox := this.Gui.Add("Text", "x" btnX " y0 w" olW " h" this.H " 0x12 BackgroundTrans E0x20", "")
            this.RegisterHover(this.OflRightBtn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
            if (modePaged)
                this.OflRightBtn.OnEvent("Click", (*) => this.ToggleRightPage())
            else
                this.OflRightBtn.OnEvent("Click", (*) => this.TogglePopup(this.OflRightGui, this.OflRightBtn.Hwnd, this.RightOflTot, this.H))
            this.OflRightBtn.OnEvent("ContextMenu", (*) => this.OpenPageBreakSettings("Right"))
        }

        this.EvalOverflowMode(CenterPlugins, &modePaged, &alignOuter)
        cX := CenX
        this.CenterTotalPages := this.CenterPagesW.Length
        curCPg := 1
        forceOverflow := false
        this.CenterOflPlugins := []
        this.CenterOflTot := 0

        for p in CenterPlugins {
            w := p.ReqWidth()
            if (w == 0) {
                p.IsOverflow := false
                p.Page := 1
                if !(HasProp(p, "IsPageBreak") && p.IsPageBreak) {
                    p.Render(this.Gui, "Center", cX, this.H, 0)
                    p.SetVisible(false)
                }
                continue
            }
            if (HasProp(p, "IsPageBreak") && p.IsPageBreak) {
                if (modePaged) {
                    curCPg++
                    cX := (this.W / 2) - ((this.CenterPagesW.Length >= curCPg ? this.CenterPagesW[curCPg] : 0) / 2)
                } else {
                    forceOverflow := true
                }
                p.IsOverflow := false
                p.Page := 1
                continue
            }

            if (forceOverflow) {
                p.IsOverflow := true
                p.Page := 1
                this.CenterOflPlugins.Push(p)
                continue
            }

            p.Page := curCPg
            p.IsOverflow := modePaged ? (p.Page != this.CenterPage) : false
            pL := Round(p.PadL * s), pR := Round(p.PadR * s)
            if (Config.General.VisualDebug)
                p.DbgBox := this.Gui.Add("Text", "x" (cX + pL) " y0 w" Max(0, w - pL - pR) " h" this.H " 0x12 BackgroundTrans E0x20", "")
            p.Render(this.Gui, "Center", cX + pL, this.H, Max(0, w - pL - pR))
            if (p.IsOverflow)
                p.SetVisible(false)
            cX += w + space
        }

        hasCenterOfl := (this.CenterTotalPages > 1) || (this.CenterOflPlugins.Length > 0)
        if (!modePaged && this.CenterOflPlugins.Length > 0) {
            this.CenterOflTot := Round(10 * s)
            for p in this.CenterOflPlugins {
                w := p.ReqWidth()
                pL := Round(p.PadL * s), pR := Round(p.PadR * s)
                if (Config.General.VisualDebug)
                    p.DbgBox := this.OflCenterGui.Add("Text", "x" (this.CenterOflTot + pL) " y0 w" Max(0, w - pL - pR) " h" this.H " 0x12 BackgroundTrans E0x20", "")
                p.Render(this.OflCenterGui, "Center", this.CenterOflTot + pL, this.H, Max(0, w - pL - pR))
                this.CenterOflTot += w + space
            }
            if (this.CenterOflPlugins.Length > 0)
                this.CenterOflTot += Round(10 * s) - space
        }

        if (hasCenterOfl) {
            this.Gui.SetFont("s" Round(13 * s) " q5 c" Config.Theme.Icon, Config.Theme.IconFont)
            iconStr := modePaged ? Chr((this.CenterPage >= this.CenterTotalPages) ? 0xE76B : 0xE76C) : Chr(0xE712)
            btnX := alignOuter ? (this.W / 2) - (this.CenterPagesW[modePaged ? this.CenterPage : 1] / 2) - Round(35 * s) - Round(10 * s) : (this.W / 2) + (this.CenterPagesW[modePaged ? this.CenterPage : 1] / 2) + Round(10 * s)
            this.OflCenterBtn := this.Gui.Add("Text", "x" btnX " y0 w" olW " h" this.H " 0x200 Center BackgroundTrans", iconStr)
            this.RegisterHover(this.OflCenterBtn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
            if (modePaged)
                this.OflCenterBtn.OnEvent("Click", (*) => this.ToggleCenterPage())
            else
                this.OflCenterBtn.OnEvent("Click", (*) => this.TogglePopup(this.OflCenterGui, this.OflCenterBtn.Hwnd, this.CenterOflTot, this.H))
            this.OflCenterBtn.OnEvent("ContextMenu", (*) => this.OpenPageBreakSettings("Center"))
        }

        this.IsRendered := true
        this.Reflow()
    }

    OpenPageBreakSettings(groupName) {
        plugins := (groupName == "Left") ? LeftPlugins : ((groupName == "Center") ? CenterPlugins : RightPlugins)
        for p in plugins {
            if (HasProp(p, "IsPageBreak") && p.IsPageBreak) {
                if HasMethod(p, "ShowSettings")
                    p.ShowSettings()
                break
            }
        }
    }

    ToggleCenterPage() {
        if (this.CenterPage >= this.CenterTotalPages)
            this.CenterPage := 1
        else
            this.CenterPage++
        for p in CenterPlugins {
            if !HasProp(p, "Page")
                continue
            if (p.Page == this.CenterPage) {
                p.IsOverflow := false
                p.SetVisible(true)
            } else {
                p.IsOverflow := true
                p.SetVisible(false)
            }
        }
        this.OflCenterBtn.Value := (this.CenterPage >= this.CenterTotalPages) ? Chr(0xE76B) : Chr(0xE76C)
        this.Reflow()
    }

    ToggleLeftPage() {
        if (this.LeftPage >= this.LeftTotalPages)
            this.LeftPage := 1
        else
            this.LeftPage++
        for p in LeftPlugins {
            if !HasProp(p, "Page")
                continue
            if (p.Page == this.LeftPage) {
                p.IsOverflow := false
                p.SetVisible(true)
            } else {
                p.IsOverflow := true
                p.SetVisible(false)
            }
        }
        this.OflLeftBtn.Value := (this.LeftPage >= this.LeftTotalPages) ? Chr(0xE76B) : Chr(0xE76C)
        this.Reflow()
    }

    ToggleRightPage() {
        if (this.RightPage >= this.RightTotalPages)
            this.RightPage := 1
        else
            this.RightPage++
        for p in RightPlugins {
            if !HasProp(p, "Page")
                continue
            if (p.Page == this.RightPage) {
                p.IsOverflow := false
                p.SetVisible(true)
            } else {
                p.IsOverflow := true
                p.SetVisible(false)
            }
        }
        this.OflRightBtn.Value := (this.RightPage >= this.RightTotalPages) ? Chr(0xE76C) : Chr(0xE76B)
        this.Reflow()
    }

    RegisterHover(hwnd, cNormal, cHover, groupHwnds := "", cbHover := "") {
        AppHoverMap[hwnd] := { Normal: cNormal, Hover: cHover, Group: groupHwnds, Callback: cbHover }
    }

    TogglePopup(popupGui, triggerHwnd, pW, pH, forceX := "", forceY := "", noToggle := false) {
        if (!triggerHwnd || !DllCall("IsWindowVisible", "Ptr", triggerHwnd)) {
            try popupGui.Destroy()
            return
        }

        if (this.ActivePopup == popupGui || (HasProp(this, "ActiveSubPopup") && this.ActiveSubPopup == popupGui)) {
            if (noToggle)
                return
            this.ClosePopup()
            return
        }

        parentGuiHwnd := DllCall("GetAncestor", "Ptr", triggerHwnd, "UInt", 1, "Ptr")
        if (!parentGuiHwnd) {
            try popupGui.Destroy()
            return
        }

        isSubPopup := (this.ActivePopup && this.ActivePopup.Hwnd == parentGuiHwnd)

        if (!isSubPopup && this.ActivePopup)
            this.ClosePopup()

        tX := 0, tY := 0, tW := 0, tH := 0
        try WinGetPos(&tX, &tY, &tW, &tH, "ahk_id " triggerHwnd)

        dropX := forceX != "" ? forceX : tX + (tW / 2) - (pW / 2)
        dropY := forceY != "" ? forceY : tY + tH + Round(5 * this.Scale)

        MInfo := Buffer(40, 0), NumPut("UInt", 40, MInfo)
        DllCall("GetMonitorInfo", "Ptr", DllCall("MonitorFromWindow", "Ptr", parentGuiHwnd, "UInt", 2, "Ptr"), "Ptr", MInfo)
        WAL := NumGet(MInfo, 20, "Int"), WAT := NumGet(MInfo, 24, "Int"), WAR := NumGet(MInfo, 28, "Int"), WAB := NumGet(MInfo, 32, "Int")

        if (dropX + pW > WAR)
            dropX := WAR - pW - Round(10 * this.Scale)
        if (dropX < WAL)
            dropX := WAL + Round(10 * this.Scale)

        if (dropY + pH > WAB)
            dropY := tY - pH - Round(5 * this.Scale)
        if (dropY < WAT)
            dropY := WAT + Round(10 * this.Scale)

        if (isSubPopup && HasProp(this, "ActiveSubPopup") && this.ActiveSubPopup) {
            if HasProp(this.ActiveSubPopup, "OnCloseCb") && this.ActiveSubPopup.OnCloseCb
                try this.ActiveSubPopup.OnCloseCb()
            try this.ActiveSubPopup.Hide()
            if HasProp(this.ActiveSubPopup, "IsDynamic") && this.ActiveSubPopup.IsDynamic
                try this.ActiveSubPopup.Destroy()
        }

        if (!HasProp(popupGui, "SkipAlpha") && Config.Theme.HasProp("PopupAlpha") && Config.Theme.PopupAlpha != "255")
            WinSetTransparent(Config.Theme.PopupAlpha, popupGui.Hwnd)

        popupGui.Show("x" dropX " y" dropY " w" pW " h" pH " NoActivate")

        if (isSubPopup) {
            this.ActiveSubPopup := popupGui
            this.ActiveSubTrigger := triggerHwnd
        } else {
            this.ActivePopup := popupGui
            this.ActiveTrigger := triggerHwnd
            try this.PopupActiveWin := WinExist("A")
            catch
                this.PopupActiveWin := 0

            if !HasProp(this, "GlobalClickHook")
                this.GlobalClickHook := ObjBindMethod(this, "OnGlobalClick")
        }
    }

    ClosePopup() {
        if (HasProp(this, "ActiveDropdown") && this.ActiveDropdown) {
            try this.ActiveDropdown.Destroy()
            this.ActiveDropdown := false
        }
        if (HasProp(this, "ActiveSubPopup") && this.ActiveSubPopup) {
            if HasProp(this.ActiveSubPopup, "OnCloseCb") && this.ActiveSubPopup.OnCloseCb
                try this.ActiveSubPopup.OnCloseCb()
            try this.ActiveSubPopup.Hide()
            if HasProp(this.ActiveSubPopup, "IsDynamic") && this.ActiveSubPopup.IsDynamic
                try this.ActiveSubPopup.Destroy()
            this.ActiveSubPopup := ""
            this.ActiveSubTrigger := 0
        }
        if (this.ActivePopup) {
            if HasProp(this.ActivePopup, "OnCloseCb") && this.ActivePopup.OnCloseCb
                try this.ActivePopup.OnCloseCb()
            try this.ActivePopup.Hide()
            if HasProp(this.ActivePopup, "IsDynamic") && this.ActivePopup.IsDynamic
                try this.ActivePopup.Destroy()

            this.ActivePopup := ""
            this.ActiveTrigger := 0
            if HasProp(this, "GlobalClickHook") {
                try Hotkey("Left", "Off")
                try Hotkey("Right", "Off")
            }
        }
    }

    CleanupDropdownHook() {
        ; Replaced with passive polling
    }

    OnGlobalClick(*) {
        if (HasProp(this, "IgnoreClicksUntil") && A_TickCount < this.IgnoreClicksUntil)
            return
        if (!this.ActivePopup && !(HasProp(this, "ActiveDropdown") && this.ActiveDropdown))
            return

        try MouseGetPos(, , &mWin, &mCtrl, 2)
        catch
            return

        if (HasProp(this, "ActiveDropdown") && this.ActiveDropdown) {
            try dHwnd := this.ActiveDropdown.Hwnd
            catch {
                dHwnd := 0
                this.ActiveDropdown := false
            }
            if (dHwnd && mWin == dHwnd)
                return
            if (dHwnd)
                try this.ActiveDropdown.Destroy()
            this.ActiveDropdown := false
            this.CleanupDropdownHook()

            if (!this.ActivePopup)
                return
            try {
                if (mWin == this.ActivePopup.Hwnd || mWin == this.Gui.Hwnd || (HasProp(this, "ActiveSubPopup") && this.ActiveSubPopup && mWin == this.ActiveSubPopup.Hwnd))
                    return
            }
        }

        pHwnd := 0
        if (this.ActivePopup) {
            try pHwnd := this.ActivePopup.Hwnd
            catch {
                this.ActivePopup := ""
                return
            }
        }

        if (pHwnd && mWin != pHwnd && mWin != this.Gui.Hwnd) {
            try {
                if (IsSet(mCtrl) && HasProp(this.ActivePopup, "AnchorHwnd") && this.ActivePopup.AnchorHwnd == mCtrl)
                    return

                cWin := mWin
                while (cWin) {
                    if (cWin == pHwnd)
                        return
                    cWin := DllCall("GetAncestor", "Ptr", cWin, "UInt", 1) ; GA_PARENT=1
                }
            }
            this.ClosePopup()
        }
    }

    BuildDropdown(parentGui, targetBg, targetText, optionsList, varObj?, varKey?, cbFun?, *) {
        if HasProp(this, "ActiveDropdown") && this.ActiveDropdown {
            try this.ActiveDropdown.Destroy()
            this.ActiveDropdown := false
            return
        }

        drop := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x08000000 +Owner" parentGui.Hwnd)
        this.ActiveDropdown := drop
        drop.BackColor := BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10)
        drop.MarginY := 4, drop.MarginX := 4
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", drop.Hwnd, "Int", 19, "Int*", 1, "Int", 4)

        yP := 4
        for idx, opt in optionsList {
            dispTxt := (IsObject(opt) && opt.HasProp("Disp")) ? opt.Disp : opt
            valTxt := (IsObject(opt) && opt.HasProp("Val")) ? opt.Val : opt

            itemBg := drop.Add("Text", "x4 y" yP " w212 h32 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10), "")
            drop.SetFont("s10 q5 cWhite", Config.Theme.Font)
            itemTxt := drop.Add("Text", "x12 y" (yP + 6) " w196 h20 BackgroundTrans cWhite", dispTxt)

            act := ((cbIdx, txt, *) => (
                targetText.Value := txt,
                IsSet(varObj) ? (varObj.%varKey% := cbIdx) : "",
                drop.Destroy(),
                this.ActiveDropdown := false,
                this.CleanupDropdownHook(),
                (IsSet(cbFun) && HasMethod(cbFun, "Call")) ? cbFun() : ""
            )).Bind(idx, valTxt)

            itemBg.OnEvent("Click", act), itemTxt.OnEvent("Click", act)
            this.RegisterHover(itemBg.Hwnd, BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10), BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15))
            AppCursorMap[itemBg.Hwnd] := 1, AppCursorMap[itemTxt.Hwnd] := 1

            yP += 32
        }

        WinGetClientPos(&gX, &gY, , , parentGui.Hwnd)
        ControlGetPos(&cX, &cY, &cW, &cH, targetBg.Hwnd, parentGui.Hwnd)
        drop.Show("x" (gX + cX) " y" (gY + cY + cH + 4) " w220 h" (yP + 4) " NoActivate")
        this.IgnoreClicksUntil := A_TickCount + 200

        if !HasProp(this, "GlobalClickHook")
            this.GlobalClickHook := ObjBindMethod(this, "OnGlobalClick")
    }

    TickUpdate() {
        needsReflow := false
        for group in [LeftPlugins, CenterPlugins, RightPlugins] {
            for p in group {
                if HasMethod(this, "EvalPluginRules") {
                    pName := StrReplace(p.__Class, "Plugin", "")
                    rStat := this.EvalPluginRules(pName)
                    if (!HasProp(p, "RuleState") || p.RuleState != rStat) {
                        p.RuleState := rStat
                        needsReflow := true
                        if (HasProp(p, "IsPageBreak") && p.IsPageBreak)
                            needsReload := true
                    }
                }
                isVisible := false
                if (!HasProp(p, "IsOverflow") || !p.IsOverflow) {
                    isVisible := true
                } else if (this.ActivePopup) {
                    if (group == LeftPlugins && HasProp(this, "OflLeftGui") && this.ActivePopup == this.OflLeftGui)
                        isVisible := true
                    else if (group == CenterPlugins && HasProp(this, "OflCenterGui") && this.ActivePopup == this.OflCenterGui)
                        isVisible := true
                    else if (group == RightPlugins && HasProp(this, "OflRightGui") && this.ActivePopup == this.OflRightGui)
                        isVisible := true
                }

                if (isVisible) {
                    if HasMethod(p, "Update")
                        p.Update()
                    if HasMethod(p, "SyncShadows")
                        p.SyncShadows()
                }
            }
        }
        if (needsReflow || (HasProp(this, "needsReflow") && this.needsReflow)) {
            this.needsReflow := false
            this.Reflow()
        }
    }

    EvalPluginRules(pName) {
        if (!Config.PluginRules.Has(pName) || Config.PluginRules[pName] == "")
            return 0

        savedTMM := A_TitleMatchMode
        savedDH := A_DetectHiddenWindows
        SetTitleMatchMode 2

        rules := StrSplit(Config.PluginRules[pName], "###")
        defAct := "Show"

        for ruleLine in rules {
            if !ruleLine
                continue

            if !InStr(ruleLine, "|") {
                if (A_Index == 1 && (ruleLine == "Show" || ruleLine == "Hide"))
                    defAct := ruleLine
                continue
            }

            parts := StrSplit(ruleLine, "|")
            if (parts.Length < 3)
                continue

            act := parts[1]
            state := parts[2]
            str := StrReplace(parts[3], "*", "")
            match := false

            chkExe := "ahk_exe " str (InStr(str, ".exe") ? "" : ".exe")

            if (state == "Active") {
                match := WinActive(str) || WinActive("ahk_exe " str) || WinActive(chkExe)
            } else if (state == "Visible") {
                match := WinExist(str) || WinExist("ahk_exe " str) || WinExist(chkExe)
            } else if (state == "Running") {
                match := ProcessExist(str) || ProcessExist(str ".exe")
                if (!match) {
                    DetectHiddenWindows True
                    match := WinExist(str) || WinExist("ahk_exe " str) || WinExist(chkExe)
                    DetectHiddenWindows False
                }
            }

            if match {
                SetTitleMatchMode savedTMM
                DetectHiddenWindows savedDH
                return act == "Show" ? 1 : -1
            }
        }

        SetTitleMatchMode savedTMM
        DetectHiddenWindows savedDH
        return defAct == "Hide" ? -1 : 0
    }

    TickHover() {
        static lastHwnd := 0
        static lastClick := false
        mCtrl := 0

        isClicked := GetKeyState("LButton", "P") || GetKeyState("RButton", "P")
        if (isClicked && !lastClick && HasProp(this, "GlobalClickHook"))
            this.OnGlobalClick()
        lastClick := isClicked

        try {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mX, &mY, &mWin)
            CoordMode("Mouse", "Client")

            if (mWin) {
                processID := 0
                DllCall("GetWindowThreadProcessId", "Ptr", mWin, "UInt*", &processID)
                if (processID == DllCall("GetCurrentProcessId")) {
                    POINT := Buffer(8)
                    NumPut("Int", mX, "Int", mY, POINT)
                    DllCall("ScreenToClient", "Ptr", mWin, "Ptr", POINT)
                    clX := NumGet(POINT, 0, "Int")
                    clY := NumGet(POINT, 4, "Int")

                    for hwnd, obj in AppHoverMap {
                        if (DllCall("IsWindowVisible", "Ptr", hwnd) && DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") == mWin) {
                            ControlGetPos(&cX, &cY, &cW, &cH, hwnd)
                            if (clX >= cX && clX <= cX + cW && clY >= cY && clY <= cY + cH) {
                                mCtrl := hwnd
                                break
                            }
                        }
                    }
                }
            }
        }
        if (this.ActivePopup && HasProp(this, "PopupActiveWin")) {
            if (HasProp(this, "IgnoreClicksUntil") && A_TickCount < this.IgnoreClicksUntil)
                return
            try curA := WinExist("A")
            catch
                curA := 0
            try pHwnd := this.ActivePopup.Hwnd
            catch {
                pHwnd := 0
                this.ActivePopup := ""
            }
            if (curA && this.PopupActiveWin && curA != this.PopupActiveWin && curA != pHwnd)
                this.ClosePopup()
        }
        if (mCtrl != lastHwnd) {
            if (lastHwnd && AppHoverMap.Has(lastHwnd))
                this.SetHoverColor(lastHwnd, "Normal")
            if (mCtrl && AppHoverMap.Has(mCtrl))
                this.SetHoverColor(mCtrl, "Hover")
            lastHwnd := mCtrl
        }

        if (Config.General.HasProp("AutoHide") && Config.General.AutoHide) {
            sens := Config.General.HasProp("AutoHideSens") ? Config.General.AutoHideSens : 1
            delay := Config.General.HasProp("AutoHideDelay") ? Config.General.AutoHideDelay : 300
            
            isHoveringBar := false
            if (mWin == this.Gui.Hwnd) {
                isHoveringBar := true
            } else if (mY >= this.MonY && mY <= this.MonY + sens) {
                if (mX >= this.MonX && mX <= this.MonX + this.W) {
                    isHoveringBar := true
                }
            } else if (this.ActivePopup || (HasProp(this, "ActiveDropdown") && this.ActiveDropdown)) {
                isHoveringBar := true
            }
            
            if (isHoveringBar) {
                if (!HasProp(this, "HoverStartTime"))
                    this.HoverStartTime := A_TickCount
                
                if (A_TickCount - this.HoverStartTime >= delay) {
                    if (!HasProp(this, "BarVisible") || !this.BarVisible) {
                        this.BarVisible := true
                        this.Gui.Show("x" this.MonX " y" this.MonY " w" this.W " h" this.H " NoActivate")
                    }
                }
            } else {
                this.HoverStartTime := A_TickCount
                if (!HasProp(this, "BarVisible") || this.BarVisible) {
                    this.BarVisible := false
                    this.Gui.Show("x" this.MonX " y" (this.MonY - this.H - 10) " w" this.W " h" this.H " NoActivate")
                }
            }
        }
    }

    CheckFullscreen() {
        if (Config.General.HasProp("AutoHide") && Config.General.AutoHide) {
            this.SetBarZOrder(true)
            return
        }
        try {
            hWnd := WinActive("A")
            if (!hWnd)
                return

            cls := WinGetClass(hWnd)
            if (hWnd == this.Gui.Hwnd || cls == "WorkerW" || cls == "Progman" || cls == "Shell_TrayWnd" || cls == "TaskSwitcherWnd" || cls == "MultitaskingViewFrame" || InStr(cls, "XamlExplorer")) {
                this.SetBarZOrder(true)
                return
            }

            WinGetPos(&X, &Y, &W, &H, hWnd)
            MonitorGet(MonitorGetPrimary(), &ML, &MT, &MR, &MB)

            if (X <= ML && Y <= MT && W >= (MR - ML) && H >= (MB - MT)) {
                this.SetBarZOrder(false)
            } else {
                this.SetBarZOrder(true)
            }
        } catch {
            this.SetBarZOrder(true)
        }
    }

    SetBarZOrder(onTop) {
        if (!HasProp(this, "IsOnTop"))
            this.IsOnTop := true

        if (this.IsOnTop != onTop) {
            this.IsOnTop := onTop
            if (onTop) {
                try WinSetAlwaysOnTop(1, "ahk_id " this.Gui.Hwnd)
            } else {
                try WinSetAlwaysOnTop(0, "ahk_id " this.Gui.Hwnd)
                try WinMoveBottom("ahk_id " this.Gui.Hwnd)
            }
        }
    }

    SetHoverColor(hwnd, state) {
        obj := AppHoverMap[hwnd]
        try col := obj.HasProp(state) ? obj.%state% : (state == "Normal" ? (obj.HasProp("Def") ? obj.Def : StrReplace(Config.Theme.Text, "#", "")) : (obj.HasProp("Hov") ? obj.Hov : StrReplace(Config.Theme.IconHover, "#", "")))
        catch {
            col := StrReplace(Config.Theme.Text, "#", "")
        }
        try {
            optKey := (obj.HasProp("IsBg") && obj.IsBg) ? "Background" : "c"
            if (obj.Group && state == "Hover") {
                for h in obj.Group {
                    GuiCtrlFromHwnd(h).Opt("c" col)
                    GuiCtrlFromHwnd(h).Redraw()
                }
            } else if (obj.Group && state == "Normal") {
                for h in obj.Group {
                    try normCol := AppHoverMap[h].HasProp("Normal") ? AppHoverMap[h].Normal : AppHoverMap[h].Def
                    catch {
                        normCol := StrReplace(Config.Theme.Text, "#", "")
                    }
                    GuiCtrlFromHwnd(h).Opt("c" normCol)
                    GuiCtrlFromHwnd(h).Redraw()
                }
            } else {
                if (optKey == "Background" && col == "Trans")
                    GuiCtrlFromHwnd(hwnd).Opt("BackgroundTrans")
                else
                    GuiCtrlFromHwnd(hwnd).Opt(optKey col)
                GuiCtrlFromHwnd(hwnd).Redraw()
            }
            if (state == "Hover" && obj.HasProp("Callback") && obj.Callback)
                try obj.Callback()
        }
    }

    ReserveSpace() {
        if (Config.General.HasProp("AutoHide") && Config.General.AutoHide) {
            this.BarVisible := false
            this.Gui.Show("x" this.MonX " y" (this.MonY - this.H - 10) " w" this.W " h" this.H " NoActivate")
            return
        }

        this.cbSize := A_PtrSize == 8 ? 48 : 36
        this.abd := Buffer(this.cbSize, 0)
        NumPut("UInt", this.cbSize, this.abd, 0)
        NumPut("Ptr", this.Gui.Hwnd, this.abd, A_PtrSize == 8 ? 8 : 4)
        NumPut("UInt", 0x8000, this.abd, A_PtrSize == 8 ? 16 : 8)
        NumPut("UInt", 1, this.abd, A_PtrSize == 8 ? 20 : 12)

        DllCall("Shell32.dll\SHAppBarMessage", "UInt", 0, "Ptr", this.abd)

        rc := A_PtrSize == 8 ? 24 : 16
        NumPut("Int", this.MonX, this.abd, rc)
        NumPut("Int", this.MonY, this.abd, rc + 4)
        NumPut("Int", this.MonX + this.W, this.abd, rc + 8)
        NumPut("Int", this.MonY + this.H, this.abd, rc + 12)

        DllCall("Shell32.dll\SHAppBarMessage", "UInt", 2, "Ptr", this.abd)
        top := NumGet(this.abd, rc + 4, "Int")
        NumPut("Int", top + this.H, this.abd, rc + 12)
        DllCall("Shell32.dll\SHAppBarMessage", "UInt", 3, "Ptr", this.abd)

        this.Gui.Show("x" NumGet(this.abd, rc, "Int") " y" NumGet(this.abd, rc + 4, "Int") " w" (NumGet(this.abd, rc + 8, "Int") - NumGet(this.abd, rc, "Int")) " h" (NumGet(this.abd, rc + 12, "Int") - NumGet(this.abd, rc + 4, "Int")) " NoActivate")
    }

    RestoreSpace(*) {
        if HasProp(this, "abd")
            DllCall("Shell32.dll\SHAppBarMessage", "UInt", 1, "Ptr", this.abd)
    }
}

; ==============================================================================
; 3. BASE PLUGIN CLASS (Auto-Handles Custom Padding & Right Clicks)
; ==============================================================================
class OverDockPlugin {
    W := 45
    App := 0

    GetConfig(key, defaultVal) {
        cn := HasProp(this, "Name") ? this.Name : this.__Class
        if !Config.PluginData.Has(cn)
            Config.PluginData[cn] := Map()
        if !Config.PluginData[cn].Has(key) {
            v := IniRead(IniFile, cn, key, defaultVal)
            if (v == "0" || v == "1")
                v := Integer(v)
            Config.PluginData[cn][key] := v
        }
        return Config.PluginData[cn][key]
    }

    SetConfig(key, val) {
        cn := HasProp(this, "Name") ? this.Name : this.__Class
        Config.PluginData[cn][key] := val
        IniWrite(val, IniFile, cn, key)
    }

    PadL => Integer(this.GetConfig("PadL", 0))
    PadR => Integer(this.GetConfig("PadR", 0))

    ReqWidth() {
        if (this.App && HasMethod(this.App, "EvalPluginRules")) {
            cn := HasProp(this, "Name") ? this.Name : this.__Class
            pName := StrReplace(cn, "Plugin", "")
            if (this.App.EvalPluginRules(pName) == -1)
                return 0
        }
        return Round(this.W * this.App.Scale) + Round(this.PadL * this.App.Scale) + Round(this.PadR * this.App.Scale)
    }

    RegisterHover(hwnd, cNorm, cHov, grp := "", cbHover := "") {
        this.App.RegisterHover(hwnd, cNorm, cHov, grp, cbHover)
    }

    AddCtrl(gui, type, options, text := "") {
        if !HasProp(this, "MyCtrls")
            this.MyCtrls := []

        if (Config.General.DropShadows && type == "Text") {
            sOptions := RegExReplace(options, "i)\bc[0-9a-fA-F]+\b", "")

            try {
                oVal := Config.Theme.ShadowOffset
                if InStr(oVal, ",") {
                    pts := StrSplit(oVal, ",")
                    ox := Number(Trim(pts[1])), oy := Number(Trim(pts[2]))
                } else if RegExMatch(Trim(oVal), "i)^(\-?[\d\.]+)\s+(\-?[\d\.]+)$", &mMatch) {
                    ox := Number(mMatch[1]), oy := Number(mMatch[2])
                } else {
                    ox := Number(oVal), oy := ox
                }
            } catch {
                ox := 2, oy := 2
            }

            if RegExMatch(sOptions, "i)\bx(\-?\d+)", &mx) && RegExMatch(sOptions, "i)\by(\-?\d+)", &my) {
                sOptions := RegExReplace(sOptions, "i)\bx(\-?\d+)", "x" (Integer(mx[1]) + ox))
                sOptions := RegExReplace(sOptions, "i)\by(\-?\d+)", "y" (Integer(my[1]) + oy))
            }
            cShad := StrReplace(Config.Theme.HasProp("Shadow") ? Config.Theme.Shadow : "000000", "#", "")
            sOptions .= " c" cShad " BackgroundTrans E0x20"
            if !HasProp(this, "ShadowPairs")
                this.ShadowPairs := Map()
            sCtrl := gui.Add(type, sOptions, text)
        }

        ctrl := gui.Add(type, options, text)
        this.MyCtrls.Push(ctrl)
        if (IsSet(sCtrl)) {
            this.ShadowPairs[ctrl.Hwnd] := sCtrl
            DllCall("SetWindowPos", "Ptr", sCtrl.Hwnd, "Ptr", ctrl.Hwnd, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        }
        return ctrl
    }

    SetVisible(state) {
        if HasProp(this, "MyCtrls") {
            for c in this.MyCtrls
                c.Visible := state
        }
        if HasProp(this, "ShadowPairs") {
            for hwnd, sCtrl in this.ShadowPairs
                sCtrl.Visible := state
        }
    }

    SyncShadows() {
        if HasProp(this, "ShadowPairs") {
            for hwnd, sCtrl in this.ShadowPairs {
                mCtrl := GuiCtrlFromHwnd(hwnd)
                if !IsObject(mCtrl)
                    continue
                changed := false
                if (sCtrl.Value != mCtrl.Value) {
                    sCtrl.Value := mCtrl.Value
                    changed := true
                }
                mCtrl.GetPos(&mX, &mY, &mW, &mH)
                sCtrl.GetPos(&sX, &sY, &sW, &sH)

                try {
                    oVal := Config.Theme.ShadowOffset
                    if InStr(oVal, ",") {
                        pts := StrSplit(oVal, ",")
                        ox := Number(Trim(pts[1])), oy := Number(Trim(pts[2]))
                    } else if RegExMatch(Trim(oVal), "i)^(\-?[\d\.]+)\s+(\-?[\d\.]+)$", &mMatch) {
                        ox := Number(mMatch[1]), oy := Number(mMatch[2])
                    } else {
                        ox := Number(oVal), oy := ox
                    }
                } catch {
                    ox := 2, oy := 2
                }

                if (sX != mX + ox || sY != mY + oy || sW != mW || sH != mH) {
                    sCtrl.Move(mX + ox, mY + oy, mW, mH)
                    changed := true
                }
                if (changed)
                    DllCall("SetWindowPos", "Ptr", sCtrl.Hwnd, "Ptr", hwnd, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
            }
        }
    }

    AddCheckbox(gui, x, y, w, h, varObj, varKey, label) {
        global AppCursorMap, Config
        ac := Config.Theme.IconHover
        hasVal := varObj.HasProp(varKey) ? varObj.%varKey% : 0
        bg := gui.Add("Text", "x" x " y" y " w" w " h" h " BackgroundTrans", "")
        gui.SetFont("s13 q5 c" ac, Config.Theme.IconFont)
        icn := gui.Add("Text", "x" x " y" (y - 2) " w20 h" h " BackgroundTrans", hasVal ? Chr(0xE73A) : Chr(0xE739))
        gui.SetFont("s10 q5 cWhite", Config.Theme.Font)
        txt := gui.Add("Text", "x" (x + 25) " y" (y + 1) " w" (w - 25) " h" (h - 2) " BackgroundTrans", label)

        act := ((obj, key, icnCtrl, *) => (
            obj.%key% := !(obj.HasProp(key) ? obj.%key% : 0),
            icnCtrl.Value := obj.%key% ? Chr(0xE73A) : Chr(0xE739)
        )).Bind(varObj, varKey, icn)

        bg.OnEvent("Click", act), icn.OnEvent("Click", act), txt.OnEvent("Click", act)
        AppCursorMap[bg.Hwnd] := 1, AppCursorMap[icn.Hwnd] := 1, AppCursorMap[txt.Hwnd] := 1
        return { Bg: bg, Icn: icn, Txt: txt }
    }

    Render(gui, align, x, h, w) {
        return w
    }
    MoveCtrls(x, w) {
    }
    Update() {
    }
    Destroy() {
    }

    ShowConfigPopup(triggerHwnd) {
        s := this.App.Scale
        this.CfgGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" this.App.Gui.Hwnd)
        this.CfgGui.IsDynamic := true
        this.CfgGui.SkipAlpha := true
        this.CfgGui.BackColor := Config.Theme.DropBg
        this.CfgGui.MarginX := 0, this.CfgGui.MarginY := 0
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.CfgGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.CfgGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        yP := Round(15 * s), dW := Round(240 * s)

        this.CfgGui.SetFont("s" Round(11 * s) " w600 q5 c" Config.Theme.IconHover, Config.Theme.Font)
        this.CfgGui.Add("Text", "x" Round(15 * s) " y" yP " w" (dW - Round(30 * s)) " h" Round(20 * s) " BackgroundTrans", StrReplace(this.__Class, "Plugin", "") " Settings")
        yP += Round(30 * s)

        this.CfgGui.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.DropText, Config.Theme.Font)
        this.CfgGui.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(80 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Padding L/R:")
        this.ePadL := this.CfgGui.Add("Edit", "x" Round(115 * s) " y" yP " w" Round(40 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Number Center", this.PadL)
        this.ePadR := this.CfgGui.Add("Edit", "x" Round(165 * s) " y" yP " w" Round(40 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Number Center", this.PadR)
        yP += Round(35 * s)

        if HasMethod(this, "BuildCustomConfig")
            yP := this.BuildCustomConfig(this.CfgGui, yP, dW)

        yP += Round(10 * s)
        btn := this.CfgGui.Add("Text", "x" Round(15 * s) " y" yP " w" (dW - Round(30 * s)) " h" Round(30 * s) " 0x200 Center Background" StrReplace(Config.Theme.Slider, "#", "") " cWhite", "Apply && Reload")
        this.RegisterHover(btn.Hwnd, "FFFFFF", "E0E0E0")

        btn.OnEvent("Click", (*) => (
            this.SetConfig("PadL", this.ePadL.Value),
            this.SetConfig("PadR", this.ePadR.Value),
            (HasMethod(this, "SaveCustomConfig") ? this.SaveCustomConfig() : 0),
            ApplyDynamicSettings()
        ))
        this.App.TogglePopup(this.CfgGui, triggerHwnd, dW, yP + Round(45 * s))
    }
}

; ==============================================================================

ExportTheme(ownerGui := "") {
    if !ownerGui {
        tmpG := Gui("+AlwaysOnTop")
        tmpG.Opt("+OwnDialogs")
    } else {
        ownerGui.Opt("+OwnDialogs")
    }
    outFile := FileSelect("S16", "MyTheme.ini", "Export Theme", "Theme Files (*.ini)")
    if (!outFile)
        return
    if !InStr(outFile, ".ini")
        outFile .= ".ini"

    try FileDelete(outFile)
    for k, v in Config.Theme.OwnProps()
        IniWrite(v, outFile, "Theme", k)

    ; Include some essential layout variables in the theme
    IniWrite(Config.General.Spacing, outFile, "General", "Spacing")
    IniWrite(Config.General.ClockSize, outFile, "General", "ClockSize")
    IniWrite(Config.General.DropShadows, outFile, "General", "DropShadows")
}

ImportTheme(ownerGui := "") {
    if !ownerGui {
        tmpG := Gui("+AlwaysOnTop")
        tmpG.Opt("+OwnDialogs")
    } else {
        ownerGui.Opt("+OwnDialogs")
    }
    inFile := FileSelect("3", "", "Import Theme", "Theme Files (*.ini)")
    if (!inFile)
        return

    try {
        themeMap := Map()
        for k in ["BarBg", "Text", "Icon", "IconHover", "DropBg", "DropText", "Font", "IconFont", "Shadow", "BarAlpha", "PopupAlpha", "Danger", "Warning", "Success", "ShadowOffset", "Slider"]
            try themeMap[k] := IniRead(inFile, "Theme", k)

        try themeMap["DropShadows"] := IniRead(inFile, "General", "DropShadows")

        ; Write to actual Config and INI
        for k, v in themeMap
            Config.Theme.%k% := v, IniWrite(v, IniFile, "Theme", k)

        try {
            Config.General.Spacing := IniRead(inFile, "General", "Spacing")
            IniWrite(Config.General.Spacing, IniFile, "General", "Spacing")
            Config.General.ClockSize := IniRead(inFile, "General", "ClockSize")
            IniWrite(Config.General.ClockSize, IniFile, "General", "ClockSize")
            Config.General.DropShadows := IniRead(inFile, "General", "DropShadows")
            IniWrite(Config.General.DropShadows, IniFile, "General", "DropShadows")
        }

        ApplyDynamicSettings()
        return true
    }
    return false
}

ApplyDynamicSettings() {
    global Config, TopBar
    Config := LoadConfig()
    if (IsSet(TopBar) && TopBar) {
        SetTimer(ObjBindMethod(TopBar, "ApplyUpdate"), -15)
    } else {
        InitializePlugins()
        TopBar := OverDockApp()
    }
}

; ==============================================================================
; 5. ADVANCED SETTINGS GUI & INI MANAGER
; ==============================================================================
LoadConfig() {
    if !FileExist(IniFile) {
        IniWrite("40", IniFile, "General", "Height")
        IniWrite("11", IniFile, "General", "ClockSize")
        IniWrite("10", IniFile, "General", "Spacing")
        IniWrite("Popup", IniFile, "General", "OverflowMode")
        IniWrite("Right", IniFile, "General", "OverflowAlign")
        IniWrite("0", IniFile, "General", "DropShadows")
        IniWrite("0", IniFile, "General", "VisualDebug")
        IniWrite("E700", IniFile, "General", "HomeIcon")
        
        IniWrite("0", IniFile, "General", "AutoHide")
        IniWrite("1", IniFile, "General", "AutoHideSens")
        IniWrite("300", IniFile, "General", "AutoHideDelay")

        IniWrite("1a1b26", IniFile, "Theme", "BarBg")
        IniWrite("c0caf5", IniFile, "Theme", "Text")
        IniWrite("a9b1d6", IniFile, "Theme", "Icon")
        IniWrite("7aa2f7", IniFile, "Theme", "IconHover")
        IniWrite("2B2D3B", IniFile, "Theme", "DropBg")
        IniWrite("c0caf5", IniFile, "Theme", "DropText")
        IniWrite("000000", IniFile, "Theme", "Shadow")
        IniWrite("0078D7", IniFile, "Theme", "Slider")
        IniWrite("FF5555", IniFile, "Theme", "Danger")
        IniWrite("FFA055", IniFile, "Theme", "Warning")
        IniWrite("55FF55", IniFile, "Theme", "Success")
        IniWrite("2", IniFile, "Theme", "ShadowOffset")
        IniWrite("Segoe UI Variable Display", IniFile, "Theme", "Font")
        IniWrite("Segoe Fluent Icons", IniFile, "Theme", "IconFont")
        IniWrite("255", IniFile, "Theme", "BarAlpha")
        IniWrite("255", IniFile, "Theme", "PopupAlpha")
        ;IniWrite("0", IniFile, "Theme", "UseMica")

        IniWrite("Power,Settings,NotificationTrigger,Audio,Battery,Wifi", IniFile, "Plugins", "RightOrder")
        IniWrite("E8D5|File Explorer|explorer.exe", IniFile, "Links", "1")
        IniWrite("E756|Terminal|wt.exe", IniFile, "Links", "2")
        IniWrite("E71B|Browser|https://google.com", IniFile, "Links", "3")
        IniWrite("E72C|Reload Bar|Reload", IniFile, "Links", "4")
        IniWrite("E711|Exit Bar|ExitApp", IniFile, "Links", "5")
    }

    cfg := { General: {}, Theme: {}, Plugins: {}, Links: [], PluginData: Map(), PluginRules: Map() }

    try {
        ruleLines := IniRead(IniFile, "PluginRules")
        for line in StrSplit(ruleLines, "`n", "`r") {
            if !line
                continue
            kv := StrSplit(line, "=", " `t", 2)
            if (kv.Length == 2)
                cfg.PluginRules[kv[1]] := kv[2]
        }
    } catch {
        ; ignore
    }

    cfg.General.Height := IniRead(IniFile, "General", "Height")
    cfg.General.ClockSize := IniRead(IniFile, "General", "ClockSize", "11")
    cfg.General.Spacing := IniRead(IniFile, "General", "Spacing", "10")
    cfg.General.OverflowMode := IniRead(IniFile, "General", "OverflowMode", "Popup")
    cfg.General.OverflowAlign := IniRead(IniFile, "General", "OverflowAlign", "Right")
    vS := IniRead(IniFile, "General", "DropShadows", "0"), cfg.General.DropShadows := (vS == "0" || vS == "1") ? Integer(vS) : vS
    vD := IniRead(IniFile, "General", "VisualDebug", "0"), cfg.General.VisualDebug := (vD == "0" || vD == "1") ? Integer(vD) : vD
    cfg.General.HomeIcon := IniRead(IniFile, "General", "HomeIcon", "E700")
    cfg.General.LeftHotareaAction := IniRead(IniFile, "General", "LeftHotareaAction", "None")
    cfg.General.LeftHotareaCustom := IniRead(IniFile, "General", "LeftHotareaCustom", "")
    cfg.General.RightHotareaAction := IniRead(IniFile, "General", "RightHotareaAction", "None")
    cfg.General.RightHotareaCustom := IniRead(IniFile, "General", "RightHotareaCustom", "")
    vE := IniRead(IniFile, "General", "HighlightEdges", "0"), cfg.General.HighlightEdges := (vE == "0" || vE == "1") ? Integer(vE) : vE

    vA := IniRead(IniFile, "General", "AutoHide", "0"), cfg.General.AutoHide := (vA == "0" || vA == "1") ? Integer(vA) : vA
    try cfg.General.AutoHideSens := Integer(IniRead(IniFile, "General", "AutoHideSens", "1"))
    catch
        cfg.General.AutoHideSens := 1
    try cfg.General.AutoHideDelay := Integer(IniRead(IniFile, "General", "AutoHideDelay", "300"))
    catch
        cfg.General.AutoHideDelay := 300

    for k in ["BarBg", "Text", "Icon", "IconHover", "DropBg", "DropText", "Font", "IconFont", "Shadow", "BarAlpha", "PopupAlpha", "Danger", "Warning", "Success", "ShadowOffset"]
        try cfg.Theme.%k% := IniRead(IniFile, "Theme", k)
        catch {
            if (k == "BarAlpha" || k == "PopupAlpha")
                cfg.Theme.%k% := "255"
            else if (k == "ShadowOffset")
                cfg.Theme.%k% := "2"
            else
                cfg.Theme.%k% := "000000"
        }
    try cfg.Theme.Slider := IniRead(IniFile, "Theme", "Slider")
    catch
        cfg.Theme.Slider := "0078D7"

    rightOrdStr := IniRead(IniFile, "Plugins", "RightOrder", "NOT_FOUND")
    if (rightOrdStr == "NOT_FOUND") {
        rightOrdStr := ""
        for k in ["Power", "Weather", "Settings", "NotificationTrigger", "Audio", "Battery", "Brightness", "Media", "SysMon", "Wifi", "Uptime"]
            if (IniRead(IniFile, "Plugins", k, "0") == "1")
                rightOrdStr .= (rightOrdStr ? "," : "") k
        if (rightOrdStr == "")
            rightOrdStr := "Power,Settings,NotificationTrigger,Audio,Battery,Wifi"
        IniWrite(rightOrdStr, IniFile, "Plugins", "RightOrder")
    }
    cfg.Plugins.RightOrder := StrSplit(rightOrdStr, ",", " `t")

    leftOrdStr := IniRead(IniFile, "Plugins", "LeftOrder", "NOT_FOUND")
    if (leftOrdStr == "NOT_FOUND") {
        leftOrdStr := "StartMenu,ExplorerContextual"
        IniWrite(leftOrdStr, IniFile, "Plugins", "LeftOrder")
    }
    cfg.Plugins.LeftOrder := StrSplit(leftOrdStr, ",", " `t")

    centerOrdStr := IniRead(IniFile, "Plugins", "CenterOrder", "NOT_FOUND")
    if (centerOrdStr == "NOT_FOUND") {
        centerOrdStr := "Clock"
        IniWrite(centerOrdStr, IniFile, "Plugins", "CenterOrder")
    }
    cfg.Plugins.CenterOrder := StrSplit(centerOrdStr, ",", " `t")

    try {
        linksStr := IniRead(IniFile, "Links")
        Loop Parse, linksStr, "`n", "`r" {
            kv := StrSplit(A_LoopField, "=", " `t", 2)
            if (kv.Length == 2) {
                parts := StrSplit(kv[2], "|")
                if (parts.Length >= 3) {
                    isPath := FileExist(parts[1]) || InStr(parts[1], ":\") || InStr(parts[1], ".")
                    if (isPath)
                        icn := parts[1]
                    else
                        icn := StrLen(parts[1]) >= 4 ? Chr("0x" parts[1]) : parts[1]
                    item := { Icon: icn, Name: parts[2], Target: parts[3], Key: kv[1], RawIcon: parts[1], IsImage: isPath }
                    item.RunArgs := parts.Length >= 4 ? parts[4] : ""
                    item.RunDir := parts.Length >= 5 ? parts[5] : ""
                    item.RunState := parts.Length >= 6 ? parts[6] : "Normal"
                    item.ParentId := parts.Length >= 7 ? parts[7] : "None"
                    item.IsFolder := parts.Length >= 8 ? (parts[8] == "1") : false
                    item.Id := parts.Length >= 9 ? parts[9] : "L" kv[1]
                    cfg.Links.Push(item)
                }
            }
        }
    }
    return cfg
}

OpenSettingsGUI(startTab := 1, startX := "", startY := "") {
    if WinExist("OverDock Settings") {
        WinActivate("OverDock Settings")
        return
    }
    sg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "OverDock Settings")

    CancelSettings(*) {
        global Config
        Config := LoadConfig()
        if IsSet(SexyPluginsList)
            SexyPluginsList.Destroy()
        if IsSet(SexyLinksList)
            SexyLinksList.Destroy()
        sg.Destroy()
    }
    sg.OnEvent("Close", CancelSettings)

    sg.SetFont("s10 q5 cWhite", Config.Theme.Font)
    sg.BackColor := "ff0000"
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", sg.Hwnd, "Int", 19, "Int*", 1, "Int", 4)

    global tabBgBox := sg.Add("Text", "x0 y0 w400 h40 Background" StrReplace(Config.Theme.BarBg, "#", ""), "")
    wt := Round(400 / 6)
    t1 := sg.Add("Text", "x0 y0 w" wt " h40 0x200 Center BackgroundTrans", "Layout")
    t2 := sg.Add("Text", "x" wt " y0 w" wt " h40 0x200 Center BackgroundTrans", "Colors")
    t3 := sg.Add("Text", "x" (wt * 2) " y0 w" wt " h40 0x200 Center BackgroundTrans", "Plugins")
    t4 := sg.Add("Text", "x" (wt * 3) " y0 w" wt " h40 0x200 Center BackgroundTrans", "Links")
    t5 := sg.Add("Text", "x" (wt * 4) " y0 w" wt " h40 0x200 Center BackgroundTrans", "Edges")
    t6 := sg.Add("Text", "x" (wt * 5) " y0 w" (400 - wt * 5) " h40 0x200 Center BackgroundTrans", "About")
    ac := StrReplace(Config.Theme.Slider, "#", "")

    global TInds := [0, wt, wt * 2, wt * 3, wt * 4, wt * 5]
    global TIndW := [wt, wt, wt, wt, wt, 400 - wt * 5]

    tInd := sg.Add("Text", "x0 y38 w" wt " h2 Background" ac, "")

    if (IsSet(TopBar)) {
        txC := StrReplace(Config.Theme.Text, "#", "")
        hC := StrReplace(Config.Theme.IconHover, "#", "")
        TopBar.RegisterHover(t1.Hwnd, txC, hC)
        TopBar.RegisterHover(t2.Hwnd, txC, hC)
        TopBar.RegisterHover(t3.Hwnd, txC, hC)
        TopBar.RegisterHover(t4.Hwnd, txC, hC)
        TopBar.RegisterHover(t5.Hwnd, txC, hC)
        TopBar.RegisterHover(t6.Hwnd, txC, hC)
    }

    Pages := [[], [], [], [], [], []]

    sg.SetFont("s14 w700 q5 cWhite", Config.Theme.Font)
    Pages[6].Push(sg.Add("Text", "x20 y60 w65 BackgroundTrans", "OverDock"))

    sg.SetFont("s9 w500 q5 c" ac, Config.Theme.Font)
    Pages[6].Push(sg.Add("Text", "x120 y64 w300 BackgroundTrans", "v0.9a"))

    sg.SetFont("s10 w400 q5 cWhite", Config.Theme.Font)
    Pages[6].Push(sg.Add("Text", "x20 y95 w360 h100 BackgroundTrans", "Developed playfully by owhs.`n`nA sleek, modern, and highly modular overdock menu`nfor the Windows operating system."))

    sg.SetFont("s10 w400 q5 c" ac, Config.Theme.Font)
    linkOwhs := sg.Add("Text", "x20 y180 w360 h20 BackgroundTrans", "github.com/owhs")
    if IsSet(TopBar)
        TopBar.RegisterHover(linkOwhs.Hwnd, ac, "FFFFFF")
    linkOwhs.OnEvent("Click", (*) => Run("https://github.com/owhs"))
    Pages[6].Push(linkOwhs)

    sg.SetFont("s10 q5 cWhite", Config.Theme.Font)

    Pages[1].Push(sg.Add("Text", "x20 y60 w120 BackgroundTrans", "Bar Height:"))
    hEdit := sg.Add("Edit", "x150 y58 w100 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Number", Config.General.Height)
    Pages[1].Push(hEdit)
    ud1 := sg.Add("UpDown", "Range30-100 -0x20", Config.General.Height)
    ud1.Visible := false

    Pages[1].Push(sg.Add("Text", "x20 y100 w120 BackgroundTrans", "Clock Size:"))
    csEdit := sg.Add("Edit", "x150 y98 w100 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Number", Config.General.ClockSize)
    Pages[1].Push(csEdit)
    ud2 := sg.Add("UpDown", "Range8-40 -0x20", Config.General.ClockSize)
    ud2.Visible := false

    Pages[1].Push(sg.Add("Text", "x20 y140 w120 BackgroundTrans", "Icon Spacing:"))
    spEdit := sg.Add("Edit", "x150 y138 w100 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Number", Config.General.Spacing)
    Pages[1].Push(spEdit)
    ud3 := sg.Add("UpDown", "Range0-50 -0x20", Config.General.Spacing)
    ud3.Visible := false

    global DropShadowsVal := Config.General.DropShadows
    ;cbShadowBg := sg.Add("Text", "x20 y180 w120 h25 Background" Config.Theme.BarBg, " ")
    sg.SetFont("s13 q5 c" ac, Config.Theme.IconFont)
    cbShadowIc := sg.Add("Text", "x20 y178 w20 h25", DropShadowsVal ? Chr(0xE73A) : Chr(0xE739))
    sg.SetFont("s10 q5 cWhite", Config.Theme.Font)
    cbShadowTxt := sg.Add("Text", "x45 y181 w95 h20", "Drop Shadows")

    TogShadow(*) {
        global DropShadowsVal
        DropShadowsVal := !DropShadowsVal
        cbShadowIc.Value := DropShadowsVal ? Chr(0xE73A) : Chr(0xE739)
    }
    cbShadowIc.OnEvent("Click", TogShadow), cbShadowTxt.OnEvent("Click", TogShadow)
    Pages[1].Push(cbShadowIc), Pages[1].Push(cbShadowTxt)

    Pages[1].Push(sg.Add("Text", "x290 y181 w50 BackgroundTrans", "Offset:"))
    global sdwOffEdit := sg.Add("Edit", "x335 y178 w45 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Center", Config.Theme.ShadowOffset)
    Pages[1].Push(sdwOffEdit)

    global VisualDebugVal := Config.General.VisualDebug
    ;cbDebugBg := sg.Add("Text", "x150 y180 w140 h25 Background" Config.Theme.BarBg, " ")
    sg.SetFont("s13 q5 c" ac, Config.Theme.IconFont)
    cbDebugIc := sg.Add("Text", "x150 y178 w20 h25", VisualDebugVal ? Chr(0xE73A) : Chr(0xE739))
    sg.SetFont("s10 q5 cWhite", Config.Theme.Font)
    cbDebugTxt := sg.Add("Text", "x175 y181 w115 h20", "Visual Debug")

    TogDebug(*) {
        global VisualDebugVal
        VisualDebugVal := !VisualDebugVal
        cbDebugIc.Value := VisualDebugVal ? Chr(0xE73A) : Chr(0xE739)
    }
    cbDebugIc.OnEvent("Click", TogDebug), cbDebugTxt.OnEvent("Click", TogDebug)
    Pages[1].Push(cbDebugIc), Pages[1].Push(cbDebugTxt)

    AppCursorMap[cbShadowIc.Hwnd] := 1, AppCursorMap[cbShadowTxt.Hwnd] := 1
    AppCursorMap[cbDebugIc.Hwnd] := 1, AppCursorMap[cbDebugTxt.Hwnd] := 1

    Pages[1].Push(sg.Add("Text", "x20 y215 w120 BackgroundTrans", "UI Font Family:"))
    fBg := sg.Add("Text", "x150 y213 w220 h25 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")
    fDropText := sg.Add("Text", "x155 y216 w190 h20 BackgroundTrans cWhite", Config.Theme.Font)
    fArrow := sg.Add("Text", "x350 y216 w15 h20 BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " Center", Chr(0x2304))
    Pages[1].Push(fBg), Pages[1].Push(fDropText), Pages[1].Push(fArrow)

    Pages[1].Push(sg.Add("Text", "x20 y255 w120 BackgroundTrans", "Overflow Mode:"))
    omBg := sg.Add("Text", "x150 y253 w95 h25 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")
    omDropText := sg.Add("Text", "x155 y256 w65 h20 BackgroundTrans cWhite", Config.General.OverflowMode)
    omArrow := sg.Add("Text", "x230 y256 w15 h20 BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " Center", Chr(0x2304))
    Pages[1].Push(omBg), Pages[1].Push(omDropText), Pages[1].Push(omArrow)

    Pages[1].Push(sg.Add("Text", "x255 y255 w45 BackgroundTrans", "Align:"))
    oaBg := sg.Add("Text", "x300 y253 w70 h25 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")
    oaDropText := sg.Add("Text", "x305 y256 w40 h20 BackgroundTrans cWhite", Config.General.OverflowAlign)
    oaArrow := sg.Add("Text", "x350 y256 w15 h20 BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " Center", Chr(0x2304))
    Pages[1].Push(oaBg), Pages[1].Push(oaDropText), Pages[1].Push(oaArrow)

    Pages[1].Push(sg.Add("Text", "x20 y295 w120 BackgroundTrans", "Bar/Pop Alpha:"))
    alpEdit := sg.Add("Edit", "x150 y293 w40 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Number", Config.Theme.BarAlpha)
    popEdit := sg.Add("Edit", "x200 y293 w40 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Number", Config.Theme.PopupAlpha)
    Pages[1].Push(alpEdit), Pages[1].Push(popEdit)

    alpEdit.OnEvent("Change", (*) => (
        Config.Theme.BarAlpha := (alpEdit.Value != "" && alpEdit.Value >= 0 && alpEdit.Value <= 255) ? alpEdit.Value : 255,
        (IsSet(TopBar) ? WinSetTransparent(Config.Theme.BarAlpha, TopBar.Gui.Hwnd) : 0)
    ))
    popEdit.OnEvent("Change", (*) => (
        Config.Theme.PopupAlpha := (popEdit.Value != "" && popEdit.Value >= 0 && popEdit.Value <= 255) ? popEdit.Value : 255
    ))

    ;global UseMicaVal := Config.Theme.UseMica
    ;cbMicaBg := sg.Add("Text", "x250 y295 w120 h25 BackgroundTrans", "")
    ;sg.SetFont("s13 q5 c" ac, Config.Theme.IconFont)
    ;cbMicaIc := sg.Add("Text", "x250 y293 w20 h25 BackgroundTrans", UseMicaVal ? Chr(0xE73A) : Chr(0xE739))
    ;sg.SetFont("s10 q5 cWhite", Config.Theme.Font)
    ;cbMicaTxt := sg.Add("Text", "x275 y296 w95 h20 BackgroundTrans", "Use Mica")

    ;TogMica(*) {
    ;    global UseMicaVal
    ;    UseMicaVal := !UseMicaVal
    ;    cbMicaIc.Value := UseMicaVal ? Chr(0xE73A) : Chr(0xE739)
    ;    if (IsSet(TopBar))
    ;        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", TopBar.Gui.Hwnd, "Int", 38, "Int*", UseMicaVal ? 2 : 1, "Int", 4)
    ;}
    ;cbMicaBg.OnEvent("Click", TogMica), cbMicaIc.OnEvent("Click", TogMica), cbMicaTxt.OnEvent("Click", TogMica)
    ;Pages[1].Push(cbMicaBg), Pages[1].Push(cbMicaIc), Pages[1].Push(cbMicaTxt)
    ;AppCursorMap[cbMicaBg.Hwnd] := 1, AppCursorMap[cbMicaIc.Hwnd] := 1, AppCursorMap[cbMicaTxt.Hwnd] := 1

    global AutoHideVal := Config.General.HasProp("AutoHide") ? Config.General.AutoHide : 0
    sg.SetFont("s13 q5 c" ac, Config.Theme.IconFont)
    cbAutoHideIc := sg.Add("Text", "x20 y333 w20 h25 BackgroundTrans", AutoHideVal ? Chr(0xE73A) : Chr(0xE739))
    sg.SetFont("s10 q5 cWhite", Config.Theme.Font)
    cbAutoHideTxt := sg.Add("Text", "x45 y336 w65 h20 BackgroundTrans", "Auto Hide")

    TogAutoHide(*) {
        global AutoHideVal
        AutoHideVal := !AutoHideVal
        cbAutoHideIc.Value := AutoHideVal ? Chr(0xE73A) : Chr(0xE739)
    }
    cbAutoHideIc.OnEvent("Click", TogAutoHide), cbAutoHideTxt.OnEvent("Click", TogAutoHide)
    Pages[1].Push(cbAutoHideIc), Pages[1].Push(cbAutoHideTxt)

    Pages[1].Push(sg.Add("Text", "x115 y336 w55 BackgroundTrans", "Sens(px):"))
    global ahSensEdit := sg.Add("Edit", "x170 y334 w40 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Center Number", Config.General.HasProp("AutoHideSens") ? Config.General.AutoHideSens : 1)
    Pages[1].Push(ahSensEdit)

    Pages[1].Push(sg.Add("Text", "x220 y336 w60 BackgroundTrans", "Delay(ms):"))
    global ahDelayEdit := sg.Add("Edit", "x280 y334 w45 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Center Number", Config.General.HasProp("AutoHideDelay") ? Config.General.AutoHideDelay : 300)
    Pages[1].Push(ahDelayEdit)

    if IsSet(AppCursorMap) {
        AppCursorMap[cbAutoHideIc.Hwnd] := 1
        AppCursorMap[cbAutoHideTxt.Hwnd] := 1
    }

    tip := sg.Add("Text", "x20 y370 w360 h50 BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.BarBg, 40), "Tip: You can dynamically configure padding, metrics, and display modes of ANY icon by simply RIGHT-CLICKING it on the bar!")
    Pages[1].Push(tip)

    FontOptions := ["Segoe UI Variable Display", "Segoe UI", "Inter", "Roboto", "Consolas", "Tahoma", "Cascadia Code", "Fira Code", "JetBrains Mono", "Courier New"]
    OmOptions := ["Popup", "Pagination"]
    OaOptions := ["Right", "Left"]

    if (IsSet(TopBar)) {
        cbDropF := ObjBindMethod(TopBar, "BuildDropdown", sg, fBg, fDropText, FontOptions)
        fBg.OnEvent("Click", cbDropF), fDropText.OnEvent("Click", cbDropF), fArrow.OnEvent("Click", cbDropF)

        cbDropOM := ObjBindMethod(TopBar, "BuildDropdown", sg, omBg, omDropText, OmOptions)
        omBg.OnEvent("Click", cbDropOM), omDropText.OnEvent("Click", cbDropOM), omArrow.OnEvent("Click", cbDropOM)

        cbDropOA := ObjBindMethod(TopBar, "BuildDropdown", sg, oaBg, oaDropText, OaOptions)
        oaBg.OnEvent("Click", cbDropOA), oaDropText.OnEvent("Click", cbDropOA), oaArrow.OnEvent("Click", cbDropOA)
    }

    y := 60, Edits := Map(), PatchMap := Map()
    ThemeControls := [{ k: "BarBg", v: "BarBG" }, { k: "Text", v: "Text" }, { k: "DropBg", v: "DropBG" }, { k: "DropText", v: "DropText" }, { k: "Icon", v: "Icon" }, { k: "IconHover", v: "IconHover" }, { k: "Slider", v: "Slider" }, { k: "Shadow", v: "Shadow" }, { k: "Danger", v: "Danger" }, { k: "Warning", v: "Warning" }, { k: "Success", v: "Success" }
    ]
    ApplyThemeLive(*) {
        fullColors := Map()
        for k, v in Config.Theme.OwnProps()
            fullColors[k] := v
        if IsSet(Edits) {
            for k, E in Edits
                if RegExMatch(E.Value, "i)^[0-9a-fA-F]{6}$")
                    fullColors[k] := E.Value
        }
        ApplyTheme(fullColors)
    }

    PickAColor(E, P, *) {
        newHex := ChooseColorHex(E.Value, sg.Hwnd)
        if (newHex) {
            E.Value := newHex
            try P.Opt("Background" newHex), P.Redraw()
            ApplyThemeLive()
        }
    }
    for i, item in ThemeControls {
        isRight := Mod(i, 2) == 0
        cX := isRight ? 210 : 15
        cY := 60 + Floor((i - 1) / 2) * 45

        Pages[2].Push(sg.Add("Text", "x" cX " y" (cY + 3) " w85 BackgroundTrans", item.v))
        E := sg.Add("Edit", "x" (cX + 85) " y" cY " w65 h22 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", Config.Theme.HasProp(item.k) ? Config.Theme.%(item.k)% : "000000")
        Pages[2].Push(E), Edits[item.k] := E
        E.OnEvent("Change", ApplyThemeLive)
        cHex := StrReplace(Config.Theme.HasProp(item.k) ? Config.Theme.%(item.k)% : "000000", "#", "")

        P := sg.Add("Text", "x" (cX + 160) " y" cY " w22 h22 Background" cHex " 0x0100", "")
        Pages[2].Push(P), P.OnEvent("Click", PickAColor.Bind(E, P))
        PatchMap[item.k] := P

        if IsSet(TopBar)
            AppCursorMap[P.Hwnd] := 1
    }

    y := 330
    ;Pages[2].Push(sg.Add("Text", "x20 y" y " w360 h1 0x10 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Slider, 25), ""))

    y += 15
    Pages[2].Push(sg.Add("Text", "x20 y" (y - 5) " w360 Center BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 30), "── Theme Presets ──"))

    y += 25
    wBtn := 175
    btnDark := sg.Add("Text", "x20 y" y " w" wBtn " h26 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10) " c" Config.Theme.Text, "Dark")
    btnLight := sg.Add("Text", "x205 y" y " w" wBtn " h26 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10) " c" Config.Theme.Text, "Light")

    y += 35
    btnMatrix := sg.Add("Text", "x20 y" y " w" wBtn " h26 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10) " c" Config.Theme.Text, "Matrix")
    btnCyber := sg.Add("Text", "x205 y" y " w" wBtn " h26 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10) " c" Config.Theme.Text, "Cyber Midnight")

    y += 35
    btnExport := sg.Add("Text", "x20 y" y " w" wBtn " h26 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10) " c" Config.Theme.Text, "Export Theme")
    btnImport := sg.Add("Text", "x205 y" y " w" wBtn " h26 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10) " c" Config.Theme.Text, "Import Theme")

    Pages[2].Push(btnDark), Pages[2].Push(btnLight), Pages[2].Push(btnMatrix), Pages[2].Push(btnCyber)
    Pages[2].Push(btnExport), Pages[2].Push(btnImport)

    if (IsSet(TopBar)) {
        cTxt := StrReplace(Config.Theme.Text, "#", "")
        TopBar.RegisterHover(btnDark.Hwnd, "FFFFFF", BlendHex(Config.Theme.Text, Config.Theme.DropBg, 60))
        TopBar.RegisterHover(btnLight.Hwnd, "FFFFFF", BlendHex(Config.Theme.Text, Config.Theme.DropBg, 60))
        TopBar.RegisterHover(btnMatrix.Hwnd, "FFFFFF", BlendHex(Config.Theme.Text, Config.Theme.DropBg, 60))
        TopBar.RegisterHover(btnCyber.Hwnd, "FFFFFF", BlendHex(Config.Theme.Text, Config.Theme.DropBg, 60))
        TopBar.RegisterHover(btnExport.Hwnd, "FFFFFF", BlendHex(Config.Theme.Text, Config.Theme.DropBg, 60))
        TopBar.RegisterHover(btnImport.Hwnd, "FFFFFF", BlendHex(Config.Theme.Text, Config.Theme.DropBg, 60))
    }
    btnExport.OnEvent("Click", (*) => (ExportTheme(sg), sg.Opt("+OwnDialogs"), MsgBox("Theme successfully exported!")))
    btnImport.OnEvent("Click", (*) => (
        sg.GetPos(&sgX, &sgY),
        ImportTheme(sg) ? (sg.Destroy(), OpenSettingsGUI(2, sgX, sgY)) : WinActivate("ahk_id " sg.Hwnd)
    ))

    ApplyTheme(colors, *) {
        for k, v in colors {
            Config.Theme.%k% := v
            if Edits.Has(k) {
                Edits[k].Value := v
                try PatchMap[k].Opt("Background" v), PatchMap[k].Redraw()
            }
        }
        if (colors.Has("DropShadows")) {
            global DropShadowsVal
            DropShadowsVal := colors["DropShadows"]
            cbShadowIc.Value := DropShadowsVal ? Chr(0xE73A) : Chr(0xE739)
        }

        try {
            global tabBgBox
            ac := StrReplace(colors["Slider"], "#", "")
            sg.BackColor := BlendHex(colors["BarBg"], colors["DropBg"], 50)
            tabBgBox.Opt("Background" colors["BarBg"])
            tInd.Opt("Background" ac)
            btnSave.Opt("Background" ac)

            cEditBg := BlendHex(colors["DropBg"], colors["Text"], 15)
            cBtnBg := BlendHex(colors["DropBg"], colors["Text"], 10)

            try fBg.Opt("Background" cEditBg), omBg.Opt("Background" cEditBg), oaBg.Opt("Background" cEditBg)
            try lhaBg.Opt("Background" cEditBg), rhaBg.Opt("Background" cEditBg)
            try cbShadowBg.Opt("Background" colors["BarBg"]), cbDebugBg.Opt("Background" colors["BarBg"])
            try btnHomeIc.Opt("Background" BlendHex(colors["DropBg"], colors["Text"], 25))

            for k, ctrl in sg {
                isP := false
                if IsSet(PatchMap) {
                    for _, p in PatchMap
                        if (p.Hwnd == ctrl.Hwnd)
                            isP := true
                }
                if isP
                    continue

                if ctrl.Type == "Edit" {
                    ctrl.Opt("Background" cEditBg " c" colors["Text"])
                } else if ctrl.Type == "Text" {
                    txt := ctrl.Text
                    if (IsSet(fBg) && ctrl.Hwnd == fBg.Hwnd) || (IsSet(tip) && ctrl.Hwnd == tip.Hwnd) || (IsSet(omBg) && ctrl.Hwnd == omBg.Hwnd) || (IsSet(oaBg) && ctrl.Hwnd == oaBg.Hwnd) || (IsSet(lhaBg) && ctrl.Hwnd == lhaBg.Hwnd) || (IsSet(rhaBg) && ctrl.Hwnd == rhaBg.Hwnd) || (IsSet(cbShadowBg) && ctrl.Hwnd == cbShadowBg.Hwnd) || (IsSet(cbDebugBg) && ctrl.Hwnd == cbDebugBg.Hwnd) || (IsSet(btnHomeIc) && ctrl.Hwnd == btnHomeIc.Hwnd) || (IsSet(tabBgBox) && ctrl.Hwnd == tabBgBox.Hwnd) || (ctrl.Hwnd == tInd.Hwnd) || (ctrl.Hwnd == btnSave.Hwnd) {
                        ; explicitly mapped
                    } else {
                        if (txt == "Dark" || txt == "Light" || txt == "Matrix" || txt == "Cyber Midnight" || txt == "Export Theme" || txt == "Import Theme" || txt == "Refresh Plugins" || txt == "+") {
                            ctrl.Opt("Background" cBtnBg " c" colors["Text"])
                        } else if (txt == "") {
                            try {
                                ctrl.GetPos(&cX, &cY, &cW, &cH)
                                if (cH == 1)
                                    ctrl.Opt("Background" BlendHex(colors["DropBg"], colors["Slider"], 25))
                            }
                        } else {
                            ctrl.Opt("c" colors["Text"])
                        }
                    }
                }
                try ctrl.Redraw()
            }
        }

        if IsSet(t1) && IsSet(TopBar) {
            cTxt := StrReplace(colors["Text"], "#", "")
            cHov := StrReplace(colors["IconHover"], "#", "")
            for hwnd in [t1.Hwnd, t2.Hwnd, t3.Hwnd, t4.Hwnd, t5.Hwnd]
                if AppHoverMap.Has(hwnd)
                    AppHoverMap[hwnd].Def := cTxt, AppHoverMap[hwnd].Hov := cHov
            for hwnd, ctrl in AppHoverMap {
                if hwnd != btnSave.Hwnd {
                    ctrl.Def := cTxt
                    ctrl.Hov := cHov
                }
            }
            try {
                cHovBtn := BlendHex(colors["Text"], colors["DropBg"], 60)
                TopBar.RegisterHover(btnDark.Hwnd, "FFFFFF", cHovBtn)
                TopBar.RegisterHover(btnLight.Hwnd, "FFFFFF", cHovBtn)
                TopBar.RegisterHover(btnMatrix.Hwnd, "FFFFFF", cHovBtn)
                TopBar.RegisterHover(btnCyber.Hwnd, "FFFFFF", cHovBtn)
                TopBar.RegisterHover(btnExport.Hwnd, "FFFFFF", cHovBtn)
                TopBar.RegisterHover(btnImport.Hwnd, "FFFFFF", cHovBtn)
                TopBar.RegisterHover(btnRefreshPl.Hwnd, cTxt, cHovBtn)
                if IsSet(btnNewLink)
                    TopBar.RegisterHover(btnNewLink.Hwnd, "FFFFFF", cHovBtn)
                if IsSet(btnHomeIc)
                    TopBar.RegisterHover(btnHomeIc.Hwnd, cTxt, cHov)
            }
        }
        if IsSet(SexyPluginsList) {
            SexyPluginsList.Outer.BackColor := StrReplace(colors["DropBg"], "#", ""), SexyPluginsList.Inner.BackColor := StrReplace(colors["DropBg"], "#", "")
            SexyPluginsList.UpdateThemeColors(colors["BarBg"], colors["Slider"])
            SexyPluginsList.Render()
        }
        if IsSet(SexyLinksList) {
            SexyLinksList.Outer.BackColor := StrReplace(colors["DropBg"], "#", ""), SexyLinksList.Inner.BackColor := StrReplace(colors["DropBg"], "#", "")
            SexyLinksList.UpdateThemeColors(colors["BarBg"], colors["Slider"])
            SexyLinksList.Render()
        }
    }

    ApplyPreset(colors, *) {
        sg.GetPos(&sgX, &sgY)
        for k, v in colors {
            Config.Theme.%k% := v
            IniWrite(v, IniFile, "Theme", k)
        }
        if (colors.Has("DropShadows")) {
            Config.General.DropShadows := colors["DropShadows"]
            IniWrite(colors["DropShadows"], IniFile, "General", "DropShadows")
        }
        ApplyDynamicSettings()
        sg.Destroy()
        OpenSettingsGUI(2, sgX, sgY)
    }

    btnDark.OnEvent("Click", ApplyPreset.Bind(Map("BarBg", "1a1b26", "DropBg", "2B2D3B", "Text", "c0caf5", "Icon", "a9b1d6", "IconHover", "7aa2f7", "Slider", "0078D7", "DropText", "c0caf5", "Shadow", "000000", "DropShadows", 1, "Font", "Inter", "IconFont", "Segoe Fluent Icons", "BarAlpha", "230", "PopupAlpha", "245", "ShadowOffset", "2", "Danger", "FF5555", "Warning", "FFA055", "Success", "55FF55")))
    btnLight.OnEvent("Click", ApplyPreset.Bind(Map("BarBg", "e5e5e5", "DropBg", "f3f3f3", "Text", "111111", "Icon", "1C1D24", "IconHover", "005FB8", "Slider", "005FB8", "DropText", "111111", "Shadow", "AAAAAA", "DropShadows", 0, "Font", "Consolas", "IconFont", "Segoe Fluent Icons", "BarAlpha", "255", "PopupAlpha", "240", "ShadowOffset", "1", "Danger", "E81123", "Warning", "D83B01", "Success", "10893E")))
    btnMatrix.OnEvent("Click", ApplyPreset.Bind(Map("BarBg", "0a0f0a", "DropBg", "111811", "Text", "DFF8AB", "Icon", "1EA21E", "IconHover", "3CF745", "Slider", "1a8c1a", "DropText", "DFF8AB", "Shadow", "000000", "DropShadows", 0, "Font", "Cascadia Code", "IconFont", "Segoe Fluent Icons", "BarAlpha", "255", "PopupAlpha", "255", "ShadowOffset", "0", "Danger", "FF0000", "Warning", "FFFF00", "Success", "3CF745")))
    btnCyber.OnEvent("Click", ApplyPreset.Bind(Map("BarBg", "030721", "DropBg", "231C4A", "Text", "E716F8", "Icon", "22BDCA", "IconHover", "E142E6", "Slider", "8000FF", "DropText", "C039DD", "Shadow", "000091", "DropShadows", 1, "Font", "Segoe UI Variable Display", "IconFont", "Segoe Fluent Icons", "BarAlpha", "240", "PopupAlpha", "250", "ShadowOffset", "1", "Danger", "FF0055", "Warning", "FFC400", "Success", "00FFCC")))
    Pages[3].Push(sg.Add("Text", "x20 y60 w200 h40 BackgroundTrans", "Configure Plugins:"))
    btnRefreshPl := sg.Add("Text", "x250 y58 w130 h25 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10) " c" Config.Theme.Text, "Refresh Plugins")
    if IsSet(TopBar)
        TopBar.RegisterHover(btnRefreshPl.Hwnd, StrReplace(Config.Theme.Text, "#", ""), BlendHex(Config.Theme.Text, Config.Theme.DropBg, 60))
    btnRefreshPl.OnEvent("Click", (*) => (
        sg.Destroy(),
        Run(A_IsCompiled ? A_ScriptFullPath : '"' A_AhkPath '" "' A_ScriptFullPath '"'),
        ExitApp()
    ))
    Pages[3].Push(btnRefreshPl)

    global GlobalPluginsData := []
    addedM := Map()

    if Config.Plugins.HasProp("LeftOrder") {
        for pName in Config.Plugins.LeftOrder {
            if (pName != "" && !addedM.Has(pName)) {
                GlobalPluginsData.Push({ Name: pName, Checked: true, Zone: "Left" })
                addedM[pName] := 1
            }
        }
    }
    if Config.Plugins.HasProp("CenterOrder") {
        for pName in Config.Plugins.CenterOrder {
            if (pName != "" && !addedM.Has(pName)) {
                GlobalPluginsData.Push({ Name: pName, Checked: true, Zone: "Center" })
                addedM[pName] := 1
            }
        }
    }
    if Config.Plugins.HasProp("RightOrder") {
        for pName in Config.Plugins.RightOrder {
            if (pName != "" && !addedM.Has(pName)) {
                GlobalPluginsData.Push({ Name: pName, Checked: true, Zone: "Right" })
                addedM[pName] := 1
            }
        }
    }

    Loop Files, A_WorkingDir "\plugins\*.ahk" {
        pName := StrReplace(A_LoopFileName, "Plugin.ahk", "")
        if !addedM.Has(pName) {
            GlobalPluginsData.Push({ Name: pName, Checked: false, Zone: "Right" })
            addedM[pName] := 1
        }
    }

    RenderPluginRow(listObj, item, idx, yP, w, bg) {
        gui := listObj.Inner
        realNm := InStr(item.Name, "-") ? StrSplit(item.Name, "-")[1] : item.Name
        clsName := realNm "Plugin"

        isMissing := !IsSet(%clsName%)
        cTxt := isMissing ? BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) : Config.Theme.Text
        cIcn := isMissing ? BlendHex(Config.Theme.IconHover, Config.Theme.DropBg, 40) : Config.Theme.IconHover

        gui.SetFont("s13 q5 c" cIcn, Config.Theme.IconFont)
        icn := gui.Add("Text", "x30 y" (yP + 5) " w20 h25 BackgroundTrans", item.Checked ? Chr(0xE73A) : Chr(0xE739))
        gui.SetFont("s10 w500 q5 c" cTxt, Config.Theme.Font)
        txt := gui.Add("Text", "x60 y" (yP + 8) " w" (w - 230) " h20 0x0100 BackgroundTrans", item.Name)

        if (!isMissing && %clsName%.HasProp("Version")) {
            RegisterCustomTooltip(txt.Hwnd, item.Name, %clsName%.Version, %clsName%.Description)
        } else if (isMissing) {
            RegisterCustomTooltip(txt.Hwnd, item.Name, "???", "Options configured, but plugin is missing.")
        } else {
            RegisterCustomTooltip(txt.Hwnd, item.Name, "1.0", "A configurable OverDock component.")
        }

        act := (*) => (
            item.Checked := !item.Checked,
            icn.Value := item.Checked ? Chr(0xE73A) : Chr(0xE739)
        )
        icn.OnEvent("Click", act)
        if IsSet(AppCursorMap) {
            AppCursorMap[icn.Hwnd] := 1, AppCursorMap[txt.Hwnd] := 0
        }

        actC := StrReplace(Config.Theme.Slider, "#", "")
        bgC := StrReplace(Config.Theme.BarBg, "#", "")
        bx := w - 85

        gui.SetFont("s12 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.IconFont)
        filterBtn := gui.Add("Text", "x" (bx - 26) " y" (yP + 6) " w20 h22 0x200 Center BackgroundTrans", Chr(0xE71C))
        cogBtn := gui.Add("Text", "x" (bx - 50) " y" (yP + 6) " w20 h22 0x200 Center BackgroundTrans", Chr(0xE713))

        isClone := InStr(item.Name, "-")
        realNm := isClone ? StrSplit(item.Name, "-")[1] : item.Name
        if (realNm == "Directory" || realNm == "Divider" || realNm == "PageBreak") {
            if (isClone) {
                gui.SetFont("s11 q5 c" BlendHex(Config.Theme.Danger, Config.Theme.DropBg, 50), Config.Theme.IconFont)
                cdBtn := gui.Add("Text", "x" (bx - 74) " y" (yP + 6) " w20 h22 0x200 Center BackgroundTrans", Chr(0xE74D))
                cdBtn.OnEvent("Click", (*) => (GlobalPluginsData.RemoveAt(idx), listObj.Render()))
                if IsSet(TopBar) {
                    TopBar.RegisterHover(cdBtn.Hwnd, BlendHex(Config.Theme.Danger, Config.Theme.DropBg, 50), StrReplace(Config.Theme.Danger, "#", ""))
                    AppCursorMap[cdBtn.Hwnd] := 1
                }
            } else {
                gui.SetFont("s14 w600 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.Font)
                cdBtn := gui.Add("Text", "x" (bx - 74) " y" (yP + 5) " w20 h22 0x200 Center BackgroundTrans", "+")
                cdBtn.OnEvent("Click", (*) => (GlobalPluginsData.InsertAt(idx + 1, { Name: realNm "-" A_TickCount, Checked: false, Zone: item.Zone }), listObj.Render()))
                if IsSet(TopBar) {
                    TopBar.RegisterHover(cdBtn.Hwnd, BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), StrReplace(Config.Theme.IconHover, "#", ""))
                    AppCursorMap[cdBtn.Hwnd] := 1
                }
            }
        }

        gui.SetFont("s10 w500 q5 c" Config.Theme.Text, Config.Theme.Font)

        lBtn := gui.Add("Text", "x" bx " y" (yP + 8) " w25 h20 0x200 Center Background" (item.Zone == "Left" ? actC : bgC), "L")
        bx += 26
        cBtn := gui.Add("Text", "x" bx " y" (yP + 8) " w25 h20 0x200 Center Background" (item.Zone == "Center" ? actC : bgC), "C")
        bx += 26
        rBtn := gui.Add("Text", "x" bx " y" (yP + 8) " w25 h20 0x200 Center Background" (item.Zone == "Right" ? actC : bgC), "R")

        zoneClick := ((zoneVal, zL, zC, zR, zItem, *) => (
            zItem.Zone := zoneVal,
            zL.Opt("Background" (zoneVal == "Left" ? actC : BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15))), zL.Redraw(),
            zC.Opt("Background" (zoneVal == "Center" ? actC : BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15))), zC.Redraw(),
            zR.Opt("Background" (zoneVal == "Right" ? actC : BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15))), zR.Redraw()
        ))

        lBtn.OnEvent("Click", zoneClick.Bind("Left", lBtn, cBtn, rBtn, item))
        cBtn.OnEvent("Click", zoneClick.Bind("Center", lBtn, cBtn, rBtn, item))
        rBtn.OnEvent("Click", zoneClick.Bind("Right", lBtn, cBtn, rBtn, item))

        filterBtn.OnEvent("Click", (*) => ShowPluginRulesPopup(item.Name, listObj.Outer))

        pClass := realNm "Plugin"
        if IsSet(%pClass%) && (HasMethod(%pClass%.Prototype, "BuildCustomConfig") || HasMethod(%pClass%.Prototype, "ShowSettings")) {
            try {
                cogBtn.OnEvent("Click", ((pC, iNx, cHwnd, *) => (
                    inst := %pC%(), inst.Name := iNx, inst.App := TopBar,
                    HasMethod(inst, "ShowSettings", 1) ? inst.ShowSettings(cHwnd) : HasMethod(inst, "ShowSettings") ? inst.ShowSettings() : inst.ShowConfigPopup(cHwnd)
                )).Bind(pClass, item.Name, cogBtn.Hwnd))
            }
        } else {
            cogBtn.Visible := false
        }

        if IsSet(TopBar) {
            TopBar.RegisterHover(filterBtn.Hwnd, BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), StrReplace(Config.Theme.IconHover, "#", ""))
            AppCursorMap[filterBtn.Hwnd] := 1
            if (cogBtn.Visible) {
                TopBar.RegisterHover(cogBtn.Hwnd, BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), StrReplace(Config.Theme.IconHover, "#", ""))
                AppCursorMap[cogBtn.Hwnd] := 1
            }
            AppCursorMap[bg.Hwnd] := 1, AppCursorMap[icn.Hwnd] := 1, AppCursorMap[txt.Hwnd] := 1
            AppCursorMap[lBtn.Hwnd] := 1, AppCursorMap[cBtn.Hwnd] := 1, AppCursorMap[rBtn.Hwnd] := 1
        }
    }

    global SexyPluginsList := SexyList(sg, 20, 100, 360, 410, GlobalPluginsData, RenderPluginRow, (*) => 0)
    Pages[3].Push(SexyPluginsList.Outer)

    Pages[4].Push(sg.Add("Text", "x20 y60 w100 BackgroundTrans", "Start Icon:"))
    homeEdit := sg.Add("Edit", "x110 y58 w70 h25 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", Config.General.HomeIcon)
    Pages[4].Push(homeEdit)

    sg.SetFont("s10 q5 cWhite", Config.Theme.IconFont)
    btnHomeIc := sg.Add("Text", "x190 y58 w25 h25 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25), Chr(0xE713))
    if IsSet(TopBar)
        TopBar.RegisterHover(btnHomeIc.Hwnd, StrReplace(Config.Theme.Text, "#", ""), StrReplace(Config.Theme.IconHover, "#", ""))

    sg.SetFont("s10 w500 q5 cWhite", Config.Theme.Font)

    btnHomeIc.OnEvent("Click", (*) => OpenIconPickerPopup(homeEdit, sg))
    Pages[4].Push(btnHomeIc)

    btnNewLink := sg.Add("Text", "x355 y58 w25 h25 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10) " c" Config.Theme.Text, "+")
    if IsSet(TopBar)
        TopBar.RegisterHover(btnNewLink.Hwnd, StrReplace(Config.Theme.Text, "#", ""), BlendHex(Config.Theme.Text, Config.Theme.DropBg, 60))
    btnNewLink.OnEvent("Click", (*) => (
        GlobalLinksData.Push({ Icon: "E71B", Name: "New Link", Target: "https://", Key: GlobalLinksData.Length + 1, RawIcon: "E71B", IsImage: false, Id: "L" A_TickCount }),
        RebuildLinkTree(),
        SexyLinksList.Data := GlobalLinksData,
        SexyLinksList.MaxScroll := Max(0, (SexyLinksList.Data.Length * SexyLinksList.RowH) - SexyLinksList.H),
        SexyLinksList.ScrollY := SexyLinksList.MaxScroll,
        SexyLinksList.Render(),
        OpenLinkEditPopup(GlobalLinksData[GlobalLinksData.Length], GlobalLinksData.Length, SexyLinksList)
    ))
    Pages[4].Push(btnNewLink)

    ;Pages[4].Push(sg.Add("Text", "x20 y90 w350 BackgroundTrans", "Configure Left Menu Links:"))

    global GlobalLinksData := []
    for item in Config.Links
        GlobalLinksData.Push(item)
    RebuildLinkTree()

    RenderLinkRow(listObj, item, idx, yP, w, bg) {
        gui := listObj.Inner
        s := IsSet(TopBar) ? TopBar.Scale : (A_ScreenDPI / 96)
        depthX := (item.HasProp("Depth") ? item.Depth : 0) * Round(20 * s)
        baseX := Round(30 * s) + depthX
        nameX := Round(60 * s) + depthX

        isFold := item.HasProp("IsFolder") && item.IsFolder

        if (HasProp(item, "IsImage") && item.IsImage && FileExist(item.RawIcon)) {
            gui.Add("Picture", "x" baseX " y" (yP + Round(8 * s)) " w" Round(20 * s) " h" Round(20 * s) " BackgroundTrans", item.RawIcon)
        } else {
            gui.SetFont("s" Round(13 * s) " q5 c" Config.Theme.Text, Config.Theme.IconFont)
            gui.Add("Text", "x" baseX " y" (yP + Round(5 * s)) " w" Round(25 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans", isFold ? Chr(0xE8B7) : item.Icon)
        }

        gui.SetFont("s" Round(10 * s) " w" (isFold ? "700" : "500") " q5 c" Config.Theme.Text, Config.Theme.Font)
        gui.Add("Text", "x" nameX " y" (yP + Round(8 * s)) " w" (w - nameX - Round(60 * s)) " h" Round(20 * s) " BackgroundTrans", item.Name (isFold ? "  (Folder)" : ""))

        gui.SetFont("s" Round(12 * s) " q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.IconFont)
        cog := gui.Add("Text", "x" (w - Round(35 * s)) " y" (yP + Round(8 * s)) " w" Round(20 * s) " h" Round(20 * s) " 0x200 Center BackgroundTrans", Chr(0xE713))
        trash := gui.Add("Text", "x" (w - Round(55 * s)) " y" (yP + Round(8 * s)) " w" Round(20 * s) " h" Round(20 * s) " 0x200 Center BackgroundTrans", Chr(0xE74D))

        if IsSet(TopBar) {
            TopBar.RegisterHover(cog.Hwnd, BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), StrReplace(Config.Theme.IconHover, "#", ""))
            TopBar.RegisterHover(trash.Hwnd, BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), StrReplace(Config.Theme.Danger, "#", ""))
            AppCursorMap[cog.Hwnd] := 1, AppCursorMap[trash.Hwnd] := 1
        }

        actCog := ((iVal, iIdx, lRef, *) => OpenLinkEditPopup(iVal, iIdx, lRef)).Bind(item, idx, listObj)
        actTrash := ((iIdx, lRef, *) => OpenDeletePopup(lRef, iIdx)).Bind(idx, listObj)
        cog.OnEvent("Click", actCog)
        trash.OnEvent("Click", actTrash)
    }

    LinkSwapLogic(dragIdx, targetIdx, listObj, snapType := "") {
        if (dragIdx < 1 || dragIdx > GlobalLinksData.Length || targetIdx < 1 || targetIdx > GlobalLinksData.Length || dragIdx == targetIdx)
            return

        dragItem := GlobalLinksData[dragIdx]
        targetItem := GlobalLinksData[targetIdx]

        newParentId := "None"
        if (snapType == "Into") {
            if (!targetItem.HasProp("Id"))
                targetItem.Id := "L" A_TickCount
            newParentId := targetItem.Id
        } else {
            newParentId := targetItem.HasProp("ParentId") ? targetItem.ParentId : "None"
        }

        if (dragItem.HasProp("Id") && dragItem.Id != "") {
            currId := newParentId
            cyclic := false
            visited := Map()
            Loop {
                if (currId == "None" || currId == "")
                    break
                if (currId == dragItem.Id) {
                    cyclic := true
                    break
                }
                if (visited.Has(currId)) {
                    cyclic := true
                    break
                }
                visited[currId] := 1
                foundPar := false
                for k, v in GlobalLinksData {
                    if (v.HasProp("Id") && v.Id == currId) {
                        currId := v.HasProp("ParentId") ? v.ParentId : "None"
                        foundPar := true
                        break
                    }
                }
                if (!foundPar)
                    break
            }
            if (cyclic)
                return
        }

        GlobalLinksData.RemoveAt(dragIdx)

        if (dragIdx < targetIdx)
            targetIdx--

        dragItem.ParentId := newParentId
        if (snapType == "Into" || snapType == "After") {
            GlobalLinksData.InsertAt(targetIdx + 1, dragItem)
        } else {
            GlobalLinksData.InsertAt(targetIdx, dragItem)
        }

        RebuildLinkTree()
        listObj.Data := GlobalLinksData
        listObj.Render()
        SaveLinks()
    }

    global SexyLinksList := SexyList(sg, 20, 100, 360, 410, GlobalLinksData, RenderLinkRow, (*) => 0, LinkSwapLogic)
    Pages[4].Push(SexyLinksList.Outer)

    Pages[5].Push(sg.Add("Text", "x20 y60 w360 BackgroundTrans", "Left Hot Area Action:"))
    lhaBg := sg.Add("Text", "x20 y85 w170 h25 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")
    lhaDropText := sg.Add("Text", "x25 y88 w140 h20 BackgroundTrans cWhite", Config.General.LeftHotareaAction)
    lhaArrow := sg.Add("Text", "x175 y88 w15 h20 BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " Center", Chr(0x2304))
    Pages[5].Push(lhaBg), Pages[5].Push(lhaDropText), Pages[5].Push(lhaArrow)

    Pages[5].Push(sg.Add("Text", "x210 y60 w160 BackgroundTrans", "Custom (CLI/AHK):"))
    lhaCustomEdit := sg.Add("Edit", "x210 y85 w170 h25 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", Config.General.LeftHotareaCustom)
    Pages[5].Push(lhaCustomEdit)

    Pages[5].Push(sg.Add("Text", "x20 y130 w360 BackgroundTrans", "Right Hot Area Action:"))
    rhaBg := sg.Add("Text", "x20 y155 w170 h25 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")
    rhaDropText := sg.Add("Text", "x25 y158 w140 h20 BackgroundTrans cWhite", Config.General.RightHotareaAction)
    rhaArrow := sg.Add("Text", "x175 y158 w15 h20 BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " Center", Chr(0x2304))
    Pages[5].Push(rhaBg), Pages[5].Push(rhaDropText), Pages[5].Push(rhaArrow)

    Pages[5].Push(sg.Add("Text", "x210 y130 w160 BackgroundTrans", "Custom (CLI/AHK):"))
    rhaCustomEdit := sg.Add("Edit", "x210 y155 w170 h25 -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", Config.General.RightHotareaCustom)
    Pages[5].Push(rhaCustomEdit)

    global HighlightEdgesVal := Config.General.HasProp("HighlightEdges") ? Config.General.HighlightEdges : 0
    sg.SetFont("s13 q5 c" ac, Config.Theme.IconFont)
    cbHighlightIc := sg.Add("Text", "x20 y200 w20 h25 BackgroundTrans", HighlightEdgesVal ? Chr(0xE73A) : Chr(0xE739))
    sg.SetFont("s10 q5 cWhite", Config.Theme.Font)
    cbHighlightTxt := sg.Add("Text", "x45 y203 w150 h20 0x0100 BackgroundTrans", "Highlight on Hover")

    TogHighlight(*) {
        global HighlightEdgesVal
        HighlightEdgesVal := !HighlightEdgesVal
        cbHighlightIc.Value := HighlightEdgesVal ? Chr(0xE73A) : Chr(0xE739)
    }
    cbHighlightIc.OnEvent("Click", TogHighlight)
    cbHighlightTxt.OnEvent("Click", TogHighlight)
    if IsSet(AppCursorMap) {
        AppCursorMap[cbHighlightIc.Hwnd] := 1
        AppCursorMap[cbHighlightTxt.Hwnd] := 1
    }
    Pages[5].Push(cbHighlightIc), Pages[5].Push(cbHighlightTxt)

    HotareaOptions := ["None", "Show Desktop", "Task View", "Start Menu", "Custom"]
    if (IsSet(TopBar)) {
        cbDropLHA := ObjBindMethod(TopBar, "BuildDropdown", sg, lhaBg, lhaDropText, HotareaOptions)
        lhaBg.OnEvent("Click", cbDropLHA), lhaDropText.OnEvent("Click", cbDropLHA), lhaArrow.OnEvent("Click", cbDropLHA)
        AppCursorMap[lhaBg.Hwnd] := 1, AppCursorMap[lhaDropText.Hwnd] := 1, AppCursorMap[lhaArrow.Hwnd] := 1

        cbDropRHA := ObjBindMethod(TopBar, "BuildDropdown", sg, rhaBg, rhaDropText, HotareaOptions)
        rhaBg.OnEvent("Click", cbDropRHA), rhaDropText.OnEvent("Click", cbDropRHA), rhaArrow.OnEvent("Click", cbDropRHA)
        AppCursorMap[rhaBg.Hwnd] := 1, AppCursorMap[rhaDropText.Hwnd] := 1, AppCursorMap[rhaArrow.Hwnd] := 1
    }

    SwitchTab(idx) {
        DllCall("SendMessage", "Ptr", sg.Hwnd, "Int", 0x000B, "Int", 0, "Int", 0)
        tInd.Move(TInds[idx], 38, TIndW[idx], 2)
        for i, page in Pages {
            for ctrl in page {
                if Type(ctrl) == "Gui" {
                    if (i == idx)
                        ctrl.Show("NoActivate")
                    else
                        ctrl.Hide()
                } else {
                    ctrl.Visible := (i == idx)
                }
            }
        }
        DllCall("SendMessage", "Ptr", sg.Hwnd, "Int", 0x000B, "Int", 1, "Int", 0)
        WinRedraw("ahk_id " sg.Hwnd)
    }

    t1.OnEvent("Click", (*) => SwitchTab(1)), t2.OnEvent("Click", (*) => SwitchTab(2))
    t3.OnEvent("Click", (*) => SwitchTab(3)), t4.OnEvent("Click", (*) => SwitchTab(4))
    t5.OnEvent("Click", (*) => SwitchTab(5)), t6.OnEvent("Click", (*) => SwitchTab(6))
    SwitchTab(startTab)

    for hwnd, ctrl in sg
        try DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

    global btnSave := sg.Add("Text", "x20 y530 w360 h40 0x200 Center Background" ac " cWhite", "Save && Apply Settings")
    if (IsSet(TopBar))
        TopBar.RegisterHover(btnSave.Hwnd, "FFFFFF", "E0E0E0")
    global DropShadowsVal, VisualDebugVal, AutoHideVal
    btnSave.OnEvent("Click", (*) => (
        IniWrite(hEdit.Value, IniFile, "General", "Height"),
        IniWrite(csEdit.Value, IniFile, "General", "ClockSize"),
        IniWrite(spEdit.Value, IniFile, "General", "Spacing"),
        IniWrite(omDropText.Value, IniFile, "General", "OverflowMode"),
        IniWrite(oaDropText.Value, IniFile, "General", "OverflowAlign"),
        IniWrite(DropShadowsVal ? "1" : "0", IniFile, "General", "DropShadows"),
        IniWrite(VisualDebugVal ? "1" : "0", IniFile, "General", "VisualDebug"),
        IniWrite(AutoHideVal ? "1" : "0", IniFile, "General", "AutoHide"),
        IniWrite(ahSensEdit.Value, IniFile, "General", "AutoHideSens"),
        IniWrite(ahDelayEdit.Value, IniFile, "General", "AutoHideDelay"),
        IniWrite(HighlightEdgesVal ? "1" : "0", IniFile, "General", "HighlightEdges"),
        IniWrite(homeEdit.Value, IniFile, "General", "HomeIcon"),
        IniWrite(lhaDropText.Value, IniFile, "General", "LeftHotareaAction"),
        IniWrite(lhaCustomEdit.Value, IniFile, "General", "LeftHotareaCustom"),
        IniWrite(rhaDropText.Value, IniFile, "General", "RightHotareaAction"),
        IniWrite(rhaCustomEdit.Value, IniFile, "General", "RightHotareaCustom"),
        IniWrite(fDropText.Value, IniFile, "Theme", "Font"),
        IniWrite(alpEdit.Value, IniFile, "Theme", "BarAlpha"),
        IniWrite(popEdit.Value, IniFile, "Theme", "PopupAlpha"),
        IniWrite(sdwOffEdit.Value, IniFile, "Theme", "ShadowOffset"),
        SaveLoop(Edits, "Theme"), SavePlugins(), SaveLinks(), ApplyDynamicSettings()
    ))

    SaveLoop(m, sec) {
        for k, v in m
            IniWrite(v.Value, IniFile, sec, k)
    }
    SavePlugins() {
        leftStr := "", centerStr := "", rightStr := ""
        for item in GlobalPluginsData {
            if item.Checked {
                if (item.Zone == "Left")
                    leftStr .= (leftStr ? "," : "") item.Name
                else if (item.Zone == "Center")
                    centerStr .= (centerStr ? "," : "") item.Name
                else
                    rightStr .= (rightStr ? "," : "") item.Name
            }
        }
        IniWrite(leftStr, IniFile, "Plugins", "LeftOrder")
        IniWrite(centerStr, IniFile, "Plugins", "CenterOrder")
        IniWrite(rightStr, IniFile, "Plugins", "RightOrder")
    }
    SaveLinks() {
        try IniDelete(IniFile, "Links")
        Loop GlobalLinksData.Length {
            item := GlobalLinksData[A_Index]
            val := item.RawIcon "|" item.Name "|" item.Target "|" (item.HasProp("RunArgs") ? item.RunArgs : "") "|" (item.HasProp("RunDir") ? item.RunDir : "") "|" (item.HasProp("RunState") ? item.RunState : "Normal") "|" (item.HasProp("ParentId") ? item.ParentId : "None") "|" (item.HasProp("IsFolder") ? (item.IsFolder ? "1" : "0") : "0") "|" (item.HasProp("Id") ? item.Id : "L" A_Index)
            IniWrite(val, IniFile, "Links", A_Index)
        }
    }

    curTheme := Map()
    for prop in Config.Theme.OwnProps()
        curTheme[prop] := Config.Theme.%prop%
    curTheme["DropShadows"] := Config.General.DropShadows
    ApplyTheme(curTheme)

    posCmd := (startX != "" && startY != "") ? (" x" startX " y" startY) : ""
    sg.Show("w400 h590" posCmd)
}

ChooseColorHex(initHex, hwndOwner) {
    static CUSTOMCOLORS := Buffer(64, 0)
    if SubStr(initHex, 1, 1) == "#"
        initHex := SubStr(initHex, 2)

    r := 0, g := 0, b := 0
    if StrLen(initHex) == 6 {
        r := Integer("0x" SubStr(initHex, 1, 2)), g := Integer("0x" SubStr(initHex, 3, 2)), b := Integer("0x" SubStr(initHex, 5, 2))
    }

    CHOOSECOLOR := Buffer(A_PtrSize == 8 ? 72 : 36, 0)
    NumPut("UInt", CHOOSECOLOR.Size, CHOOSECOLOR, 0), NumPut("Ptr", hwndOwner, CHOOSECOLOR, A_PtrSize)
    NumPut("UInt", (b << 16) | (g << 8) | r, CHOOSECOLOR, 3 * A_PtrSize)
    NumPut("Ptr", CUSTOMCOLORS.Ptr, CHOOSECOLOR, 4 * A_PtrSize)
    NumPut("UInt", 0x103, CHOOSECOLOR, 5 * A_PtrSize)

    if DllCall("comdlg32\ChooseColor", "Ptr", CHOOSECOLOR) {
        c := NumGet(CHOOSECOLOR, 3 * A_PtrSize, "UInt")
        return Format("{:02X}{:02X}{:02X}", c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF)
    }
    return false
}

MeasureTextWidth(text, fontOptions, fontName) {
    guiTmp := Gui()
    guiTmp.SetFont(fontOptions, fontName)
    ctrl := guiTmp.Add("Text", "", text)
    ctrl.GetPos(&x, &y, &w, &h)
    guiTmp.Destroy()
    return w
}

GlobalSaveLinks() {
    try IniDelete(IniFile, "Links")
    Loop GlobalLinksData.Length {
        item := GlobalLinksData[A_Index]
        val := item.RawIcon "|" item.Name "|" item.Target "|" (item.HasProp("RunArgs") ? item.RunArgs : "") "|" (item.HasProp("RunDir") ? item.RunDir : "") "|" (item.HasProp("RunState") ? item.RunState : "Normal") "|" (item.HasProp("ParentId") ? item.ParentId : "None") "|" (item.HasProp("IsFolder") ? (item.IsFolder ? "1" : "0") : "0") "|" (item.HasProp("Id") ? item.Id : "L" A_Index)
        IniWrite(val, IniFile, "Links", A_Index)
    }
}

RebuildLinkTree() {
    treeMap := Map()
    rootItems := []
    for v in GlobalLinksData {
        pId := v.HasProp("ParentId") ? v.ParentId : "None"
        if (pId == "" || pId == "None")
            rootItems.Push(v)
        else {
            if !treeMap.Has(pId)
                treeMap[pId] := []
            treeMap[pId].Push(v)
        }
    }

    res := []
    RecurseNode(arr, depth) {
        Loop arr.Length {
            v := arr[A_Index]
            v.Depth := depth
            res.Push(v)
            if (v.HasProp("IsFolder") && v.IsFolder && v.HasProp("Id") && treeMap.Has(v.Id))
                RecurseNode(treeMap[v.Id], depth + 1)
        }
    }
    RecurseNode(rootItems, 0)

    global GlobalLinksData := res
}

OpenLinkEditPopup(item, idx, listRef) {
    s := IsSet(TopBar) ? TopBar.Scale : (A_ScreenDPI / 96)
    ag := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" listRef.Parent.Hwnd)
    ag.BackColor := Config.Theme.DropBg
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

    W := Round(300 * s)
    ag.SetFont("s" Round(12 * s) " w600 q5 c" Config.Theme.IconHover, Config.Theme.Font)
    ag.Add("Text", "x" Round(15 * s) " y" Round(15 * s) " w" (W - Round(30 * s)) " h" Round(25 * s) " BackgroundTrans", "Configure Link")

    yP := Round(45 * s)
    ag.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.DropText, Config.Theme.Font)
    ag.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(80 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Type:")

    typeVal := ag.Add("Text", "x0 y0 w0 h0 Hidden", item.HasProp("IsFolder") && item.IsFolder ? "Folder" : "Link")
    typeBg := ag.Add("Text", "x" Round(100 * s) " y" yP " w" Round(165 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", typeVal.Value)
    typeArrow := ag.Add("Text", "x" Round(265 * s) " y" yP " w" Round(15 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Chr(0x2304))
    yP += Round(35 * s)

    ag.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(80 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Parent:")
    parVal := ag.Add("Text", "x0 y0 w0 h0 Hidden", item.HasProp("ParentId") && item.ParentId != "" ? item.ParentId : "None")

    parList := [{ Disp: "None", Val: "None" }]
    parNames := Map("None", "None")
    for lIdx, l in GlobalLinksData {
        l_id := l.HasProp("Id") ? l.Id : "L" lIdx
        if (l.HasProp("IsFolder") && l.IsFolder && (!item.HasProp("Id") || l_id != item.Id)) {
            parList.Push({ Disp: l.Name, Val: l_id })
            parNames[l_id] := l.Name
        }
    }

    parDisp := parNames.Has(parVal.Value) ? parNames[parVal.Value] : "None"
    parBg := ag.Add("Text", "x" Round(100 * s) " y" yP " w" Round(165 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", parDisp)
    parArrow := ag.Add("Text", "x" Round(265 * s) " y" yP " w" Round(15 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Chr(0x2304))
    yP += Round(35 * s)

    ag.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(80 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Name:")
    eName := ag.Add("Edit", "x" Round(100 * s) " y" yP " w" Round(180 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", item.Name)
    yP += Round(35 * s)

    tLab := ag.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(80 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Target:")
    eTarg := ag.Add("Edit", "x" Round(100 * s) " y" yP " w" Round(180 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", item.Target)
    yP += Round(35 * s)

    aLab := ag.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(80 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Arguments:")
    eArgs := ag.Add("Edit", "x" Round(100 * s) " y" yP " w" Round(180 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", item.HasProp("RunArgs") ? item.RunArgs : "")
    yP += Round(35 * s)

    dLab := ag.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(80 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Work Dir:")
    eDir := ag.Add("Edit", "x" Round(100 * s) " y" yP " w" Round(180 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", item.HasProp("RunDir") ? item.RunDir : "")
    yP += Round(35 * s)

    sLab := ag.Add("Text", "x" Round(15 * s) " y" Round(yP + 2 * s) " w" Round(80 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Run State:")
    stateVal := ag.Add("Text", "x0 y0 w0 h0 Hidden", item.HasProp("RunState") ? item.RunState : "Normal")
    stateBg := ag.Add("Text", "x" Round(100 * s) " y" yP " w" Round(165 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", stateVal.Value)
    stateArrow := ag.Add("Text", "x" Round(265 * s) " y" yP " w" Round(15 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Chr(0x2304))
    yP += Round(35 * s)

    toggleVis := (*) => (
        v := (typeVal.Value == "Link"),
        tLab.Visible := v, eTarg.Visible := v,
        aLab.Visible := v, eArgs.Visible := v,
        dLab.Visible := v, eDir.Visible := v,
        sLab.Visible := v, stateBg.Visible := v, stateArrow.Visible := v
    )
    toggleVis()

    cbType := (*) => (IsSet(TopBar) ? TopBar.BuildDropdown(ag, typeBg, typeVal, ["Link", "Folder"], , , toggleVis) : 0)
    typeBg.OnEvent("Click", cbType), typeArrow.OnEvent("Click", cbType)

    cbPar := (*) => (
        (IsSet(TopBar) ? TopBar.BuildDropdown(ag, parBg, parVal, parList, , , (*) => (parBg.Value := parNames[parVal.Value])) : 0)
    )
    parBg.OnEvent("Click", cbPar), parArrow.OnEvent("Click", cbPar)

    cbState := (*) => (IsSet(TopBar) ? TopBar.BuildDropdown(ag, stateBg, stateVal, ["Normal", "Maximized", "Minimized", "Hidden"]) : 0)
    stateBg.OnEvent("Click", cbState), stateArrow.OnEvent("Click", cbState)

    ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(260 * s) " h" Round(20 * s) " 0x200 BackgroundTrans", "Icon (Choose or type image path):")
    yP += Round(25 * s)

    rawIc := HasProp(item, "RawIcon") ? item.RawIcon : (HasProp(item, "Icon") ? item.Icon : "")
    eIc := ag.Add("Edit", "x" Round(15 * s) " y" yP " w" Round(230 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", rawIc)
    ag.SetFont("s" Round(10 * s) " q5 cWhite", Config.Theme.IconFont)
    btnF := ag.Add("Text", "x" Round(250 * s) " y" yP " w" Round(30 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25), Chr(0xE8D5))
    btnF.OnEvent("Click", (*) => (
        ag.Opt("+OwnDialogs"),
        imgPath := FileSelect("1", "", "Select Icon Image", "Images (*.png; *.jpg; *.ico)"),
        (imgPath ? eIc.Value := imgPath : 0)
    ))
    if IsSet(TopBar)
        TopBar.RegisterHover(btnF.Hwnd, StrReplace(Config.Theme.Icon, "#", ""), StrReplace(Config.Theme.IconHover, "#", ""))
    yP += Round(35 * s)

    ag.SetFont("s" Round(14 * s) " q5 cWhite", Config.Theme.IconFont)
    iconGrid := ["E8D5", "E71B", "E756", "E70B", "E713", "E74D", "E909", "E7FA", "E715", "E768", "E7B8", "E115", "E11A", "E720", "E767", "E701", "E774", "E74C", "E70F", "E13D", "E787", "E80F", "E7FC", "E943", "E838", "E749", "E8D6", "E8C8", "E8C6", "E77F", "E12B", "E1D0", "E8B9", "E714", "E7F6", "E17B", "E753", "EB51", "E734", "E718"]

    gX := Round(15 * s)
    for ic in iconGrid {
        bg := ag.Add("Text", "x" gX " y" yP " w" Round(25 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), Chr("0x" ic))
        if IsSet(TopBar)
            TopBar.RegisterHover(bg.Hwnd, StrReplace(Config.Theme.Icon, "#", ""), StrReplace(Config.Theme.IconHover, "#", ""))
        bg.OnEvent("Click", ((h, *) => eIc.Value := h).Bind(ic))
        gX += Round(27 * s)
        if (gX > W - Round(30 * s)) {
            gX := Round(15 * s)
            yP += Round(27 * s)
        }
    }
    if (gX != Round(15 * s))
        yP += Round(35 * s)
    else
        yP += Round(10 * s)

    ag.SetFont("s" Round(10 * s) " w600 q5 cWhite", Config.Theme.Font)
    ac := StrReplace(Config.Theme.Slider, "#", "")
    btnSave := ag.Add("Text", "x" Round(15 * s) " y" yP " w" (W - Round(30 * s)) " h" Round(30 * s) " 0x200 Center Background" ac, "Save Link")
    if IsSet(TopBar)
        TopBar.RegisterHover(btnSave.Hwnd, "FFFFFF", "E0E0E0")

    btnSave.OnEvent("Click", (*) => (
        item.Name := eName.Value,
        item.Target := eTarg.Value,
        item.RawIcon := eIc.Value,
        item.RunArgs := eArgs.Value,
        item.RunDir := eDir.Value,
        item.RunState := stateVal.Value,
        item.ParentId := parVal.Value,
        item.IsFolder := (typeVal.Value == "Folder"),
        isP := FileExist(eIc.Value) || InStr(eIc.Value, ":\") || InStr(eIc.Value, "."),
        item.IsImage := isP,
        item.Icon := isP ? eIc.Value : (StrLen(eIc.Value) >= 4 ? Chr("0x" eIc.Value) : eIc.Value),
        RebuildLinkTree(),
        listRef.Data := GlobalLinksData,
        listRef.Render(),
        GlobalSaveLinks(),
        listRef.Parent.Opt("-Disabled"),
        ag.Destroy(),
        WinActivate("ahk_id " listRef.Parent.Hwnd)
    ))

    ag.SetFont("s" Round(10 * s) " q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 70), Config.Theme.IconFont)
    btnExit := ag.Add("Text", "x" (W - Round(35 * s)) " y" Round(10 * s) " w" Round(25 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans", Chr(0xE711))
    if IsSet(TopBar)
        TopBar.RegisterHover(btnExit.Hwnd, BlendHex(Config.Theme.Text, Config.Theme.DropBg, 70), StrReplace(Config.Theme.Danger, "#", ""))
    btnExit.OnEvent("Click", (*) => (listRef.Parent.Opt("-Disabled"), ag.Destroy(), WinActivate("ahk_id " listRef.Parent.Hwnd)))

    ag.OnEvent("Escape", (*) => (listRef.Parent.Opt("-Disabled"), ag.Destroy(), WinActivate("ahk_id " listRef.Parent.Hwnd)))

    listRef.Parent.GetPos(&pX, &pY, &pW, &pH)
    newH := yP + Round(45 * s)
    ag.Show("x" (pX + (pW / 2) - (W / 2)) " y" (pY + (pH / 2) - (newH / 2)) " w" W " h" newH)
    listRef.Parent.Opt("+Disabled")
}

ShowPluginRulesPopup(pName, parentGui) {
    if WinExist("Plugin Rules") {
        try WinClose("Plugin Rules")
    }

    rootHwnd := DllCall("GetAncestor", "Ptr", parentGui.Hwnd, "UInt", 2, "Ptr")
    rootGui := GuiFromHwnd(rootHwnd)

    s := IsSet(TopBar) ? TopBar.Scale : (A_ScreenDPI / 96)
    ag := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x08000000 +Owner" rootGui.Hwnd, "Plugin Rules")
    ag.BackColor := Config.Theme.DropBg
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 33, "Int*", 2, "Int", 4)
    ag.MarginX := 0, ag.MarginY := 0

    W := Round(380 * s)
    ag.SetFont("s" Round(12 * s) " w600 q5 c" Config.Theme.IconHover, Config.Theme.Font)
    ag.Add("Text", "x" Round(20 * s) " y" Round(15 * s) " w" (W - Round(50 * s)) " h" Round(25 * s) " BackgroundTrans", "Match Rules: " pName)

    local PluginRulesData := []
    defActVal := "Show"

    if !Config.PluginRules.Has(pName)
        Config.PluginRules[pName] := ""

    for line in StrSplit(Config.PluginRules[pName], "###") {
        if !line
            continue
        if !InStr(line, "|") {
            if (A_Index == 1 && (line == "Show" || line == "Hide"))
                defActVal := line
            continue
        }
        parts := StrSplit(line, "|")
        if (parts.Length >= 3)
            PluginRulesData.Push({ Action: parts[1], State: parts[2], String: parts[3], Idx: A_Index })
    }

    yP := Round(40 * s)
    ag.SetFont("s" Round(10 * s) " w500 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.Font)
    ag.Add("Text", "x" Round(20 * s) " y" yP " w" Round(110 * s) " h" Round(20 * s) " BackgroundTrans", "Default Visibility:")

    ag.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)
    defBg := ag.Add("Text", "x" Round(130 * s) " y" Round(yP - 3 * s) " w" Round(60 * s) " h" Round(22 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), defActVal)
    defArrow := ag.Add("Text", "x" Round(185 * s) " y" Round(yP - 3 * s) " w" Round(15 * s) " h" Round(22 * s) " 0x200 Center BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Chr(0x2304))

    yP += Round(38 * s)
    ag.SetFont("s" Round(9 * s) " w600 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.Font)
    ag.Add("Text", "x" Round(20 * s) " y" yP " w" Round(60 * s) " BackgroundTrans", "ACTION")
    ag.Add("Text", "x" Round(90 * s) " y" yP " w" Round(70 * s) " BackgroundTrans", "STATE")
    ag.Add("Text", "x" Round(170 * s) " y" yP " w" Round(200 * s) " BackgroundTrans", "MATCH PATTERN")

    yP += Round(25 * s)
    ag.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)

    actBg := ag.Add("Text", "x" Round(20 * s) " y" yP " w" Round(60 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "Show")
    actArrow := ag.Add("Text", "x" Round(65 * s) " y" yP " w" Round(15 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Chr(0x2304))

    stateBg := ag.Add("Text", "x" Round(90 * s) " y" yP " w" Round(70 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "Active")
    stateArrow := ag.Add("Text", "x" Round(145 * s) " y" yP " w" Round(15 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Chr(0x2304))

    strEdit := ag.Add("Edit", "x" Round(170 * s) " y" (yP - 1) " w" Round(150 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", "*")

    ag.SetFont("s" Round(12 * s) " q5 cWhite", Config.Theme.IconFont)
    addBtn := ag.Add("Text", "x" Round(330 * s) " y" yP " w" Round(30 * s) " h" Round(25 * s) " 0x200 Center Background" StrReplace(Config.Theme.IconHover, "#", ""), Chr(0xE710))

    SaveMemRules() {
        str := defBg.Value
        for pRule in PluginRulesData {
            if HasProp(pRule, "Action")
                str .= "###" pRule.Action "|" pRule.State "|" pRule.String
        }

        if (str == "Show")
            str := ""

        Config.PluginRules[pName] := str
        if (str != "")
            IniWrite(str, IniFile, "PluginRules", pName)
        else
            try IniDelete(IniFile, "PluginRules", pName)

        if IsSet(TopBar)
            TopBar.TickUpdate()
    }

    if IsSet(TopBar) {
        TopBar.RegisterHover(addBtn.Hwnd, "FFFFFF", "E0E0E0")
        AppCursorMap[addBtn.Hwnd] := 1

        AppCursorMap[defBg.Hwnd] := 1, AppCursorMap[defArrow.Hwnd] := 1
        AppCursorMap[actBg.Hwnd] := 1, AppCursorMap[actArrow.Hwnd] := 1
        AppCursorMap[stateBg.Hwnd] := 1, AppCursorMap[stateArrow.Hwnd] := 1

        defDropBound := ObjBindMethod(TopBar, "BuildDropdown", ag, defBg, defBg, ["Show", "Hide"], unset, unset, SaveMemRules)
        defBg.OnEvent("Click", defDropBound), defArrow.OnEvent("Click", defDropBound)

        actDropBound := ObjBindMethod(TopBar, "BuildDropdown", ag, actBg, actBg, ["Show", "Hide"])
        actBg.OnEvent("Click", actDropBound), actArrow.OnEvent("Click", actDropBound)

        stateDropBound := ObjBindMethod(TopBar, "BuildDropdown", ag, stateBg, stateBg, ["Active", "Visible", "Running"])
        stateBg.OnEvent("Click", stateDropBound), stateArrow.OnEvent("Click", stateDropBound)
    }

    yP += Round(35 * s)

    RenderRuleRow := (listObj, item, idx, rowY, rowW, bg) => (
        ActCol := item.Action == "Show" ? StrReplace(Config.Theme.Success, "#", "") : StrReplace(Config.Theme.Warning, "#", ""),
        listObj.Inner.SetFont("s" Round(9 * s) " w600 q5 c" ActCol, Config.Theme.Font),
        listObj.Inner.Add("Text", "x" Round(25 * s) " y" (rowY + 5 * s) " w" Round(45 * s) " h" Round(20 * s) " BackgroundTrans", item.Action),
        listObj.Inner.SetFont("s" Round(9 * s) " w500 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.Font),
        listObj.Inner.Add("Text", "x" Round(75 * s) " y" (rowY + 5 * s) " w" Round(55 * s) " h" Round(20 * s) " BackgroundTrans", item.State),
        listObj.Inner.SetFont("s" Round(9 * s) " w500 q5 c" Config.Theme.Text, Config.Theme.Font),
        listObj.Inner.Add("Text", "x" Round(135 * s) " y" (rowY + 5 * s) " w" (rowW - Round(170 * s)) " h" Round(20 * s) " BackgroundTrans", item.String),
        listObj.Inner.SetFont("s" Round(12 * s) " q5 c" Config.Theme.Icon, Config.Theme.IconFont),
        trash := listObj.Inner.Add("Text", "x" (rowW - Round(30 * s)) " y" (rowY + 5 * s) " w" Round(20 * s) " h" Round(20 * s) " 0x200 Center BackgroundTrans", Chr(0xE74D)),
        (IsSet(TopBar) ? (TopBar.RegisterHover(trash.Hwnd, StrReplace(Config.Theme.Icon, "#", ""), StrReplace(Config.Theme.Danger, "#", "")), AppCursorMap[trash.Hwnd] := 1) : 0),
        trash.OnEvent("Click", (*) => (
            PluginRulesData.RemoveAt(idx),
            SaveMemRules(),
            rulesList.Render()
        ))
    )


    global rulesList := SexyList(ag, Round(20 * s), yP, W - Round(40 * s), Round(150 * s), PluginRulesData, RenderRuleRow, (*) => 0)

    addBtn.OnEvent("Click", (*) => (
        (strEdit.Value != "") ? (
            PluginRulesData.Push({ Action: actBg.Value, State: stateBg.Value, String: strEdit.Value, Idx: PluginRulesData.Length + 1 }),
            SaveMemRules(),
            rulesList.Render()
        ) : 0
    ))

    ag.SetFont("s" Round(10 * s) " w600 q5 cWhite", Config.Theme.Font)
    botBtn := ag.Add("Text", "x" Round(20 * s) " y" (yP + Round(155 * s)) " w" (W - Round(40 * s)) " h" Round(28 * s) " 0x200 Center Background" StrReplace(Config.Theme.IconHover, "#", ""), "Close Rules")
    if IsSet(TopBar) {
        TopBar.RegisterHover(botBtn.Hwnd, "FFFFFF", "E0E0E0")
        AppCursorMap[botBtn.Hwnd] := 1
    }
    botBtn.OnEvent("Click", (*) => (rootGui.Opt("-Disabled"), rulesList.Destroy(), ag.Destroy(), WinActivate("ahk_id " rootGui.Hwnd)))

    ag.SetFont("s" Round(10 * s) " q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 70), Config.Theme.IconFont)
    exitBtn := ag.Add("Text", "x" (W - Round(35 * s)) " y" Round(10 * s) " w" Round(25 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans c" StrReplace(Config.Theme.Icon, "#", ""), Chr(0xE711))
    if IsSet(TopBar) {
        TopBar.RegisterHover(exitBtn.Hwnd, StrReplace(Config.Theme.Icon, "#", ""), StrReplace(Config.Theme.Danger, "#", ""))
        AppCursorMap[exitBtn.Hwnd] := 1
    }
    exitBtn.OnEvent("Click", (*) => (rootGui.Opt("-Disabled"), rulesList.Destroy(), ag.Destroy(), WinActivate("ahk_id " rootGui.Hwnd)))

    ag.OnEvent("Escape", (*) => (rootGui.Opt("-Disabled"), rulesList.Destroy(), ag.Destroy(), WinActivate("ahk_id " rootGui.Hwnd)))

    rootGui.GetPos(&pX, &pY, &pW, &pH)
    newH := yP + Round(195 * s)
    ag.Show("x" (pX + (pW / 2) - (W / 2)) " y" (pY + (pH / 2) - (newH / 2)) " w" W " h" newH)
    rootGui.Opt("+Disabled")
}

OpenIconPickerPopup(editCtrl, parentGui) {
    s := IsSet(TopBar) ? TopBar.Scale : (A_ScreenDPI / 96)
    ag := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" parentGui.Hwnd)
    ag.BackColor := Config.Theme.DropBg
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

    W := Round(300 * s)
    ag.SetFont("s" Round(12 * s) " w600 q5 c" Config.Theme.IconHover, Config.Theme.Font)
    ag.Add("Text", "x" Round(15 * s) " y" Round(15 * s) " w" (W - Round(30 * s)) " h" Round(25 * s) " BackgroundTrans", "Choose Start Icon")

    yP := Round(45 * s)
    ag.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.DropText, Config.Theme.Font)
    ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(260 * s) " h" Round(20 * s) " 0x200 BackgroundTrans cWhite", "Icon or an image:")
    yP += Round(25 * s)

    eIc := ag.Add("Edit", "x" Round(15 * s) " y" yP " w" Round(230 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", editCtrl.Value)
    ag.SetFont("s" Round(10 * s) " q5 cWhite", Config.Theme.IconFont)

    btnF := ag.Add("Text", "x" Round(250 * s) " y" yP " w" Round(30 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25), Chr(0xE8D5))
    btnF.OnEvent("Click", (*) => (
        ag.Opt("+OwnDialogs"),
        imgPath := FileSelect("1", "", "Select Icon Image", "Images (*.png; *.jpg; *.ico)"),
        (imgPath ? eIc.Value := imgPath : 0)
    ))
    if IsSet(TopBar)
        TopBar.RegisterHover(btnF.Hwnd, "FFFFFF", Config.Theme.IconHover)
    yP += Round(35 * s)

    ag.SetFont("s" Round(14 * s) " q5 cWhite", Config.Theme.IconFont)
    iconGrid := ["E700", "E71B", "E756", "E70B", "E713", "E74D", "E909", "E7FA", "E715", "E768", "E7B8", "E115", "E11A", "E720", "E767", "E701", "E774", "E74C", "E70F", "E13D", "E787", "E80F", "E7FC", "E943", "E838", "E749", "E8D6", "E8C8", "E8C6", "E77F", "E12B", "E1D0", "E8B9", "E714", "E7F6", "E17B", "E753", "EB51", "E734", "E718"]

    gX := Round(15 * s)
    for ic in iconGrid {
        bg := ag.Add("Text", "x" gX " y" yP " w" Round(25 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), Chr("0x" ic))
        if IsSet(TopBar)
            TopBar.RegisterHover(bg.Hwnd, "FFFFFF", Config.Theme.IconHover)
        bg.OnEvent("Click", ((h, *) => eIc.Value := h).Bind(ic))
        gX += Round(27 * s)
        if (gX > W - Round(30 * s)) {
            gX := Round(15 * s)
            yP += Round(27 * s)
        }
    }
    if (gX != Round(15 * s))
        yP += Round(35 * s)
    else
        yP += Round(10 * s)

    ag.SetFont("s" Round(10 * s) " w600 q5 cWhite", Config.Theme.Font)
    ac := StrReplace(Config.Theme.Slider, "#", "")
    btnSave := ag.Add("Text", "x" Round(15 * s) " y" yP " w" (W - Round(30 * s)) " h" Round(30 * s) " 0x200 Center Background" ac, "Save && Close")
    if IsSet(TopBar)
        TopBar.RegisterHover(btnSave.Hwnd, "FFFFFF", "E0E0E0")

    btnSave.OnEvent("Click", (*) => (
        editCtrl.Value := eIc.Value,
        parentGui.Opt("-Disabled"),
        ag.Destroy(),
        WinActivate("ahk_id " parentGui.Hwnd)
    ))

    ag.SetFont("s" Round(10 * s) " q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 70), Config.Theme.IconFont)
    btnExit := ag.Add("Text", "x" (W - Round(35 * s)) " y" Round(10 * s) " w" Round(25 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans", Chr(0xE711))
    if IsSet(TopBar)
        TopBar.RegisterHover(btnExit.Hwnd, BlendHex(Config.Theme.Text, Config.Theme.DropBg, 70), StrReplace(Config.Theme.Danger, "#", ""))
    btnExit.OnEvent("Click", (*) => (parentGui.Opt("-Disabled"), ag.Destroy(), WinActivate("ahk_id " parentGui.Hwnd)))

    ag.OnEvent("Escape", (*) => (parentGui.Opt("-Disabled"), ag.Destroy(), WinActivate("ahk_id " parentGui.Hwnd)))

    parentGui.GetPos(&pX, &pY, &pW, &pH)
    newH := yP + Round(45 * s)
    ag.Show("x" (pX + (pW / 2) - (W / 2)) " y" (pY + (pH / 2) - (newH / 2)) " w" W " h" newH)
    parentGui.Opt("+Disabled")
}

OpenDeletePopup(listRef, idx) {
    s := IsSet(TopBar) ? TopBar.Scale : (A_ScreenDPI / 96)
    ag := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" listRef.Parent.Hwnd)
    ag.BackColor := Config.Theme.DropBg
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

    W := Round(250 * s)
    ag.SetFont("s" Round(12 * s) " w600 q5 c" StrReplace(Config.Theme.Danger, "#", ""), Config.Theme.Font)
    ag.Add("Text", "x" Round(15 * s) " y" Round(15 * s) " w" (W - Round(30 * s)) " h" Round(25 * s) " BackgroundTrans", "Delete Link?")

    yP := Round(45 * s)
    ag.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.DropText, Config.Theme.Font)
    ag.Add("Text", "x" Round(15 * s) " y" yP " w" (W - Round(30 * s)) " h" Round(40 * s) " 0x200 BackgroundTrans cWhite", "Are you sure you want to delete this link?")
    yP += Round(45 * s)

    ag.SetFont("s" Round(10 * s) " w600 q5 cWhite", Config.Theme.Font)
    btnY := ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(105 * s) " h" Round(30 * s) " 0x200 Center BackgroundFF5555 cWhite", "Delete")
    btnN := ag.Add("Text", "x" Round(130 * s) " y" yP " w" Round(105 * s) " h" Round(30 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", "Cancel")

    if IsSet(TopBar) {
        TopBar.RegisterHover(btnY.Hwnd, "FFFFFF", BlendHex(Config.Theme.Danger, Config.Theme.DropBg, 50))
        TopBar.RegisterHover(btnN.Hwnd, "FFFFFF", BlendHex(Config.Theme.Text, Config.Theme.DropBg, 70))
    }

    btnY.OnEvent("Click", (*) => (
        listRef.Data.RemoveAt(idx),
        GlobalLinksData := listRef.Data,
        RebuildLinkTree(),
        listRef.Data := GlobalLinksData,
        listRef.Render(),
        GlobalSaveLinks(),
        ag.Destroy()
    ))
    btnN.OnEvent("Click", (*) => ag.Destroy())

    ag.SetFont("s" Round(10 * s) " q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 70), Config.Theme.IconFont)
    btnExit := ag.Add("Text", "x" (W - Round(35 * s)) " y" Round(10 * s) " w" Round(25 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans", Chr(0xE711))
    if IsSet(TopBar)
        TopBar.RegisterHover(btnExit.Hwnd, BlendHex(Config.Theme.Text, Config.Theme.DropBg, 70), StrReplace(Config.Theme.Danger, "#", ""))
    btnExit.OnEvent("Click", (*) => ag.Destroy())

    yP += Round(45 * s)
    ag.Show("w" W " h" yP)
}

class SexyList {
    __New(parentGui, x, y, w, h, dataArray, renderRowCb, onUpdateCb, customSwapCb := "") {
        this.CustomSwapCb := customSwapCb
        this.Parent := parentGui
        this.Data := dataArray
        this.RenderRowCb := renderRowCb
        this.OnUpdateCb := onUpdateCb

        this.X := x, this.Y := y, this.W := w, this.H := h
        this.RowH := 36
        this.ScrollY := 0
        this.MaxScroll := 0

        bgMain := StrReplace(Config.Theme.DropBg, "#", "")

        this.Outer := Gui("-Caption +Parent" parentGui.Hwnd)
        this.Outer.BackColor := bgMain
        this.Outer.MarginX := 0, this.Outer.MarginY := 0

        ac := StrReplace(Config.Theme.Slider, "#", "")
        this.BaseThumbColor := ac
        this.HoverThumbColor := this.LightenHex(ac, 0.4)

        bgC := StrReplace(Config.Theme.BarBg, "#", "")
        this.SbTrack := this.Outer.Add("Text", "x" (w - 12) " y0 w12 h" h " 0x0100 Background" bgC, "")
        this.SbThumb := this.Outer.Add("Text", "x" (w - 12) " y0 w12 h40 0x0100 Background" ac, "")

        this.Inner := Gui("-Caption +Parent" this.Outer.Hwnd)
        this.Inner.BackColor := bgMain
        this.Inner.MarginX := 0, this.Inner.MarginY := 0

        this.Outer.Show("x" x " y" y " w" w " h" h " NoActivate")

        this.IsHoveringThumb := false
        this.IsDragging := false
        this.WasClicking := false
        this.LastScrollY := -1

        this.Grabbers := []
        this.DragMode := false
        this.DragIdx := 0
        this.DragGui := ""

        this.IsPendingDrag := false
        this.PendingDragIdx := 0
        this.PendingDragX := 0
        this.PendingDragY := 0

        this.IsHoveringGrabber := false

        this._fnWheel := ObjBindMethod(this, "OnWheel")
        OnMessage(0x020A, this._fnWheel)

        this._fnCursor := ObjBindMethod(this, "OnSetCursor")
        OnMessage(0x0020, this._fnCursor)

        this._fnPoll := ObjBindMethod(this, "InteractionPoll")
        SetTimer(this._fnPoll, 15)

        this.Render()
    }

    Destroy() {
        try OnMessage(0x020A, this._fnWheel, 0)
        try OnMessage(0x0020, this._fnCursor, 0)
        if HasProp(this, "_fnPoll")
            try SetTimer(this._fnPoll, 0)
        try this.Inner.Destroy()
        try this.Outer.Destroy()
        if (HasProp(this, "DragGui") && this.DragGui)
            try this.DragGui.Destroy()
    }

    LightenHex(hex, factor := 0.2) {
        if StrLen(hex) != 6
            return "FFFFFF"
        r := Integer("0x" SubStr(hex, 1, 2)), g := Integer("0x" SubStr(hex, 3, 2)), b := Integer("0x" SubStr(hex, 5, 2))
        r := Min(255, Round(r + (255 - r) * factor)), g := Min(255, Round(g + (255 - g) * factor)), b := Min(255, Round(b + (255 - b) * factor))
        return Format("{:02X}{:02X}{:02X}", r, g, b)
    }

    UpdateThemeColors(bgHex, sliderHex) {
        this.BaseThumbColor := StrReplace(sliderHex, "#", "")
        this.HoverThumbColor := this.LightenHex(this.BaseThumbColor, 0.4)
        if !this.IsHoveringThumb {
            try this.SbThumb.Opt("Background" this.BaseThumbColor)
            try this.SbThumb.Redraw()
        }
        bgC := StrReplace(bgHex, "#", "")
        try this.SbTrack.Opt("Background" bgC)
        try this.SbTrack.Redraw()
    }

    Swap(idx1, idx2) {
        if (idx1 < 1 || idx1 > this.Data.Length || idx2 < 1 || idx2 > this.Data.Length)
            return
        tmp := this.Data[idx1]
        this.Data[idx1] := this.Data[idx2]
        this.Data[idx2] := tmp
        this.Render()
        cb := this.OnUpdateCb
        cb()
    }

    Delete(idx) {
        if (idx < 1 || idx > this.Data.Length)
            return
        this.Data.RemoveAt(idx)
        this.Render()
        cb := this.OnUpdateCb
        cb()
    }

    Render() {
        try {
            for hwnd in WinGetControlsHwnd(this.Inner.Hwnd)
                DllCall("DestroyWindow", "Ptr", hwnd)
        } catch {

        }

        totalH := this.Data.Length * this.RowH
        this.Inner.Show("x0 y0 w" (this.W - 14) " h" totalH " NoActivate")

        this.MaxScroll := Max(0, totalH - this.H)
        if (this.ScrollY > this.MaxScroll)
            this.ScrollY := this.MaxScroll
        this.Inner.Move(0, -this.ScrollY)
        this.UpdateScrollbar()

        this.Grabbers := []

        acCol := StrReplace(Config.Theme.Slider, "#", "")
        this.SnapHL := this.Inner.Add("Text", "x0 y0 w" (this.W - 14) " h" this.RowH " Background" acCol " Hidden", "")
        this.SnapLine := this.Inner.Add("Text", "x0 y0 w" (this.W - 14) " h3 Background" acCol " Hidden", "")

        yP := 0
        for i, item in this.Data {
            bg := this.Inner.Add("Text", "x0 y" yP " w" (this.W - 14) " h" this.RowH " BackgroundTrans", "")

            this.Inner.SetFont("s12 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 30), Config.Theme.IconFont)
            grabber := this.Inner.Add("Text", "x5 y" (yP + (this.RowH / 2) - 10) " w20 h20 0x200 Center BackgroundTrans", Chr(0xE700))
            if (IsSet(TopBar)) {
                TopBar.RegisterHover(grabber.Hwnd, BlendHex(Config.Theme.Text, Config.Theme.DropBg, 30), "FFFFFF")
            }
            this.Grabbers.Push({ Hwnd: grabber.Hwnd, Idx: i, StartY: yP })

            cb := this.RenderRowCb
            cb(this, item, i, yP, this.W - 14, bg)
            yP += this.RowH
        }
    }

    OnWheel(wParam, lParam, msg, hwnd) {
        if (!this.MaxScroll)
            return
        CoordMode("Mouse", "Client")
        try {
            MouseGetPos(&mX, &mY, &mWin, &mCtrl, 2)
            if (mWin == this.Parent.Hwnd) {
                if (mX >= this.X && mX <= this.X + this.W && mY >= this.Y && mY <= this.Y + this.H) {
                    dir := (wParam << 32 >> 48) > 0 ? -1 : 1
                    this.ScrollY += dir * 36
                    this.ClampScroll()
                    this.UpdateScrollbar()
                }
            }
        }
    }

    OnSetCursor(wParam, lParam, msg, hwnd) {
        if (this.DragMode) {
            DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Int", 32646))
            return 1
        }
        if (this.IsHoveringGrabber) {
            DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Int", 32649))
            return 1
        }
    }

    ClampScroll() {
        if (this.ScrollY < 0)
            this.ScrollY := 0
        if (this.ScrollY > this.MaxScroll)
            this.ScrollY := this.MaxScroll
        this.Inner.Move(0, -this.ScrollY)
    }

    InteractionPoll() {
        try {
            if (!DllCall("IsWindowVisible", "Ptr", this.Outer.Hwnd))
                return
        } catch {
            return
        }

        CoordMode("Mouse", "Screen")
        MouseGetPos(&mX, &mY, &mWin)

        WinGetPos(&gX, &gY, &gW, &gH, this.Outer.Hwnd)
        relX := mX - gX, relY := mY - gY

        isOverThumb := false
        isOverTrack := false

        sbX := this.W - 16

        thumbH := Round(Max(20, (this.H / (this.MaxScroll + this.H)) * this.H))
        pct := (this.MaxScroll > 0) ? (this.ScrollY / this.MaxScroll) : 0
        thumbY := Round(pct * (this.H - thumbH))
        cY := thumbY, cH := thumbH

        if (relX >= sbX && relX <= this.W && relY >= 0 && relY <= this.H) {
            if (relY >= cY && relY <= cY + cH)
                isOverThumb := true
            else
                isOverTrack := true
        }

        if (isOverThumb && !this.IsHoveringThumb && !this.IsDragging) {
            this.IsHoveringThumb := true
            this.SbThumb.Opt("Background" this.HoverThumbColor)
            this.SbThumb.Redraw()
        } else if (!isOverThumb && this.IsHoveringThumb && !this.IsDragging) {
            this.IsHoveringThumb := false
            this.SbThumb.Opt("Background" this.BaseThumbColor)
            this.SbThumb.Redraw()
        }

        isClicking := GetKeyState("LButton", "P")

        this.IsHoveringGrabber := false
        hoverGrabberIdx := 0

        if (relX >= 0 && relX <= 30 && relY >= 0 && relY <= this.H) {
            innerY := relY + this.ScrollY
            for g in this.Grabbers {
                if (innerY >= g.StartY && innerY <= g.StartY + this.RowH) {
                    this.IsHoveringGrabber := true
                    hoverGrabberIdx := g.Idx
                    break
                }
            }
        }

        ; Cursor is handled by OnSetCursor message trap now.
        ; E0x20 transparent DragGui won't steal WM_SETCURSOR.

        if (isClicking && !this.WasClicking) {
            if (isOverThumb) {
                this.IsDragging := true
                this.DragStartY := mY
                this.DragStartScroll := this.ScrollY
            } else if (isOverTrack) {
                if (relY > cY + (cH / 2))
                    this.ScrollY += 60
                else
                    this.ScrollY -= 60
                this.ClampScroll()
                this.UpdateScrollbar()
            } else if (this.IsHoveringGrabber) {
                this.IsPendingDrag := true
                this.PendingDragIdx := hoverGrabberIdx
                this.PendingDragX := mX
                this.PendingDragY := mY
            }
        }

        if (this.IsPendingDrag) {
            if (!isClicking) {
                this.IsPendingDrag := false
            } else if (Abs(mX - this.PendingDragX) > 3 || Abs(mY - this.PendingDragY) > 3) {
                this.IsPendingDrag := false
                this.DragMode := true
                this.DragIdx := this.PendingDragIdx
                try this.DragGui.Destroy()
                this.DragGui := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 -DPIScale +Owner" this.Parent.Hwnd)
                this.DragGui.BackColor := Config.Theme.DropBg
                this.DragGui.MarginX := 0, this.DragGui.MarginY := 0
                WinSetTransparent(180, this.DragGui.Hwnd)

                this.DragGui.SetFont("s12 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 30), Config.Theme.IconFont)
                this.DragGui.Add("Text", "x5 y" ((this.RowH / 2) - 10) " w20 h20 0x200 Center BackgroundTrans", Chr(0xE700))

                bg := this.DragGui.Add("Text", "x0 y0 w" (this.W - 14) " h" this.RowH " BackgroundTrans", "")
                fakeList := { Inner: this.DragGui, Outer: this.Outer, Data: this.Data }
                cb := this.RenderRowCb
                cb(fakeList, this.Data[this.DragIdx], this.DragIdx, 0, this.W - 14, bg)

                this.DragGui.Show("NoActivate x" (mX + 15) " y" (mY - (this.RowH / 2)) " w" (this.W - 14) " h" this.RowH)
                this.DragStartY := mY
                this.SnapLine.Visible := false
                this.SnapHL.Visible := false
                this.SnapTargetIdx := 0
            }
        }

        if (this.DragMode) {
            if (!isClicking) {
                this.DragMode := false
                if (this.DragGui)
                    this.DragGui.Destroy()
                this.SnapLine.Visible := false
                this.SnapHL.Visible := false

                if (this.SnapTargetIdx > 0 && this.DragIdx != this.SnapTargetIdx) {
                    if (this.CustomSwapCb) {
                        cb := this.CustomSwapCb
                        cb(this.DragIdx, this.SnapTargetIdx, this, this.SnapType)
                    } else {
                        if (this.SnapType == "Before") {
                            item := this.Data.RemoveAt(this.DragIdx)
                            adj := (this.SnapTargetIdx > this.DragIdx) ? (this.SnapTargetIdx - 1) : this.SnapTargetIdx
                            this.Data.InsertAt(adj, item)
                        } else if (this.SnapType == "After") {
                            item := this.Data.RemoveAt(this.DragIdx)
                            adj := (this.SnapTargetIdx > this.DragIdx) ? this.SnapTargetIdx : (this.SnapTargetIdx + 1)
                            this.Data.InsertAt(adj, item)
                        }
                        this.Render()
                        if (this.OnUpdateCb) {
                            cbD := this.OnUpdateCb
                            cbD()
                        }
                    }
                }
            } else {
                this.DragGui.Move(mX + 10, mY - (this.RowH / 2))

                if (relY < 20) {
                    this.ScrollY -= Min(15, this.ScrollY)
                    this.ClampScroll()
                    this.UpdateScrollbar()
                } else if (relY > this.H - 20) {
                    this.ScrollY += Min(15, this.MaxScroll - this.ScrollY)
                    this.ClampScroll()
                    this.UpdateScrollbar()
                }

                innerY := relY + this.ScrollY
                this.SnapTargetIdx := 0
                this.SnapType := ""

                if (relX >= -10 && relX <= this.W + 10 && innerY >= 0 && innerY <= (this.Data.Length * this.RowH)) {
                    for i, g in this.Grabbers {
                        if (innerY >= g.StartY && innerY <= g.StartY + this.RowH) {
                            this.SnapTargetIdx := g.Idx
                            isFold := this.Data[g.Idx].HasProp("IsFolder") && this.Data[g.Idx].IsFolder
                            yDist := innerY - g.StartY

                            if (isFold && yDist > (this.RowH * 0.25) && yDist < (this.RowH * 0.75)) {
                                this.SnapType := "Into"
                                this.SnapHL.Move(0, g.StartY)
                                this.SnapHL.Visible := true
                                this.SnapLine.Visible := false
                            } else if (yDist <= this.RowH / 2) {
                                this.SnapType := "Before"
                                this.SnapLine.Move(0, g.StartY - 1)
                                this.SnapLine.Visible := true
                                this.SnapHL.Visible := false
                            } else {
                                this.SnapType := "After"
                                this.SnapLine.Move(0, g.StartY + this.RowH - 1)
                                this.SnapLine.Visible := true
                                this.SnapHL.Visible := false
                            }
                            break
                        }
                    }
                } else {
                    this.SnapLine.Visible := false
                    this.SnapHL.Visible := false
                    this.SnapTargetIdx := 0
                }
            }
        }


        if (this.IsDragging) {
            if (!isClicking) {
                this.IsDragging := false
            } else {
                dy := mY - this.DragStartY
                if (dy != 0) {
                    thumbH := Round(Max(20, (this.H / (this.MaxScroll + this.H)) * this.H))
                    sr := this.MaxScroll > 0 ? this.MaxScroll / (Max(1, this.H - thumbH)) : 0
                    this.ScrollY := Round(this.DragStartScroll + (dy * sr))
                    this.ClampScroll()
                    this.UpdateScrollbar()
                }
            }
        }

        this.WasClicking := isClicking
    }

    UpdateScrollbar() {
        if (this.MaxScroll == 0) {
            this.SbThumb.Visible := false
            this.SbTrack.Visible := false
            return
        }
        this.SbThumb.Visible := true
        this.SbTrack.Visible := true

        thumbH := Round(Max(20, (this.H / (this.MaxScroll + this.H)) * this.H))
        pct := (this.MaxScroll > 0) ? (this.ScrollY / this.MaxScroll) : 0
        thumbY := Round(pct * (this.H - thumbH))

        try this.SbThumb.Move(, thumbY, , thumbH)
    }
}
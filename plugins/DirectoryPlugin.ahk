#Include ../overdock.ahk

class DirectoryPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Provides shortcuts to specific folders."
    W := 40

    Render(gui, align, x, h, w) {
        if (w <= 0) w := Round(this.W * this.App.Scale)
            iconHex := this.GetConfig("Icon", "E8D5")

        gui.SetFont("s15 q5 c" Config.Theme.Icon, Config.Theme.IconFont)
        this.Btn := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", Chr("0x" iconHex))
        this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)

        this.Btn.OnEvent("Click", (*) => this.HandleClick())
        this.Btn.OnEvent("ContextMenu", (*) => this.ShowSettings())

        this.CbWheel := ObjBindMethod(this, "OnWheel")
        OnMessage(0x020A, this.CbWheel)
        return w
    }

    MoveCtrls(x, w) {
        this.Btn.Move(x, , w)
    }

    HandleClick() {
        path := this.GetConfig("Path", "")
        if (!path || !DirExist(path)) {
            this.ShowSettings()
            return
        }

        if (HasProp(this, "MenuCache") && this.MenuCache) {
            for k, g in this.MenuCache
                try g.Gui.Destroy()
        }
        this.MenuCache := Map()

        this.DropGui := this.CreateMenu(path, this.App.Gui.Hwnd, &dW, &dH)
        this.DW := dW, this.DH := dH

        if this.DropGui
            this.App.TogglePopup(this.DropGui, this.Btn.Hwnd, this.DW, this.DH)
    }

    HideRecursive(mGui) {
        if !(mGui.HasProp("ActiveChild") && mGui.ActiveChild)
            return
        this.HideRecursive(mGui.ActiveChild)
        try mGui.ActiveChild.Hide()
        mGui.ActiveChild := 0
        mGui.ActiveChildPath := ""
    }

    CreateMenu(rootPath, parentHwnd, &outW, &outH) {
        if this.MenuCache.Has(rootPath) {
            c := this.MenuCache[rootPath]
            outW := c.DW, outH := c.DH
            return c.Gui
        }

        s := this.App.Scale
        dW := Round(240 * s)
        maxH := this.GetConfig("MaxHeight", 600) * s
        useFolders := this.GetConfig("Nested", 1)

        menuGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" parentHwnd)
        menuGui.BackColor := Config.Theme.DropBg
        menuGui.MarginX := 0, menuGui.MarginY := 0
        menuGui.ActiveChild := 0
        menuGui.OnCloseCb := (*) => this.HideRecursive(menuGui)

        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", menuGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", menuGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        innerGui := Gui("-Caption -DPIScale +Parent" menuGui.Hwnd)
        innerGui.BackColor := Config.Theme.DropBg
        innerGui.MarginX := 0, innerGui.MarginY := 0

        yP := Round(5 * s), rH := Round(35 * s)

        allFiles := []
        Loop Files, rootPath "\*", "DF"
            allFiles.Push({ Name: A_LoopFileName, Path: A_LoopFilePath, IsDir: InStr(A_LoopFileAttrib, "D") })

        if (this.GetConfig("FoldersFirst", 1)) {
            dirs := [], fils := []
            for item in allFiles
                (item.IsDir ? dirs.Push(item) : fils.Push(item))
            allFiles := dirs
            for item in fils
                allFiles.Push(item)
        }

        hasItems := allFiles.Length > 0
        for itemObj in allFiles {
            itemName := itemObj.Name
            isDir := itemObj.IsDir
            itemPath := itemObj.Path

            bg := innerGui.Add("Text", "x0 y" yP " w" dW " h" rH " BackgroundTrans", "")

            iH := isDir ? "E8D5" : "E7C3"
            if (!isDir && (InStr(itemName, ".lnk") || InStr(itemName, ".url")))
                iH := "E71B"

            grp := []
            loadIcons := this.GetConfig("LoadIcons", 0)
            addedIco := false
            if (loadIcons) {
                sfi := Buffer(A_PtrSize + 688)
                DllCall("Shell32\SHGetFileInfoW", "WStr", itemPath, "UInt", isDir ? 0x10 : 0x80, "Ptr", sfi, "UInt", sfi.Size, "UInt", 0x111)
                if (hIco := NumGet(sfi, 0, "Ptr")) {
                    picSize := Round(18 * s)
                    pY := yP + (rH / 2) - (picSize / 2)
                    iL := innerGui.Add("Picture", "x" Round(20 * s) " y" pY " w" picSize " h" picSize " BackgroundTrans", "HICON:" hIco)
                    addedIco := true
                }
            }
            if (!addedIco) {
                innerGui.SetFont("s" Round(13 * s) " q5 c" Config.Theme.Text, Config.Theme.IconFont)
                iL := innerGui.Add("Text", "x" Round(15 * s) " y" yP " w" Round(30 * s) " h" rH " 0x200 BackgroundTrans", Chr("0x" iH))
            }
            grp.Push(iL.Hwnd)

            innerGui.SetFont("s" Round(11 * s) " w400 q5 c" Config.Theme.Text, Config.Theme.Font)
            tW := isDir && useFolders ? Round(150 * s) : Round(180 * s)
            tL := innerGui.Add("Text", "x" Round(45 * s) " y" yP " w" tW " h" rH " 0x200 BackgroundTrans", isDir ? itemName : RegExReplace(itemName, "\.(lnk|url)$", ""))
            grp.Push(tL.Hwnd)

            if (isDir && useFolders) {
                innerGui.SetFont("s" Round(10 * s) " q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.IconFont)
                aL := innerGui.Add("Text", "x" (dW - Round(30 * s)) " y" yP " w" Round(20 * s) " h" rH " 0x200 Center BackgroundTrans", Chr(0xE76C))
                grp.Push(aL.Hwnd)

                showSub := ((bgHwnd, mGui, mPath, xOffset, *) => (
                    (mGui.HasProp("ActiveChildPath") && mGui.ActiveChildPath == mPath) ? 0 : (
                        (mGui.ActiveChild) ? this.HideRecursive(mGui) : 0,
                        subG := this.CreateMenu(mPath, mGui.Hwnd, &sW, &sH),
                        mGui.ActiveChild := subG,
                        mGui.ActiveChildPath := mPath,
                        WinGetPos(&mX, , , , mGui.Hwnd),
                        WinGetPos(, &cY, , , bgHwnd),
                        this.ShowSubMenuSafely(subG, sW, sH, mX, cY, xOffset)
                    )
                )).Bind(bg.Hwnd, menuGui, itemPath, dW)

                this.RegisterHover(bg.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp, showSub)
                for ctrlHwnd in grp
                    this.RegisterHover(ctrlHwnd, Config.Theme.Text, Config.Theme.IconHover, grp, showSub)

                bg.OnEvent("Click", showSub), iL.OnEvent("Click", showSub), tL.OnEvent("Click", showSub), aL.OnEvent("Click", showSub)
            } else {
                hideSub := ((mGui, *) => this.HideRecursive(mGui)).Bind(menuGui)
                this.RegisterHover(bg.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp, hideSub)
                for ctrlHwnd in grp
                    this.RegisterHover(ctrlHwnd, Config.Theme.Text, Config.Theme.IconHover, grp, hideSub)

                act := ((mPath, mDir, *) => (this.App.ClosePopup(), Run((mDir ? "explorer.exe `"" : "`"") mPath "`""))).Bind(itemPath, isDir)
                bg.OnEvent("Click", act)
                if (iL)
                    iL.OnEvent("Click", act)
                tL.OnEvent("Click", act)
            }

            yP += rH
        }

        if (!hasItems) {
            innerGui.SetFont("s" Round(11 * s) " w400 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.Font)
            innerGui.Add("Text", "x0 y" yP " w" dW " h" rH " 0x200 Center BackgroundTrans", "(Empty)")
            yP += rH
        }

        innerH := yP + Round(5 * s)
        outerH := innerH > maxH ? maxH : innerH

        iW := (innerH > maxH) ? dW - Round(4 * s) : dW
        innerGui.Show("x0 y0 w" iW " h" innerH " NoActivate")

        if (innerH > maxH) {
            trackW := Round(4 * s)
            trackX := dW - trackW
            menuGui.Add("Text", "x" trackX " y0 w" trackW " h" outerH " Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 10))
            thumbH := Round(Max(20 * s, (outerH / innerH) * outerH))
            menuGui.ScrollThumb := menuGui.Add("Text", "x" trackX " y0 w" trackW " h" thumbH " Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 30))
        }

        outW := dW, outH := outerH

        menuGui.InnerGui := innerGui
        menuGui.InnerH := innerH
        menuGui.OuterH := outerH

        this.MenuCache[rootPath] := { Gui: menuGui, DW: outW, DH: outH }
        return menuGui
    }

    ShowSubMenuSafely(subG, sW, sH, mX, cY, xOffset) {
        s := this.App.Scale
        targetX := mX + xOffset - Round(5 * s)
        targetY := cY

        monCount := MonitorGetCount()
        L := 0, T := 0, R := A_ScreenWidth, B := A_ScreenHeight
        closestDist := 0xFFFFFFFF

        Loop monCount {
            MonitorGet(A_Index, &mL, &mT, &mR, &mB)
            cx := mX + (xOffset / 2)
            if (mX >= mL && mX <= mR && cY >= mT && cY <= mB) {
                L := mL, T := mT, R := mR, B := mB
                break
            }
            dx := Max(mL - cx, 0, cx - mR)
            dy := Max(mT - cY, 0, cY - mB)
            dist := dx * dx + dy * dy
            if (dist < closestDist) {
                closestDist := dist
                L := mL, T := mT, R := mR, B := mB
            }
        }

        if (targetX + sW > R) {
            altX := mX - sW + Round(5 * s)
            if (altX >= L)
                targetX := altX
            else
                targetX := R - sW
        }

        if (targetY + sH > B)
            targetY := B - sH
        if (targetY < T)
            targetY := T

        subG.Show("NA x" targetX " y" targetY " w" sW " h" sH)
    }

    OnWheel(wParam, lParam, msg, hwnd) {
        if !HasProp(this, "MenuCache") || !this.MenuCache
            return

        try MouseGetPos(, , &mWin)
        catch
            return

        tGui := 0
        for k, c in this.MenuCache {
            if (c.Gui.Hwnd == mWin || (c.Gui.HasProp("InnerGui") && c.Gui.InnerGui.Hwnd == mWin)) {
                tGui := c.Gui
                break
            }
        }

        if !tGui || !tGui.HasProp("InnerGui") || tGui.InnerH <= tGui.OuterH
            return

        dir := (wParam << 32 >> 48) > 0 ? 1 : -1
        step := 40 * this.App.Scale

        inner := tGui.InnerGui
        ControlGetPos(, &cY, , , inner.Hwnd)
        nY := cY + (dir * step)
        if (nY > 0)
            nY := 0
        if (nY < tGui.OuterH - tGui.InnerH)
            nY := tGui.OuterH - tGui.InnerH

        inner.Move(, nY)

        if (tGui.HasProp("ScrollThumb") && tGui.ScrollThumb) {
            ratio := Abs(nY) / (tGui.InnerH - tGui.OuterH)
            ControlGetPos(, , , &tH, tGui.ScrollThumb.Hwnd)
            tY := ratio * (tGui.OuterH - tH)
            tGui.ScrollThumb.Move(, tY)
        }
    }

    ShowSettings() {
        s := this.App.Scale
        ag := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale")
        ag.BackColor := Config.Theme.DropBg
        ag.MarginX := 0, ag.MarginY := 0
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 19, "Int*", 1, "Int", 4)

        W := Round(300 * s)
        ag.SetFont("s" Round(12 * s) " w600 q5 c" Config.Theme.Text, Config.Theme.Font)
        ag.Add("Text", "x" Round(15 * s) " y" Round(15 * s) " w" (W - Round(30 * s)) " h" Round(25 * s) " BackgroundTrans", this.__Class " Settings")

        yP := Round(45 * s)
        ag.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.Text, Config.Theme.Font)
        ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(60 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Icon Hex:")

        iconHex := StrReplace(this.GetConfig("Icon", "E8D5"), "#", "")
        eIc := ag.Add("Edit", "x" Round(80 * s) " y" yP " w" Round(165 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", iconHex)
        ag.SetFont("s" Round(12 * s) " q5 cWhite", Config.Theme.IconFont)
        bg := ag.Add("Text", "x" Round(255 * s) " y" yP " w" Round(25 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), Chr("0x" iconHex))
        eIc.OnEvent("Change", (*) => (StrLen(eIc.Value) == 4 ? (bg.Value := Chr("0x" eIc.Value)) : 0))

        yP += Round(35 * s)
        ag.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.Text, Config.Theme.Font)
        ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(150 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Target Directory:")
        curPath := this.GetConfig("Path", "")
        yP += Round(30 * s)
        ePath := ag.Add("Edit", "x" Round(15 * s) " y" yP " w" Round(270 * s) " h" Round(25 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", curPath)

        yP += Round(35 * s)
        btnF := ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(130 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "Browse Folder...")
        btnF.OnEvent("Click", (*) => (
            this.App.IgnoreClicksUntil := A_TickCount + 999999,
            sel := DirSelect("*" ePath.Value, 0, "Select a Directory"),
            this.App.IgnoreClicksUntil := 0,
            sel ? ePath.Value := sel : 0
        ))
        btnO := ag.Add("Text", "x" Round(155 * s) " y" yP " w" Round(130 * s) " h" Round(25 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "Open in Explorer")
        btnO.OnEvent("Click", (*) => (ePath.Value != "" && DirExist(ePath.Value) ? Run("explorer.exe `"" ePath.Value "`"") : 0))

        yP += Round(35 * s)
        ag.SetFont("s" Round(12 * s) " q5 cWhite", Config.Theme.IconFont)
        cBoxBg := ag.Add("Text", "x" Round(15 * s) " y" (yP - Round(2 * s)) " w" Round(200 * s) " h" Round(25 * s) " BackgroundTrans", "")
        nestedChecked := this.GetConfig("Nested", 1)
        cBoxIc := ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(20 * s) " h" Round(25 * s) " BackgroundTrans", Chr(nestedChecked ? 0xE73A : 0xE739))

        ag.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.Text, Config.Theme.Font)
        cBoxText := ag.Add("Text", "x" Round(40 * s) " y" Round(yP + 3 * s) " w" Round(160 * s) " h" Round(20 * s) " BackgroundTrans", "Work with folders (nested)")

        togNested := (*) => (
            nestedChecked := !nestedChecked,
            cBoxIc.Value := Chr(nestedChecked ? 0xE73A : 0xE739)
        )
        cBoxBg.OnEvent("Click", togNested), cBoxIc.OnEvent("Click", togNested), cBoxText.OnEvent("Click", togNested)

        yP += Round(35 * s)
        ag.SetFont("s" Round(12 * s) " q5 cWhite", Config.Theme.IconFont)
        fBoxBg := ag.Add("Text", "x" Round(15 * s) " y" (yP - Round(2 * s)) " w" Round(250 * s) " h" Round(25 * s) " BackgroundTrans", "")
        foldersFirstChecked := this.GetConfig("FoldersFirst", 1)
        fBoxIc := ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(20 * s) " h" Round(25 * s) " BackgroundTrans", Chr(foldersFirstChecked ? 0xE73A : 0xE739))

        ag.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.Text, Config.Theme.Font)
        fBoxText := ag.Add("Text", "x" Round(40 * s) " y" Round(yP + 3 * s) " w" Round(200 * s) " h" Round(20 * s) " BackgroundTrans", "Show directories at top")

        togFFirst := (*) => (
            foldersFirstChecked := !foldersFirstChecked,
            fBoxIc.Value := Chr(foldersFirstChecked ? 0xE73A : 0xE739)
        )
        fBoxBg.OnEvent("Click", togFFirst), fBoxIc.OnEvent("Click", togFFirst), fBoxText.OnEvent("Click", togFFirst)

        yP += Round(35 * s)
        ag.SetFont("s" Round(12 * s) " q5 cWhite", Config.Theme.IconFont)
        iBoxBg := ag.Add("Text", "x" Round(15 * s) " y" (yP - Round(2 * s)) " w" Round(250 * s) " h" Round(25 * s) " BackgroundTrans", "")
        loadIconsChecked := this.GetConfig("LoadIcons", 0)
        iBoxIc := ag.Add("Text", "x" Round(15 * s) " y" yP " w" Round(20 * s) " h" Round(25 * s) " BackgroundTrans", Chr(loadIconsChecked ? 0xE73A : 0xE739))

        ag.SetFont("s" Round(10 * s) " w400 q5 c" Config.Theme.Text, Config.Theme.Font)
        iBoxText := ag.Add("Text", "x" Round(40 * s) " y" Round(yP + 3 * s) " w" Round(200 * s) " h" Round(20 * s) " BackgroundTrans", "Load OS Icons (slower)")

        togLoad := (*) => (
            loadIconsChecked := !loadIconsChecked,
            iBoxIc.Value := Chr(loadIconsChecked ? 0xE73A : 0xE739)
        )
        iBoxBg.OnEvent("Click", togLoad), iBoxIc.OnEvent("Click", togLoad), iBoxText.OnEvent("Click", togLoad)

        yP += Round(35 * s)
        ag.Add("Text", "x" Round(15 * s) " y" (yP + 3 * s) " w" Round(150 * s) " h" Round(25 * s) " 0x200 BackgroundTrans", "Max Height (px):")
        vMax := this.GetConfig("MaxHeight", 600)
        eMax := ag.Add("Edit", "x" Round(155 * s) " y" yP " w" Round(130 * s) " h" Round(25 * s) " -E0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite Number", vMax)

        yP += Round(45 * s)
        ac := StrReplace(Config.Theme.Slider, "#", "")
        ag.SetFont("s" Round(11 * s) " w600 q5 cWhite", Config.Theme.Font)
        btnSave := ag.Add("Text", "x" Round(15 * s) " y" yP " w" (W - Round(30 * s)) " h" Round(30 * s) " 0x200 Center Background" ac, "Save && Apply")

        btnSave.OnEvent("Click", (*) => (
            this.SetConfig("Icon", eIc.Value),
            this.SetConfig("Path", ePath.Value),
            this.SetConfig("Nested", nestedChecked),
            this.SetConfig("FoldersFirst", foldersFirstChecked),
            this.SetConfig("LoadIcons", loadIconsChecked),
            this.SetConfig("MaxHeight", eMax.Value),
            ag.Destroy(),
            ApplyDynamicSettings()
        ))

        ag.SetFont("s" Round(12 * s) " q5 c" Config.Theme.Icon, Config.Theme.IconFont)
        btnExit := ag.Add("Text", "x" (W - Round(35 * s)) " y" Round(10 * s) " w" Round(25 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans", Chr(0xE711))
        btnExit.OnEvent("Click", (*) => ag.Destroy())

        if IsSet(TopBar) {
            TopBar.RegisterHover(btnF.Hwnd, "FFFFFF", "E0E0E0")
            TopBar.RegisterHover(btnO.Hwnd, "FFFFFF", "E0E0E0")
            TopBar.RegisterHover(btnSave.Hwnd, "FFFFFF", "E0E0E0")
            TopBar.RegisterHover(btnExit.Hwnd, StrReplace(Config.Theme.Icon, "#", ""), StrReplace(Config.Theme.Danger, "#", ""))
        }

        newH := yP + Round(45 * s)
        ag.Opt("+Owner" this.App.Gui.Hwnd)
        this.App.TogglePopup(ag, IsSet(triggerHwnd) ? triggerHwnd : this.Btn.Hwnd, W, newH)
    }
}
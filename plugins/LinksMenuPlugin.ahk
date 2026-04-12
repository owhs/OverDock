#Include ../overdock.ahk

class LinksMenuPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Launch the Windows start menu."
    W := 40
    Render(gui, align, x, h, w) {
        if (w <= 0) w := Round(this.W * this.App.Scale)
            homeIcn := Config.General.HomeIcon
        isPath := FileExist(homeIcn) || InStr(homeIcn, ":") || InStr(homeIcn, ".")

        if (isPath) {
            picSize := Round(26 * this.App.Scale)
            pX := x + (w / 2) - (picSize / 2)
            pY := (h / 2) - (picSize / 2)
            this.Btn := this.AddCtrl(gui, "Picture", "x" pX " y" pY " w" picSize " h" picSize " BackgroundTrans", homeIcn)
            this.RegisterHover(this.Btn.Hwnd, "", "", [])
        } else {
            gui.SetFont("s14 q5 c" Config.Theme.Icon, Config.Theme.IconFont)
            this.Btn := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", Chr("0x" homeIcn))
            this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)
        }

        this.BuildDrop()

        showMain() {
            if (this.DropGui.HasProp("ActiveChild") && this.DropGui.ActiveChild)
                this.HideRecursive(this.DropGui)
            this.App.TogglePopup(this.DropGui, this.Btn.Hwnd, this.DW, this.DH)
        }
        this.Btn.OnEvent("Click", (*) => showMain())
        this.Btn.OnEvent("ContextMenu", (*) => OpenSettingsGUI(4))
        return w
    }

    MoveCtrls(x, w) {
        homeIcn := Config.General.HomeIcon
        isPath := FileExist(homeIcn) || InStr(homeIcn, ":") || InStr(homeIcn, ".")
        if (isPath) {
            picSize := Round(26 * this.App.Scale)
            pX := x + (w / 2) - (picSize / 2)
            this.Btn.Move(pX, , picSize)
        } else {
            this.Btn.Move(x, , w)
        }
    }

    HideRecursive(mGui) {
        if !(mGui.HasProp("ActiveChild") && mGui.ActiveChild)
            return
        this.HideRecursive(mGui.ActiveChild)
        try mGui.ActiveChild.Hide()
        mGui.ActiveChild := 0
    }

    BuildDrop() {
        this.LinkMap := Map()
        rootItems := []
        for item in Config.Links {
            pId := item.HasProp("ParentId") ? item.ParentId : "None"
            if (pId == "" || pId == "None")
                rootItems.Push(item)
            else {
                if !this.LinkMap.Has(pId)
                    this.LinkMap[pId] := []
                this.LinkMap[pId].Push(item)
            }
        }

        this.DropGui := this.CreateMenu(rootItems, this.App.Gui.Hwnd, &dW, &dH)
        this.DW := dW, this.DH := dH
    }

    CreateMenu(items, parentHwnd, &outW, &outH) {
        s := this.App.Scale
        menuGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" parentHwnd)
        menuGui.BackColor := Config.Theme.DropBg
        menuGui.MarginX := 0, menuGui.MarginY := Round(5 * s)
        menuGui.ActiveChild := 0
        menuGui.OnCloseCb := (*) => this.HideRecursive(menuGui)

        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", menuGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", menuGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        yP := Round(5 * s), rH := Round(35 * s), dW := Round(240 * s)

        for item in items {
            isFold := item.HasProp("IsFolder") && item.IsFolder
            bg := menuGui.Add("Text", "x0 y" yP " w" dW " h" rH " BackgroundTrans", "")

            if (HasProp(item, "IsImage") && item.IsImage && FileExist(item.RawIcon)) {
                picSize := Round(20 * s)
                pY := yP + (rH / 2) - (picSize / 2)
                iL := menuGui.Add("Picture", "x" Round(20 * s) " y" pY " w" picSize " h" picSize " BackgroundTrans", item.RawIcon)
            } else {
                menuGui.SetFont("s" Round(13 * s) " q5 c" Config.Theme.Text, Config.Theme.IconFont)
                iL := menuGui.Add("Text", "x" Round(15 * s) " y" yP " w" Round(30 * s) " h" rH " 0x200 BackgroundTrans", isFold ? Chr(0xE8B7) : item.Icon)
            }

            menuGui.SetFont("s" Round(11 * s) " w400 q5 c" Config.Theme.Text, Config.Theme.Font)
            tL := menuGui.Add("Text", "x" Round(45 * s) " y" yP " w" Round(170 * s) " h" rH " 0x200 BackgroundTrans", item.Name)

            if (isFold) {
                menuGui.SetFont("s" Round(10 * s) " q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.IconFont)
                aL := menuGui.Add("Text", "x" (dW - Round(30 * s)) " y" yP " w" Round(20 * s) " h" rH " 0x200 Center BackgroundTrans", Chr(0xE76C))
            }

            grp := [iL.Hwnd, tL.Hwnd]
            if (isFold)
                grp.Push(aL.Hwnd)

            if (isFold) {
                subItems := this.LinkMap.Has(item.Id) ? this.LinkMap[item.Id] : []
                subGui := this.CreateMenu(subItems, menuGui.Hwnd, &sW, &sH)

                showSub := ((bgHwnd, subG, mGui, xOffset, *) => (
                    (mGui.ActiveChild && mGui.ActiveChild != subG) ? this.HideRecursive(mGui) : 0,
                    mGui.ActiveChild := subG,
                    WinGetPos(&mX, &mY, , , mGui.Hwnd),
                    ControlGetPos(&cX, &cY, , , bgHwnd),
                    subG.Show("NA x" (mX + xOffset - Round(5 * s)) " y" (mY + cY))
                )).Bind(bg.Hwnd, subGui, menuGui, dW)

                this.RegisterHover(bg.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp, showSub)
                this.RegisterHover(iL.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp, showSub)
                this.RegisterHover(tL.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp, showSub)

                bg.OnEvent("Click", showSub), iL.OnEvent("Click", showSub), tL.OnEvent("Click", showSub)
            } else {
                hideSub := ((mGui, *) => this.HideRecursive(mGui)).Bind(menuGui)
                this.RegisterHover(bg.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp, hideSub)
                this.RegisterHover(iL.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp, hideSub)
                this.RegisterHover(tL.Hwnd, Config.Theme.Text, Config.Theme.IconHover, grp, hideSub)

                act := this.MakeAction(item)
                bg.OnEvent("Click", act), iL.OnEvent("Click", act), tL.OnEvent("Click", act)
            }

            yP += rH
        }

        if (items.Length == 0) {
            menuGui.SetFont("s" Round(11 * s) " w400 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.Font)
            menuGui.Add("Text", "x0 y" yP " w" dW " h" rH " 0x200 Center BackgroundTrans", "(Empty)")
            yP += rH
        }

        outW := dW, outH := yP + Round(5 * s)
        return menuGui
    }

    MakeAction(item) {
        cmd := item.Target
        args := item.HasProp("RunArgs") ? item.RunArgs : ""
        dr := item.HasProp("RunDir") ? item.RunDir : ""
        st := item.HasProp("RunState") ? item.RunState : "Normal"
        strStat := (st == "Maximized") ? "Max" : ((st == "Minimized") ? "Min" : ((st == "Hidden") ? "Hide" : ""))

        return (*) => (
            this.App.ClosePopup(),
            (cmd == "Reload" ? Reload() : (cmd == "ExitApp" ? ExitApp() : Run(cmd (args ? " " args : ""), dr, strStat)))
        )
    }
}
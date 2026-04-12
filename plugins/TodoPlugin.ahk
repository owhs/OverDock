#Include ../overdock.ahk

class TodoPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Manage tasks directly from the bar."
    W := 40

    ReqWidth() {
        return super.ReqWidth()
    }

    Render(gui, align, x, h, w) {
        s := this.App.Scale
        if (w <= 0) w := Round(this.W * s)
            gui.SetFont("s13 q5 c" Config.Theme.Icon, Config.Theme.IconFont)
        this.Btn := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", Chr(0xE73A))
        this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)

        this.Btn.OnEvent("Click", (*) => this.ShowPopup())
        return w
    }

    MoveCtrls(x, w) {
        this.Btn.Move(x, , w)
    }

    LoadTasks() {
        if (!HasProp(this, "Tasks"))
            this.Tasks := []
        else
            return

        try {
            str := IniRead(IniFile, "TodoData", "Tasks", "")
            if (str == "") {
                this.Tasks := [{ Name: "Continue to be awesome", Cat: "Inbox", Done: true }, { Name: "Review pending pull requests", Cat: "Work", Done: false }, { Name: "Update styling tokens", Cat: "Dev", Done: false }
                ]
            } else {
                for line in StrSplit(str, "###") {
                    if !line
                        continue
                    parts := StrSplit(line, "|")
                    if (parts.Length >= 3)
                        this.Tasks.Push({ Name: parts[1], Cat: parts[2], Done: (parts[3] == "1") })
                }
            }
        } catch {
            this.Tasks := []
        }
    }

    SaveTasks() {
        str := ""
        for t in this.Tasks {
            str .= "###" t.Name "|" t.Cat "|" (t.Done ? "1" : "0")
        }
        IniWrite(str, IniFile, "TodoData", "Tasks")
    }

    ShowPopup() {
        s := this.App.Scale
        this.DropGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" this.App.Gui.Hwnd)
        this.DropGui.BackColor := Config.Theme.DropBg
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.DropGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.DropGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        this.PW := Round(300 * s)

        ; Header
        this.DropGui.SetFont("s" Round(12 * s) " w600 q5 c" Config.Theme.IconHover, Config.Theme.IconFont)
        this.DropGui.Add("Text", "x" Round(15 * s) " y" Round(15 * s) " w" Round(20 * s) " h" Round(25 * s) " BackgroundTrans", Chr(0xE73A))

        this.DropGui.SetFont("s" Round(11 * s) " w600 q5 c" Config.Theme.DropText, Config.Theme.Font)
        this.DropGui.Add("Text", "x" Round(40 * s) " y" Round(15 * s) " w" Round(150 * s) " h" Round(25 * s) " BackgroundTrans", "Todoist")

        this.DropGui.Add("Text", "x" Round(15 * s) " y" Round(45 * s) " w" (this.PW - Round(30 * s)) " h1 0x0100 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25), "")

        yP := Round(55 * s)

        ; Add Task Input
        this.DropGui.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)
        this.eTask := this.DropGui.Add("Edit", "x" Round(15 * s) " y" yP " w" (this.PW - Round(135 * s)) " h" Round(30 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " cWhite", "")

        this.DropGui.SetFont("s" Round(9 * s) " w400 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.Font)
        this.eCat := this.DropGui.Add("Edit", "x" (this.PW - Round(110 * s)) " y" yP " w" Round(55 * s) " h" Round(30 * s) " -E0x200 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) " c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " Center", "Inbox")

        this.DropGui.SetFont("s" Round(14 * s) " w600 q5 cWhite", Config.Theme.IconFont)
        btnAdd := this.DropGui.Add("Text", "x" (this.PW - Round(45 * s)) " y" yP " w" Round(30 * s) " h" Round(30 * s) " 0x200 Center Background" StrReplace(Config.Theme.IconHover, "#", ""), Chr(0xE710))
        this.App.RegisterHover(btnAdd.Hwnd, "FFFFFF", "E0E0E0")
        if IsSet(AppCursorMap)
            AppCursorMap[btnAdd.Hwnd] := 1

        yP += Round(45 * s)

        this.LoadTasks()

        if (HasProp(this, "SList") && this.SList) {
            try this.SList.Destroy()
        }

        renderRow := ObjBindMethod(this, "RenderTaskRow")
        this.SList := SexyList(this.DropGui, 0, yP, this.PW, Round(210 * s), this.Tasks, renderRow, (*) => this.SaveTasks())
        this.SList.RowH := Round(45 * s)
        try this.SList.Outer.BackColor := Config.Theme.DropBg
        try this.SList.Inner.BackColor := Config.Theme.DropBg
        this.SList.Render()

        btnAdd.OnEvent("Click", (*) => (
            val := Trim(this.eTask.Value),
            cVal := Trim(this.eCat.Value),
            (cVal == "") ? cVal := "Inbox" : 0,
            (val != "") ? (
                this.Tasks.InsertAt(1, { Name: StrReplace(StrReplace(val, "|"), "###"), Cat: StrReplace(StrReplace(cVal, "|"), "###"), Done: false }),
                this.eTask.Value := "",
                this.SList.Render(),
                this.SaveTasks()
            ) : 0
        ))

        this.DropGui.OnEvent("Close", (*) => (HasProp(this, "SList") ? this.SList.Destroy() : 0))
        this.DropGui.OnEvent("Escape", (*) => (HasProp(this, "SList") ? this.SList.Destroy() : 0))

        this.App.TogglePopup(this.DropGui, this.Btn.Hwnd, this.PW, yP + Round(210 * s))
    }

    RenderTaskRow(listObj, t, idx, yP, w, bg) {
        s := this.App.Scale
        g := listObj.Inner
        pw := this.PW
        bg.Opt("BackgroundTrans 0x0100")

        ; Physically truncate the row background so it CANNOT artificially catch clicks over the trash icon!
        bg.Move(, , pw - Round(50 * s))

        cIcn := t.Done ? BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25) : BlendHex(Config.Theme.Text, Config.Theme.DropBg, 50)
        g.SetFont("s" Round(14 * s) " q5 c" cIcn, Config.Theme.IconFont)
        icn := g.Add("Text", "x" Round(25 * s) " y" (yP + Round(12 * s)) " w" Round(20 * s) " h" Round(20 * s) " BackgroundTrans Center", t.Done ? Chr(0xE73E) : Chr(0xE739))

        fntOpt := "s" Round(10 * s) " w500 q5 c" (t.Done ? BlendHex(Config.Theme.Text, Config.Theme.DropBg, 50) : "White")
        g.SetFont(fntOpt, Config.Theme.Font)
        txt := g.Add("Text", "x" Round(55 * s) " y" (yP + Round(8 * s)) " w" (pw - Round(110 * s)) " h" Round(20 * s) " BackgroundTrans", t.Name)

        if (t.Done) {
            tw := this.App.MeasureTextWidth(t.Name, "s" Round(10 * s) " w500 q5", Config.Theme.Font)
            maxW := pw - Round(110 * s)
            actW := (tw / s > maxW) ? maxW : (tw / s)
            g.Add("Text", "x" Round(55 * s) " y" (yP + Round(18 * s)) " w" Round(actW) " h" Max(1, Round(1 * s)) " Background888888", "")
        }

        g.SetFont("s" Round(8 * s) " w600 q5 c777777", Config.Theme.Font)
        cat := g.Add("Text", "x" Round(55 * s) " y" (yP + Round(26 * s)) " w" Round(100 * s) " h" Round(15 * s) " BackgroundTrans", t.Cat)

        g.SetFont("s" Round(12 * s) " q5 c" StrReplace(Config.Theme.Icon, "#", ""), Config.Theme.IconFont)
        trash := g.Add("Text", "x" (pw - Round(50 * s)) " y" yP " w" Round(50 * s) " h" Round(45 * s) " 0x0100 +0x0200 Center", Chr(0xE74D))

        togAct := ((item, *) => (item.Done := !item.Done, listObj.Render(), this.SaveTasks())).Bind(t)
        icn.OnEvent("Click", togAct), txt.OnEvent("Click", togAct), bg.OnEvent("Click", togAct)
        cat.OnEvent("Click", togAct)

        delAct := ((i, lObj, *) => (this.Tasks.RemoveAt(i), lObj.Render(), this.SaveTasks())).Bind(idx, listObj)
        trash.OnEvent("Click", delAct)

        if IsSet(AppCursorMap) {
            AppCursorMap[bg.Hwnd] := 1, AppCursorMap[icn.Hwnd] := 1, AppCursorMap[txt.Hwnd] := 1
            AppCursorMap[cat.Hwnd] := 1, AppCursorMap[trash.Hwnd] := 1
        }
        if IsSet(TopBar) {
            TopBar.RegisterHover(trash.Hwnd, StrReplace(Config.Theme.Icon, "#", ""), StrReplace(Config.Theme.Danger, "#", ""))
        }
    }
}
#Include ../overdock.ahk

class NotesPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Floating quick access note taking tool."
    W := 40

    ReqWidth() {
        return super.ReqWidth()
    }

    Render(gui, align, x, h, w) {
        s := this.App.Scale
        if (w <= 0) w := Round(this.W * s)
            gui.SetFont("s13 q5 c" Config.Theme.Icon, Config.Theme.IconFont)
        this.Btn := this.AddCtrl(gui, "Text", "x" x " y0 w" w " h" h " 0x200 Center BackgroundTrans", Chr(0xE70B))
        this.RegisterHover(this.Btn.Hwnd, Config.Theme.Icon, Config.Theme.IconHover)

        this.Btn.OnEvent("Click", (*) => this.ShowPopup())
        return w
    }

    MoveCtrls(x, w) {
        this.Btn.Move(x, , w)
    }

    LoadNotes() {
        if (!HasProp(this, "NotesData"))
            this.NotesData := []
        else
            return

        try {
            str := IniRead(IniFile, "NotesData", "Data", "")
            if (str == "") {
                this.NotesData := [{ Title: "Scratchpad", Text: "Write something brilliant here...", Expires: 0 }]
            } else {
                for line in StrSplit(str, "###") {
                    if !line
                        continue
                    parts := StrSplit(line, "|", 4)
                    if (parts.Length == 3)
                        this.NotesData.Push({ Title: parts[1], Expires: parts[2], Tag: "General", Text: StrReplace(parts[3], "<br>", "`n") })
                    else if (parts.Length >= 4)
                        this.NotesData.Push({ Title: parts[1], Expires: parts[2], Tag: parts[3], Text: StrReplace(parts[4], "<br>", "`n") })
                }
            }
        } catch {
            this.NotesData := [{ Title: "Scratchpad", Text: "Write something brilliant here...", Tag: "General", Expires: 0 }]
        }
    }

    SaveNotes() {
        if (!HasProp(this, "NotesData"))
            return
        str := ""
        for n in this.NotesData {
            safeTxt := StrReplace(n.Text, "`n", "<br>")
            safeTxt := StrReplace(safeTxt, "`r", "")
            safeTxt := StrReplace(safeTxt, "|", "")
            safeTag := StrReplace(n.Tag, "|", "")
            str .= "###" n.Title "|" n.Expires "|" safeTag "|" safeTxt
        }
        IniWrite(str, IniFile, "NotesData", "Data")
    }

    ShowPopup() {
        s := this.App.Scale
        if (!HasProp(this, "DropGui") || !this.DropGui) {
            this.DropGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" this.App.Gui.Hwnd)
            this.DropGui.BackColor := Config.Theme.DropBg
            try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.DropGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
            try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.DropGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

            this.DropGui.OnEvent("Escape", (*) => this.DropGui.Hide())

            ; Draw static headers once
            this.DropGui.SetFont("s" Round(12 * s) " w600 q5 c" Config.Theme.IconHover, Config.Theme.IconFont)
            this.DropGui.Add("Text", "x" Round(15 * s) " y" Round(15 * s) " w" Round(20 * s) " h" Round(25 * s) " BackgroundTrans", Chr(0xE70B))

            this.DropGui.SetFont("s" Round(11 * s) " w600 q5 c" Config.Theme.DropText, Config.Theme.Font)
            this.DropGui.Add("Text", "x" Round(40 * s) " y" Round(15 * s) " w" Round(200 * s) " h" Round(25 * s) " BackgroundTrans", "Quick Notes")
        }

        this.PW := Round(400 * s)

        this.LoadNotes()
        this.CheckExpirations()

        if (!HasProp(this, "ActiveTab"))
            this.ActiveTab := 1

        this.RenderUI()

        this.DropGui.OnEvent("Escape", (*) => this.DropGui.Hide())

        this.App.TogglePopup(this.DropGui, this.Btn.Hwnd, this.PW, Round(450 * s))
    }

    CheckExpirations() {
        if (!HasProp(this, "NotesData") || this.NotesData.Length == 0) {
            this.NotesData := [{ Title: "Scratchpad", Text: "Write something brilliant here...", Tag: "General", Expires: 0 }]
        }

        nowStamp := A_Now
        idx := 1
        while (idx <= this.NotesData.Length) {
            n := this.NotesData[idx]
            if (n.Expires != "" && n.Expires != 0) {
                try {
                    diff := DateDiff(nowStamp, n.Expires, "Seconds")
                    if (diff >= 0) {
                        this.NotesData.RemoveAt(idx)
                        continue
                    }
                }
            }
            idx++
        }

        if (this.NotesData.Length == 0) {
            this.NotesData.Push({ Title: "New Note", Text: "", Tag: "General", Expires: 0 })
        }
    }

    SaveNoteContent() {
        if (HasProp(this, "eNote") && this.ActiveTab <= this.NotesData.Length) {
            this.NotesData[this.ActiveTab].Text := this.eNote.Value
        }
    }

    RenderUI() {
        s := this.App.Scale

        if (HasProp(this, "NotesGui") && this.NotesGui) {
            try this.NotesGui.Destroy()
        }

        this.NotesGui := Gui("-Caption +Parent" this.DropGui.Hwnd)
        this.NotesGui.BackColor := Config.Theme.DropBg

        this.CheckExpirations()

        if (this.ActiveTab > this.NotesData.Length)
            this.ActiveTab := Max(1, this.NotesData.Length)

        curNote := this.NotesData[this.ActiveTab]

        ; Note Expires text
        if (curNote.Expires && curNote.Expires != 0) {
            try {
                this.NotesGui.SetFont("s" Round(8 * s) " w600 q5 c" BlendHex(Config.Theme.Danger, Config.Theme.DropBg, 50), Config.Theme.Font)
                diff := DateDiff(curNote.Expires, A_Now, "Minutes")
                expStr := (diff > 1440) ? Round(diff / 1440) "d" : ((diff > 60) ? Round(diff / 60) "h" : diff "m")
                this.NotesGui.Add("Text", "x" (this.PW - Round(150 * s)) " y" Round(17 * s) " w" Round(100 * s) " h" Round(20 * s) " Right BackgroundTrans", "Destructs in " expStr)
            }
        }

        ; Timer config icon
        this.NotesGui.SetFont("s" Round(12 * s) " w600 q5 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), Config.Theme.IconFont)
        btnTimer := this.NotesGui.Add("Text", "x" (this.PW - Round(40 * s)) " y" Round(15 * s) " w" Round(25 * s) " h" Round(25 * s) " 0x200 Center BackgroundTrans", Chr(0xE823))
        this.App.RegisterHover(btnTimer.Hwnd, BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40), "FFFFFF")
        btnTimer.OnEvent("Click", (*) => this.OpenTimerPopup(curNote))
        if IsSet(AppCursorMap)
            AppCursorMap[btnTimer.Hwnd] := 1

        ; TABS area
        tX := Round(15 * s)
        tY := Round(45 * s)

        this.NotesGui.SetFont("s" Round(10 * s) " w600 q5 cWhite", Config.Theme.Font)
        for idx, n in this.NotesData {
            ; Show Tag on the tab visually
            dispTxt := (n.Tag && n.Tag != "General" && n.Tag != "") ? ("[" n.Tag "] " n.Title) : n.Title
            tw := this.App.MeasureTextWidth(dispTxt, "s" Round(10 * s) " w600 q5", Config.Theme.Font)
            tw := Max(Round(50 * s), min(Round(tw / s), Round(150 * s)))

            cTxt := (idx == this.ActiveTab) ? "cWhite" : "c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40)
            cBg := (idx == this.ActiveTab) ? BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15) : Config.Theme.DropBg

            tabBg := this.NotesGui.Add("Text", "x" tX " y" tY " w" (tw + Round(30 * s)) " h" Round(30 * s) " Background" cBg " 0x0100", "")

            this.NotesGui.SetFont("s" Round(10 * s) " w600 q5 " cTxt, Config.Theme.Font)
            txt := this.NotesGui.Add("Text", "x" (tX + Round(10 * s)) " y" (tY + Round(5 * s)) " w" tw " h" Round(20 * s) " BackgroundTrans", dispTxt)

            delBtn := this.NotesGui.Add("Text", "x" (tX + tw + Round(12 * s)) " y" (tY + Round(5 * s)) " w" Round(14 * s) " h" Round(20 * s) " 0x200 Center BackgroundTrans c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 70), "x")

            if (idx == this.ActiveTab)
                this.NotesGui.Add("Text", "x" tX " y" (tY + Round(28 * s)) " w" (tw + Round(30 * s)) " h" Round(2 * s) " Background" StrReplace(Config.Theme.IconHover, "#", ""), "")

            actSwitch := ((i, *) => (this.SaveNoteContent(), this.ActiveTab := i, this.RenderUI())).Bind(idx)
            actDel := ((i, *) => (
                this.SaveNoteContent(),
                this.NotesData.RemoveAt(i),
                (this.NotesData.Length == 0) ? this.NotesData.Push({ Title: "New Note", Text: "", Tag: "General", Expires: 0 }) : 0,
                this.SaveNotes(),
                this.RenderUI()
            )).Bind(idx)

            tabBg.OnEvent("Click", actSwitch), txt.OnEvent("Click", actSwitch)
            delBtn.OnEvent("Click", actDel)

            if (idx != this.ActiveTab)
                this.App.RegisterHover(tabBg.Hwnd, Config.Theme.DropBg, BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15))
            this.App.RegisterHover(delBtn.Hwnd, StrReplace(Config.Theme.Icon, "#", ""), StrReplace(Config.Theme.Danger, "#", ""))
            if IsSet(AppCursorMap) {
                AppCursorMap[tabBg.Hwnd] := 1, AppCursorMap[txt.Hwnd] := 1, AppCursorMap[delBtn.Hwnd] := 1
            }

            tX += tw + Round(30 * s) + Round(5 * s)
        }

        ; ADD TAB BTN
        if (this.NotesData.Length < 5) {
            this.NotesGui.SetFont("s" Round(14 * s) " w600 q5 cWhite", Config.Theme.IconFont)
            btnAdd := this.NotesGui.Add("Text", "x" tX " y" tY " w" Round(30 * s) " h" Round(30 * s) " 0x200 Center BackgroundTrans", Chr(0xE710))
            this.App.RegisterHover(btnAdd.Hwnd, Config.Theme.DropBg, BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15))
            btnAdd.OnEvent("Click", (*) => (
                this.SaveNoteContent(),
                this.NotesData.Push({ Title: "Note " (this.NotesData.Length + 1), Text: "", Tag: "General", Expires: 0 }),
                this.ActiveTab := this.NotesData.Length,
                this.RenderUI()
            ))
            if IsSet(AppCursorMap)
                AppCursorMap[btnAdd.Hwnd] := 1
        }

        this.NotesGui.Add("Text", "x0 y" (tY + Round(30 * s)) " w" this.PW " h1 0x0100 Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), "")

        ; MAIN EDITOR
        yP := tY + Round(45 * s)

        this.NotesGui.SetFont("s" Round(11 * s) " w600 q5 cWhite", Config.Theme.Font)

        ; Layout Tag & Title beautifully
        this.NotesGui.Add("Edit", "x" Round(15 * s) " y" yP " w" Round(40 * s) " h" Round(25 * s) " Background" Config.Theme.DropBg " -E0x200 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " ReadOnly -VScroll", "Title:")
        eTitle := this.NotesGui.Add("Edit", "x" Round(55 * s) " y" yP " w" Round(160 * s) " h" Round(25 * s) " Background" Config.Theme.DropBg " -E0x200 cWhite -VScroll", curNote.Title)

        this.NotesGui.Add("Edit", "x" Round(225 * s) " y" yP " w" Round(35 * s) " h" Round(25 * s) " Background" Config.Theme.DropBg " -E0x200 c" BlendHex(Config.Theme.Text, Config.Theme.DropBg, 40) " ReadOnly -VScroll", "Tag:")
        eTag := this.NotesGui.Add("Edit", "x" Round(260 * s) " y" yP " w" (this.PW - Round(275 * s)) " h" Round(25 * s) " Background" Config.Theme.DropBg " -E0x200 cWhite -VScroll", curNote.Tag)

        eTitle.OnEvent("Change", ((n, e, *) => (n.Title := e.Value, this.SaveNotes(), this.UpdateTabTitle(e.Value))).Bind(curNote, eTitle))
        eTag.OnEvent("Change", ((n, e, *) => (n.Tag := e.Value, this.SaveNotes(), this.UpdateTabTitle(e.Value))).Bind(curNote, eTag))
        yP += Round(30 * s)

        this.NotesGui.SetFont("s" Round(10 * s) " w400 q5 cE0E0E0", Config.Theme.Font)
        this.eNote := this.NotesGui.Add("Edit", "x" Round(15 * s) " y" yP " w" (this.PW - Round(30 * s)) " h" Round(290 * s) " Background" Config.Theme.DropBg " -E0x200 cE0E0E0 Multi -VScroll", curNote.Text)

        this.eNote.OnEvent("Change", ((n, e, *) => (n.Text := e.Value, this.SaveNotes())).Bind(curNote, this.eNote))

        this.NotesGui.Show("x0 y0 w" this.PW " h" Round(450 * s) " NoActivate")
    }

    UpdateTabTitle(newVal) {
        ; Just queue a render or ignore until re-click to avoid losing focus
    }

    OpenTimerPopup(nObj) {
        s := this.App.Scale
        tGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" this.DropGui.Hwnd)
        tGui.BackColor := "1e1e1e"
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", tGui.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", tGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        tW := Round(200 * s)
        tGui.SetFont("s" Round(12 * s) " w600 q5 c" BlendHex(Config.Theme.Danger, Config.Theme.DropBg, 50), Config.Theme.Font)
        tGui.Add("Text", "x" Round(15 * s) " y" Round(15 * s) " w" Round(170 * s) " h" Round(25 * s) " BackgroundTrans", "Self-Destruct Timer")

        opts := [{ L: "1 Hour", V: 1 }, { L: "24 Hours", V: 24 }, { L: "48 Hours", V: 48 }, { L: "1 Week", V: 168 }, { L: "Forever (Manual)", V: 0 }
        ]

        yP := Round(45 * s)
        tGui.SetFont("s" Round(10 * s) " w500 q5 cWhite", Config.Theme.Font)
        for opt in opts {
            b := tGui.Add("Text", "x" Round(15 * s) " y" yP " w" (tW - Round(30 * s)) " h" Round(30 * s) " 0x200 Center Background" BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), opt.L)
            this.App.RegisterHover(b.Hwnd, BlendHex(Config.Theme.DropBg, Config.Theme.Text, 15), BlendHex(Config.Theme.DropBg, Config.Theme.Text, 25))
            if IsSet(AppCursorMap)
                AppCursorMap[b.Hwnd] := 1

            b.OnEvent("Click", ((val, gui, note, *) => (
                (val == 0) ? (note.Expires := 0) : (
                    fut := DateAdd(A_Now, val, "Hours"),
                    note.Expires := fut
                ),
                this.SaveNotes(),
                gui.Destroy(),
                this.RenderUI()
            )).Bind(opt.V, tGui, nObj))

            yP += Round(35 * s)
        }

        tGui.Show("w" tW " h" (yP + Round(15 * s)))
    }
}
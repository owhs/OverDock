#Include ../overdock.ahk
#Include lib/Socket.ahk
#Include lib/WebSockets.ahk

class WebNowPlayingPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Integration for web-browser media."

    Init() {
        this.WSSrv := ""
        this.ActiveWSClient := ""
        this.CStatus := "Starting..."
        this.PlayerState := Map(
            "TITLE", "",
            "ARTIST", "",
            "STATE", "STOPPED",
            "COVER_URL", ""
        )
        this.CoverPath := A_Temp "\webnowplaying_cover.jpg"
        this.MarqOffset := 0
        this.MarqTimer := ObjBindMethod(this, "TickMarquee")
        valTick := Integer(this.GetConfig("MarqueeTickSpeed", "300"))
        SetTimer(this.MarqTimer, valTick > 0 ? valTick : 300)
        
        this.ServerEnabled := this.GetConfig("ServerEnabled", 0)
        if (this.ServerEnabled)
            this.ConnectWS()
        else
            this.CStatus := "Server Disabled (Enable in Settings)"
    }

    Destroy() {
        this.CloseImagePopup()
        if HasProp(this, "MarqTimer") {
            try SetTimer(this.MarqTimer, 0)
        }

        if HasProp(this, "ActiveWSClient") && this.ActiveWSClient {
            try this.ActiveWSClient.onMessage := ""
            try this.ActiveWSClient.onClose := ""
            try this.ActiveWSClient.WsClose()
            this.ActiveWSClient := ""
        }

        if HasProp(this, "WSSrv") && this.WSSrv {
            try this.WSSrv.onClientConnect := ""
            this.WSSrv := ""
        }
    }

    ConnectWS() {
        if this.WSSrv {
            try this.WSSrv.__Delete()
            this.WSSrv := ""
        }
        port := this.GetConfig("Port", "8973")
        try {
            this.WSSrv := WebSockets.Server(Integer(port))
            this.WSSrv.onClientConnect := ObjBindMethod(this, "OnClientConnect")
            this.CStatus := "Awaiting connection (" port ")"
        } catch as err {
            this.CStatus := "Failed to bind port " port " (Check Firewall)"
            this.WSSrv := ""
        }
        this.NeedsUpdate := true
    }

    OnClientConnect(srv, client) {
        this.ActiveWSClient := client
        client.onMessage := ObjBindMethod(this, "OnMessage")
        client.onClose := ObjBindMethod(this, "OnClose")

        try client.SendText("ADAPTER_VERSION 1.0.0;WNPLIB_REVISION 1")
        this.CStatus := "Connected (" this.GetConfig("Port", "8973") ")"
        this.NeedsUpdate := true
    }

    OnMessage(client, msg) {
        msg := StrReplace(msg, "`r", "")
        msg := StrReplace(msg, "`n", "")

        idx1 := InStr(msg, " ")
        idx2 := InStr(msg, ":")
        idx := idx1
        if (idx2 && (!idx1 || idx2 < idx1))
            idx := idx2

        if (!idx)
            return

        type := Trim(SubStr(msg, 1, idx - 1))
        data := Trim(SubStr(msg, idx + 1))

        switch type {
            case "STATE":
                lastState := this.PlayerState["STATE"]
                this.PlayerState["STATE"] := (data == "1" || data == "PLAYING") ? "PLAYING" : ((data == "2" || data == "PAUSED") ? "PAUSED" : "STOPPED")
                if (lastState != this.PlayerState["STATE"]) {
                    this.NeedsUpdate := true
                    try this.App.needsReflow := true
                }
            case "TITLE":
                this.PlayerState["TITLE"] := data
            case "ARTIST":
                this.PlayerState["ARTIST"] := data
            case "COVER":
                this.PlayerState["COVER_URL"] := data
                if (data != "")
                    this.DownloadCover(data)
        }
    }

    OnClose(client, errCode) {
        if (HasProp(this, "ActiveWSClient") && this.ActiveWSClient == client) {
            this.ActiveWSClient := ""
            this.CStatus := "Disconnected"
            this.NeedsUpdate := true
            try this.App.needsReflow := true
        }
    }

    DownloadCover(url) {
        if (SubStr(url, 1, 4) != "http")
            return

        if (HasProp(this, "LastCoverUrl") && this.LastCoverUrl == url)
            return

        this.LastCoverUrl := url
        try {
            Download(url, this.CoverPath)
            this.NeedsUpdate := true
            if (this.GetConfig("ShowArtworkPopup", 1)) {
                SetTimer(ObjBindMethod(this, "ShowImagePopup"), -100)
            }
        }
    }

    ShowImagePopup() {
        if (!FileExist(this.CoverPath))
            return

        if (HasProp(this, "ArtPopup")) {
            try this.ArtPopup.Destroy()
            this.DeleteProp("ArtPopup")
        }

        s := this.App.Scale
        ag := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +Owner" this.App.Gui.Hwnd)
        ag.BackColor := Config.Theme.BarBg
        this.ArtPopup := ag

        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ag.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

        try {
            opc := Integer(this.GetConfig("ArtworkOpacity", "255"))
            if (opc != 255 && opc >= 0 && opc <= 255)
                WinSetTransparent(opc, ag.Hwnd)

            size := Round(200 * s)
            pic := ag.Add("Picture", "x0 y0 w" size " h" size, this.CoverPath)
            pic.OnEvent("Click", (*) => this.CloseImagePopup())

            dur := Integer(this.GetConfig("ArtworkPopupDuration", "5"))
            if (dur > 0) {
                this.ArtTimer := ObjBindMethod(this, "CloseImagePopup")
                SetTimer(this.ArtTimer, -(dur * 1000))
            }

            if HasProp(this, "TrackTxt") && DllCall("IsWindow", "Ptr", this.TrackTxt.Hwnd)
                this.App.TogglePopup(ag, this.TrackTxt.Hwnd, size, size)
        }
    }

    CloseImagePopup() {
        if HasProp(this, "ArtPopup") {
            try this.ArtPopup.Destroy()
            this.DeleteProp("ArtPopup")
        }
        if HasProp(this, "ArtTimer") {
            try SetTimer(this.ArtTimer, 0)
        }
    }

    ReqWidth() {
        if (!HasProp(this, "WSSrv"))
            this.Init()

        this.ShowOnlyWhenPlaying := this.GetConfig("ShowOnlyWhenPlaying", 0)
        if (this.ShowOnlyWhenPlaying) {
            if (this.PlayerState["STATE"] != "PLAYING")
                return 0
        }

        this.W := Integer(this.GetConfig("MarqueeWidth", "150")) * this.App.Scale
        return Round(this.W)
    }

    BuildCustomConfig(gui, yP, dW) {
        s := this.App.Scale
        this.ShowOnlyWhenPlaying := this.GetConfig("ShowOnlyWhenPlaying", 0)
        this.ShowArtworkPopup := this.GetConfig("ShowArtworkPopup", 1)
        this.ServerEnabled := this.GetConfig("ServerEnabled", 0)
        this.MarqueeWidth := this.GetConfig("MarqueeWidth", "150")
        this.ArtworkPopupDuration := this.GetConfig("ArtworkPopupDuration", "5")
        this.Port := this.GetConfig("Port", "8973")

        this.AddCheckbox(gui, Round(15 * s), yP, Round(240 * s), Round(25 * s), this, "ServerEnabled", "Enable WNP WebSocket Server")
        yP += Round(30 * s)
        this.AddCheckbox(gui, Round(15 * s), yP, Round(240 * s), Round(25 * s), this, "ShowOnlyWhenPlaying", "Auto-hide when not playing")
        yP += Round(30 * s)
        this.AddCheckbox(gui, Round(15 * s), yP, Round(240 * s), Round(25 * s), this, "ShowArtworkPopup", "Popup Artwork on track change")
        yP += Round(35 * s)

        gui.SetFont("s" Round(10 * s) " w400 q5 c" BlendHex(Config.Theme.DropText, Config.Theme.DropBg, 70), Config.Theme.Font)

        gui.Add("Text", "x" Round(15 * s) " y" (yP + 4) " w" Round(70 * s) " h" Round(20 * s) " BackgroundTrans", "Marq Width:")
        this.WidthEdit := gui.Add("Edit", "x" Round(85 * s) " y" yP " w" Round(35 * s) " h" Round(25 * s) " -E0x200 Background" Config.Theme.BarBg " c" Config.Theme.DropText, this.MarqueeWidth)

        gui.Add("Text", "x" Round(125 * s) " y" (yP + 4) " w" Round(65 * s) " h" Round(20 * s) " BackgroundTrans", "Tick(ms):")
        this.TickEdit := gui.Add("Edit", "x" Round(190 * s) " y" yP " w" Round(35 * s) " h" Round(25 * s) " -E0x200 Background" Config.Theme.BarBg " c" Config.Theme.DropText, this.GetConfig("MarqueeTickSpeed", "300"))
        yP += Round(35 * s)

        gui.Add("Text", "x" Round(15 * s) " y" (yP + 4) " w" Round(70 * s) " h" Round(20 * s) " BackgroundTrans", "Popup (s):")
        this.DurEdit := gui.Add("Edit", "x" Round(85 * s) " y" yP " w" Round(35 * s) " h" Round(25 * s) " -E0x200 Background" Config.Theme.BarBg " c" Config.Theme.DropText, this.ArtworkPopupDuration)

        gui.Add("Text", "x" Round(125 * s) " y" (yP + 4) " w" Round(65 * s) " h" Round(20 * s) " BackgroundTrans", "Scroll Amt:")
        this.AmtEdit := gui.Add("Edit", "x" Round(190 * s) " y" yP " w" Round(35 * s) " h" Round(25 * s) " -E0x200 Background" Config.Theme.BarBg " c" Config.Theme.DropText, this.GetConfig("MarqueeScrollAmt", "1"))
        yP += Round(35 * s)

        gui.Add("Text", "x" Round(15 * s) " y" (yP + 4) " w" Round(70 * s) " h" Round(20 * s) " BackgroundTrans", "WNP Port:")
        this.PortEdit := gui.Add("Edit", "x" Round(85 * s) " y" yP " w" Round(50 * s) " h" Round(25 * s) " -E0x200 Background" Config.Theme.BarBg " c" Config.Theme.DropText, this.Port)

        gui.Add("Text", "x" Round(140 * s) " y" (yP + 4) " w" Round(50 * s) " h" Round(20 * s) " BackgroundTrans", "Opacity:")
        this.OpEdit := gui.Add("Edit", "x" Round(190 * s) " y" yP " w" Round(35 * s) " h" Round(25 * s) " -E0x200 Background" Config.Theme.BarBg " c" Config.Theme.DropText, this.GetConfig("ArtworkOpacity", "255"))
        yP += Round(35 * s)

        gui.SetFont("s" Round(10 * s) " w500 q5 c" BlendHex(Config.Theme.DropText, Config.Theme.DropBg, 80), Config.Theme.Font)
        this.StatusText := gui.Add("Text", "x" Round(15 * s) " y" yP " w" Round(270 * s) " h" Round(20 * s) " BackgroundTrans", "Status: " StrReplace(this.HasProp("CStatus") ? this.CStatus : "Awaiting...", "Awaiting connection", "Awaiting..."))
        yP += Round(35 * s)

        return yP
    }

    SaveCustomConfig() {
        this.SetConfig("ShowOnlyWhenPlaying", this.ShowOnlyWhenPlaying)
        this.SetConfig("ShowArtworkPopup", this.ShowArtworkPopup)
        
        if (this.ServerEnabled != this.GetConfig("ServerEnabled", 0)) {
            this.SetConfig("ServerEnabled", this.ServerEnabled)
            if (this.ServerEnabled)
                this.ConnectWS()
            else {
                if this.WSSrv {
                    try this.WSSrv.__Delete()
                    this.WSSrv := ""
                }
                this.CStatus := "Server Disabled (Enable in Settings)"
                this.NeedsUpdate := true
            }
        }

        this.SetConfig("MarqueeWidth", this.WidthEdit.Value)
        this.SetConfig("ArtworkPopupDuration", this.DurEdit.Value)
        this.SetConfig("MarqueeScrollAmt", this.AmtEdit.Value)
        this.SetConfig("ArtworkOpacity", this.OpEdit.Value)

        newTick := this.TickEdit.Value
        if (newTick != this.GetConfig("MarqueeTickSpeed", "300")) {
            this.SetConfig("MarqueeTickSpeed", newTick)
            try {
                if (Integer(newTick) > 0)
                    SetTimer(this.MarqTimer, Integer(newTick))
            }
        }

        newPort := this.PortEdit.Value
        if (newPort != this.GetConfig("Port", "8973")) {
            this.SetConfig("Port", newPort)
            if (this.ServerEnabled)
                this.ConnectWS()
        }
    }

    Render(gui, align, x, h, w) {
        s := this.App.Scale
        cx := x
        tW := Round(Integer(this.GetConfig("MarqueeWidth", "150")) * s)
        gui.SetFont("s" Round(11 * s) " w500 q5 c" Config.Theme.Text, Config.Theme.Font)
        this.TrackTxt := this.AddCtrl(gui, "Text", "x" cx " y0 w" tW " h" h " 0x200 BackgroundTrans Center", " Waiting...")
        this.TrackTxt.OnEvent("Click", (*) => this.ShowImagePopup())
        this.TrackTxt.OnEvent("ContextMenu", (*) => this.ShowConfigPopup(this.TrackTxt.Hwnd))
        return cx + tW - x
    }

    MoveCtrls(x, w) {
        if HasProp(this, "TrackTxt")
            this.TrackTxt.Move(x, , w)
    }

    TickMarquee() {
        if (!DllCall("IsWindow", "Ptr", this.App.Gui.Hwnd)) {
            try SetTimer(this.MarqTimer, 0)
            return
        }
        if (!HasProp(this, "TrackTxt") || !DllCall("IsWindow", "Ptr", this.TrackTxt.Hwnd))
            return

        t := this.PlayerState.Has("TITLE") && this.PlayerState["TITLE"] != "" ? this.PlayerState["TITLE"] : "No Media"
        fullTxt := " " t
        if (this.PlayerState.Has("ARTIST") && this.PlayerState["ARTIST"] != "")
            fullTxt .= " - " this.PlayerState["ARTIST"]

        maxLength := Round(Integer(this.GetConfig("MarqueeWidth", "150")) / 6)
        if (StrLen(fullTxt) <= maxLength) {
            this.MarqOffset := 0
            if (this.TrackTxt.Value != fullTxt)
                this.TrackTxt.Value := fullTxt
            return
        }

        fullTxt .= "   •   "

        step := Integer(this.GetConfig("MarqueeScrollAmt", "1"))
        this.MarqOffset += step
        if (this.MarqOffset > StrLen(fullTxt))
            this.MarqOffset := Mod(this.MarqOffset - 1, StrLen(fullTxt)) + 1

        disp := SubStr(fullTxt, this.MarqOffset, maxLength)
        rem := maxLength - StrLen(disp)
        if (rem > 0)
            disp .= SubStr(fullTxt, 1, rem)

        this.TrackTxt.Value := StrReplace(disp, "&", "&&")
        if HasMethod(this, "SyncShadows")
            this.SyncShadows()
    }

    Update() {
        if (!HasProp(this, "NeedsUpdate") || !this.NeedsUpdate)
            return

        this.NeedsUpdate := false
        playing := (this.PlayerState["STATE"] == "PLAYING")

        this.ShowOnlyWhenPlaying := this.GetConfig("ShowOnlyWhenPlaying", 0)
        if (HasProp(this, "LastPlaying") && this.LastPlaying != playing) {
            if (this.ShowOnlyWhenPlaying)
                this.App.needsReflow := true
        }
        this.LastPlaying := playing

        if HasProp(this, "StatusText") {
            try {
                if DllCall("IsWindow", "Ptr", this.StatusText.Hwnd) {
                    if (this.StatusText.Value != "Status: " this.CStatus)
                        this.StatusText.Value := "Status: " this.CStatus
                }
            }
        }
    }
}
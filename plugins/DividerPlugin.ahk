#Include ../overdock.ahk
class DividerPlugin extends OverDockPlugin {
    static Version := "1.0"
    static Description := "Visual separator between items."
    W := 4

    Render(gui, align, x, h, w) {
        s := this.App.Scale
        if (w <= 0) w := Round(this.W * s)
            bgHex := BlendHex(Config.Theme.Text, Config.Theme.BarBg, 15)
        this.Btn := this.AddCtrl(gui, "Text", "x" (x + (w / 2) - Round(1 * s)) " y" (h / 2 - Round(10 * s)) " w" Round(2 * s) " h" Round(20 * s) " Background" bgHex, "")
        return w
    }

    MoveCtrls(x, w) {
        if HasProp(this, "Btn")
            this.Btn.Move(x + (w / 2) - Round(1 * this.App.Scale))
    }

    Update() {
    }
}
// Placeholder screen shown until provisioning (oga bead: auth UI) and device
// control (oga bead: control UI) land. Lays out from getWidth()/getHeight()
// rather than fixed coordinates so the same code renders on both round watch
// faces and tall rectangular Edge screens (see manifest.xml comment).
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

class StatusView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height / 2 - 20, Graphics.FONT_MEDIUM, "Orion Sleep", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height / 2 + 12, Graphics.FONT_XTINY, "Setup coming soon", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class StatusDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Lang.Boolean {
        System.exit();
        return true;
    }
}

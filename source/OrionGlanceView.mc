// Glance view -- shown in the watch's glance list. Line 1 is the app name.
// Line 2 says whether the user's side of the bed is on and what it is set
// to (oga-6bf).
//
// It does no network I/O and builds no OrionAuth or OrionClient: it reads
// the sign-in flag, the saved bed state (GlanceCache) and the primary side
// setting, and draws. The app's views and the background refresh
// (GlanceRefresh.mc) keep the saved state current. Everything this file
// calls must be annotated (:glance).
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Time;
using Toybox.WatchUi;

(:glance)
class OrionGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, height / 2 - 12, Graphics.FONT_GLANCE, "Orion Sleep", Graphics.TEXT_JUSTIFY_LEFT);

        var line = GlanceCache.secondLine(
            OrionSession.hasStoredToken(),
            GlanceCache.read(),
            GlanceCache.glanceBed(),
            DeviceModel.primaryZoneId(),
            Time.now().value()
        );
        var text = line[0] as Lang.String;
        var stale = line[1] as Lang.Boolean;
        var y = height / 2 + 10;

        // Old state (more than 2 hours): dimmer where the screen has a gray.
        // Black-and-white screens have none, so there the line keeps its
        // colour and gets a dashed underline instead.
        var dim = stale && GlanceCache.canDim();
        dc.setColor(dim ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_LEFT);
        if (stale && !dim) {
            var w = dc.getTextWidthInPixels(text, Graphics.FONT_XTINY);
            // One font height below the top of the text, but never below the
            // glance: on the Instinct glance (61 px high) that would be y=63.
            var uy = y + dc.getFontHeight(Graphics.FONT_XTINY);
            if (uy > height - 1) {
                uy = height - 1;
            }
            for (var x = 8; x < 8 + w; x += 4) {
                dc.drawLine(x, uy, x + 2, uy);
            }
        }
    }
}

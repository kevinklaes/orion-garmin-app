// Glance view (oga-fsf pivot to widget) -- shown in the watch's widget
// swipe loop. Deliberately does no network I/O: glances run on a tight
// update budget and must render fast, so this only reads the no-network
// OrionAuth.hasStoredToken() check. Tapping/selecting the glance opens the
// same OrionSleepApp.getInitialView() flow (ProvisioningView or
// DeviceListView) that a launched-from-Apps-menu open would show.
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.WatchUi;

class OrionGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, height / 2 - 12, Graphics.FONT_GLANCE, "Orion Sleep", Graphics.TEXT_JUSTIFY_LEFT);

        var status = OrionAuth.hasStoredToken() ? "Tap to control" : "Sign in required";
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, height / 2 + 10, Graphics.FONT_XTINY, status, Graphics.TEXT_JUSTIFY_LEFT);
    }
}

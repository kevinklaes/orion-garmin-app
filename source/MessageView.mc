// Messages that must be readable in full on a round watch (oga-2cx).
//
// MessageText.draw() wraps a text by word inside a box that fits the
// glass: on a round screen the box is as wide as the chord at whichever of
// its top and bottom edges is further from the middle, so no line reaches
// the bezel. WatchUi.TextArea (API 3.1.0) does the wrapping and drops to a
// smaller font when the text does not fit. The control view uses it for
// load errors and long status lines.
//
// MessageView and MessageDelegate show a set-up message at start-up when
// Ember & Tide mode is chosen but the address or key is unusable
// (OrionSleepApp.getInitialView()). Back exits the app.
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.WatchUi;

module MessageText {

    // Draws text centred between y = top and y = bottom.
    function draw(dc as Graphics.Dc, text as Lang.String, color as Graphics.ColorType, top as Lang.Number, bottom as Lang.Number) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var boxWidth = width - 24;
        if (System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND) {
            var r = width / 2;
            var dTop = (height / 2) - top;
            var dBottom = bottom - (height / 2);
            var d = dTop.abs() > dBottom.abs() ? dTop.abs() : dBottom.abs();
            if (d < r) {
                boxWidth = (2 * Math.sqrt(r * r - d * d)).toNumber() - 8;
            } else {
                boxWidth = 40;
            }
        }
        if (boxWidth < 40) {
            boxWidth = 40;
        }
        var boxHeight = bottom - top;
        if (boxHeight < 20) {
            boxHeight = 20;
        }
        var area = new WatchUi.TextArea({
            :text => text,
            :color => color,
            :backgroundColor => Graphics.COLOR_TRANSPARENT,
            :font => [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY],
            :justification => Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER,
            :locX => (width - boxWidth) / 2,
            :locY => top,
            :width => boxWidth,
            :height => boxHeight
        });
        area.draw(dc);
    }
}

class MessageView extends WatchUi.View {

    private var _title as Lang.String;
    private var _message as Lang.String;

    function initialize(title as Lang.String, message as Lang.String) {
        View.initialize();
        _title = title;
        _message = message;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 8, Graphics.FONT_MEDIUM, _title, Graphics.TEXT_JUSTIFY_CENTER);

        var headerBottom = 34;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(10, headerBottom, width - 10, headerBottom);

        MessageText.draw(dc, _message, Graphics.COLOR_WHITE, headerBottom + 10, height - 34);
    }
}

class MessageDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Lang.Boolean {
        System.exit();
    }
}

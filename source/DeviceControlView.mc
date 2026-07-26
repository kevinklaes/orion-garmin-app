// Device control view (oga-8m6) — per zone power toggle + temperature
// adjust, via GET/PUT /v1/devices/{serial_number}/live
// (update_live_device_zones -- the canonical control primitive per api.py's
// docstring). One zone shown at a time; UP/DOWN (or swipe up/down) adjust
// its temperature, SELECT (or tap) toggles its power, and — when a device
// has more than one zone — swipe left/right or the page keys switch which
// zone is focused. Mirrors GarminMerge's PRDetailView structure (view +
// delegate + confirmation/menu delegates in one file).
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

class DeviceControlView extends WatchUi.View {

    // Mirrors climate.py's _attr_target_temperature_step.
    private const TEMP_STEP = 0.5;

    private var _device as OrionDevice;
    private var _auth as OrionAuth;
    private var _zones as Lang.Array<OrionZone>;
    private var _selectedZone as Lang.Number;
    private var _loading as Lang.Boolean;
    private var _busy as Lang.Boolean;
    private var _error as Lang.String or Null;
    private var _status as Lang.String;
    // Held across an in-flight update so onUpdateDone() can roll back the
    // optimistic local mutation if the PUT fails.
    private var _pendingRevertOn as Lang.Boolean;
    private var _pendingRevertTemp as Lang.Float;
    private var _pendingZoneId as Lang.String;

    function initialize(device as OrionDevice) {
        View.initialize();
        _device = device;
        _auth = new OrionAuth();
        _zones = [] as Lang.Array<OrionZone>;
        _selectedZone = 0;
        _loading = true;
        _busy = false;
        _error = null;
        _status = "";
        _pendingRevertOn = false;
        _pendingRevertTemp = 0.0;
        _pendingZoneId = "";
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onShow() as Void {
        if (_zones.size() == 0 && _loading) {
            refresh();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 8, Graphics.FONT_MEDIUM, _device.name, Graphics.TEXT_JUSTIFY_CENTER);

        var headerBottom = 34;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(10, headerBottom, width - 10, headerBottom);

        if (_loading) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2, Graphics.FONT_SMALL, "Loading…", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        if (_error != null) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            drawWrapped(dc, 16, headerBottom + 16, width - 32, "Error: " + (_error as Lang.String));
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height - 22, Graphics.FONT_XTINY, "SELECT to retry", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var zone = getSelectedZone();
        if (zone == null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2, Graphics.FONT_SMALL, "No zones reported", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var zoneTop = headerBottom + 14;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, zoneTop, Graphics.FONT_SMALL, DeviceModel.zoneLabel(zone.id), Graphics.TEXT_JUSTIFY_CENTER);

        if (_zones.size() > 1) {
            drawZonePageDots(dc, width, zoneTop + 24);
        }

        var powerLabel = zone.on ? "ON" : "OFF";
        dc.setColor(zone.on ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height / 2 - 44, Graphics.FONT_MEDIUM, powerLabel, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var tempText = zone.temp.format("%.1f") + "°";
        dc.drawText(width / 2, height / 2 - 8, Graphics.FONT_NUMBER_MEDIUM, tempText, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var rangeText = _device.tempMin.format("%.0f") + "–" + _device.tempMax.format("%.0f") + "°";
        dc.drawText(width / 2, height / 2 + 40, Graphics.FONT_XTINY, rangeText, Graphics.TEXT_JUSTIFY_CENTER);

        if (_status.length() > 0) {
            dc.setColor(_status.find("Error") == 0 ? Graphics.COLOR_RED : Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height - 78, Graphics.FONT_XTINY, _status, Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        // Round screens are narrower than dc.getWidth() near the bottom
        // edge (the bezel cuts the chord short), so a single wide hint
        // line clips on round watches even though there's room higher up.
        // Splitting into two short lines keeps each one within the chord.
        var isRound = System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND;
        if (isRound) {
            dc.drawText(width / 2, height - 54, Graphics.FONT_XTINY, "UP/DOWN temp", Graphics.TEXT_JUSTIFY_CENTER);
            var hint2 = "SELECT power";
            if (_zones.size() > 1) {
                hint2 = hint2 + " · SWIPE";
            }
            dc.drawText(width / 2, height - 32, Graphics.FONT_XTINY, hint2, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var hint = "UP/DOWN temp · SELECT power";
            if (_zones.size() > 1) {
                hint = hint + " · SWIPE zone";
            }
            dc.drawText(width / 2, height - 40, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawZonePageDots(dc as Graphics.Dc, width as Lang.Number, y as Lang.Number) as Void {
        var count = _zones.size();
        var spacing = 14;
        var startX = (width / 2) - (((count - 1) * spacing) / 2);
        for (var i = 0; i < count; i += 1) {
            var x = startX + (i * spacing);
            dc.setColor(i == _selectedZone ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 3);
        }
    }

    function refresh() as Void {
        _loading = true;
        _error = null;
        _status = "";
        WatchUi.requestUpdate();
        _auth.getLiveDevice(_device.serialNumber, method(:onLiveLoaded));
    }

    function onLiveLoaded(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        _loading = false;
        if (error != null) {
            _error = error;
            WatchUi.requestUpdate();
            return;
        }
        if (result != null && result instanceof Lang.Dictionary) {
            _zones = DeviceModel.zonesFromLiveJson(result as Lang.Dictionary);
            if (_selectedZone >= _zones.size()) {
                _selectedZone = _zones.size() > 0 ? _zones.size() - 1 : 0;
            }
        }
        WatchUi.requestUpdate();
    }

    function getSelectedZone() as OrionZone or Null {
        if (_zones.size() == 0 || _selectedZone < 0 || _selectedZone >= _zones.size()) {
            return null;
        }
        return _zones[_selectedZone];
    }

    function selectNextZone() as Void {
        if (_zones.size() <= 1) {
            return;
        }
        _selectedZone = (_selectedZone + 1) % _zones.size();
        WatchUi.requestUpdate();
    }

    function selectPreviousZone() as Void {
        if (_zones.size() <= 1) {
            return;
        }
        _selectedZone = (_selectedZone - 1 + _zones.size()) % _zones.size();
        WatchUi.requestUpdate();
    }

    function togglePower() as Void {
        if (_busy || _loading || _error != null) {
            return;
        }
        var zone = getSelectedZone();
        if (zone == null) {
            return;
        }
        var newOn = !zone.on;
        var previousOn = zone.on;
        zone.on = newOn;
        WatchUi.requestUpdate();
        sendZoneUpdate(zone.id, newOn, null, previousOn, zone.temp);
    }

    function increaseTemp() as Void {
        adjustTemp(TEMP_STEP);
    }

    function decreaseTemp() as Void {
        adjustTemp(-TEMP_STEP);
    }

    private function adjustTemp(delta as Lang.Float) as Void {
        if (_busy || _loading || _error != null) {
            return;
        }
        var zone = getSelectedZone();
        if (zone == null) {
            return;
        }
        var newTemp = zone.temp + delta;
        if (newTemp < _device.tempMin) {
            newTemp = _device.tempMin;
        }
        if (newTemp > _device.tempMax) {
            newTemp = _device.tempMax;
        }
        if (newTemp == zone.temp) {
            return;
        }
        var previousTemp = zone.temp;
        zone.temp = newTemp;
        WatchUi.requestUpdate();
        sendZoneUpdate(zone.id, null, newTemp, zone.on, previousTemp);
    }

    // Applies the change optimistically (caller already mutated the local
    // zone before calling this) and reverts to the previous value if the
    // PUT fails, so the UI never claims a change that didn't actually land.
    private function sendZoneUpdate(
        zoneId as Lang.String,
        on as Lang.Boolean or Null,
        temp as Lang.Float or Null,
        revertOn as Lang.Boolean,
        revertTemp as Lang.Float
    ) as Void {
        var zoneUpdate = { "id" => zoneId } as Lang.Dictionary;
        if (on != null) {
            zoneUpdate.put("on", on);
        }
        if (temp != null) {
            zoneUpdate.put("temp", temp);
        }

        _pendingRevertOn = revertOn;
        _pendingRevertTemp = revertTemp;
        _pendingZoneId = zoneId;
        _busy = true;
        _status = "Updating…";
        WatchUi.requestUpdate();
        _auth.updateLiveDeviceZones(_device.serialNumber, [zoneUpdate], method(:onUpdateDone));
    }

    function onUpdateDone(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        _busy = false;
        if (error != null) {
            revertZone(_pendingZoneId, _pendingRevertOn, _pendingRevertTemp);
            _status = "Error: " + error;
            WatchUi.requestUpdate();
            return;
        }
        if (result != null && result instanceof Lang.Dictionary) {
            var updated = DeviceModel.zonesFromLiveJson(result as Lang.Dictionary);
            if (updated.size() > 0) {
                _zones = updated;
                if (_selectedZone >= _zones.size()) {
                    _selectedZone = _zones.size() - 1;
                }
            }
        }
        _status = "";
        WatchUi.requestUpdate();
    }

    private function revertZone(zoneId as Lang.String, on as Lang.Boolean, temp as Lang.Float) as Void {
        for (var i = 0; i < _zones.size(); i += 1) {
            if (_zones[i].id.equals(zoneId)) {
                _zones[i].on = on;
                _zones[i].temp = temp;
                return;
            }
        }
    }

    private function drawWrapped(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, maxWidth as Lang.Number, text as Lang.String) as Void {
        var maxChars = (maxWidth / 8).toNumber();
        if (maxChars < 12) {
            maxChars = 12;
        }
        var remaining = text;
        var lineY = y;
        var lines = 0;
        while (remaining.length() > 0 && lines < 8) {
            if (remaining.length() <= maxChars) {
                dc.drawText(x, lineY, Graphics.FONT_SMALL, remaining, Graphics.TEXT_JUSTIFY_LEFT);
                break;
            }
            dc.drawText(x, lineY, Graphics.FONT_SMALL, remaining.substring(0, maxChars), Graphics.TEXT_JUSTIFY_LEFT);
            remaining = remaining.substring(maxChars, remaining.length());
            lineY += 22;
            lines += 1;
        }
    }
}

class DeviceControlDelegate extends WatchUi.BehaviorDelegate {

    private var _view as DeviceControlView;
    // True when this view replaced DeviceListView outright (the
    // exactly-one-device auto-select case in DeviceListView.onDevicesLoaded)
    // rather than being pushed on top of it -- there is no view underneath
    // to pop back to, so Back must exit the app instead of popView().
    private var _isRoot as Lang.Boolean;

    function initialize(view as DeviceControlView, isRoot as Lang.Boolean) {
        BehaviorDelegate.initialize();
        _view = view;
        _isRoot = isRoot;
    }

    function onKey(evt as WatchUi.KeyEvent) as Lang.Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_UP) {
            _view.increaseTemp();
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            _view.decreaseTemp();
            return true;
        } else if (key == WatchUi.KEY_ENTER) {
            _view.togglePower();
            return true;
        } else if (key == WatchUi.KEY_START || key == WatchUi.KEY_LAP) {
            _view.refresh();
            return true;
        } else if (key == WatchUi.KEY_ESC) {
            return onBack();
        }
        return false;
    }

    function onSelect() as Lang.Boolean {
        _view.togglePower();
        return true;
    }

    function onBack() as Lang.Boolean {
        if (_isRoot) {
            System.exit();
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Lang.Boolean {
        _view.togglePower();
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Lang.Boolean {
        var dir = evt.getDirection();
        if (dir == WatchUi.SWIPE_UP) {
            _view.increaseTemp();
            return true;
        } else if (dir == WatchUi.SWIPE_DOWN) {
            _view.decreaseTemp();
            return true;
        } else if (dir == WatchUi.SWIPE_LEFT) {
            _view.selectNextZone();
            return true;
        } else if (dir == WatchUi.SWIPE_RIGHT) {
            _view.selectPreviousZone();
            return true;
        }
        return false;
    }

    // On 5-button devices the physical UP/DOWN buttons are dispatched as
    // onPreviousPage()/onNextPage() by BehaviorDelegate, not as onKey()
    // KEY_UP/KEY_DOWN -- that branch in onKey() never actually fires on
    // this hardware. These need to drive temperature (UP=previous page
    // behavior, DOWN=next page behavior), matching onKey()/onSwipe()'s
    // UP=increase/DOWN=decrease convention. Zone switching stays on swipe
    // left/right only.
    function onPreviousPage() as Lang.Boolean {
        _view.increaseTemp();
        return true;
    }

    function onNextPage() as Lang.Boolean {
        _view.decreaseTemp();
        return true;
    }
}

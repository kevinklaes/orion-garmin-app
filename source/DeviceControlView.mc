// Device control view (oga-8m6) — per zone power toggle + temperature
// adjust, via GET/PUT /v1/devices/{serial_number}/live
// (update_live_device_zones -- the canonical control primitive per api.py's
// docstring). One zone shown at a time; UP/DOWN (or swipe up/down) adjust
// its temperature, SELECT (or tap) toggles its power, and — when a device
// has more than one zone — swipe left/right or the page keys switch which
// zone is focused. Mirrors GarminMerge's PRDetailView structure (view +
// delegate + confirmation/menu delegates in one file).
//
// Temperature batching (oga-23f): a press only changes the number on screen
// and restarts a one-shot timer. One PUT carrying the final temperature goes
// out QUIET_PERIOD_MS after the last press. Switching zone, a power tap, Back
// and onHide() end the wait early and send at once. For each zone the view
// keeps the shown values (the OrionZone in _zones) and the confirmed values
// (the last on/temp the server reported, in _confirmed by zone id); a zone is
// sent when the two differ. A failed send puts the confirmed value back on
// screen unless the user changed it again during the send. Only one request
// (PUT or GET) is handed to OrionAuth at a time; sendNextIfIdle() is the only
// sender of updates. START/LAP refresh is ignored while a change is waiting
// or a request is in flight.
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

class DeviceControlView extends WatchUi.View {

    // Mirrors climate.py's _attr_target_temperature_step.
    private const TEMP_STEP = 0.5;
    // How long after the last temperature press the batch is sent.
    private const QUIET_PERIOD_MS = 1000;

    private var _device as OrionDevice;
    private var _auth as OrionAuth;
    private var _zones as Lang.Array<OrionZone>;
    private var _selectedZone as Lang.Number;
    // The primary side is applied once per view, on the first load that
    // returns zones, so a refresh never moves the user off the side they chose.
    private var _primaryApplied as Lang.Boolean;
    private var _loading as Lang.Boolean;
    private var _error as Lang.String or Null;
    private var _status as Lang.String;
    // The one timer. Started one-shot by a temperature press, stopped by a
    // flush.
    private var _timer as Timer.Timer;
    // Zone whose temperature batch is still waiting for the timer, or null.
    private var _quietZoneId as Lang.String or Null;
    // Last on/temp the server reported, by zone id. Separate objects from the
    // ones in _zones, which hold the values shown on screen.
    private var _confirmed as Lang.Dictionary<Lang.String, OrionZone>;
    // True from handing any request (PUT or GET) to _auth until its callback.
    private var _inFlight as Lang.Boolean;
    // What the in-flight PUT carried. Null means the field was not sent.
    private var _sentZoneId as Lang.String;
    private var _sentTemp as Lang.Float or Null;
    private var _sentOn as Lang.Boolean or Null;

    function initialize(device as OrionDevice) {
        View.initialize();
        _device = device;
        _auth = new OrionAuth();
        _zones = [] as Lang.Array<OrionZone>;
        _selectedZone = 0;
        _primaryApplied = false;
        _loading = true;
        _error = null;
        _status = "";
        _timer = new Timer.Timer();
        _quietZoneId = null;
        _confirmed = {} as Lang.Dictionary<Lang.String, OrionZone>;
        _inFlight = false;
        _sentZoneId = "";
        _sentTemp = null;
        _sentOn = null;
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onShow() as Void {
        // Opening a bed makes it the bed the glance reports on.
        GlanceCache.setGlanceBed(_device.serialNumber);
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
        var tempText = DeviceModel.tempText(zone.temp);
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

    function onHide() as Void {
        flushPending();
    }

    // START/LAP is ignored while a temperature batch is waiting, a change is
    // unsent, or any request is in flight (REQ-013). The waiting change is
    // sent as normal; press again afterwards to refresh.
    function refresh() as Void {
        if (_inFlight || hasUnsentChanges()) {
            return;
        }
        _inFlight = true;
        _loading = true;
        _error = null;
        _status = "";
        WatchUi.requestUpdate();
        // Nothing after the _auth call: the callback may already have run.
        _auth.getLiveDevice(_device.serialNumber, method(:onLiveLoaded));
    }

    function onLiveLoaded(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        _loading = false;
        _inFlight = false;
        if (error != null) {
            _error = error;
            WatchUi.requestUpdate();
            return;
        }
        if (result != null && result instanceof Lang.Dictionary) {
            _zones = DeviceModel.zonesFromLiveJson(result as Lang.Dictionary);
            resetConfirmed();
            saveGlanceCache();
            if (!_primaryApplied && _zones.size() > 0) {
                _selectedZone = DeviceModel.primaryZoneIndex(_zones);
                _primaryApplied = true;
            } else if (_selectedZone >= _zones.size()) {
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
        flushPending();
        _selectedZone = (_selectedZone + 1) % _zones.size();
        WatchUi.requestUpdate();
    }

    function selectPreviousZone() as Void {
        if (_zones.size() <= 1) {
            return;
        }
        flushPending();
        _selectedZone = (_selectedZone - 1 + _zones.size()) % _zones.size();
        WatchUi.requestUpdate();
    }

    // Power taps are never batched. The tap shows at once and ends any quiet
    // period, so a waiting temperature for the zone travels in the same PUT
    // (REQ-009). With a request in flight it is sent when that one returns.
    function togglePower() as Void {
        if (_loading || _error != null) {
            return;
        }
        var zone = getSelectedZone();
        if (zone == null) {
            return;
        }
        zone.on = !zone.on;
        clearErrorStatus();
        WatchUi.requestUpdate();
        flushPending();
    }

    function increaseTemp() as Void {
        adjustTemp(TEMP_STEP);
    }

    function decreaseTemp() as Void {
        adjustTemp(-TEMP_STEP);
    }

    // Changes the shown value only and restarts the quiet period. Never
    // calls _auth and is never blocked by a request in flight.
    private function adjustTemp(delta as Lang.Float) as Void {
        if (_loading || _error != null) {
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
            // At the limit: no batch, no timer.
            return;
        }
        zone.temp = newTemp;
        clearErrorStatus();
        _quietZoneId = zone.id;
        _timer.stop();
        _timer.start(method(:onQuietTimer), QUIET_PERIOD_MS, false);
        WatchUi.requestUpdate();
    }

    // Timer callback. Public so method(:onQuietTimer) can reach it.
    function onQuietTimer() as Void {
        _quietZoneId = null;
        sendNextIfIdle();
    }

    // End the quiet period now and send what is waiting. If a request is in
    // flight, the send starts when that request returns. Safe to call when
    // nothing is waiting.
    function flushPending() as Void {
        _timer.stop();
        _quietZoneId = null;
        sendNextIfIdle();
    }

    // The only caller of updateLiveDeviceZones(). Sends the first zone whose
    // shown values differ from its confirmed values, one zone per request,
    // and only when no request is in flight (REQ-011).
    private function sendNextIfIdle() as Void {
        if (_inFlight) {
            return;
        }
        for (var i = 0; i < _zones.size(); i += 1) {
            var zone = _zones[i];
            var conf = _confirmed.get(zone.id);
            if (conf == null) {
                continue;
            }
            var inQuiet = (_quietZoneId != null) && zone.id.equals(_quietZoneId);
            var sendTemp = !inQuiet && !sameTemp(zone.temp, conf.temp);
            var sendOn = (zone.on != conf.on);
            if (!sendTemp && !sendOn) {
                continue;
            }
            var body = { "id" => zone.id } as Lang.Dictionary;
            if (sendOn) {
                body.put("on", zone.on);
            }
            if (sendTemp) {
                body.put("temp", zone.temp);
            }

            _sentZoneId = zone.id;
            _sentTemp = sendTemp ? zone.temp : null;
            _sentOn = sendOn ? zone.on : null;
            _inFlight = true;
            _status = "Updating…";
            WatchUi.requestUpdate();
            // Nothing after the _auth call: the callback may already have run.
            _auth.updateLiveDeviceZones(_device.serialNumber, [body], method(:onUpdateDone));
            return;
        }
    }

    function onUpdateDone(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        _inFlight = false;
        if (error != null) {
            revertSentFields();
            _status = "Error: " + error;
        } else {
            adoptServerZones(result);
            saveGlanceCache();
            _status = "";
        }
        _sentZoneId = "";
        _sentTemp = null;
        _sentOn = null;
        WatchUi.requestUpdate();
        sendNextIfIdle();
    }

    // Failed PUT: each sent field the user has not changed since goes back to
    // the confirmed value, which is the value from before the batch began
    // (REQ-006). A field changed during the send stays on screen and is sent
    // next (REQ-010). Confirmed values never change on failure.
    private function revertSentFields() as Void {
        var zone = findZone(_sentZoneId);
        var conf = _confirmed.get(_sentZoneId);
        if (zone == null || conf == null) {
            return;
        }
        var sentTemp = _sentTemp;
        if (sentTemp != null && sameTemp(zone.temp, sentTemp)) {
            zone.temp = conf.temp;
        }
        var sentOn = _sentOn;
        if (sentOn != null && zone.on == sentOn) {
            zone.on = conf.on;
        }
    }

    // Successful PUT: take the server's zones as today, except that a field
    // the user changed again since it was sent (or that was never sent and
    // is dirty) keeps its shown value (REQ-012). All lookups are by zone id.
    private function adoptServerZones(result as Lang.Object or Null) as Void {
        var updated = [] as Lang.Array<OrionZone>;
        if (result != null && result instanceof Lang.Dictionary) {
            updated = DeviceModel.zonesFromLiveJson(result as Lang.Dictionary);
        }
        if (updated.size() == 0) {
            // No zones in the reply: trust the PUT.
            var sentConf = _confirmed.get(_sentZoneId);
            if (sentConf != null) {
                var sentTemp = _sentTemp;
                if (sentTemp != null) {
                    sentConf.temp = sentTemp;
                }
                var sentOn = _sentOn;
                if (sentOn != null) {
                    sentConf.on = sentOn;
                }
            }
            return;
        }

        var newConfirmed = {} as Lang.Dictionary<Lang.String, OrionZone>;
        for (var i = 0; i < updated.size(); i += 1) {
            var nz = updated[i];
            var serverOn = nz.on;
            var serverTemp = nz.temp;
            var oldShown = findZone(nz.id);
            var oldConf = _confirmed.get(nz.id);
            if (oldShown != null && oldConf != null) {
                var isSent = nz.id.equals(_sentZoneId);
                var expectedTemp = oldConf.temp;
                var sentTemp = _sentTemp;
                if (isSent && sentTemp != null) {
                    expectedTemp = sentTemp;
                }
                var expectedOn = oldConf.on;
                var sentOn = _sentOn;
                if (isSent && sentOn != null) {
                    expectedOn = sentOn;
                }
                if (!sameTemp(oldShown.temp, expectedTemp)) {
                    nz.temp = oldShown.temp;
                }
                if (oldShown.on != expectedOn) {
                    nz.on = oldShown.on;
                }
            }
            newConfirmed.put(nz.id, new OrionZone(nz.id, serverOn, serverTemp));
        }

        _zones = updated;
        _confirmed = newConfirmed;
        if (_selectedZone >= _zones.size()) {
            _selectedZone = _zones.size() - 1;
        }
        var quietId = _quietZoneId;
        if (quietId != null && findZone(quietId) == null) {
            _timer.stop();
            _quietZoneId = null;
        }
    }

    private function findZone(zoneId as Lang.String) as OrionZone or Null {
        for (var i = 0; i < _zones.size(); i += 1) {
            if (_zones[i].id.equals(zoneId)) {
                return _zones[i];
            }
        }
        return null;
    }

    // Float temperatures do not survive +0.5 then -0.5 exactly, so compare
    // with a small tolerance instead of ==.
    private function sameTemp(a as Lang.Float, b as Lang.Float) as Lang.Boolean {
        var d = a - b;
        if (d < 0) {
            d = -d;
        }
        return d < 0.01;
    }

    // Rebuild _confirmed from _zones with new OrionZone copies. Sharing the
    // objects would make shown and confirmed always equal.
    private function resetConfirmed() as Void {
        _confirmed = {} as Lang.Dictionary<Lang.String, OrionZone>;
        for (var i = 0; i < _zones.size(); i += 1) {
            var z = _zones[i];
            _confirmed.put(z.id, new OrionZone(z.id, z.on, z.temp));
        }
    }

    // Saves the confirmed values (what the server last reported), never the
    // values that are only on screen. Called only after a successful load
    // or update. GlanceCache.write() ignores a bed that is not the glance
    // bed and an empty list.
    private function saveGlanceCache() as Void {
        var confirmed = [] as Lang.Array<OrionZone>;
        for (var i = 0; i < _zones.size(); i += 1) {
            var conf = _confirmed.get(_zones[i].id);
            if (conf != null) {
                confirmed.add(conf);
            }
        }
        GlanceCache.write(_device.serialNumber, DeviceModel.glanceEntries(confirmed), null);
    }

    private function hasUnsentChanges() as Lang.Boolean {
        if (_quietZoneId != null) {
            return true;
        }
        for (var i = 0; i < _zones.size(); i += 1) {
            var zone = _zones[i];
            var conf = _confirmed.get(zone.id);
            if (conf != null && (zone.on != conf.on || !sameTemp(zone.temp, conf.temp))) {
                return true;
            }
        }
        return false;
    }

    // Clears a stale "Error: …" status. Leaves "Updating…" alone.
    private function clearErrorStatus() as Void {
        if (_status.find("Error") == 0) {
            _status = "";
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
        // Hand any waiting temperature batch to the network before leaving;
        // in the root case System.exit() would otherwise drop it.
        _view.flushPending();
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

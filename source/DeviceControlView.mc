// Device control view (oga-8m6) — per side power toggle + temperature
// adjust. One side shown at a time; UP/DOWN (or swipe up/down) adjust its
// temperature, SELECT (or tap) toggles its power, and — when there is more
// than one side — swipe left/right or the page keys switch which side is
// focused. Mirrors GarminMerge's PRDetailView structure (view + delegate +
// confirmation/menu delegates in one file).
//
// Backend seam (oga-2cx): the view reaches the network only through one
// BedBackend (see BedBackend.mc): OrionBackend for an Orion bed (zones,
// GET/PUT /v1/devices/{serial_number}/live) or the Ember & Tide client for a
// self-hosted Ember & Tide server (people). It never branches on which one
// it has; a side says itself whether it is read-only and what its power
// labels are, and a BedState carries the range, step and number format.
// Error texts arrive complete from the backend.
//
// Temperature batching (oga-23f): a press only changes the number on screen
// and restarts a one-shot timer. One request carrying the final temperature
// goes out QUIET_PERIOD_MS after the last press. Switching side, a power
// tap, Back and onHide() end the wait early and send at once. For each side
// the view keeps the shown values (the BedSide in _zones) and the confirmed
// values (the last on/temp the server reported, in _confirmed by side id); a
// side is sent when the two differ. A failed send puts the confirmed value
// back on screen unless the user changed it again during the send. Only one
// request is handed to the backend at a time; sendNextIfIdle() is the only
// sender of updates. When the backend cannot carry power and temperature in
// one request, the temperature goes first and the power change follows its
// reply. START/LAP refresh is ignored while a change is waiting or a request
// is in flight.
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

class DeviceControlView extends WatchUi.View {

    // How long after the last temperature press the batch is sent.
    private const QUIET_PERIOD_MS = 1000;

    private var _backend as BedBackend;
    // From _backend.describe().
    private var _title as Lang.String;
    private var _powerWithTemp as Lang.Boolean;
    // From the last BedState: range, step and number format, as shown.
    private var _tempMin as Lang.Float;
    private var _tempMax as Lang.Float;
    private var _step as Lang.Float;
    private var _tempFormat as Lang.String;
    private var _zones as Lang.Array<BedSide>;
    private var _selectedZone as Lang.Number;
    // The home side is applied once per view, on the first load that
    // returns sides, so a refresh never moves the user off the side they chose.
    private var _primaryApplied as Lang.Boolean;
    private var _loading as Lang.Boolean;
    private var _error as Lang.String or Null;
    private var _status as Lang.String;
    // True when _status is an error (drawn red, cleared by the next press).
    private var _statusIsError as Lang.Boolean;
    // The one timer. Started one-shot by a temperature press, stopped by a
    // flush.
    private var _timer as Timer.Timer;
    // Side whose temperature batch is still waiting for the timer, or null.
    private var _quietZoneId as Lang.String or Null;
    // Last on/temp the server reported, by side id. Copies, separate from
    // the objects in _zones, which hold the values shown on screen.
    private var _confirmed as Lang.Dictionary<Lang.String, BedSide>;
    // True from handing any request to _backend until its callback.
    private var _inFlight as Lang.Boolean;
    // What the in-flight update carried. Null means the field was not sent.
    private var _sentZoneId as Lang.String;
    private var _sentTemp as Lang.Float or Null;
    private var _sentOn as Lang.Boolean or Null;

    function initialize(backend as BedBackend) {
        View.initialize();
        _backend = backend;
        var info = backend.describe();
        _title = info.title;
        _powerWithTemp = info.powerCarriesTemperature;
        _tempMin = 0.0;
        _tempMax = 0.0;
        _step = 0.5;
        _tempFormat = "%.1f";
        _zones = [] as Lang.Array<BedSide>;
        _selectedZone = 0;
        _primaryApplied = false;
        _loading = true;
        _error = null;
        _status = "";
        _statusIsError = false;
        _timer = new Timer.Timer();
        _quietZoneId = null;
        _confirmed = {} as Lang.Dictionary<Lang.String, BedSide>;
        _inFlight = false;
        _sentZoneId = "";
        _sentTemp = null;
        _sentOn = null;
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
        dc.drawText(width / 2, 8, Graphics.FONT_MEDIUM, _title, Graphics.TEXT_JUSTIFY_CENTER);

        var headerBottom = 34;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(10, headerBottom, width - 10, headerBottom);

        if (_loading) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2, Graphics.FONT_SMALL, "Loading…", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        if (_error != null) {
            // Wrapped by word inside the round glass (MessageText).
            MessageText.draw(dc, _error as Lang.String, Graphics.COLOR_RED, headerBottom + 6, height - 34);
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
        dc.drawText(width / 2, zoneTop, Graphics.FONT_SMALL, zone.label, Graphics.TEXT_JUSTIFY_CENTER);

        if (_zones.size() > 1) {
            drawZonePageDots(dc, width, zoneTop + 24);
        }

        var powerLabel = zone.on ? zone.onText : zone.offText;
        dc.setColor((zone.on && zone.running) ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height / 2 - 44, Graphics.FONT_MEDIUM, powerLabel, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var temp = zone.temp;
        if (temp != null) {
            var tempText = temp.format(_tempFormat) + "°";
            dc.drawText(width / 2, height / 2 - 8, Graphics.FONT_NUMBER_MEDIUM, tempText, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            // Number fonts may have no dash glyph.
            dc.drawText(width / 2, height / 2 - 2, Graphics.FONT_MEDIUM, "--", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // A status too wide for one line wraps over the range and hint lines.
        if (_status.length() > 0 && dc.getTextWidthInPixels(_status, Graphics.FONT_XTINY) > (width * 3) / 4) {
            MessageText.draw(dc, _status, statusColor(), height / 2 + 30, height - 36);
            return;
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var rangeText = _tempMin.format("%.0f") + "–" + _tempMax.format("%.0f") + "°";
        var measured = zone.measured;
        if (measured != null) {
            rangeText = "Now " + measured.format(_tempFormat) + "° · " + rangeText;
        }
        dc.drawText(width / 2, height / 2 + 40, Graphics.FONT_XTINY, rangeText, Graphics.TEXT_JUSTIFY_CENTER);

        if (_status.length() > 0) {
            dc.setColor(statusColor(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height - 78, Graphics.FONT_XTINY, _status, Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        if (zone.readOnly) {
            var viewOnly = "View only";
            if (_zones.size() > 1) {
                viewOnly = viewOnly + " · SWIPE";
            }
            dc.drawText(width / 2, height - 44, Graphics.FONT_XTINY, viewOnly, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
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

    private function statusColor() as Graphics.ColorType {
        return _statusIsError ? Graphics.COLOR_RED : Graphics.COLOR_YELLOW;
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
        _statusIsError = false;
        WatchUi.requestUpdate();
        // Nothing after the backend call: the callback may already have run.
        _backend.loadState(method(:onLiveLoaded));
    }

    function onLiveLoaded(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        _loading = false;
        _inFlight = false;
        if (error != null) {
            _error = error;
            WatchUi.requestUpdate();
            return;
        }
        var state = _backend.stateFrom(result);
        if (state != null) {
            applyState(state);
            _zones = state.sides;
            resetConfirmed();
            if (!_primaryApplied && _zones.size() > 0) {
                _selectedZone = state.homeIndex;
                _primaryApplied = true;
            } else if (_selectedZone >= _zones.size()) {
                _selectedZone = _zones.size() > 0 ? _zones.size() - 1 : 0;
            }
        }
        WatchUi.requestUpdate();
    }

    function getSelectedZone() as BedSide or Null {
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
        clearNoteStatus();
        _selectedZone = (_selectedZone + 1) % _zones.size();
        WatchUi.requestUpdate();
    }

    function selectPreviousZone() as Void {
        if (_zones.size() <= 1) {
            return;
        }
        flushPending();
        clearNoteStatus();
        _selectedZone = (_selectedZone - 1 + _zones.size()) % _zones.size();
        WatchUi.requestUpdate();
    }

    // Power taps are never batched. The tap shows at once and ends any quiet
    // period, so a waiting temperature for the side is sent with it, or just
    // before it when the backend needs two requests (REQ-009). With a
    // request in flight it is sent when that one returns. On the load-error
    // screen SELECT retries the load.
    function togglePower() as Void {
        if (_loading) {
            return;
        }
        if (_error != null) {
            refresh();
            return;
        }
        var zone = getSelectedZone();
        if (zone == null || zone.readOnly) {
            return;
        }
        zone.on = !zone.on;
        clearErrorStatus();
        WatchUi.requestUpdate();
        flushPending();
    }

    function increaseTemp() as Void {
        adjustTemp(_step);
    }

    function decreaseTemp() as Void {
        adjustTemp(-_step);
    }

    // Changes the shown value only and restarts the quiet period. Never
    // calls the backend and is never blocked by a request in flight.
    private function adjustTemp(delta as Lang.Float) as Void {
        if (_loading || _error != null) {
            return;
        }
        var zone = getSelectedZone();
        if (zone == null || zone.readOnly) {
            return;
        }
        // With no set temperature the first press starts from startTemp
        // (REQ-012); with neither there is nothing to change.
        var base = zone.temp;
        if (base == null) {
            base = zone.startTemp;
        }
        if (base == null) {
            _status = "No temperature to change yet";
            _statusIsError = false;
            WatchUi.requestUpdate();
            return;
        }
        var newTemp = base + delta;
        if (newTemp < _tempMin) {
            newTemp = _tempMin;
        }
        if (newTemp > _tempMax) {
            newTemp = _tempMax;
        }
        var current = zone.temp;
        if (current != null && newTemp == current) {
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

    // The only sender of updates. Sends the first side whose shown values
    // differ from its confirmed values, one side per request and one
    // backend call per batch, and only when no request is in flight
    // (REQ-011). Read-only sides are never sent.
    private function sendNextIfIdle() as Void {
        if (_inFlight) {
            return;
        }
        for (var i = 0; i < _zones.size(); i += 1) {
            var zone = _zones[i];
            var conf = _confirmed.get(zone.id);
            if (conf == null || zone.readOnly) {
                continue;
            }
            var inQuiet = (_quietZoneId != null) && zone.id.equals(_quietZoneId);
            var sendTemp = !inQuiet && zone.temp != null && !sameTemp(zone.temp, conf.temp);
            var sendOn = (zone.on != conf.on);
            if (sendTemp && sendOn && !_powerWithTemp) {
                // Temperature first; the power change goes after its reply.
                sendOn = false;
            }
            if (!sendTemp && !sendOn) {
                continue;
            }

            _sentZoneId = zone.id;
            _sentTemp = sendTemp ? zone.temp : null;
            _sentOn = sendOn ? zone.on : null;
            _inFlight = true;
            _status = "Updating…";
            _statusIsError = false;
            WatchUi.requestUpdate();
            // Nothing after the backend call: the callback may already have run.
            if (sendOn) {
                _backend.setPower(zone.id, zone.on, sendTemp ? zone.temp : null, method(:onUpdateDone));
            } else {
                _backend.setTemperature(zone.id, zone.temp as Lang.Float, method(:onUpdateDone));
            }
            return;
        }
    }

    function onUpdateDone(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        _inFlight = false;
        if (error != null) {
            revertSentFields();
            _status = error;
            _statusIsError = true;
        } else {
            _status = adoptServerState(_backend.stateFrom(result));
            _statusIsError = false;
        }
        _sentZoneId = "";
        _sentTemp = null;
        _sentOn = null;
        WatchUi.requestUpdate();
        sendNextIfIdle();
    }

    // Failed update: each sent field the user has not changed since goes
    // back to the confirmed value, which is the value from before the batch
    // began (REQ-006). A field changed during the send stays on screen and
    // is sent next (REQ-010). Confirmed values never change on failure.
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

    // Successful update: take the server's sides, except that a field the
    // user changed again since it was sent (or that was never sent and is
    // dirty) keeps its shown value (REQ-012). All lookups are by side id.
    // Returns the status text to show.
    private function adoptServerState(state as BedState or Null) as Lang.String {
        if (state == null || state.sides.size() == 0) {
            // No sides in the reply: trust the update.
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
            if (state != null && state.notice != null) {
                return state.notice as Lang.String;
            }
            return "";
        }

        applyState(state);
        var updated = state.sides;
        var tempDropped = false;
        var newConfirmed = {} as Lang.Dictionary<Lang.String, BedSide>;
        for (var i = 0; i < updated.size(); i += 1) {
            var nz = updated[i];
            var serverCopy = nz.copy();
            var oldShown = findZone(nz.id);
            var oldConf = _confirmed.get(nz.id);
            if (oldShown != null && oldConf != null) {
                var isSent = nz.id.equals(_sentZoneId);
                var expectedTemp = oldConf.temp;
                var sentTemp = _sentTemp;
                if (isSent && sentTemp != null) {
                    expectedTemp = sentTemp;
                    if (nz.temp == null) {
                        tempDropped = true;
                    }
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
            newConfirmed.put(nz.id, serverCopy);
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
        if (tempDropped) {
            // The server took the write but reports no set temperature (the
            // side stays off): show the dash and say why (REQ-014).
            return "Side is off. Temperature not set.";
        }
        return state.notice != null ? state.notice as Lang.String : "";
    }

    private function applyState(state as BedState) as Void {
        _tempMin = state.tempMin;
        _tempMax = state.tempMax;
        _step = state.step;
        _tempFormat = state.tempFormat;
    }

    private function findZone(zoneId as Lang.String) as BedSide or Null {
        for (var i = 0; i < _zones.size(); i += 1) {
            if (_zones[i].id.equals(zoneId)) {
                return _zones[i];
            }
        }
        return null;
    }

    // Float temperatures do not survive +0.5 then -0.5 exactly, so compare
    // with a small tolerance instead of ==. Two nulls are equal; a null and
    // a number are not.
    private function sameTemp(a as Lang.Float or Null, b as Lang.Float or Null) as Lang.Boolean {
        if (a == null || b == null) {
            return a == null && b == null;
        }
        var d = a - b;
        if (d < 0) {
            d = -d;
        }
        return d < 0.01;
    }

    // Rebuild _confirmed from _zones with copies. Sharing the objects would
    // make shown and confirmed always equal.
    private function resetConfirmed() as Void {
        _confirmed = {} as Lang.Dictionary<Lang.String, BedSide>;
        for (var i = 0; i < _zones.size(); i += 1) {
            var z = _zones[i];
            _confirmed.put(z.id, z.copy());
        }
    }

    private function hasUnsentChanges() as Lang.Boolean {
        if (_quietZoneId != null) {
            return true;
        }
        for (var i = 0; i < _zones.size(); i += 1) {
            var zone = _zones[i];
            var conf = _confirmed.get(zone.id);
            if (conf != null && !zone.readOnly && (zone.on != conf.on || (zone.temp != null && !sameTemp(zone.temp, conf.temp)))) {
                return true;
            }
        }
        return false;
    }

    // Clears a stale error status. Leaves "Updating…" and notes alone.
    private function clearErrorStatus() as Void {
        if (_statusIsError) {
            _status = "";
            _statusIsError = false;
        }
    }

    // On a side switch: a note about the old side ("No temperature to
    // change yet") goes; "Updating…" and errors stay.
    private function clearNoteStatus() as Void {
        if (!_inFlight && !_statusIsError) {
            _status = "";
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

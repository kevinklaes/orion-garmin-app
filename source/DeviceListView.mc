// Device list view (oga-8m6) — GET /v1/devices, one row per paired topper
// (name, model, quick on/off glyph). List layout/selection/scroll mirrors
// GarminMerge's PRListView; input mirrors PRListDelegate (onKey/onSelect/
// onTap/onSwipe) so button-only and touch devices both work.
//
// If the account has exactly one device, this view skips itself entirely
// and switches straight to DeviceControlView (docs/DESIGN.md: "reasonable
// to auto-select it... a UX call for the implementer, not a hard
// requirement").
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

class DeviceListView extends WatchUi.View {

    private var _auth as OrionAuth;
    private var _devices as Lang.Array<OrionDevice>;
    // Per-row on/off summary, populated by sequential live fetches after the
    // list loads: true/false once known, null while unknown/failed. Index
    // matches _devices.
    private var _liveOn as Lang.Array<Lang.Boolean or Null>;
    private var _selected as Lang.Number;
    private var _scrollOffset as Lang.Number;
    private var _loading as Lang.Boolean;
    private var _error as Lang.String or Null;
    private var _autoSelected as Lang.Boolean;
    private var _pendingLiveIdx as Lang.Number;

    function initialize() {
        View.initialize();
        _auth = new OrionAuth();
        _devices = [] as Lang.Array<OrionDevice>;
        _liveOn = [] as Lang.Array<Lang.Boolean or Null>;
        _selected = 0;
        _scrollOffset = 0;
        _loading = true;
        _error = null;
        _autoSelected = false;
        _pendingLiveIdx = 0;
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onShow() as Void {
        if (_devices.size() == 0 && _loading && !_autoSelected) {
            refresh();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 8, Graphics.FONT_MEDIUM, "Your Beds", Graphics.TEXT_JUSTIFY_CENTER);

        var headerBottom = 36;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(10, headerBottom, width - 10, headerBottom);

        if (_loading) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2, Graphics.FONT_SMALL, "Loading devices…", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        if (_error != null) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            drawWrapped(dc, 16, headerBottom + 16, width - 32, "Error: " + _error);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height - 22, Graphics.FONT_XTINY, "SELECT to retry", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        if (_devices.size() == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2, Graphics.FONT_SMALL, "No devices found", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height - 22, Graphics.FONT_XTINY, "SELECT to retry", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var rowHeight = 52;
        var listTop = headerBottom + 8;
        var footerH = 28;
        var visibleRows = ((height - listTop - footerH) / rowHeight).toNumber();
        if (visibleRows < 1) {
            visibleRows = 1;
        }

        ensureSelectionVisible(visibleRows);

        for (var i = 0; i < visibleRows; i += 1) {
            var idx = _scrollOffset + i;
            if (idx >= _devices.size()) {
                break;
            }
            var device = _devices[idx];
            var y = listTop + (i * rowHeight);
            var selected = (idx == _selected);

            if (selected) {
                dc.setColor(Graphics.COLOR_DK_BLUE, Graphics.COLOR_DK_BLUE);
                dc.fillRectangle(8, y, width - 16, rowHeight - 4);
            }

            dc.setColor(selected ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(16, y + 4, Graphics.FONT_SMALL, device.name, Graphics.TEXT_JUSTIFY_LEFT);

            dc.setColor(selected ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(16, y + 26, Graphics.FONT_XTINY, device.model, Graphics.TEXT_JUSTIFY_LEFT);

            dc.setColor(onOffColor(idx), Graphics.COLOR_TRANSPARENT);
            dc.drawText(width - 20, y + 14, Graphics.FONT_SMALL, onOffGlyph(idx), Graphics.TEXT_JUSTIFY_RIGHT);
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height - 22, Graphics.FONT_XTINY, "SELECT open · MENU sign out", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function onOffGlyph(idx as Lang.Number) as Lang.String {
        var on = _liveOn[idx];
        if (on == null) {
            return "?";
        }
        return (on as Lang.Boolean) ? "●" : "○";
    }

    private function onOffColor(idx as Lang.Number) as Lang.Number {
        var on = _liveOn[idx];
        if (on == null) {
            return Graphics.COLOR_DK_GRAY;
        }
        return (on as Lang.Boolean) ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY;
    }

    function refresh() as Void {
        _loading = true;
        _error = null;
        WatchUi.requestUpdate();
        _auth.listDevices(method(:onDevicesLoaded));
    }

    function onDevicesLoaded(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        _loading = false;
        if (error != null) {
            _error = error;
            _devices = [] as Lang.Array<OrionDevice>;
            WatchUi.requestUpdate();
            return;
        }

        var devices = [] as Lang.Array<OrionDevice>;
        if (result != null && result instanceof Lang.Array) {
            devices = DeviceModel.devicesFromArray(result as Lang.Array);
        }
        _devices = devices;
        _liveOn = new [devices.size()];
        for (var i = 0; i < devices.size(); i += 1) {
            _liveOn[i] = null;
        }
        if (_selected >= devices.size()) {
            _selected = devices.size() > 0 ? devices.size() - 1 : 0;
        }

        if (devices.size() == 1) {
            _autoSelected = true;
            var controlView = new DeviceControlView(devices[0]);
            WatchUi.switchToView(controlView, new DeviceControlDelegate(controlView, true), WatchUi.SLIDE_IMMEDIATE);
            return;
        }

        WatchUi.requestUpdate();
        if (devices.size() > 0) {
            fetchLiveState(0);
        }
    }

    // Sequential per-row live fetch (OrionAuth only tracks one in-flight
    // call at a time) so the list can show a real on/off glyph per row.
    private function fetchLiveState(idx as Lang.Number) as Void {
        if (idx >= _devices.size()) {
            return;
        }
        _pendingLiveIdx = idx;
        _auth.getLiveDevice(_devices[idx].serialNumber, method(:onLiveStateLoaded));
    }

    function onLiveStateLoaded(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        var idx = _pendingLiveIdx;
        if (idx < _liveOn.size()) {
            if (result != null && result instanceof Lang.Dictionary) {
                var zones = DeviceModel.zonesFromLiveJson(result as Lang.Dictionary);
                var anyOn = false;
                for (var i = 0; i < zones.size(); i += 1) {
                    if (zones[i].on) {
                        anyOn = true;
                        break;
                    }
                }
                _liveOn[idx] = anyOn;
            } else {
                _liveOn[idx] = null;
            }
            WatchUi.requestUpdate();
        }
        fetchLiveState(idx + 1);
    }

    function selectPrevious() as Void {
        if (_devices.size() == 0) {
            return;
        }
        if (_selected > 0) {
            _selected -= 1;
            WatchUi.requestUpdate();
        }
    }

    function selectNext() as Void {
        if (_devices.size() == 0) {
            return;
        }
        if (_selected < _devices.size() - 1) {
            _selected += 1;
            WatchUi.requestUpdate();
        }
    }

    function getSelected() as OrionDevice or Null {
        if (_devices.size() == 0 || _selected < 0 || _selected >= _devices.size()) {
            return null;
        }
        return _devices[_selected];
    }

    function openSelected() as Void {
        if (_loading || _error != null) {
            refresh();
            return;
        }
        var device = getSelected();
        if (device == null) {
            return;
        }
        var controlView = new DeviceControlView(device);
        WatchUi.pushView(controlView, new DeviceControlDelegate(controlView, false), WatchUi.SLIDE_LEFT);
    }

    function selectAtTap(y as Lang.Number, height as Lang.Number) as Void {
        if (_loading || _error != null || _devices.size() == 0) {
            return;
        }
        var headerBottom = 36;
        var listTop = headerBottom + 8;
        var rowHeight = 52;
        var footerH = 28;
        var visibleRows = ((height - listTop - footerH) / rowHeight).toNumber();
        if (visibleRows < 1) {
            visibleRows = 1;
        }
        if (y < listTop) {
            return;
        }
        var row = ((y - listTop) / rowHeight).toNumber();
        if (row < 0 || row >= visibleRows) {
            return;
        }
        var idx = _scrollOffset + row;
        if (idx >= 0 && idx < _devices.size()) {
            _selected = idx;
            openSelected();
        }
    }

    function signOut() as Void {
        OrionAuth.clearStoredToken();
        var view = new ProvisioningView();
        WatchUi.switchToView(view, new ProvisioningDelegate(view), WatchUi.SLIDE_IMMEDIATE);
    }

    private function ensureSelectionVisible(visibleRows as Lang.Number) as Void {
        if (_selected < _scrollOffset) {
            _scrollOffset = _selected;
        } else if (_selected >= _scrollOffset + visibleRows) {
            _scrollOffset = _selected - visibleRows + 1;
        }
        if (_scrollOffset < 0) {
            _scrollOffset = 0;
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

class DeviceListDelegate extends WatchUi.BehaviorDelegate {

    private var _view as DeviceListView;

    function initialize(view as DeviceListView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onMenu() as Lang.Boolean {
        var menu = new WatchUi.Menu2({ :title => "Orion Sleep" });
        menu.addItem(new WatchUi.MenuItem("Refresh", null, :refresh, null));
        menu.addItem(new WatchUi.MenuItem("Sign out", null, :signout, null));
        WatchUi.pushView(menu, new DeviceListMenuDelegate(_view), WatchUi.SLIDE_LEFT);
        return true;
    }

    function onKey(evt as WatchUi.KeyEvent) as Lang.Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_UP) {
            _view.selectPrevious();
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            _view.selectNext();
            return true;
        } else if (key == WatchUi.KEY_ENTER) {
            _view.openSelected();
            return true;
        } else if (key == WatchUi.KEY_START || key == WatchUi.KEY_LAP) {
            _view.refresh();
            return true;
        } else if (key == WatchUi.KEY_MENU) {
            return onMenu();
        } else if (key == WatchUi.KEY_ESC) {
            System.exit();
            return true;
        }
        return false;
    }

    function onPreviousPage() as Lang.Boolean {
        _view.selectPrevious();
        return true;
    }

    function onNextPage() as Lang.Boolean {
        _view.selectNext();
        return true;
    }

    function onSelect() as Lang.Boolean {
        _view.openSelected();
        return true;
    }

    function onBack() as Lang.Boolean {
        System.exit();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Lang.Boolean {
        var coords = evt.getCoordinates();
        var deviceSettings = System.getDeviceSettings();
        _view.selectAtTap(coords[1], deviceSettings.screenHeight);
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Lang.Boolean {
        var dir = evt.getDirection();
        if (dir == WatchUi.SWIPE_UP) {
            _view.selectNext();
            return true;
        } else if (dir == WatchUi.SWIPE_DOWN) {
            _view.selectPrevious();
            return true;
        }
        return false;
    }
}

class DeviceListMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as DeviceListView;

    function initialize(view as DeviceListView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        if (id == :refresh) {
            _view.refresh();
        } else if (id == :signout) {
            _view.signOut();
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

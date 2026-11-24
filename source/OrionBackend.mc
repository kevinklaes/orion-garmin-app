// Orion cloud behind the BedBackend seam (oga-2cx). A thin adapter over
// OrionAuth for one OrionDevice: it makes the same calls with the same
// zone bodies DeviceControlView made before the seam existed, so the URLs,
// methods, headers, bodies and console lines sent to Orion do not change.
// OrionAuth and OrionClient are not modified.
//
// Errors come back as "Error: <text>", the text the control view used to
// build itself, so Orion failures read as before.
using Toybox.Lang;

class OrionBackend extends BedBackend {

    // Mirrors climate.py's _attr_target_temperature_step.
    private const TEMP_STEP = 0.5;

    private var _device as OrionDevice;
    private var _auth as OrionAuth;
    private var _callback as Lang.Method or Null;

    function initialize(device as OrionDevice) {
        BedBackend.initialize();
        _device = device;
        _auth = new OrionAuth();
        _callback = null;
    }

    function describe() as BedInfo {
        return new BedInfo(_device.name, true);
    }

    function loadState(callback as Lang.Method) as Void {
        _callback = callback;
        _auth.getLiveDevice(_device.serialNumber, method(:onReply));
    }

    function setTemperature(sideId as Lang.String, temp as Lang.Float, callback as Lang.Method) as Void {
        _callback = callback;
        var body = { "id" => sideId, "temp" => temp } as Lang.Dictionary;
        _auth.updateLiveDeviceZones(_device.serialNumber, [body], method(:onReply));
    }

    function setPower(sideId as Lang.String, on as Lang.Boolean, temp as Lang.Float or Null, callback as Lang.Method) as Void {
        _callback = callback;
        var body = { "id" => sideId, "on" => on } as Lang.Dictionary;
        if (temp != null) {
            body.put("temp", temp);
        }
        _auth.updateLiveDeviceZones(_device.serialNumber, [body], method(:onReply));
    }

    // The one reply path. Public so method(:onReply) can reach it.
    function onReply(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        var callback = _callback;
        _callback = null;
        if (callback == null) {
            return;
        }
        if (error != null) {
            (callback as Lang.Method).invoke(null, "Error: " + error);
        } else {
            (callback as Lang.Method).invoke(result, null);
        }
    }

    // A live-JSON dictionary -> one side per zone. A dictionary without
    // zones gives a state with no sides; anything else gives null.
    function stateFrom(reply as Lang.Object or Null) as BedState or Null {
        if (reply == null || !(reply instanceof Lang.Dictionary)) {
            return null;
        }
        var zones = DeviceModel.zonesFromLiveJson(reply as Lang.Dictionary);
        var sides = [] as Lang.Array<BedSide>;
        for (var i = 0; i < zones.size(); i += 1) {
            var z = zones[i];
            sides.add(new BedSide(z.id, DeviceModel.zoneLabel(z.id), z.on, z.temp));
        }
        var state = new BedState(sides, _device.tempMin, _device.tempMax, TEMP_STEP, "%.1f");
        state.homeIndex = DeviceModel.primaryZoneIndex(zones);
        return state;
    }
}

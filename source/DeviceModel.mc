// Device + zone models for the device list/control UI (oga-8m6).
//
// Parses the JSON shapes documented on api.py's list_devices()/
// get_live_device()/update_live_device_zones() docstrings. `serialNumber`
// (not the UUID `id`) is what every live/control call keys on -- see
// OrionClient's CRITICAL comment; `id` is kept only for display/dedup.
using Toybox.Lang;

class OrionDevice {
    var id as Lang.String;
    var serialNumber as Lang.String;
    var name as Lang.String;
    var model as Lang.String;
    var tempMin as Lang.Float;
    var tempMax as Lang.Float;
    var zoneIds as Lang.Array<Lang.String>;

    function initialize(
        id as Lang.String,
        serialNumber as Lang.String,
        name as Lang.String,
        model as Lang.String,
        tempMin as Lang.Float,
        tempMax as Lang.Float,
        zoneIds as Lang.Array<Lang.String>
    ) {
        me.id = id;
        me.serialNumber = serialNumber;
        me.name = name;
        me.model = model;
        me.tempMin = tempMin;
        me.tempMax = tempMax;
        me.zoneIds = zoneIds;
    }
}

class OrionZone {
    var id as Lang.String;
    var on as Lang.Boolean;
    var temp as Lang.Float;

    function initialize(id as Lang.String, on as Lang.Boolean, temp as Lang.Float) {
        me.id = id;
        me.on = on;
        me.temp = temp;
    }
}

module DeviceModel {

    // GET /v1/devices item -> OrionDevice. Returns null if serial_number is
    // missing -- a device we can never control is not worth listing.
    function fromDeviceJson(item as Lang.Dictionary) as OrionDevice or Null {
        var serialNumber = stringOrNull(item.get("serial_number"));
        if (serialNumber == null) {
            return null;
        }
        var id = stringOrDefault(item.get("id"), serialNumber);
        var name = stringOrDefault(item.get("name"), "Orion Bed");
        var model = stringOrDefault(item.get("model"), "");

        // Defaults mirror climate.py's OrionZoneClimate fallback (min=10, max=45).
        var tempMin = 10.0;
        var tempMax = 45.0;
        var range = item.get("temperature_range");
        if (range != null && range instanceof Lang.Dictionary) {
            var rangeDict = range as Lang.Dictionary;
            tempMin = floatOrDefault(rangeDict.get("min"), tempMin);
            tempMax = floatOrDefault(rangeDict.get("max"), tempMax);
        }

        var zoneIds = [] as Lang.Array<Lang.String>;
        var zones = item.get("zones");
        if (zones != null && zones instanceof Lang.Array) {
            var arr = zones as Lang.Array;
            for (var i = 0; i < arr.size(); i += 1) {
                var z = arr[i];
                if (z instanceof Lang.Dictionary) {
                    var zid = stringOrNull((z as Lang.Dictionary).get("id"));
                    if (zid != null) {
                        zoneIds.add(zid);
                    }
                } else if (z instanceof Lang.String) {
                    zoneIds.add(z as Lang.String);
                }
            }
        }

        return new OrionDevice(id, serialNumber, name, model, tempMin, tempMax, zoneIds);
    }

    function devicesFromArray(items as Lang.Array) as Lang.Array<OrionDevice> {
        var devices = [] as Lang.Array<OrionDevice>;
        for (var i = 0; i < items.size(); i += 1) {
            var item = items[i];
            if (item instanceof Lang.Dictionary) {
                var device = fromDeviceJson(item as Lang.Dictionary);
                if (device != null) {
                    devices.add(device);
                }
            }
        }
        return devices;
    }

    // GET/PUT .../live unwrapped response -> per-zone on/off + temp.
    // Shape: {"serial_number", "zones": [{"id","on","temp"}, ...], "status": {...}}.
    function zonesFromLiveJson(data as Lang.Dictionary) as Lang.Array<OrionZone> {
        var zones = [] as Lang.Array<OrionZone>;
        var raw = data.get("zones");
        if (raw == null || !(raw instanceof Lang.Array)) {
            return zones;
        }
        var arr = raw as Lang.Array;
        for (var i = 0; i < arr.size(); i += 1) {
            var z = arr[i];
            if (!(z instanceof Lang.Dictionary)) {
                continue;
            }
            var zd = z as Lang.Dictionary;
            var id = stringOrNull(zd.get("id"));
            if (id == null) {
                continue;
            }
            var on = false;
            var onVal = zd.get("on");
            if (onVal != null && onVal instanceof Lang.Boolean) {
                on = onVal as Lang.Boolean;
            }
            var temp = floatOrDefault(zd.get("temp"), 0.0);
            zones.add(new OrionZone(id, on, temp));
        }
        return zones;
    }

    // "zone_a" -> "Zone A"; falls back to the raw id for unrecognised shapes.
    function zoneLabel(id as Lang.String) as Lang.String {
        if (id.length() > 5 && id.substring(0, 5).equals("zone_")) {
            return "Zone " + id.substring(5, id.length()).toUpper();
        }
        return id;
    }

    function stringOrNull(value as Lang.Object or Null) as Lang.String or Null {
        if (value != null && value instanceof Lang.String) {
            return value as Lang.String;
        }
        return null;
    }

    function stringOrDefault(value as Lang.Object or Null, fallback as Lang.String) as Lang.String {
        var s = stringOrNull(value);
        return s != null ? s : fallback;
    }

    function floatOrDefault(value as Lang.Object or Null, fallback as Lang.Float) as Lang.Float {
        if (value != null && value instanceof Lang.Float) {
            return value as Lang.Float;
        }
        if (value != null && value instanceof Lang.Number) {
            return (value as Lang.Number).toFloat();
        }
        if (value != null && value instanceof Lang.Double) {
            return (value as Lang.Double).toFloat();
        }
        return fallback;
    }
}

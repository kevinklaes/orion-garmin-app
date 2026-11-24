// What the glance shows about the bed, and the saved state it reads
// (oga-6bf). The glance never talks to the network. It reads one value from
// Application.Storage, written by the app's views and by the background
// refresh (GlanceRefresh.mc).
//
// Storage keys:
//   "glance_bed"   the bed the glance reports on: the one last opened in the
//                  app (a String, the bed's serial number).
//   "glance_cache" one Dictionary, written whole:
//                  { "bed"   => String,   which bed these values are for
//                    "at"    => Number,   epoch seconds when they were fetched
//                    "zones" => [ { "id" => String, "on" => Boolean,
//                                   "temp" => Float }, ... ] }
// Nothing here knows the Orion reply format, so another backend can write
// the same cache (oga-19od).
using Toybox.Application;
using Toybox.Lang;
using Toybox.Time;

module GlanceCache {

    (:glance, :background) const KEY_BED = "glance_bed";
    (:glance, :background) const KEY_CACHE = "glance_cache";

    // How often the background refresh runs.
    const REFRESH_INTERVAL_SECONDS = 1800;
    // A cache older than this is drawn as old.
    (:glance) const STALE_AFTER_SECONDS = 7200;

    (:glance, :background)
    function glanceBed() as Lang.String or Null {
        var v = Application.Storage.getValue(KEY_BED);
        if (v != null && v instanceof Lang.String && (v as Lang.String).length() > 0) {
            return v as Lang.String;
        }
        return null;
    }

    // Called when a bed's control view opens. The old bed's cache stays in
    // Storage but secondLine() ignores it, because its "bed" no longer
    // matches.
    function setGlanceBed(serial as Lang.String) as Void {
        var current = glanceBed();
        if (current == null || !(current as Lang.String).equals(serial)) {
            Application.Storage.setValue(KEY_BED, serial);
        }
    }

    (:glance)
    function read() as Lang.Object or Null {
        return Application.Storage.getValue(KEY_CACHE);
    }

    (:background)
    function zoneEntry(id as Lang.String, on as Lang.Boolean, temp as Lang.Float) as Lang.Dictionary {
        return { "id" => id, "on" => on, "temp" => temp } as Lang.Dictionary;
    }

    // Saves `zones` (zoneEntry() values, in the bed's order) as the cache
    // for `serial`, fetched now. Returns true when it wrote.
    //
    // Writes nothing when `serial` is not the glance bed, or when `zones` is
    // empty. The background passes the time its run started as
    // `skipIfNewerThan`: a cache fetched at or after that moment came from
    // the app while the run was waiting for its reply, and is kept. Times
    // are whole seconds, so "at or after" is the safe side. The app passes
    // null.
    (:background)
    function write(serial as Lang.String, zones as Lang.Array, skipIfNewerThan as Lang.Number or Null) as Lang.Boolean {
        var bed = glanceBed();
        if (bed == null || !(bed as Lang.String).equals(serial) || zones.size() == 0) {
            return false;
        }
        if (skipIfNewerThan != null) {
            var old = Application.Storage.getValue(KEY_CACHE);
            if (old != null && old instanceof Lang.Dictionary) {
                var at = (old as Lang.Dictionary).get("at");
                if (at != null && at instanceof Lang.Number && (at as Lang.Number) >= (skipIfNewerThan as Lang.Number)) {
                    return false;
                }
            }
        }
        Application.Storage.setValue(KEY_CACHE, {
            "bed" => serial,
            "at" => Time.now().value(),
            "zones" => zones
        } as Lang.Dictionary);
        return true;
    }

    // Sign-out: forget the bed and its state.
    function clear() as Void {
        Application.Storage.deleteValue(KEY_CACHE);
        Application.Storage.deleteValue(KEY_BED);
    }

    // The glance's second line. Pure: no Storage, no clock, no settings.
    // Returns [text as String, stale as Boolean].
    //
    //   signedIn  OrionSession.hasStoredToken()
    //   cache     read()
    //   bed       glanceBed()
    //   zoneId    DeviceModel.primaryZoneId()
    //   now       epoch seconds
    //
    // The zone shown is the one whose id is `zoneId`, or the first zone when
    // the bed does not report that id: the same rule as
    // DeviceModel.zoneIndexForId().
    (:glance)
    function secondLine(
        signedIn as Lang.Boolean,
        cache as Lang.Object or Null,
        bed as Lang.String or Null,
        zoneId as Lang.String,
        now as Lang.Number
    ) as Lang.Array {
        if (!signedIn) {
            return ["Sign in required", false];
        }
        var none = ["Tap to control", false];
        if (bed == null || cache == null || !(cache instanceof Lang.Dictionary)) {
            return none;
        }
        var c = cache as Lang.Dictionary;
        var cacheBed = c.get("bed");
        var at = c.get("at");
        var zones = c.get("zones");
        if (cacheBed == null || !(cacheBed instanceof Lang.String) || !(cacheBed as Lang.String).equals(bed)
            || at == null || !(at instanceof Lang.Number)
            || zones == null || !(zones instanceof Lang.Array) || (zones as Lang.Array).size() == 0) {
            return none;
        }

        var arr = zones as Lang.Array;
        var entry = arr[0];
        for (var i = 0; i < arr.size(); i += 1) {
            var z = arr[i];
            if (z != null && z instanceof Lang.Dictionary) {
                var id = (z as Lang.Dictionary).get("id");
                if (id != null && id instanceof Lang.String && (id as Lang.String).equals(zoneId)) {
                    entry = z;
                    break;
                }
            }
        }
        if (entry == null || !(entry instanceof Lang.Dictionary)) {
            return none;
        }
        var on = (entry as Lang.Dictionary).get("on");
        if (on == null || !(on instanceof Lang.Boolean)) {
            return none;
        }

        // A fetch time in the future (the clock was changed) counts as fresh.
        var stale = (now - (at as Lang.Number)) > STALE_AFTER_SECONDS;
        if (!(on as Lang.Boolean)) {
            return ["Off · Tap to control", stale];
        }
        var temp = (entry as Lang.Dictionary).get("temp");
        if (temp == null || !(temp instanceof Lang.Float)) {
            return none;
        }
        return ["On · " + DeviceModel.tempText(temp as Lang.Float), stale];
    }

    // Whether this screen can draw an old line dimmer. monkey.jungle keeps
    // exactly one of these two per product: black-and-white screens (1 bit
    // per pixel) get the second one.
    (:glance, :colorScreen)
    function canDim() as Lang.Boolean {
        return true;
    }

    (:glance, :monoScreen)
    function canDim() as Lang.Boolean {
        return false;
    }
}

// Unit tests for the glance's second line and its saved state (oga-6bf).
// Run with a --unit-test build and `monkeydo <prg> <device> -t`; see
// docs/TESTING.md. The whole module is annotated (:test) so none of it is
// part of a normal build.
//
// The Storage tests write the two GlanceCache keys and put back what was
// there, so a run leaves the simulator's glance as it found it.
using Toybox.Application;
using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;

(:test)
module GlanceCacheTest {

    const NOW = 1800000000;
    const MINUTE = 60;
    const HOUR = 3600;

    function zone(id as Lang.String, on as Lang.Boolean, temp as Lang.Float) as Lang.Dictionary {
        return GlanceCache.zoneEntry(id, on, temp);
    }

    function cacheAt(bed as Lang.String, at as Lang.Number, zones as Lang.Array) as Lang.Dictionary {
        return { "bed" => bed, "at" => at, "zones" => zones } as Lang.Dictionary;
    }

    // Zone A on at 19.5, fetched 10 minutes ago, for bed "B1".
    function aOn() as Lang.Dictionary {
        return cacheAt("B1", NOW - 10 * MINUTE, [zone("zone_a", true, 19.5)]);
    }

    function check(
        logger as Test.Logger,
        name as Lang.String,
        signedIn as Lang.Boolean,
        cache as Lang.Object or Null,
        bed as Lang.String or Null,
        zoneId as Lang.String,
        expectedText as Lang.String,
        expectedStale as Lang.Boolean
    ) as Lang.Boolean {
        var line = GlanceCache.secondLine(signedIn, cache, bed, zoneId, NOW);
        var text = line[0] as Lang.String;
        var stale = line[1] as Lang.Boolean;
        if (!text.equals(expectedText) || stale != expectedStale) {
            logger.error(name + ": expected '" + expectedText + "' stale=" + expectedStale
                + ", got '" + text + "' stale=" + stale);
            return false;
        }
        return true;
    }

    // REQ-001
    (:test)
    function signedOutIgnoresTheCache(logger as Test.Logger) as Lang.Boolean {
        return check(logger, "signed out", false, aOn(), "B1", "zone_a", "Sign in required", false)
            && check(logger, "signed out, no cache", false, null, null, "zone_a", "Sign in required", false);
    }

    // REQ-002, REQ-013, REQ-014
    (:test)
    function nothingUsableMeansTapToControl(logger as Test.Logger) as Lang.Boolean {
        var tap = "Tap to control";
        var noAt = { "bed" => "B1", "zones" => [zone("zone_a", true, 19.5)] } as Lang.Dictionary;
        var onNotBool = cacheAt("B1", NOW, [{ "id" => "zone_a", "on" => "yes", "temp" => 19.5 } as Lang.Dictionary]);
        var tempNotFloat = cacheAt("B1", NOW, [{ "id" => "zone_a", "on" => true, "temp" => "19.5" } as Lang.Dictionary]);
        var zoneNotDict = cacheAt("B1", NOW, ["zone_a"]);
        var ok = true;
        ok = check(logger, "no cache", true, null, "B1", "zone_a", tap, false) && ok;
        ok = check(logger, "no glance bed", true, aOn(), null, "zone_a", tap, false) && ok;
        ok = check(logger, "another bed's cache", true, aOn(), "B2", "zone_a", tap, false) && ok;
        ok = check(logger, "empty zone list", true, cacheAt("B1", NOW, []), "B1", "zone_a", tap, false) && ok;
        ok = check(logger, "cache is not a dictionary", true, "junk", "B1", "zone_a", tap, false) && ok;
        ok = check(logger, "no fetch time", true, noAt, "B1", "zone_a", tap, false) && ok;
        ok = check(logger, "on is not a boolean", true, onNotBool, "B1", "zone_a", tap, false) && ok;
        ok = check(logger, "temp is not a float", true, tempNotFloat, "B1", "zone_a", tap, false) && ok;
        ok = check(logger, "zone is not a dictionary", true, zoneNotDict, "B1", "zone_a", tap, false) && ok;
        return ok;
    }

    // REQ-003, REQ-004, AC-2
    (:test)
    function onShowsTheSetTemperatureOffSaysOff(logger as Test.Logger) as Lang.Boolean {
        var on20 = cacheAt("B1", NOW - 10 * MINUTE, [zone("zone_a", true, 20.0)]);
        var off = cacheAt("B1", NOW - 10 * MINUTE, [zone("zone_a", false, 19.5)]);
        var ok = true;
        ok = check(logger, "on 19.5", true, aOn(), "B1", "zone_a", "On · 19.5°", false) && ok;
        ok = check(logger, "on 20.0", true, on20, "B1", "zone_a", "On · 20.0°", false) && ok;
        ok = check(logger, "off", true, off, "B1", "zone_a", "Off · Tap to control", false) && ok;
        return ok;
    }

    // AC-2: the glance and the control view format a temperature with the
    // same function.
    (:test)
    function temperatureTextHasOneDecimalAndADegreeSign(logger as Test.Logger) as Lang.Boolean {
        return DeviceModel.tempText(19.5).equals("19.5°") && DeviceModel.tempText(20.0).equals("20.0°");
    }

    // REQ-005
    (:test)
    function showsThePrimaryZoneOrTheFirstZone(logger as Test.Logger) as Lang.Boolean {
        var both = cacheAt("B1", NOW - 10 * MINUTE, [zone("zone_a", false, 19.5), zone("zone_b", true, 22.0)]);
        var ok = true;
        ok = check(logger, "primary A", true, both, "B1", "zone_a", "Off · Tap to control", false) && ok;
        ok = check(logger, "primary B", true, both, "B1", "zone_b", "On · 22.0°", false) && ok;
        ok = check(logger, "primary B, bed has only zone_a", true, aOn(), "B1", "zone_b", "On · 19.5°", false) && ok;
        return ok;
    }

    // REQ-006
    (:test)
    function olderThanTwoHoursIsStale(logger as Test.Logger) as Lang.Boolean {
        var z = [zone("zone_a", true, 19.5)];
        var offYesterday = cacheAt("B1", NOW - 24 * HOUR, [zone("zone_a", false, 19.5)]);
        var ok = true;
        ok = check(logger, "1 h 59 min", true, cacheAt("B1", NOW - 119 * MINUTE, z), "B1", "zone_a", "On · 19.5°", false) && ok;
        ok = check(logger, "exactly 2 h", true, cacheAt("B1", NOW - 2 * HOUR, z), "B1", "zone_a", "On · 19.5°", false) && ok;
        ok = check(logger, "2 h 1 min", true, cacheAt("B1", NOW - 121 * MINUTE, z), "B1", "zone_a", "On · 19.5°", true) && ok;
        ok = check(logger, "off, yesterday", true, offYesterday, "B1", "zone_a", "Off · Tap to control", true) && ok;
        ok = check(logger, "fetched in the future", true, cacheAt("B1", NOW + 30 * MINUTE, z), "B1", "zone_a", "On · 19.5°", false) && ok;
        return ok;
    }

    // ── Storage tests ────────────────────────────────────────────────────

    function saveKeys() as Lang.Array {
        return [
            Application.Storage.getValue(GlanceCache.KEY_BED),
            Application.Storage.getValue(GlanceCache.KEY_CACHE)
        ];
    }

    function restoreKeys(saved as Lang.Array) as Void {
        putOrDelete(GlanceCache.KEY_BED, saved[0]);
        putOrDelete(GlanceCache.KEY_CACHE, saved[1]);
    }

    function putOrDelete(key as Lang.String, value as Lang.Object or Null) as Void {
        if (value == null) {
            Application.Storage.deleteValue(key);
        } else {
            Application.Storage.setValue(key, value as Application.PropertyValueType);
        }
    }

    function storedAt() as Lang.Number or Null {
        var c = Application.Storage.getValue(GlanceCache.KEY_CACHE);
        if (c != null && c instanceof Lang.Dictionary) {
            var at = (c as Lang.Dictionary).get("at");
            if (at != null && at instanceof Lang.Number) {
                return at as Lang.Number;
            }
        }
        return null;
    }

    // REQ-010, REQ-012, REQ-014
    (:test)
    function writesOnlyForTheGlanceBed(logger as Test.Logger) as Lang.Boolean {
        var saved = saveKeys();
        var ok = true;
        try {
            GlanceCache.clear();
            var z = [zone("zone_a", true, 19.5)];
            if (GlanceCache.write("B1", z, null)) {
                logger.error("wrote with no glance bed");
                ok = false;
            }
            GlanceCache.setGlanceBed("B1");
            if (GlanceCache.write("B2", z, null) || GlanceCache.read() != null) {
                logger.error("wrote another bed's state");
                ok = false;
            }
            if (GlanceCache.write("B1", [], null)) {
                logger.error("wrote an empty zone list");
                ok = false;
            }
            if (!GlanceCache.write("B1", z, null)) {
                logger.error("did not write the glance bed's state");
                ok = false;
            }
            var now = Time.now().value();
            var line = GlanceCache.secondLine(true, GlanceCache.read(), GlanceCache.glanceBed(), "zone_a", now);
            if (!(line[0] as Lang.String).equals("On · 19.5°")) {
                logger.error("read back: " + line[0]);
                ok = false;
            }
            // Another bed is opened: the old state is no longer shown.
            GlanceCache.setGlanceBed("B2");
            line = GlanceCache.secondLine(true, GlanceCache.read(), GlanceCache.glanceBed(), "zone_a", now);
            if (!(line[0] as Lang.String).equals("Tap to control")) {
                logger.error("after changing bed: " + line[0]);
                ok = false;
            }
        } finally {
            restoreKeys(saved);
        }
        return ok;
    }

    // REQ-020
    (:test)
    function backgroundDoesNotReplaceNewerState(logger as Test.Logger) as Lang.Boolean {
        var saved = saveKeys();
        var ok = true;
        try {
            GlanceCache.clear();
            GlanceCache.setGlanceBed("B1");
            GlanceCache.write("B1", [zone("zone_a", true, 19.5)], null);
            var at = storedAt() as Lang.Number;
            var older = [zone("zone_a", false, 19.5)];
            if (GlanceCache.write("B1", older, at - 5) || GlanceCache.write("B1", older, at)) {
                logger.error("a run that started before the app's write replaced it");
                ok = false;
            }
            if (!GlanceCache.write("B1", older, at + 1)) {
                logger.error("a run that started after the last write was refused");
                ok = false;
            }
        } finally {
            restoreKeys(saved);
        }
        return ok;
    }

    // REQ-021
    (:test)
    function clearForgetsTheBedAndItsState(logger as Test.Logger) as Lang.Boolean {
        var saved = saveKeys();
        var ok = true;
        try {
            GlanceCache.setGlanceBed("B1");
            GlanceCache.write("B1", [zone("zone_a", true, 19.5)], null);
            GlanceCache.clear();
            ok = GlanceCache.glanceBed() == null && GlanceCache.read() == null;
        } finally {
            restoreKeys(saved);
        }
        return ok;
    }

    // REQ-008, REQ-009: the control view saves after a successful load, and
    // a failed load or update saves nothing. No press is simulated here: a
    // press would start a timer and a real request.
    (:test)
    function controlViewSavesConfirmedStateOnly(logger as Test.Logger) as Lang.Boolean {
        var saved = saveKeys();
        var ok = true;
        try {
            GlanceCache.clear();
            var view = PrimarySideTest.newControlView();
            var ids = ["zone_a", "zone_b"] as Lang.Array<Lang.String>;

            // Not the glance bed yet: a load saves nothing.
            view.onLiveLoaded(PrimarySideTest.liveJson(ids), null);
            if (GlanceCache.read() != null) {
                logger.error("saved a bed that is not the glance bed");
                ok = false;
            }

            GlanceCache.setGlanceBed("SN");
            view.onLiveLoaded(null, "boom");
            view.onUpdateDone(null, "boom");
            if (GlanceCache.read() != null) {
                logger.error("a failed load or update saved state");
                ok = false;
            }

            view.onLiveLoaded(PrimarySideTest.liveJson(ids), null);
            var line = GlanceCache.secondLine(true, GlanceCache.read(), "SN", "zone_b", Time.now().value());
            if (!(line[0] as Lang.String).equals("Off · Tap to control")) {
                logger.error("after a load: " + line[0]);
                ok = false;
            }
        } finally {
            restoreKeys(saved);
        }
        return ok;
    }

    // The three reply shapes OrionSession.extractTokens() accepts.
    (:test)
    function extractTokensReadsAllThreeShapes(logger as Test.Logger) as Lang.Boolean {
        var nested = { "response" => { "session" => { "access_token" => "a", "refresh_token" => "r", "expires_at" => 7 } } } as Lang.Dictionary;
        var camel = { "accessToken" => "a", "refreshToken" => "r", "expiresAt" => 7 } as Lang.Dictionary;
        var snake = { "access_token" => "a", "refresh_token" => "r", "expires_at" => 7 } as Lang.Dictionary;
        var shapes = [nested, camel, snake] as Lang.Array<Lang.Dictionary>;
        var ok = true;
        for (var i = 0; i < shapes.size(); i += 1) {
            var t = OrionSession.extractTokens(shapes[i]);
            if (t == null || !(t.get("access_token") as Lang.String).equals("a")
                || !(t.get("refresh_token") as Lang.String).equals("r")
                || (t.get("expires_at") as Lang.Number) != 7) {
                logger.error("shape #" + i + " was not read");
                ok = false;
            }
        }
        if (OrionSession.extractTokens({ "success" => true } as Lang.Dictionary) != null) {
            logger.error("an unknown shape returned tokens");
            ok = false;
        }
        return ok;
    }
}

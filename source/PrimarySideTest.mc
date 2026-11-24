// Unit tests for the primary side setting (oga-ep7): the DeviceModel
// helpers and the "apply once" rule in DeviceControlView.onLiveLoaded().
// Run with a --unit-test build and `monkeydo <prg> <device> -t`; see
// docs/TESTING.md. The whole module is annotated (:test) so none of it is
// part of a normal build.
using Toybox.Lang;
using Toybox.Test;

(:test)
module PrimarySideTest {

    function zones(ids as Lang.Array<Lang.String>) as Lang.Array<OrionZone> {
        var out = [] as Lang.Array<OrionZone>;
        for (var i = 0; i < ids.size(); i += 1) {
            out.add(new OrionZone(ids[i], false, 20.0));
        }
        return out;
    }

    function liveJson(ids as Lang.Array<Lang.String>) as Lang.Dictionary {
        var list = [] as Lang.Array<Lang.Dictionary>;
        for (var i = 0; i < ids.size(); i += 1) {
            list.add({ "id" => ids[i], "on" => false, "temp" => 20.0 } as Lang.Dictionary);
        }
        return { "zones" => list } as Lang.Dictionary;
    }

    function newControlView() as DeviceControlView {
        var ids = ["zone_a", "zone_b"] as Lang.Array<Lang.String>;
        return new DeviceControlView(new OrionDevice("id", "SN", "Bed", "", 10.0, 45.0, ids));
    }

    function focusedId(view as DeviceControlView) as Lang.String {
        var zone = view.getSelectedZone();
        return zone != null ? zone.id : "(none)";
    }

    function checkIndex(logger as Test.Logger, ids as Lang.Array<Lang.String>, zoneId as Lang.String, expected as Lang.Number) as Lang.Boolean {
        var actual = DeviceModel.zoneIndexForId(zones(ids), zoneId);
        if (actual != expected) {
            logger.error(ids.toString() + " with " + zoneId + ": expected " + expected + ", got " + actual);
            return false;
        }
        return true;
    }

    (:test)
    function sideValueMapsToZoneId(logger as Test.Logger) as Lang.Boolean {
        return DeviceModel.zoneIdForSide(0).equals("zone_a")
            && DeviceModel.zoneIdForSide(1).equals("zone_b");
    }

    (:test)
    function unexpectedSideValueMeansZoneA(logger as Test.Logger) as Lang.Boolean {
        var bad = [null, 2, -1, "1", 1.0] as Lang.Array;
        var ok = true;
        for (var i = 0; i < bad.size(); i += 1) {
            if (!DeviceModel.zoneIdForSide(bad[i]).equals("zone_a")) {
                logger.error("value #" + i + " did not map to zone_a");
                ok = false;
            }
        }
        return ok;
    }

    (:test)
    function zoneIndexFindsThePrimaryZone(logger as Test.Logger) as Lang.Boolean {
        var ok = checkIndex(logger, ["zone_a", "zone_b"], "zone_a", 0);
        ok = checkIndex(logger, ["zone_a", "zone_b"], "zone_b", 1) && ok;
        ok = checkIndex(logger, ["zone_b", "zone_a"], "zone_a", 1) && ok;
        return ok;
    }

    (:test)
    function zoneIndexFallsBackToFirstZone(logger as Test.Logger) as Lang.Boolean {
        var ok = checkIndex(logger, ["zone_a"], "zone_b", 0);
        ok = checkIndex(logger, ["zone_b"], "zone_a", 0) && ok;
        ok = checkIndex(logger, ["left", "right"], "zone_b", 0) && ok;
        ok = checkIndex(logger, [] as Lang.Array<Lang.String>, "zone_b", 0) && ok;
        return ok;
    }

    // Exercises the real Application.Properties read. The stored value may
    // be 0 or 1 depending on the simulator's settings, so this checks the
    // contract (a known zone id, no exception), not a particular side.
    (:test)
    function primaryZoneIdReturnsAKnownZone(logger as Test.Logger) as Lang.Boolean {
        var id = DeviceModel.primaryZoneId();
        logger.debug("primaryZoneId() = " + id);
        var both = zones(["zone_a", "zone_b"]);
        return (id.equals("zone_a") || id.equals("zone_b"))
            && DeviceModel.primaryZoneIndex(both) == DeviceModel.zoneIndexForId(both, id);
    }

    // The two zone orders matter: whichever side the simulator's setting
    // says, the primary zone is not at index 0 in one of them, so these
    // tests fail against a view that always starts on the first zone.
    function bothOrders() as Lang.Array<Lang.Array<Lang.String> > {
        return [["zone_a", "zone_b"], ["zone_b", "zone_a"]] as Lang.Array<Lang.Array<Lang.String> >;
    }

    (:test)
    function controlViewOpensOnPrimaryZone(logger as Test.Logger) as Lang.Boolean {
        var orders = bothOrders();
        var ok = true;
        for (var i = 0; i < orders.size(); i += 1) {
            var view = newControlView();
            view.onLiveLoaded(liveJson(orders[i]), null);
            if (!focusedId(view).equals(DeviceModel.primaryZoneId())) {
                logger.error(orders[i].toString() + ": opened on " + focusedId(view));
                ok = false;
            }
        }
        return ok;
    }

    (:test)
    function controlViewAppliesPrimaryOnlyOnce(logger as Test.Logger) as Lang.Boolean {
        var view = newControlView();
        var json = liveJson(["zone_a", "zone_b"]);
        view.onLiveLoaded(json, null);
        view.selectNextZone();
        var chosen = focusedId(view);
        if (chosen.equals(DeviceModel.primaryZoneId())) {
            logger.error("selectNextZone() did not leave the primary zone");
            return false;
        }
        // A refresh must not pull focus back to the primary side.
        view.onLiveLoaded(json, null);
        return focusedId(view).equals(chosen);
    }

    (:test)
    function controlViewAppliesPrimaryAfterFailedFirstLoad(logger as Test.Logger) as Lang.Boolean {
        var orders = bothOrders();
        var ok = true;
        for (var i = 0; i < orders.size(); i += 1) {
            var view = newControlView();
            view.onLiveLoaded(null, "network error");
            if (view.getSelectedZone() != null) {
                logger.error("a failed load left a zone focused");
                ok = false;
            }
            view.onLiveLoaded(liveJson(orders[i]), null);
            if (!focusedId(view).equals(DeviceModel.primaryZoneId())) {
                logger.error(orders[i].toString() + ": opened on " + focusedId(view) + " after a failed first load");
                ok = false;
            }
        }
        return ok;
    }

    (:test)
    function controlViewFallsBackOnSingleZoneBed(logger as Test.Logger) as Lang.Boolean {
        var view = newControlView();
        view.onLiveLoaded(liveJson(["left"]), null);
        return focusedId(view).equals("left");
    }
}

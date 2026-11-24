// Unit tests for DeviceControlView through the BedBackend seam (oga-2cx):
// a fake backend records what the view asks it to send, so the batching,
// read-only sides and the first-press rule are checked without a network.
// Also checks that OrionBackend turns Orion live JSON into the same sides
// the view showed before the seam. Run with a --unit-test build and
// `monkeydo <prg> <device> -t`; see docs/TESTING.md. Everything here is
// annotated (:test) so none of it is part of a normal build.
using Toybox.Lang;
using Toybox.Test;

// Returns the BedState it is handed through onLiveLoaded() from
// stateFrom(), records every write, and never invokes a callback.
(:test)
class FakeBedBackend extends BedBackend {

    var powerWithTemp as Lang.Boolean;
    // One entry per write: "temp <id> <value>" or "power <id> <on> <temp>".
    var calls as Lang.Array<Lang.String>;

    function initialize(powerWithTemp as Lang.Boolean) {
        BedBackend.initialize();
        me.powerWithTemp = powerWithTemp;
        calls = [] as Lang.Array<Lang.String>;
    }

    function describe() as BedInfo {
        return new BedInfo("Fake", powerWithTemp);
    }

    function loadState(callback as Lang.Method) as Void {
    }

    function setTemperature(sideId as Lang.String, temp as Lang.Float, callback as Lang.Method) as Void {
        calls.add("temp " + sideId + " " + temp.format("%.1f"));
    }

    function setPower(sideId as Lang.String, on as Lang.Boolean, temp as Lang.Float or Null, callback as Lang.Method) as Void {
        calls.add("power " + sideId + " " + on + " " + (temp != null ? temp.format("%.1f") : "-"));
    }

    function stateFrom(reply as Lang.Object or Null) as BedState or Null {
        if (reply != null && reply instanceof BedState) {
            return reply as BedState;
        }
        return null;
    }
}

(:test)
module BackendViewTest {

    // Two sides, "me" (on, 20.0) and "partner" (on, 18.5, read-only), range
    // 12..35 in 0.5 steps.
    function twoSides(homeIndex as Lang.Number) as BedState {
        var mine = new BedSide("me", "Me", true, 20.0);
        var partner = new BedSide("partner", "Partner", true, 18.5);
        partner.readOnly = true;
        var state = new BedState([mine, partner] as Lang.Array<BedSide>, 12.0, 35.0, 0.5, "%.1f");
        state.homeIndex = homeIndex;
        return state;
    }

    function oneSide(temp as Lang.Float or Null, startTemp as Lang.Float or Null) as BedState {
        var side = new BedSide("me", "Me", true, temp);
        side.startTemp = startTemp;
        return new BedState([side] as Lang.Array<BedSide>, 12.0, 35.0, 0.5, "%.1f");
    }

    function openView(backend as FakeBedBackend, state as BedState) as DeviceControlView {
        var view = new DeviceControlView(backend);
        view.onLiveLoaded(state, null);
        return view;
    }

    function checkCalls(logger as Test.Logger, backend as FakeBedBackend, expected as Lang.Array<Lang.String>) as Lang.Boolean {
        var ok = backend.calls.size() == expected.size();
        for (var i = 0; ok && i < expected.size(); i += 1) {
            ok = backend.calls[i].equals(expected[i]);
        }
        if (!ok) {
            logger.error("expected " + expected.toString() + ", got " + backend.calls.toString());
        }
        return ok;
    }

    (:test)
    function viewOpensOnHomeSide(logger as Test.Logger) as Lang.Boolean {
        var view = openView(new FakeBedBackend(false), twoSides(1));
        var zone = view.getSelectedZone();
        return zone != null && zone.id.equals("partner");
    }

    (:test)
    function readOnlySideSendsNothing(logger as Test.Logger) as Lang.Boolean {
        var backend = new FakeBedBackend(false);
        var view = openView(backend, twoSides(1));
        view.increaseTemp();
        view.decreaseTemp();
        view.togglePower();
        view.flushPending();
        var zone = view.getSelectedZone();
        if (zone == null || !zone.on || zone.temp != 18.5) {
            logger.error("the partner side changed");
            return false;
        }
        return checkCalls(logger, backend, [] as Lang.Array<Lang.String>);
    }

    (:test)
    function oneCallPerBatch(logger as Test.Logger) as Lang.Boolean {
        var backend = new FakeBedBackend(false);
        var view = openView(backend, twoSides(0));
        for (var i = 0; i < 5; i += 1) {
            view.increaseTemp();
        }
        view.flushPending();
        return checkCalls(logger, backend, ["temp me 22.5"] as Lang.Array<Lang.String>);
    }

    (:test)
    function firstPressUsesStartTemp(logger as Test.Logger) as Lang.Boolean {
        var backend = new FakeBedBackend(false);
        var view = openView(backend, oneSide(null, 20.5));
        view.increaseTemp();
        var zone = view.getSelectedZone();
        if (zone == null || zone.temp == null || zone.temp != 21.0) {
            logger.error("first press did not show 21.0");
            return false;
        }
        view.flushPending();
        return checkCalls(logger, backend, ["temp me 21.0"] as Lang.Array<Lang.String>);
    }

    (:test)
    function noStartTempDoesNothing(logger as Test.Logger) as Lang.Boolean {
        var backend = new FakeBedBackend(false);
        var view = openView(backend, oneSide(null, null));
        view.increaseTemp();
        view.flushPending();
        var zone = view.getSelectedZone();
        if (zone == null || zone.temp != null) {
            logger.error("a press set a temperature");
            return false;
        }
        return checkCalls(logger, backend, [] as Lang.Array<Lang.String>);
    }

    (:test)
    function temperatureBeforePower(logger as Test.Logger) as Lang.Boolean {
        var backend = new FakeBedBackend(false);
        var view = openView(backend, twoSides(0));
        view.increaseTemp();
        view.togglePower();
        if (!checkCalls(logger, backend, ["temp me 20.5"] as Lang.Array<Lang.String>)) {
            return false;
        }
        // The write was taken but its reply could not be read.
        view.onUpdateDone(null, null);
        return checkCalls(logger, backend, ["temp me 20.5", "power me false -"] as Lang.Array<Lang.String>);
    }

    (:test)
    function powerCarriesTemperature(logger as Test.Logger) as Lang.Boolean {
        var backend = new FakeBedBackend(true);
        var view = openView(backend, twoSides(0));
        view.increaseTemp();
        view.togglePower();
        return checkCalls(logger, backend, ["power me false 20.5"] as Lang.Array<Lang.String>);
    }

    (:test)
    function orionSidesFromLiveJson(logger as Test.Logger) as Lang.Boolean {
        var ids = ["zone_a", "zone_b"] as Lang.Array<Lang.String>;
        var backend = new OrionBackend(new OrionDevice("id", "SN", "Bed", "", 10.0, 45.0, ids));
        var json = {
            "zones" => [
                { "id" => "zone_a", "on" => true, "temp" => 21.5 },
                { "id" => "zone_b", "on" => false, "temp" => 19.0 }
            ]
        } as Lang.Dictionary;
        var state = backend.stateFrom(json);
        if (state == null || state.sides.size() != 2) {
            logger.error("expected two sides");
            return false;
        }
        var a = state.sides[0];
        var b = state.sides[1];
        var ok = a.label.equals("Zone A") && b.label.equals("Zone B")
            && a.on && !b.on && a.temp == 21.5 && b.temp == 19.0
            && !a.readOnly && !b.readOnly
            && state.tempMin == 10.0 && state.tempMax == 45.0 && state.step == 0.5;
        if (!ok) {
            logger.error("sides or range differ from the live JSON");
        }
        var zones = DeviceModel.zonesFromLiveJson(json);
        if (state.homeIndex != DeviceModel.primaryZoneIndex(zones)) {
            logger.error("homeIndex " + state.homeIndex + " is not the primary zone");
            ok = false;
        }
        return ok && backend.stateFrom(null) == null && backend.stateFrom("x") == null;
    }
}

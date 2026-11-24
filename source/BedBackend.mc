// The backend seam (oga-2cx): what DeviceControlView talks to in place of
// a network client. Two backends extend BedBackend: OrionBackend (the Orion
// cloud, wrapping OrionAuth unchanged) and EmberTideClient (a self-hosted
// Ember & Tide server). The view never knows which one it has.
//
// Contract for every backend:
// - Callbacks are (result as Lang.Object or Null, error as Lang.String or
//   Null), the same shape OrionAuth uses.
// - error non-null means the request failed. The text is complete and
//   ready to show; the view adds nothing to it.
// - error null means the server took the request and result is its reply.
//   The caller reads a reply only through stateFrom(result).
// - stateFrom() sends nothing and never throws. Null, or a state with no
//   sides, means "nothing to adopt".
// - One request at a time: the caller does not call again until the
//   callback has run. The callback may run before the method returns.
// - Nothing here or in a backend uses Toybox.WatchUi, so a glance or a
//   background service can use a backend too (oga-19od).
//
// Monkey C has no abstract methods, so the base bodies answer "not
// supported" through the callback.
using Toybox.Lang;

// What a backend can say about itself without a request.
class BedInfo {
    // Header line of the control view.
    var title as Lang.String;
    // True when one request can carry a power change and a temperature for
    // the same side (Orion's PUT). False makes the view send the
    // temperature first and the power change after its reply.
    var powerCarriesTemperature as Lang.Boolean;

    function initialize(title as Lang.String, powerCarriesTemperature as Lang.Boolean) {
        me.title = title;
        me.powerCarriesTemperature = powerCarriesTemperature;
    }
}

// One page of the control view: an Orion zone or an Ember & Tide person.
// Temperatures are in the unit shown on screen.
class BedSide {
    var id as Lang.String;
    // Page title: "Zone A", "Kevin".
    var label as Lang.String;
    // The power switch.
    var on as Lang.Boolean;
    // Set temperature as shown; null means there is none.
    var temp as Lang.Float or Null;
    // Where the first press starts when temp is null; null means presses
    // do nothing.
    var startTemp as Lang.Float or Null;
    // Measured temperature as shown; null means not reported.
    var measured as Lang.Float or Null;
    // Power label when the switch is on / off.
    var onText as Lang.String;
    var offText as Lang.String;
    // Draw the on label green.
    var running as Lang.Boolean;
    // Presses on this side send nothing.
    var readOnly as Lang.Boolean;

    function initialize(id as Lang.String, label as Lang.String, on as Lang.Boolean, temp as Lang.Float or Null) {
        me.id = id;
        me.label = label;
        me.on = on;
        me.temp = temp;
        startTemp = null;
        measured = null;
        onText = "ON";
        offText = "OFF";
        running = true;
        readOnly = false;
    }

    function copy() as BedSide {
        var c = new BedSide(id, label, on, temp);
        c.startTemp = startTemp;
        c.measured = measured;
        c.onText = onText;
        c.offText = offText;
        c.running = running;
        c.readOnly = readOnly;
        return c;
    }
}

// Everything the control view draws, built by a backend from one reply.
class BedState {
    var sides as Lang.Array<BedSide>;
    // The side to open on.
    var homeIndex as Lang.Number;
    // Range and step, in the unit shown.
    var tempMin as Lang.Float;
    var tempMax as Lang.Float;
    var step as Lang.Float;
    // "%.1f" or "%.0f".
    var tempFormat as Lang.String;
    // A note for the status line, not an error. Null for none.
    var notice as Lang.String or Null;

    function initialize(sides as Lang.Array<BedSide>, tempMin as Lang.Float, tempMax as Lang.Float, step as Lang.Float, tempFormat as Lang.String) {
        me.sides = sides;
        homeIndex = 0;
        me.tempMin = tempMin;
        me.tempMax = tempMax;
        me.step = step;
        me.tempFormat = tempFormat;
        notice = null;
    }
}

class BedBackend {

    const NOT_SUPPORTED = "Not supported";

    function initialize() {
    }

    function describe() as BedInfo {
        return new BedInfo("", true);
    }

    function loadState(callback as Lang.Method) as Void {
        callback.invoke(null, NOT_SUPPORTED);
    }

    // temp is the shown value.
    function setTemperature(sideId as Lang.String, temp as Lang.Float, callback as Lang.Method) as Void {
        callback.invoke(null, NOT_SUPPORTED);
    }

    // temp is non-null only when describe().powerCarriesTemperature is true
    // and a temperature is waiting for the same side.
    function setPower(sideId as Lang.String, on as Lang.Boolean, temp as Lang.Float or Null, callback as Lang.Method) as Void {
        callback.invoke(null, NOT_SUPPORTED);
    }

    function stateFrom(reply as Lang.Object or Null) as BedState or Null {
        return null;
    }
}

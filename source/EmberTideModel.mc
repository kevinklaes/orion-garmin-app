// Ember & Tide pure code (oga-2cx): everything about the self-hosted
// Ember & Tide server that can be worked out without a request. Parsing
// the snapshot and the auth state, the label table, the request paths,
// headers and bodies, the one pair of temperature conversions in the app,
// and the on-watch error texts. EmberTideClient sends the requests; this
// module only takes values and returns values, so (:test) code can call
// every function (EmberTideTest.mc).
//
// Facts relied on (ember-tide origin/main at c46accc, under core/embertide/;
// see plans/embertide-backend/build/implementation-plan.md for the table):
// - The snapshot does not say who the caller is. GET /api/auth/state does:
//   me.person for the Bearer key (auth_api.py:286-304).
// - Per person (engine/controller.py:1306-1339): id, name, settings.units
//   ("F" or "C", default "F"), night.{state, skip, pause_until, target_c},
//   bed.{on, setpoint_c, measured_c}. Any of these can be null. Top-level
//   `now` is unix seconds; household.user_min_c / user_max_c is the range.
// - The set temperature is night.target_c, the engine's target (night.py:548).
// - Refusals are {"detail": "<text>"} (auth_api.py:645-653).
// The parser reads only those fields and never walks actual, curve,
// rhythm_curve or phases.
//
// Units: requests always carry Celsius; the watch shows *my* unit for every
// side. Fahrenheit is whole degrees with a step of 1, Celsius one decimal
// with a step of 0.5, as Ember & Tide's own clients show them. A value from
// the server, shown, and sent back unchanged does not drift: 20.0 C shows
// as 68, one press makes 69, sent as 20.56, which shows as 69 again.
using Toybox.Communications;
using Toybox.Lang;
using Toybox.Math;

// One person from the snapshot, with only the fields the watch uses.
class EtPerson {
    var id as Lang.String;
    var name as Lang.String;
    var fahrenheit as Lang.Boolean;
    var state as Lang.String;
    var skip as Lang.Boolean;
    // Unix seconds, kept as a Double: a Float would round to minutes.
    var pauseUntil as Lang.Double or Null;
    var targetC as Lang.Float or Null;
    var bedOn as Lang.Boolean or Null;
    var setpointC as Lang.Float or Null;
    var measuredC as Lang.Float or Null;

    function initialize(id as Lang.String) {
        me.id = id;
        name = id;
        fahrenheit = true;
        state = "";
        skip = false;
        pauseUntil = null;
        targetC = null;
        bedOn = null;
        setpointC = null;
        measuredC = null;
    }
}

module EmberTideModel {

    const SNAPSHOT_PATH = "/api/snapshot";
    const AUTH_STATE_PATH = "/api/auth/state";
    const PEOPLE_PATH = "/api/people/";
    // A change from the watch holds until the night ends: the watch shows
    // one number and has nowhere to show phases (implementation plan,
    // decision 5). Never "every_night", which would edit the saved rhythm.
    const ADJUST_UNTIL = "night";
    // Off turns the side off for tonight; on undoes skip and pause.
    const OFF_ACTION = "skip";
    const ON_ACTION = "resume";
    const SOURCE = "watch";

    const DEFAULT_MIN_C = 12.0;
    const DEFAULT_MAX_C = 35.0;
    // What the server accepts for temp_c (api.py:24).
    const API_MIN_C = 10.0;
    const API_MAX_C = 45.0;

    // On-watch texts.
    const TOO_LARGE_TEXT = "Reply too large for this watch";
    const UNREACHABLE_TEXT = "Can't reach your server";
    const KEY_TEXT = "Key not accepted, make a new one";
    const NO_PERSON_TEXT = "This key has no side of the bed";
    const UNEXPECTED_TEXT = "Unexpected reply from your server";
    const NOT_ON_BED_TEXT = "Your side is not on this bed";
    const SENT_UNREADABLE_TEXT = "Sent. Reply too large to read.";
    const VIEW_ONLY_TEXT = "View only";
    const DEVICE_KEY_PREFIX = "This device key can't do that";

    // ── Requests ─────────────────────────────────────────────────────────

    // The only place that builds Ember & Tide headers. Without the JSON
    // content type Connect IQ sends a POST body form-encoded.
    function headers(key as Lang.String) as Lang.Dictionary {
        return {
            "Authorization" => "Bearer " + key,
            "X-Embertide" => "1",
            "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
        } as Lang.Dictionary;
    }

    function adjustPath(personId as Lang.String) as Lang.String {
        return PEOPLE_PATH + personId + "/adjust";
    }

    function tonightPath(personId as Lang.String) as Lang.String {
        return PEOPLE_PATH + personId + "/tonight";
    }

    function adjustBody(tempC as Lang.Float) as Lang.Dictionary {
        return { "temp_c" => tempC, "until" => ADJUST_UNTIL, "source" => SOURCE } as Lang.Dictionary;
    }

    function tonightBody(on as Lang.Boolean) as Lang.Dictionary {
        return { "action" => on ? ON_ACTION : OFF_ACTION, "source" => SOURCE } as Lang.Dictionary;
    }

    // ── Units: the only temperature conversion in the app ─────────────────

    function cToF(c as Lang.Float) as Lang.Float {
        return c * 9 / 5 + 32;
    }

    function fToC(f as Lang.Float) as Lang.Float {
        return (f - 32) * 5 / 9;
    }

    // Celsius from the server -> the number shown.
    function toShown(c as Lang.Float, fahrenheit as Lang.Boolean) as Lang.Float {
        if (fahrenheit) {
            return Math.round(cToF(c)).toFloat();
        }
        return c;
    }

    // The number shown -> Celsius for a request, rounded to 2 decimals and
    // inside both the household range and what the server accepts.
    function toCelsius(shown as Lang.Float, fahrenheit as Lang.Boolean, minC as Lang.Float, maxC as Lang.Float) as Lang.Float {
        var c = fahrenheit ? fToC(shown) : shown;
        c = (Math.round(c * 100) / 100.0).toFloat();
        var low = minC > API_MIN_C ? minC : API_MIN_C;
        var high = maxC < API_MAX_C ? maxC : API_MAX_C;
        if (c < low) {
            c = low;
        }
        if (c > high) {
            c = high;
        }
        return c;
    }

    // Fahrenheit rounds the bottom of the range up and the top down, so
    // every whole degree shown converts to a Celsius value inside the range.
    function shownMin(minC as Lang.Float, fahrenheit as Lang.Boolean) as Lang.Float {
        return fahrenheit ? Math.ceil(cToF(minC) - 0.001).toFloat() : minC;
    }

    function shownMax(maxC as Lang.Float, fahrenheit as Lang.Boolean) as Lang.Float {
        return fahrenheit ? Math.floor(cToF(maxC) + 0.001).toFloat() : maxC;
    }

    function stepFor(fahrenheit as Lang.Boolean) as Lang.Float {
        return fahrenheit ? 1.0 : 0.5;
    }

    function formatFor(fahrenheit as Lang.Boolean) as Lang.String {
        return fahrenheit ? "%.0f" : "%.1f";
    }

    // Where the first press starts when a side has no set temperature: the
    // measured temperature in shown units, rounded to the nearest step,
    // inside the shown range. Null when nothing is measured.
    function startShown(measuredC as Lang.Float or Null, fahrenheit as Lang.Boolean, minC as Lang.Float, maxC as Lang.Float) as Lang.Float or Null {
        if (measuredC == null) {
            return null;
        }
        var shown = fahrenheit ? cToF(measuredC) : measuredC;
        var step = stepFor(fahrenheit);
        var v = (Math.round(shown / step) * step).toFloat();
        var low = shownMin(minC, fahrenheit);
        var high = shownMax(maxC, fahrenheit);
        if (v < low) {
            v = low;
        }
        if (v > high) {
            v = high;
        }
        return v;
    }

    // ── Who is me ────────────────────────────────────────────────────────

    function personIdFromAuthState(data as Lang.Object or Null) as Lang.String or Null {
        var meDict = dictOrNull(dictGet(data, "me"));
        var person = stringOrNull(dictGet(meDict, "person"));
        if (person == null || person.length() == 0) {
            return null;
        }
        return person;
    }

    // Why an auth-state reply gives no person, or null when it does. An
    // unknown key gets `me: null` with status 200.
    function authStateProblem(data as Lang.Object or Null) as Lang.String or Null {
        if (dictOrNull(data) == null || dictOrNull(dictGet(data, "me")) == null) {
            return KEY_TEXT;
        }
        if (personIdFromAuthState(data) == null) {
            return NO_PERSON_TEXT;
        }
        return null;
    }

    // ── Parsing ──────────────────────────────────────────────────────────

    function personFrom(value as Lang.Object or Null) as EtPerson or Null {
        var id = stringOrNull(dictGet(value, "id"));
        if (id == null) {
            return null;
        }
        var p = new EtPerson(id);
        var name = stringOrNull(dictGet(value, "name"));
        if (name != null) {
            p.name = name;
        }
        var units = stringOrNull(dictGet(dictGet(value, "settings"), "units"));
        p.fahrenheit = !(units != null && units.equals("C"));
        var night = dictGet(value, "night");
        var state = stringOrNull(dictGet(night, "state"));
        if (state != null) {
            p.state = state;
        }
        var skip = dictGet(night, "skip");
        p.skip = skip != null && skip instanceof Lang.Boolean && (skip as Lang.Boolean);
        p.pauseUntil = doubleOrNull(dictGet(night, "pause_until"));
        p.targetC = floatOrNull(dictGet(night, "target_c"));
        var bed = dictGet(value, "bed");
        var bedOn = dictGet(bed, "on");
        if (bedOn != null && bedOn instanceof Lang.Boolean) {
            p.bedOn = bedOn as Lang.Boolean;
        }
        p.setpointC = floatOrNull(dictGet(bed, "setpoint_c"));
        p.measuredC = floatOrNull(dictGet(bed, "measured_c"));
        return p;
    }

    // snapshot["people"], skipping entries without an id. Empty for
    // anything unexpected.
    function peopleFrom(snapshot as Lang.Object or Null) as Lang.Array<EtPerson> {
        var out = [] as Lang.Array<EtPerson>;
        var raw = dictGet(snapshot, "people");
        if (raw == null || !(raw instanceof Lang.Array)) {
            return out;
        }
        var arr = raw as Lang.Array;
        for (var i = 0; i < arr.size(); i += 1) {
            var p = personFrom(arr[i]);
            if (p != null) {
                out.add(p);
            }
        }
        return out;
    }

    function findPerson(people as Lang.Array<EtPerson>, id as Lang.String or Null) as EtPerson or Null {
        if (id == null) {
            return null;
        }
        for (var i = 0; i < people.size(); i += 1) {
            if (people[i].id.equals(id)) {
                return people[i];
            }
        }
        return null;
    }

    function rangeMinC(snapshot as Lang.Object or Null) as Lang.Float {
        var v = floatOrNull(dictGet(dictGet(snapshot, "household"), "user_min_c"));
        return v != null ? v : DEFAULT_MIN_C;
    }

    function rangeMaxC(snapshot as Lang.Object or Null) as Lang.Float {
        var v = floatOrNull(dictGet(dictGet(snapshot, "household"), "user_max_c"));
        return v != null ? v : DEFAULT_MAX_C;
    }

    // My unit, used for every side. Fahrenheit unless my settings say "C".
    function meFahrenheit(snapshot as Lang.Object or Null, meId as Lang.String or Null) as Lang.Boolean {
        var p = findPerson(peopleFrom(snapshot), meId);
        return p == null || p.fahrenheit;
    }

    // ── What each person looks like ──────────────────────────────────────

    // The engine's target; with none but the bed running, the bed's own
    // setpoint (something the engine did not target, such as a guest).
    function setTempC(p as EtPerson) as Lang.Float or Null {
        if (p.targetC != null) {
            return p.targetC;
        }
        if (p.bedOn != null && (p.bedOn as Lang.Boolean)) {
            return p.setpointC;
        }
        return null;
    }

    function isSkipped(p as EtPerson) as Lang.Boolean {
        return p.skip || p.state.equals("skipped");
    }

    function isPaused(p as EtPerson, nowS as Lang.Double or Null) as Lang.Boolean {
        if (p.state.equals("paused")) {
            return true;
        }
        var until = p.pauseUntil;
        return until != null && nowS != null && until > nowS;
    }

    // True when the person turned the side off (skipped or paused). A side
    // idle because of the schedule is not off for the switch.
    function isOffByMe(p as EtPerson, nowS as Lang.Double or Null) as Lang.Boolean {
        return isSkipped(p) || isPaused(p, nowS);
    }

    // The tonight action SELECT sends from the current state.
    function powerAction(p as EtPerson, nowS as Lang.Double or Null) as Lang.String {
        return isOffByMe(p, nowS) ? ON_ACTION : OFF_ACTION;
    }

    // One side for the control view. The first matching row gives the
    // labels; the label for the other switch position shows between a tap
    // and the reply.
    //
    //   condition                         switch  on label    off label    green
    //   skip, or state skipped            off     Resuming    Off tonight  no
    //   pause_until after now, or paused  off     Resuming    Paused       no
    //   a set temperature exists          on      On          Off tonight  yes
    //   state out_of_bed                  on      Out of bed  Off tonight  no
    //   state away                        on      Away        Off tonight  no
    //   anything else                     on      Idle        Off tonight  no
    function sideFrom(p as EtPerson, isMe as Lang.Boolean, fahrenheit as Lang.Boolean, nowS as Lang.Double or Null, minC as Lang.Float, maxC as Lang.Float) as BedSide {
        var setC = setTempC(p);
        var side = new BedSide(p.id, p.name, !isOffByMe(p, nowS), setC != null ? toShown(setC, fahrenheit) : null);
        var measuredC = p.measuredC;
        side.measured = measuredC != null ? toShown(measuredC, fahrenheit) : null;
        side.startTemp = startShown(measuredC, fahrenheit, minC, maxC);
        side.offText = "Off tonight";
        side.running = false;
        if (isSkipped(p)) {
            side.onText = "Resuming";
        } else if (isPaused(p, nowS)) {
            side.onText = "Resuming";
            side.offText = "Paused";
        } else if (setC != null) {
            side.onText = "On";
            side.running = true;
        } else if (p.state.equals("out_of_bed")) {
            side.onText = "Out of bed";
        } else if (p.state.equals("away")) {
            side.onText = "Away";
        } else {
            side.onText = "Idle";
        }
        side.readOnly = !isMe;
        return side;
    }

    // My side first, then every other person in snapshot order. Null when
    // the snapshot is not a dictionary or I am not in it. The range comes
    // from the household, shown in my unit.
    function stateFromSnapshot(snapshot as Lang.Object or Null, meId as Lang.String or Null) as BedState or Null {
        if (dictOrNull(snapshot) == null) {
            return null;
        }
        var people = peopleFrom(snapshot);
        var mine = findPerson(people, meId);
        if (mine == null) {
            return null;
        }
        var fahrenheit = mine.fahrenheit;
        var minC = rangeMinC(snapshot);
        var maxC = rangeMaxC(snapshot);
        var nowS = doubleOrNull(dictGet(snapshot, "now"));
        var sides = [sideFrom(mine, true, fahrenheit, nowS, minC, maxC)] as Lang.Array<BedSide>;
        for (var i = 0; i < people.size(); i += 1) {
            if (people[i] != mine) {
                sides.add(sideFrom(people[i], false, fahrenheit, nowS, minC, maxC));
            }
        }
        return new BedState(sides, shownMin(minC, fahrenheit), shownMax(maxC, fahrenheit), stepFor(fahrenheit), formatFor(fahrenheit));
    }

    // ── Errors ───────────────────────────────────────────────────────────

    // Connect IQ could not hold the reply (NETWORK_RESPONSE_TOO_LARGE -402,
    // NETWORK_RESPONSE_OUT_OF_MEMORY -403). The server may still have
    // applied a write.
    function isUnreadable(code as Lang.Number) as Lang.Boolean {
        return code == Communications.NETWORK_RESPONSE_TOO_LARGE
            || code == Communications.NETWORK_RESPONSE_OUT_OF_MEMORY;
    }

    // The on-watch text for a failed request; first match wins.
    function errorText(code as Lang.Number, data as Lang.Object or Null) as Lang.String {
        if (isUnreadable(code)) {
            return TOO_LARGE_TEXT;
        }
        if (code < 0) {
            return UNREACHABLE_TEXT;
        }
        var detail = stringOrNull(dictGet(data, "detail"));
        if (code == 403 && detail != null && detail.find(DEVICE_KEY_PREFIX) == 0) {
            return detail;
        }
        if (code == 401 || code == 403) {
            return KEY_TEXT;
        }
        if (detail != null) {
            return detail;
        }
        return "HTTP " + code;
    }

    // ── Value helpers: JSON numbers arrive as Number, Long, Float or Double ──

    function dictOrNull(value as Lang.Object or Null) as Lang.Dictionary or Null {
        if (value != null && value instanceof Lang.Dictionary) {
            return value as Lang.Dictionary;
        }
        return null;
    }

    function dictGet(value as Lang.Object or Null, key as Lang.String) as Lang.Object or Null {
        var d = dictOrNull(value);
        return d != null ? d.get(key) : null;
    }

    function stringOrNull(value as Lang.Object or Null) as Lang.String or Null {
        if (value != null && value instanceof Lang.String) {
            return value as Lang.String;
        }
        return null;
    }

    function floatOrNull(value as Lang.Object or Null) as Lang.Float or Null {
        if (value == null) {
            return null;
        }
        if (value instanceof Lang.Float) {
            return value as Lang.Float;
        }
        if (value instanceof Lang.Number) {
            return (value as Lang.Number).toFloat();
        }
        if (value instanceof Lang.Long) {
            return (value as Lang.Long).toFloat();
        }
        if (value instanceof Lang.Double) {
            return (value as Lang.Double).toFloat();
        }
        return null;
    }

    function doubleOrNull(value as Lang.Object or Null) as Lang.Double or Null {
        if (value == null) {
            return null;
        }
        if (value instanceof Lang.Double) {
            return value as Lang.Double;
        }
        if (value instanceof Lang.Float) {
            return (value as Lang.Float).toDouble();
        }
        if (value instanceof Lang.Number) {
            return (value as Lang.Number).toDouble();
        }
        if (value instanceof Lang.Long) {
            return (value as Lang.Long).toDouble();
        }
        return null;
    }
}

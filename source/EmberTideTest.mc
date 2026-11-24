// Unit tests for the Ember & Tide pure code (oga-2cx): headers, who is me,
// snapshot parsing, request bodies, the power action, labels, units and
// error texts in EmberTideModel. The samples are hand-written from the
// snapshot shape in ember-tide core/embertide/engine/controller.py:1306-1356
// (origin/main at c46accc); no sample holds a real key. Run with a
// --unit-test build and `monkeydo <prg> <device> -t`; see docs/TESTING.md.
using Toybox.Communications;
using Toybox.Lang;
using Toybox.Test;

(:test)
module EmberTideTest {

    const NOW = 1795544349.0d;

    function dict(keys as Lang.Array<Lang.String>, values as Lang.Array) as Lang.Dictionary {
        var d = {} as Lang.Dictionary;
        for (var i = 0; i < keys.size(); i += 1) {
            d.put(keys[i], values[i]);
        }
        return d;
    }

    function night(state as Lang.String, skip as Lang.Boolean, pauseUntil as Lang.Object or Null, targetC as Lang.Object or Null) as Lang.Dictionary {
        return dict(["state", "skip", "pause_until", "target_c"] as Lang.Array<Lang.String>, [state, skip, pauseUntil, targetC] as Lang.Array);
    }

    function bed(on as Lang.Object or Null, setpointC as Lang.Object or Null, measuredC as Lang.Object or Null) as Lang.Dictionary {
        return dict(["on", "setpoint_c", "measured_c"] as Lang.Array<Lang.String>, [on, setpointC, measuredC] as Lang.Array);
    }

    function personDict(id as Lang.String, name as Lang.String, units as Lang.String, nightDict as Lang.Dictionary, bedDict as Lang.Dictionary) as Lang.Dictionary {
        var d = dict(["id", "name", "night", "bed"] as Lang.Array<Lang.String>, [id, name, nightDict, bedDict] as Lang.Array);
        d.put("settings", dict(["units", "wake_time"] as Lang.Array<Lang.String>, [units, "06:30"] as Lang.Array));
        return d;
    }

    // The per-minute history, curve and phases the parser must ignore.
    function addHistory(person as Lang.Dictionary) as Lang.Dictionary {
        person.put("zone", "left");
        person.put("actual", [[1795540000, 19.0] as Lang.Array, [1795540060, 19.1] as Lang.Array] as Lang.Array);
        person.put("curve", [[0, 18.5] as Lang.Array, [3600, 18.0] as Lang.Array] as Lang.Array);
        person.put("phases", [dict(["name", "start"] as Lang.Array<Lang.String>, ["settle", 0] as Lang.Array)] as Lang.Array);
        return person;
    }

    function snapshot(people as Lang.Array) as Lang.Dictionary {
        var d = dict(["now", "people"] as Lang.Array<Lang.String>, [NOW, people] as Lang.Array);
        return d;
    }

    // Sample A: two people, Sam first (units C, running), Kevin second
    // (units F), each with actual, curve and phases arrays to ignore.
    function sampleA() as Lang.Dictionary {
        var sam = addHistory(personDict("p_sam", "Sam", "C", night("rhythm", false, null, 18.5), bed(true, 18.5, 19.2)));
        var kevin = addHistory(personDict("p_kevin", "Kevin", "F", night("rhythm", false, null, 20.0), bed(true, 20.5, 20.4)));
        var d = snapshot([sam, kevin] as Lang.Array);
        d.put("household", dict(["user_min_c", "user_max_c"] as Lang.Array<Lang.String>, [12, 35.0] as Lang.Array));
        return d;
    }

    // Sample B: one person, bed values and target_c null, state day, no
    // household.
    function sampleB() as Lang.Dictionary {
        var kevin = personDict("p_kevin", "Kevin", "C", night("day", false, null, null), bed(null, null, null));
        return snapshot([kevin] as Lang.Array);
    }

    function person(state as Lang.String, skip as Lang.Boolean, pauseUntil as Lang.Object or Null, targetC as Lang.Object or Null) as EtPerson {
        var p = EmberTideModel.personFrom(personDict("p_kevin", "Kevin", "C", night(state, skip, pauseUntil, targetC), bed(targetC != null, targetC, 20.0)));
        return p as EtPerson;
    }

    function near(a as Lang.Float or Null, b as Lang.Float) as Lang.Boolean {
        if (a == null) {
            return false;
        }
        var d = a - b;
        return d < 0.001 && d > -0.001;
    }

    // Logs a failed check and returns its result, so a test can run every
    // check as its own statement: ok = expect(...) && ok.
    function expect(logger as Test.Logger, cond as Lang.Boolean, label as Lang.String) as Lang.Boolean {
        if (!cond) {
            logger.error("failed: " + label);
        }
        return cond;
    }

    function isText(value as Lang.Object or Null, text as Lang.String) as Lang.Boolean {
        return text.equals(value);
    }

    (:test)
    function headersCarryKeyAndMarker(logger as Test.Logger) as Lang.Boolean {
        var h = EmberTideModel.headers("test-key");
        var ok = expect(logger, isText(h.get("Authorization"), "Bearer test-key"), "Authorization");
        ok = expect(logger, isText(h.get("X-Embertide"), "1"), "X-Embertide") && ok;
        ok = expect(logger, h.get("Content-Type") == Communications.REQUEST_CONTENT_TYPE_JSON, "Content-Type") && ok;
        return ok;
    }

    (:test)
    function authStateGivesPerson(logger as Test.Logger) as Lang.Boolean {
        var key = "Key not accepted, make a new one";
        var good = { "me" => dict(["kind", "id", "name", "role", "person"] as Lang.Array<Lang.String>, ["token", "t1", "Garmin watch", "sleeper", "p_kevin"] as Lang.Array) } as Lang.Dictionary;
        var ok = expect(logger, isText(EmberTideModel.personIdFromAuthState(good), "p_kevin"), "good gives p_kevin");
        ok = expect(logger, EmberTideModel.authStateProblem(good) == null, "good has no problem") && ok;
        var unknown = { "me" => null } as Lang.Dictionary;
        ok = expect(logger, EmberTideModel.personIdFromAuthState(unknown) == null, "me null gives no id") && ok;
        ok = expect(logger, isText(EmberTideModel.authStateProblem(unknown), key), "me null text") && ok;
        var noPerson = { "me" => dict(["kind", "role", "person"] as Lang.Array<Lang.String>, ["token", "owner", null] as Lang.Array) } as Lang.Dictionary;
        ok = expect(logger, EmberTideModel.personIdFromAuthState(noPerson) == null, "person null gives no id") && ok;
        ok = expect(logger, isText(EmberTideModel.authStateProblem(noPerson), "This key has no side of the bed"), "person null text") && ok;
        ok = expect(logger, isText(EmberTideModel.authStateProblem("not json"), key), "not a dictionary") && ok;
        return ok;
    }

    function checkPerson(logger as Test.Logger, p as EtPerson, id as Lang.String, name as Lang.String, fahrenheit as Lang.Boolean, targetC as Lang.Float, setpointC as Lang.Float, measuredC as Lang.Float) as Lang.Boolean {
        var ok = expect(logger, p.id.equals(id), id + " id");
        ok = expect(logger, p.name.equals(name), id + " name") && ok;
        ok = expect(logger, p.fahrenheit == fahrenheit, id + " unit") && ok;
        ok = expect(logger, p.bedOn == true, id + " bed on") && ok;
        ok = expect(logger, near(p.targetC, targetC), id + " target") && ok;
        ok = expect(logger, near(p.setpointC, setpointC), id + " setpoint") && ok;
        ok = expect(logger, near(p.measuredC, measuredC), id + " measured") && ok;
        ok = expect(logger, p.state.equals("rhythm"), id + " state") && ok;
        ok = expect(logger, !p.skip, id + " skip") && ok;
        ok = expect(logger, p.pauseUntil == null, id + " pause_until") && ok;
        return ok;
    }

    (:test)
    function snapshotParsesTwoPeople(logger as Test.Logger) as Lang.Boolean {
        var people = EmberTideModel.peopleFrom(sampleA());
        if (!expect(logger, people.size() == 2, "two people")) {
            return false;
        }
        var ok = checkPerson(logger, people[0], "p_sam", "Sam", false, 18.5, 18.5, 19.2);
        ok = checkPerson(logger, people[1], "p_kevin", "Kevin", true, 20.0, 20.5, 20.4) && ok;
        ok = expect(logger, near(EmberTideModel.rangeMinC(sampleA()), 12.0), "min") && ok;
        ok = expect(logger, near(EmberTideModel.rangeMaxC(sampleA()), 35.0), "max") && ok;
        return ok;
    }

    (:test)
    function snapshotSurvivesNulls(logger as Test.Logger) as Lang.Boolean {
        var people = EmberTideModel.peopleFrom(sampleB());
        if (!expect(logger, people.size() == 1, "one person")) {
            return false;
        }
        var p = people[0];
        var ok = expect(logger, p.bedOn == null, "bed.on null");
        ok = expect(logger, p.setpointC == null, "setpoint null") && ok;
        ok = expect(logger, p.measuredC == null, "measured null") && ok;
        ok = expect(logger, p.targetC == null, "target null") && ok;
        ok = expect(logger, EmberTideModel.setTempC(p) == null, "no set temperature") && ok;
        var state = EmberTideModel.stateFromSnapshot(sampleB(), "p_kevin");
        if (!expect(logger, state != null, "state from sample B")) {
            return false;
        }
        var st = state as BedState;
        var side = st.sides[0];
        ok = expect(logger, side.temp == null, "side temp null") && ok;
        ok = expect(logger, side.measured == null, "side measured null") && ok;
        ok = expect(logger, side.startTemp == null, "side start null") && ok;
        ok = expect(logger, side.on && side.onText.equals("Idle"), "idle") && ok;
        // Range defaults to 12-35 when the household is missing.
        ok = expect(logger, near(st.tempMin, 12.0) && near(st.tempMax, 35.0), "default range") && ok;
        ok = expect(logger, EmberTideModel.peopleFrom(null).size() == 0, "null snapshot") && ok;
        ok = expect(logger, EmberTideModel.peopleFrom({ "people" => "x" } as Lang.Dictionary).size() == 0, "people not a list") && ok;
        return ok;
    }

    (:test)
    function meComesFirst(logger as Test.Logger) as Lang.Boolean {
        var state = EmberTideModel.stateFromSnapshot(sampleA(), "p_kevin");
        if (!expect(logger, state != null, "state")) {
            return false;
        }
        var st = state as BedState;
        if (!expect(logger, st.sides.size() == 2, "two sides")) {
            return false;
        }
        var mine = st.sides[0];
        var sam = st.sides[1];
        var ok = expect(logger, mine.id.equals("p_kevin") && mine.label.equals("Kevin"), "Kevin first");
        ok = expect(logger, !mine.readOnly, "Kevin controllable") && ok;
        ok = expect(logger, st.homeIndex == 0, "home 0") && ok;
        ok = expect(logger, sam.id.equals("p_sam") && sam.readOnly, "Sam read-only") && ok;
        // Kevin's unit (F) is used for both pages.
        ok = expect(logger, near(mine.temp, 68.0), "Kevin 68") && ok;
        ok = expect(logger, near(sam.temp, 65.0), "Sam 65") && ok;
        ok = expect(logger, near(st.step, 1.0) && st.tempFormat.equals("%.0f"), "F step and format") && ok;
        return ok;
    }

    (:test)
    function missingMeGivesNull(logger as Test.Logger) as Lang.Boolean {
        var ok = expect(logger, EmberTideModel.stateFromSnapshot(sampleA(), "p_nobody") == null, "p_nobody");
        ok = expect(logger, EmberTideModel.stateFromSnapshot(sampleA(), null) == null, "null id") && ok;
        ok = expect(logger, EmberTideModel.stateFromSnapshot(null, "p_kevin") == null, "null snapshot") && ok;
        return ok;
    }

    (:test)
    function adjustBodyAndPath(logger as Test.Logger) as Lang.Boolean {
        var body = EmberTideModel.adjustBody(22.5);
        var temp = body.get("temp_c");
        var ok = expect(logger, body.size() == 3, "three keys");
        ok = expect(logger, temp instanceof Lang.Float && (temp as Lang.Float) == 22.5, "temp_c 22.5") && ok;
        ok = expect(logger, isText(body.get("until"), "night"), "until night") && ok;
        ok = expect(logger, isText(body.get("source"), "watch"), "source watch") && ok;
        ok = expect(logger, EmberTideModel.adjustPath("p_kevin").equals("/api/people/p_kevin/adjust"), "path") && ok;
        return ok;
    }

    (:test)
    function tonightBodies(logger as Test.Logger) as Lang.Boolean {
        var off = EmberTideModel.tonightBody(false);
        var on = EmberTideModel.tonightBody(true);
        var ok = expect(logger, off.size() == 2 && isText(off.get("action"), "skip"), "off is skip");
        ok = expect(logger, isText(off.get("source"), "watch"), "off source") && ok;
        ok = expect(logger, on.size() == 2 && isText(on.get("action"), "resume"), "on is resume") && ok;
        ok = expect(logger, isText(on.get("source"), "watch"), "on source") && ok;
        ok = expect(logger, EmberTideModel.tonightPath("p_kevin").equals("/api/people/p_kevin/tonight"), "path") && ok;
        return ok;
    }

    (:test)
    function powerActionByState(logger as Test.Logger) as Lang.Boolean {
        var later = 1795548000;
        var ok = expect(logger, EmberTideModel.powerAction(person("rhythm", false, null, 20.0), NOW).equals("skip"), "rhythm");
        ok = expect(logger, EmberTideModel.powerAction(person("skipped", true, null, null), NOW).equals("resume"), "skipped") && ok;
        ok = expect(logger, EmberTideModel.powerAction(person("paused", false, later, null), NOW).equals("resume"), "paused") && ok;
        ok = expect(logger, EmberTideModel.powerAction(person("day", false, null, null), NOW).equals("skip"), "day") && ok;
        // A pause that has run out no longer counts as off.
        ok = expect(logger, EmberTideModel.powerAction(person("rhythm", false, 1795500000, 20.0), NOW).equals("skip"), "old pause") && ok;
        return ok;
    }

    function checkLabel(logger as Test.Logger, p as EtPerson, on as Lang.Boolean, onText as Lang.String, offText as Lang.String, green as Lang.Boolean) as Lang.Boolean {
        var side = EmberTideModel.sideFrom(p, true, false, NOW, 12.0, 35.0);
        var ok = side.on == on;
        ok = ok && side.onText.equals(onText);
        ok = ok && side.offText.equals(offText);
        ok = ok && side.running == green;
        return expect(logger, ok, p.state + ": got " + side.on + " " + side.onText + "/" + side.offText + " " + side.running);
    }

    (:test)
    function labelsByState(logger as Test.Logger) as Lang.Boolean {
        var ok = checkLabel(logger, person("skipped", true, null, null), false, "Resuming", "Off tonight", false);
        ok = checkLabel(logger, person("paused", false, 1795548000, null), false, "Resuming", "Paused", false) && ok;
        ok = checkLabel(logger, person("rhythm", false, null, 20.0), true, "On", "Off tonight", true) && ok;
        ok = checkLabel(logger, person("out_of_bed", false, null, null), true, "Out of bed", "Off tonight", false) && ok;
        ok = checkLabel(logger, person("away", false, null, null), true, "Away", "Off tonight", false) && ok;
        ok = checkLabel(logger, person("done", false, null, null), true, "Idle", "Off tonight", false) && ok;
        ok = checkLabel(logger, person("no_rhythm", false, null, null), true, "Idle", "Off tonight", false) && ok;
        // No target but the bed running: its own setpoint is shown.
        var guest = EmberTideModel.personFrom(personDict("p_kevin", "Kevin", "C", night("day", false, null, null), bed(true, 21.0, null))) as EtPerson;
        var side = EmberTideModel.sideFrom(guest, true, false, NOW, 12.0, 35.0);
        ok = expect(logger, near(side.temp, 21.0) && side.onText.equals("On"), "bed setpoint fallback") && ok;
        return ok;
    }

    (:test)
    function firstPressBase(logger as Test.Logger) as Lang.Boolean {
        var ok = expect(logger, near(EmberTideModel.startShown(20.4, false, 12.0, 35.0), 20.5), "20.4 C -> 20.5");
        ok = expect(logger, near(EmberTideModel.startShown(20.4, true, 12.0, 35.0), 69.0), "20.4 C -> 69 F") && ok;
        ok = expect(logger, EmberTideModel.startShown(null, true, 12.0, 35.0) == null, "null measured") && ok;
        // Clamped into the shown range.
        ok = expect(logger, near(EmberTideModel.startShown(40.0, false, 12.0, 35.0), 35.0), "clamped") && ok;
        return ok;
    }

    (:test)
    function unitsRoundTrip(logger as Test.Logger) as Lang.Boolean {
        var ok = expect(logger, near(EmberTideModel.toShown(20.0, true), 68.0), "20.0 C shows 68");
        var sent = EmberTideModel.toCelsius(69.0, true, 12.0, 35.0);
        ok = expect(logger, sent > 20.5 && sent < 20.6, "69 F sent as " + sent) && ok;
        ok = expect(logger, near(EmberTideModel.toShown(sent, true), 69.0), "sent value shows 69") && ok;
        ok = expect(logger, near(EmberTideModel.shownMin(12.0, true), 54.0), "min 54") && ok;
        ok = expect(logger, near(EmberTideModel.shownMax(35.0, true), 95.0), "max 95") && ok;
        // Celsius is unchanged.
        ok = expect(logger, near(EmberTideModel.toShown(20.5, false), 20.5), "C shown") && ok;
        ok = expect(logger, near(EmberTideModel.toCelsius(22.5, false, 12.0, 35.0), 22.5), "C sent") && ok;
        ok = expect(logger, near(EmberTideModel.shownMin(12.0, false), 12.0), "C min") && ok;
        ok = expect(logger, near(EmberTideModel.shownMax(35.0, false), 35.0), "C max") && ok;
        // Clamped to the household range and the server's 10-45.
        ok = expect(logger, near(EmberTideModel.toCelsius(40.0, false, 12.0, 35.0), 35.0), "household clamp") && ok;
        ok = expect(logger, near(EmberTideModel.toCelsius(5.0, false, 0.0, 50.0), 10.0), "server clamp") && ok;
        return ok;
    }

    function checkError(logger as Test.Logger, code as Lang.Number, data as Lang.Object or Null, expected as Lang.String) as Lang.Boolean {
        var actual = EmberTideModel.errorText(code, data);
        return expect(logger, actual.equals(expected), code + ": expected '" + expected + "', got '" + actual + "'");
    }

    function detail(value as Lang.Object) as Lang.Dictionary {
        return { "detail" => value } as Lang.Dictionary;
    }

    (:test)
    function errorTexts(logger as Test.Logger) as Lang.Boolean {
        var key = "Key not accepted, make a new one";
        var deviceKey = "This device key can't do that. Open the app instead.";
        var guest = "that side is lent to a guest: use the guest controls";
        var tooLarge = "Reply too large for this watch";
        var validation = [dict(["loc", "msg"] as Lang.Array<Lang.String>, [["body", "temp_c"] as Lang.Array, "too high"] as Lang.Array)] as Lang.Array;
        var ok = checkError(logger, 401, detail("Please sign in."), key);
        ok = checkError(logger, 403, detail(deviceKey), deviceKey) && ok;
        ok = checkError(logger, 403, detail("This account can only look."), key) && ok;
        ok = checkError(logger, 409, detail(guest), guest) && ok;
        ok = checkError(logger, 422, detail(validation), "HTTP 422") && ok;
        ok = checkError(logger, 500, null, "HTTP 500") && ok;
        ok = checkError(logger, -104, null, "Can't reach your server") && ok;
        ok = checkError(logger, -402, null, tooLarge) && ok;
        ok = checkError(logger, -403, null, tooLarge) && ok;
        ok = expect(logger, EmberTideModel.isUnreadable(-402) && EmberTideModel.isUnreadable(-403), "unreadable codes") && ok;
        ok = expect(logger, !EmberTideModel.isUnreadable(-104), "-104 readable") && ok;
        return ok;
    }
}

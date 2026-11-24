// Ember & Tide requests (oga-2cx): a BedBackend for a self-hosted Ember &
// Tide server, used when the `backend` setting is 1. Built at app start
// from BackendConfig.url() and key(); a changed setting takes effect the
// next time the app opens.
//
// Only four routes, all a watch-scope device key may call:
//   GET  /api/auth/state             once per app run: who the key acts as
//   GET  /api/snapshot               the state of the bed
//   POST /api/people/{me}/adjust     {temp_c, until: "night", source: "watch"}
//   POST /api/people/{me}/tonight    {action: "skip" | "resume", source: "watch"}
// {me} is always the person id from /api/auth/state, never a side id passed
// in by the view, so no request ever names another person. Every write
// replies with a full snapshot, which the view adopts through stateFrom().
//
// send() is the only place that makes a web request, and it always
// uses EmberTideModel.headers(). One request at a time, as the view asks.
// The key is held in memory only and is never printed: the console shows
// the method and path before a request and the operation and response code
// after it.
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;

class EmberTideClient extends BedBackend {

    private var _url as Lang.String;
    private var _key as Lang.String;
    // My person id from /api/auth/state; null until asked. In memory only.
    private var _meId as Lang.String or Null;
    private var _callback as Lang.Method or Null;
    // "auth_state", "snapshot", "adjust" or "tonight".
    private var _op as Lang.String;
    // My unit and the household range from the last state built, for
    // converting a shown temperature back to Celsius.
    private var _fahrenheit as Lang.Boolean;
    private var _minC as Lang.Float;
    private var _maxC as Lang.Float;

    function initialize(url as Lang.String, key as Lang.String) {
        BedBackend.initialize();
        _url = url;
        _key = key;
        _meId = null;
        _callback = null;
        _op = "";
        _fahrenheit = true;
        _minC = EmberTideModel.DEFAULT_MIN_C;
        _maxC = EmberTideModel.DEFAULT_MAX_C;
    }

    function describe() as BedInfo {
        return new BedInfo("Ember & Tide", false);
    }

    function loadState(callback as Lang.Method) as Void {
        _callback = callback;
        if (_meId == null) {
            send(Communications.HTTP_REQUEST_METHOD_GET, "GET", EmberTideModel.AUTH_STATE_PATH, null, "auth_state");
        } else {
            send(Communications.HTTP_REQUEST_METHOD_GET, "GET", EmberTideModel.SNAPSHOT_PATH, null, "snapshot");
        }
    }

    function setTemperature(sideId as Lang.String, temp as Lang.Float, callback as Lang.Method) as Void {
        _callback = callback;
        var meId = _meId;
        if (meId == null || !sideId.equals(meId)) {
            finish(null, EmberTideModel.VIEW_ONLY_TEXT);
            return;
        }
        var tempC = EmberTideModel.toCelsius(temp, _fahrenheit, _minC, _maxC);
        send(Communications.HTTP_REQUEST_METHOD_POST, "POST", EmberTideModel.adjustPath(meId), EmberTideModel.adjustBody(tempC), "adjust");
    }

    // temp is ignored: Ember & Tide needs a separate request for it.
    function setPower(sideId as Lang.String, on as Lang.Boolean, temp as Lang.Float or Null, callback as Lang.Method) as Void {
        _callback = callback;
        var meId = _meId;
        if (meId == null || !sideId.equals(meId)) {
            finish(null, EmberTideModel.VIEW_ONLY_TEXT);
            return;
        }
        send(Communications.HTTP_REQUEST_METHOD_POST, "POST", EmberTideModel.tonightPath(meId), EmberTideModel.tonightBody(on), "tonight");
    }

    // A snapshot -> my side first, partners read-only. Null (a write whose
    // reply was too large to read) -> no sides and a note; the view keeps
    // the value the user chose.
    function stateFrom(reply as Lang.Object or Null) as BedState or Null {
        if (reply == null) {
            var state = new BedState([] as Lang.Array<BedSide>, 0.0, 0.0, EmberTideModel.stepFor(_fahrenheit), EmberTideModel.formatFor(_fahrenheit));
            state.notice = EmberTideModel.SENT_UNREADABLE_TEXT;
            return state;
        }
        var built = EmberTideModel.stateFromSnapshot(reply, _meId);
        if (built != null) {
            _fahrenheit = EmberTideModel.meFahrenheit(reply, _meId);
            _minC = EmberTideModel.rangeMinC(reply);
            _maxC = EmberTideModel.rangeMaxC(reply);
        }
        return built;
    }

    // Every request goes through here.
    private function send(httpMethod as Communications.HttpRequestMethod, methodName as Lang.String, path as Lang.String, body as Lang.Dictionary or Null, op as Lang.String) as Void {
        _op = op;
        var options = {
            :method => httpMethod,
            :headers => EmberTideModel.headers(_key),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        System.println("EmberTideClient: " + methodName + " " + path);
        Communications.makeWebRequest(_url + path, body, options, method(:onResponse));
    }

    function onResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        System.println("EmberTideClient: " + _op + " response " + responseCode.toString());
        var ok = responseCode >= 200 && responseCode < 300;
        var dict = (data != null && data instanceof Lang.Dictionary) ? data as Lang.Dictionary : null;

        if (_op.equals("auth_state")) {
            if (!ok) {
                finish(null, EmberTideModel.errorText(responseCode, data));
                return;
            }
            var problem = EmberTideModel.authStateProblem(dict);
            if (problem != null) {
                finish(null, problem);
                return;
            }
            _meId = EmberTideModel.personIdFromAuthState(dict);
            send(Communications.HTTP_REQUEST_METHOD_GET, "GET", EmberTideModel.SNAPSHOT_PATH, null, "snapshot");
        } else if (_op.equals("snapshot")) {
            if (!ok) {
                finish(null, EmberTideModel.errorText(responseCode, data));
            } else if (dict == null) {
                finish(null, EmberTideModel.UNEXPECTED_TEXT);
            } else if (EmberTideModel.findPerson(EmberTideModel.peopleFrom(dict), _meId) == null) {
                finish(null, EmberTideModel.NOT_ON_BED_TEXT);
            } else {
                finish(dict, null);
            }
        } else {
            // A write. The server may have applied it even when the reply
            // was too large to read, so that is not a failure.
            if (ok && dict != null) {
                finish(dict, null);
            } else if (ok || EmberTideModel.isUnreadable(responseCode)) {
                finish(null, null);
            } else {
                finish(null, EmberTideModel.errorText(responseCode, data));
            }
        }
    }

    // Clear the pending callback before invoking it, as OrionBackend does: the
    // callback may start the next request.
    private function finish(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        var callback = _callback;
        _callback = null;
        if (callback != null) {
            (callback as Lang.Method).invoke(result, error);
        }
    }
}

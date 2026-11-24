// Background refresh for the glance (oga-6bf). Every 30 minutes the system
// wakes this delegate in its own small process (32 KB on some products, 30
// seconds at most). It fetches the glance bed's live zones, saves them to
// GlanceCache and exits.
//
// Rules:
//   - No UI. Toybox.WatchUi does not exist here.
//   - No request when signed out, with no glance bed, or with no phone.
//   - Never GET /v1/devices: that reply is too large for this process.
//   - On any failure nothing is changed: not the cache, not the tokens.
//     The only token write is saving the tokens from a successful refresh.
//   - The cache write is the last step of a successful run.
//   - One println per request and one for the outcome. Never print a token.
//
// This file does not use OrionClient or OrionAuth: loading them here costs
// about twice the memory (see docs/DESIGN.md). The shared rules live in
// OrionSession.
using Toybox.Application;
using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

(:background)
class GlanceRefreshDelegate extends System.ServiceDelegate {

    private var _startedAt as Lang.Number;
    private var _serial as Lang.String;

    function initialize() {
        ServiceDelegate.initialize();
        _startedAt = 0;
        _serial = "";
    }

    function onTemporalEvent() as Void {
        _startedAt = Time.now().value();
        if (!OrionSession.hasStoredToken()) {
            finish("skipped: signed out", false);
            return;
        }
        var serial = GlanceCache.glanceBed();
        if (serial == null) {
            finish("skipped: no glance bed", false);
            return;
        }
        _serial = serial as Lang.String;
        if (!System.getDeviceSettings().phoneConnected) {
            finish("skipped: no phone connection", false);
            return;
        }
        var method = Application.Storage.getValue(OrionSession.KEY_AUTH_METHOD);
        var isApiKey = (method != null && method instanceof Lang.String && (method as Lang.String).equals("api_key"));
        if (!isApiKey) {
            var expiresAt = Application.Storage.getValue(OrionSession.KEY_EXPIRES_AT);
            var exp = (expiresAt != null && expiresAt instanceof Lang.Number) ? expiresAt as Lang.Number : 0;
            if ((_startedAt + OrionSession.REFRESH_MARGIN_SECONDS) >= exp) {
                refresh();
                return;
            }
        }
        fetch();
    }

    private function refresh() as Void {
        var rt = Application.Storage.getValue(OrionSession.KEY_REFRESH_TOKEN);
        if (rt == null || !(rt instanceof Lang.String) || (rt as Lang.String).length() == 0) {
            finish("failed: no refresh token", false);
            return;
        }
        System.println("GlanceRefresh: POST /v1/auth/refresh");
        Communications.makeWebRequest(
            OrionSession.BASE_URL + "/v1/auth/refresh",
            { "refreshToken" => rt, "refresh_token" => rt },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onRefreshed)
        );
    }

    function onRefreshed(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (code < 200 || code >= 300 || data == null || !(data instanceof Lang.Dictionary)) {
            finish("failed: refresh " + code.toString(), false);
            return;
        }
        var tokens = OrionSession.extractTokens(data as Lang.Dictionary);
        if (tokens == null || !(tokens.get("access_token") instanceof Lang.String)) {
            finish("failed: refresh reply shape", false);
            return;
        }
        OrionSession.saveOtpTokens(
            tokens.get("access_token") as Lang.String,
            tokens.get("refresh_token") as Lang.String,
            tokens.get("expires_at") as Lang.Number
        );
        fetch();
    }

    private function fetch() as Void {
        var token = Application.Storage.getValue(OrionSession.KEY_ACCESS_TOKEN);
        System.println("GlanceRefresh: GET /v1/devices/" + _serial + "/live");
        Communications.makeWebRequest(
            OrionSession.BASE_URL + "/v1/devices/" + _serial + "/live",
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + (token as Lang.String)
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onLive)
        );
    }

    function onLive(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (code < 200 || code >= 300 || data == null || !(data instanceof Lang.Dictionary)) {
            finish("failed: live " + code.toString(), false);
            return;
        }
        var body = data as Lang.Dictionary;
        var inner = body.get("response");
        if (inner != null && inner instanceof Lang.Dictionary) {
            body = inner as Lang.Dictionary;
        }
        var raw = body.get("zones");
        var zones = [] as Lang.Array;
        if (raw != null && raw instanceof Lang.Array) {
            var arr = raw as Lang.Array;
            for (var i = 0; i < arr.size(); i += 1) {
                var z = arr[i];
                if (!(z instanceof Lang.Dictionary)) {
                    continue;
                }
                var zd = z as Lang.Dictionary;
                var id = zd.get("id");
                if (id == null || !(id instanceof Lang.String)) {
                    continue;
                }
                var on = zd.get("on");
                zones.add(GlanceCache.zoneEntry(
                    id as Lang.String,
                    (on != null && on instanceof Lang.Boolean) ? on as Lang.Boolean : false,
                    DeviceModel.floatOrDefault(zd.get("temp"), 0.0)
                ));
            }
        }
        if (zones.size() == 0) {
            finish("failed: no zones in reply", false);
            return;
        }
        if (GlanceCache.write(_serial, zones, _startedAt)) {
            finish("updated", true);
        } else {
            finish("skipped: the app saved newer state", false);
        }
    }

    private function finish(outcome as Lang.String, changed as Lang.Boolean) as Void {
        System.println("GlanceRefresh: " + outcome);
        Background.exit(changed ? true : null);
    }
}

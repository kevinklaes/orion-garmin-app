// Orion Sleep REST client (oga-vjk).
//
// Ports home_assistant_orion_integration's OrionApiClient (custom_components/
// orion_sleep/api.py) to Monkey C: same request shapes, same auth flows
// (API key vs OTP JWT), same response-shape tolerance, same error
// classification. Communications.makeWebRequest() usage (headers, JSON
// responseType, onResponse callback dispatch by op) follows GarminMerge's
// GitHubClient.mc pattern.
//
// Auth: the constructor's `isApiKey` flag mirrors api.py's `is_api_key`.
// When true, `access_token` (set via setApiKey()) is a long-lived Orion API
// key sent as `Authorization: Bearer <key>` and never refreshed -- a revoked
// key just 401s on the next call. When false, it holds a short-lived OTP
// JWT with a companion refresh token.
//
// This class does NOT auto-refresh before calls -- api.py's
// ensure_valid_token() orchestration (checking expiry, calling refresh,
// persisting to Storage, sign-out) belongs to oga-aw5, which wraps this
// class. OrionClient only exposes refreshTokens() and isTokenExpired() as
// primitives for that caller to use.
//
// CRITICAL (see api.py's update_live_device_zones docstring): the live
// endpoints below key on the device's `serial_number`, NOT the UUID `id`
// returned by listDevices() -- using the UUID returns 403.
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

class OrionClient {

    // Callback signature: (result as Lang.Object or Null, error as Lang.String or Null).
    // Only one request is in flight at a time (tracked via _op), so the
    // caller always knows which method's result/error shape to expect.
    private var _callback as Lang.Method;
    private var _op as Lang.String;

    private var _accessToken as Lang.String or Null;
    private var _refreshToken as Lang.String or Null;
    private var _expiresAt as Lang.Number;
    private var _isApiKey as Lang.Boolean;

    // Held across the /v1/auth/do -> /v1/auth/verify fallback retry.
    private var _pendingCode as Lang.String or Null;
    private var _pendingPhone as Lang.String or Null;

    function initialize(callback as Lang.Method, isApiKey as Lang.Boolean) {
        _callback = callback;
        _op = "";
        _accessToken = null;
        _refreshToken = null;
        _expiresAt = 0;
        _isApiKey = isApiKey;
        _pendingCode = null;
        _pendingPhone = null;
    }

    // ── Token state ──────────────────────────────────────────────────
    // Read/write so a caller (oga-aw5's storage layer) can persist tokens
    // to Application.Storage and restore them on next launch.

    function setTokens(accessToken as Lang.String, refreshToken as Lang.String or Null, expiresAt as Lang.Number) as Void {
        _accessToken = accessToken;
        _refreshToken = refreshToken;
        _expiresAt = expiresAt;
    }

    function setApiKey(apiKey as Lang.String) as Void {
        _isApiKey = true;
        _accessToken = apiKey;
        _refreshToken = null;
        _expiresAt = 0;
    }

    function getAccessToken() as Lang.String or Null {
        return _accessToken;
    }

    function getRefreshToken() as Lang.String or Null {
        return _refreshToken;
    }

    function getExpiresAt() as Lang.Number {
        return _expiresAt;
    }

    function isApiKeyAuth() as Lang.Boolean {
        return _isApiKey;
    }

    // Mirrors api.py's _token_expired(margin_seconds). Always false for
    // API-key auth (long-lived, no expiry).
    function isTokenExpired(marginSeconds as Lang.Number) as Lang.Boolean {
        if (_isApiKey) {
            return false;
        }
        return (Time.now().value() + marginSeconds) >= _expiresAt;
    }

    // ── Auth methods (no bearer token needed) ──────────────────────────

    // POST /v1/auth/code -- send a phone verification code.
    function requestAuthCode(phone as Lang.String) as Void {
        _op = "auth_code";
        var url = apiUrl("/v1/auth/code");
        var params = { "phone" => phone };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => unauthHeaders(),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        System.println("OrionClient: POST /v1/auth/code");
        Communications.makeWebRequest(url, params, options, method(:onResponse));
    }

    // Verify a code and return normalised session tokens. Tries
    // POST /v1/auth/do first (current spec), then falls back to the legacy
    // POST /v1/auth/verify -- mirrors api.py's verify_auth_code exactly,
    // including which failures trigger the fallback (anything except a 401
    // auth failure, which is surfaced immediately).
    //
    // On success, invokes callback with
    // {"access_token", "refresh_token", "expires_at"}.
    function verifyAuthCode(code as Lang.String, phone as Lang.String) as Void {
        _pendingCode = code;
        _pendingPhone = phone;
        startVerifyRequest("/v1/auth/do", "verify_do");
    }

    private function startVerifyRequest(path as Lang.String, op as Lang.String) as Void {
        _op = op;
        var url = apiUrl(path);
        var params = { "code" => _pendingCode, "phone" => _pendingPhone };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => unauthHeaders(),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        System.println("OrionClient: POST " + path);
        Communications.makeWebRequest(url, params, options, method(:onResponse));
    }

    // ── Token management ────────────────────────────────────────────────

    // POST /v1/auth/refresh. Sends both refreshToken (current spec) and
    // refresh_token (legacy) so it works regardless of which key the live
    // API requires, mirroring api.py's _refresh_tokens. On success, updates
    // internal token state and invokes callback with the new token dict.
    function refreshTokens() as Void {
        if (_isApiKey) {
            _callback.invoke(null, "API keys cannot be refreshed");
            return;
        }
        if (_refreshToken == null || (_refreshToken as Lang.String).length() == 0) {
            _callback.invoke(null, "No refresh token available");
            return;
        }

        _op = "refresh";
        var url = apiUrl("/v1/auth/refresh");
        var params = {
            "refreshToken" => _refreshToken,
            "refresh_token" => _refreshToken
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => unauthHeaders(),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        System.println("OrionClient: POST /v1/auth/refresh");
        Communications.makeWebRequest(url, params, options, method(:onResponse));
    }

    // ── Data fetchers (all require a valid bearer token) ────────────────

    // GET /v1/auth/me -- current user profile. Used to validate a pasted
    // API key (401 means invalid/revoked).
    function getCurrentUser() as Void {
        _op = "me";
        var url = apiUrl("/v1/auth/me");
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => authHeaders(),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        System.println("OrionClient: GET /v1/auth/me");
        Communications.makeWebRequest(url, null, options, method(:onResponse));
    }

    // GET /v1/devices -- list the user's paired Orion devices. Each device
    // dictionary includes id, serial_number, name, zones, etc. Remember:
    // live/action endpoints key on serial_number, not id.
    function listDevices() as Void {
        _op = "devices";
        var url = apiUrl("/v1/devices");
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => authHeaders(),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        System.println("OrionClient: GET /v1/devices");
        Communications.makeWebRequest(url, null, options, method(:onResponse));
    }

    // GET /v1/devices/{serial_number}/live -- live zone on/off + temp
    // snapshot. `deviceSerial` MUST be the device's serial_number, NOT its
    // UUID id -- the UUID returns 403.
    function getLiveDevice(deviceSerial as Lang.String) as Void {
        _op = "live";
        var url = apiUrl("/v1/devices/" + deviceSerial + "/live");
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => authHeaders(),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        System.println("OrionClient: GET /v1/devices/" + deviceSerial + "/live");
        Communications.makeWebRequest(url, null, options, method(:onResponse));
    }

    // PUT /v1/devices/{serial_number}/live -- bulk zone power/temp update,
    // the canonical control primitive. `zones` is an array of dictionaries
    // like {"id" => "zone_a", "on" => true, "temp" => 20.5}. `deviceSerial`
    // MUST be the device's serial_number, NOT its UUID id -- the UUID
    // returns 403 (see api.py's update_live_device_zones docstring).
    function updateLiveDeviceZones(deviceSerial as Lang.String, zones as Lang.Array) as Void {
        _op = "update_live";
        var url = apiUrl("/v1/devices/" + deviceSerial + "/live");
        var params = { "zones" => zones };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_PUT,
            :headers => authHeaders(),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        System.println("OrionClient: PUT /v1/devices/" + deviceSerial + "/live");
        Communications.makeWebRequest(url, params, options, method(:onResponse));
    }

    // ── Response dispatch ────────────────────────────────────────────────

    function onResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        System.println("OrionClient: " + _op + " response " + responseCode.toString());

        if (_op.equals("auth_code")) {
            handleAuthCodeResponse(responseCode, data);
        } else if (_op.equals("verify_do")) {
            handleVerifyResponse(responseCode, data, true);
        } else if (_op.equals("verify_verify")) {
            handleVerifyResponse(responseCode, data, false);
        } else if (_op.equals("refresh")) {
            handleRefreshResponse(responseCode, data);
        } else if (_op.equals("me")) {
            handleUnwrappedDictResponse(responseCode, data);
        } else if (_op.equals("devices")) {
            handleDevicesResponse(responseCode, data);
        } else if (_op.equals("live")) {
            handleUnwrappedDictResponse(responseCode, data);
        } else if (_op.equals("update_live")) {
            handleUnwrappedDictResponse(responseCode, data);
        } else {
            _callback.invoke(null, "unknown op");
        }
    }

    private function handleAuthCodeResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (responseCode < 0 || responseCode >= 300) {
            _callback.invoke(false, describeError(responseCode, data));
            return;
        }
        if (data != null && data instanceof Lang.Dictionary) {
            var success = (data as Lang.Dictionary).get("success");
            if (success != null && success instanceof Lang.Boolean) {
                _callback.invoke(success as Lang.Boolean, null);
                return;
            }
        }
        _callback.invoke(false, null);
    }

    private function handleVerifyResponse(
        responseCode as Lang.Number,
        data as Lang.Dictionary or Lang.String or Null,
        tryFallback as Lang.Boolean
    ) as Void {
        // 401 (invalid/expired code) is surfaced immediately -- no
        // fallback, matching api.py's `except OrionAuthError: raise`.
        if (responseCode == 401) {
            _callback.invoke(null, describeError(responseCode, data));
            return;
        }

        if (responseCode >= 200 && responseCode < 300) {
            var tokens = null;
            if (data != null && data instanceof Lang.Dictionary) {
                tokens = extractTokens(data as Lang.Dictionary);
            }
            if (tokens != null) {
                _callback.invoke(tokens, null);
                return;
            }
            // 200 but an unrecognised shape -- api.py treats this the same
            // as a failure and tries the next endpoint.
        }

        if (tryFallback) {
            startVerifyRequest("/v1/auth/verify", "verify_verify");
            return;
        }

        _callback.invoke(null, "Could not complete auth via any known endpoint: " + describeError(responseCode, data));
    }

    private function handleRefreshResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (responseCode < 0 || responseCode >= 300) {
            _callback.invoke(null, describeError(responseCode, data));
            return;
        }
        if (data == null || !(data instanceof Lang.Dictionary)) {
            _callback.invoke(null, "Unexpected refresh response shape");
            return;
        }
        var tokens = extractTokens(data as Lang.Dictionary);
        if (tokens == null) {
            _callback.invoke(null, "Unexpected refresh response shape");
            return;
        }
        _accessToken = tokens.get("access_token") as Lang.String;
        _refreshToken = tokens.get("refresh_token") as Lang.String;
        _expiresAt = tokens.get("expires_at") as Lang.Number;
        _callback.invoke(tokens, null);
    }

    // Shared by getCurrentUser/getLiveDevice/updateLiveDeviceZones: all
    // three return {"response": {...fields...}, "success": true} and are
    // handed back to the caller unwrapped (data.get("response", data) in
    // api.py's terms).
    private function handleUnwrappedDictResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (responseCode == 401) {
            _callback.invoke(null, describeError(responseCode, data));
            return;
        }
        if (responseCode < 0 || responseCode >= 300) {
            _callback.invoke(null, describeError(responseCode, data));
            return;
        }
        if (data == null || !(data instanceof Lang.Dictionary)) {
            _callback.invoke(null, "unexpected response shape");
            return;
        }
        _callback.invoke(unwrapResponse(data as Lang.Dictionary), null);
    }

    private function handleDevicesResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (responseCode == 401) {
            _callback.invoke(null, describeError(responseCode, data));
            return;
        }
        if (responseCode < 0 || responseCode >= 300) {
            _callback.invoke(null, describeError(responseCode, data));
            return;
        }
        if (data == null || !(data instanceof Lang.Dictionary)) {
            _callback.invoke(null, "unexpected response shape");
            return;
        }

        var response = unwrapResponse(data as Lang.Dictionary);
        if (response instanceof Lang.Dictionary) {
            var devices = (response as Lang.Dictionary).get("devices");
            if (devices != null && devices instanceof Lang.Array) {
                _callback.invoke(devices, null);
                return;
            }
            _callback.invoke([], null);
            return;
        }
        if (response instanceof Lang.Array) {
            _callback.invoke(response, null);
            return;
        }
        _callback.invoke([], null);
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private function apiUrl(path as Lang.String) as Lang.String {
        return "https://api1.orionbed.com" + path;
    }

    private function authHeaders() as Lang.Dictionary {
        var headers = { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON };
        if (_accessToken != null && (_accessToken as Lang.String).length() > 0) {
            headers.put("Authorization", "Bearer " + _accessToken);
        }
        return headers;
    }

    private function unauthHeaders() as Lang.Dictionary {
        return { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON };
    }

    // data.get("response", data) in Python terms: unwrap the envelope if
    // present, otherwise return the payload as-is.
    private function unwrapResponse(data as Lang.Dictionary) as Lang.Object {
        var response = data.get("response");
        if (response != null) {
            return response;
        }
        return data;
    }

    // Extracts a normalised {"access_token", "refresh_token", "expires_at"}
    // dict from any of the three known response shapes -- mirrors api.py's
    // _extract_tokens exactly (nested snake_case, flat camelCase, flat
    // snake_case). Returns null if none match.
    private function extractTokens(data as Lang.Dictionary) as Lang.Dictionary or Null {
        // 1. Nested snake_case: response.session.access_token
        var response = data.get("response");
        if (response != null && response instanceof Lang.Dictionary) {
            var session = (response as Lang.Dictionary).get("session");
            if (session != null && session instanceof Lang.Dictionary) {
                var sessionDict = session as Lang.Dictionary;
                if (sessionDict.get("access_token") != null) {
                    return {
                        "access_token" => sessionDict.get("access_token"),
                        "refresh_token" => stringOrDefault(sessionDict.get("refresh_token"), ""),
                        "expires_at" => numberOrDefault(sessionDict.get("expires_at"), 0)
                    };
                }
            }
        }

        // 2. Flat camelCase: accessToken / refreshToken / expiresAt
        if (data.get("accessToken") != null) {
            var expiresAt = data.get("expiresAt");
            if (expiresAt == null) {
                expiresAt = data.get("expires_at");
            }
            return {
                "access_token" => data.get("accessToken"),
                "refresh_token" => stringOrDefault(data.get("refreshToken"), ""),
                "expires_at" => numberOrDefault(expiresAt, 0)
            };
        }

        // 3. Flat snake_case: access_token / refresh_token / expires_at
        if (data.get("access_token") != null) {
            return {
                "access_token" => data.get("access_token"),
                "refresh_token" => stringOrDefault(data.get("refresh_token"), ""),
                "expires_at" => numberOrDefault(data.get("expires_at"), 0)
            };
        }

        return null;
    }

    private function stringOrDefault(value as Lang.Object or Null, fallback as Lang.String) as Lang.String {
        if (value != null && value instanceof Lang.String) {
            return value as Lang.String;
        }
        return fallback;
    }

    private function numberOrDefault(value as Lang.Object or Null, fallback as Lang.Number) as Lang.Number {
        if (value != null && value instanceof Lang.Number) {
            return value as Lang.Number;
        }
        if (value != null && value instanceof Lang.Float) {
            return (value as Lang.Float).toNumber();
        }
        return fallback;
    }

    // Distinguishes connection failures (negative/no responseCode -- no
    // network path at all) from HTTP-level errors, matching
    // GitHubClient.mc's httpError()/negative-responseCode handling.
    private function describeError(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Lang.String {
        if (responseCode < 0) {
            return "No network path — check phone/Bluetooth connection";
        }
        if (responseCode == 401) {
            return "Authentication failed: " + httpError(responseCode, data);
        }
        return httpError(responseCode, data);
    }

    private function httpError(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Lang.String {
        var msg = "HTTP " + responseCode.toString();
        if (data != null && data instanceof Lang.Dictionary) {
            var message = (data as Lang.Dictionary).get("message");
            if (message != null) {
                msg = msg + ": " + (message as Lang.String);
            }
        } else if (data != null && data instanceof Lang.String) {
            msg = msg + ": " + (data as Lang.String);
        }
        return msg;
    }
}

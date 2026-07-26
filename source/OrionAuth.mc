// On-device auth storage + token refresh handling (oga-aw5).
//
// Wraps OrionClient (oga-vjk) so callers (provisioning UI, device list/
// control views) never touch raw tokens or the refresh dance directly.
// Mirrors GarminMerge's GitHubOAuth.mc storeToken()/hasStoredToken()/
// clearStoredToken() pattern, adapted for Orion's two auth methods and
// its OTP refresh token -- see docs/DESIGN.md's "Auth: dual provisioning
// paths" and "Token refresh vs. Background Service" sections.
//
// Storage vs. Properties (per docs/DESIGN.md): Application.Storage holds
// everything that rotates or is only known post-validation (active access
// token / refresh token / expires_at, the auth method in use, the API key
// once validated). Application.Properties (resources/settings/
// properties.xml: api_key, phone) holds only static user-entered
// convenience values and is read-only from device code -- nothing here
// ever writes to Properties.
//
// No Background Service: refresh happens synchronously, on-demand, right
// before an authenticated call -- see startAuthenticatedCall()'s
// isTokenExpired() check. This mirrors api.py's ensure_valid_token() /
// _token_expired(margin_seconds=60) exactly. That's a deliberate decision
// documented in docs/DESIGN.md; don't relitigate it here.
using Toybox.Application;
using Toybox.Lang;
using Toybox.System;

class OrionAuth {

    // Mirrors api.py's ensure_valid_token(margin_seconds=60).
    private static const TOKEN_REFRESH_MARGIN_SECONDS = 60;

    private static const STORAGE_AUTH_METHOD = "orion_auth_method";
    private static const STORAGE_ACCESS_TOKEN = "orion_access_token";
    private static const STORAGE_REFRESH_TOKEN = "orion_refresh_token";
    private static const STORAGE_EXPIRES_AT = "orion_expires_at";

    private var _client as OrionClient;

    // State for the single in-flight wrapped call (OrionClient itself only
    // tracks one op at a time -- see its class comment -- so OrionAuth
    // follows the same one-at-a-time contract).
    private var _pendingCallback as Lang.Method or Null;
    private var _pendingOp as Lang.String;
    private var _pendingDeviceSerial as Lang.String or Null;
    private var _pendingZones as Lang.Array or Null;
    private var _pendingApiKey as Lang.String or Null;
    private var _awaitingRefresh as Lang.Boolean;

    function initialize() {
        _pendingCallback = null;
        _pendingOp = "";
        _pendingDeviceSerial = null;
        _pendingZones = null;
        _pendingApiKey = null;
        _awaitingRefresh = false;

        var authMethod = Application.Storage.getValue(STORAGE_AUTH_METHOD);
        var isApiKey = (authMethod != null && authMethod instanceof Lang.String && (authMethod as Lang.String).equals("api_key"));
        _client = new OrionClient(method(:onClientResponse), isApiKey);
        restoreFromStorage(authMethod);
    }

    // ── Signed-in state ──────────────────────────────────────────────────

    function isSignedIn() as Lang.Boolean {
        var token = _client.getAccessToken();
        return token != null && (token as Lang.String).length() > 0;
    }

    // "api_key" | "otp" | null (not signed in).
    function authMethod() as Lang.String or Null {
        if (!isSignedIn()) {
            return null;
        }
        return _client.isApiKeyAuth() ? "api_key" : "otp";
    }

    static function hasStoredToken() as Lang.Boolean {
        var token = Application.Storage.getValue(OrionAuth.STORAGE_ACCESS_TOKEN);
        if (token != null && token instanceof Lang.String) {
            return (token as Lang.String).length() > 0;
        }
        return false;
    }

    // Mirrors GitHubOAuth.clearStoredToken(). Clears ALL Storage auth
    // state (access/refresh token, expiry, method flag) -- the API key
    // once validated lives under the same access-token key, so this is
    // sufficient for both auth methods.
    static function clearStoredToken() as Void {
        Application.Storage.deleteValue(OrionAuth.STORAGE_AUTH_METHOD);
        Application.Storage.deleteValue(OrionAuth.STORAGE_ACCESS_TOKEN);
        Application.Storage.deleteValue(OrionAuth.STORAGE_REFRESH_TOKEN);
        Application.Storage.deleteValue(OrionAuth.STORAGE_EXPIRES_AT);
        System.println("OrionAuth: cleared stored auth state");
    }

    function signOut() as Void {
        OrionAuth.clearStoredToken();
        _client = new OrionClient(method(:onClientResponse), false);
        _pendingCallback = null;
        _pendingOp = "";
        _awaitingRefresh = false;
        System.println("OrionAuth: signed out");
    }

    // ── Provisioning (no valid token required yet) ──────────────────────
    // Callback shape matches OrionClient's: (result, error).

    function requestAuthCode(phone as Lang.String, callback as Lang.Method) as Void {
        _pendingOp = "auth_code";
        _pendingCallback = callback;
        _awaitingRefresh = false;
        _client.requestAuthCode(phone);
    }

    // On success, persists the returned session tokens and hydrates the
    // wrapped client so subsequent authenticated calls work immediately.
    function verifyAuthCode(code as Lang.String, phone as Lang.String, callback as Lang.Method) as Void {
        _pendingOp = "verify_code";
        _pendingCallback = callback;
        _awaitingRefresh = false;
        _client.verifyAuthCode(code, phone);
    }

    // Validates a pasted API key via GET /v1/auth/me (401 = invalid) and
    // persists it only on success.
    function validateApiKey(apiKey as Lang.String, callback as Lang.Method) as Void {
        _pendingOp = "validate_api_key";
        _pendingApiKey = apiKey;
        _pendingCallback = callback;
        _awaitingRefresh = false;
        _client.setApiKey(apiKey);
        _client.getCurrentUser();
    }

    // ── Authenticated calls (ensure_valid_token()-equivalent) ───────────
    // Each of these refreshes synchronously first if the token is expired
    // (or near-expiry, per TOKEN_REFRESH_MARGIN_SECONDS) before dispatching
    // the real request -- a no-op check for API-key auth, which never
    // expires client-side (a revoked key just 401s on the real call).

    function getCurrentUser(callback as Lang.Method) as Void {
        startAuthenticatedCall("current_user", callback);
    }

    function listDevices(callback as Lang.Method) as Void {
        startAuthenticatedCall("list_devices", callback);
    }

    function getLiveDevice(deviceSerial as Lang.String, callback as Lang.Method) as Void {
        _pendingDeviceSerial = deviceSerial;
        startAuthenticatedCall("live_device", callback);
    }

    function updateLiveDeviceZones(deviceSerial as Lang.String, zones as Lang.Array, callback as Lang.Method) as Void {
        _pendingDeviceSerial = deviceSerial;
        _pendingZones = zones;
        startAuthenticatedCall("update_live", callback);
    }

    private function startAuthenticatedCall(op as Lang.String, callback as Lang.Method) as Void {
        _pendingOp = op;
        _pendingCallback = callback;
        if (_client.isTokenExpired(TOKEN_REFRESH_MARGIN_SECONDS)) {
            System.println("OrionAuth: token expired/near-expiry, refreshing before " + op);
            _awaitingRefresh = true;
            _client.refreshTokens();
            return;
        }
        dispatchPendingAction();
    }

    private function dispatchPendingAction() as Void {
        if (_pendingOp.equals("list_devices")) {
            _client.listDevices();
        } else if (_pendingOp.equals("live_device")) {
            _client.getLiveDevice(_pendingDeviceSerial as Lang.String);
        } else if (_pendingOp.equals("update_live")) {
            _client.updateLiveDeviceZones(_pendingDeviceSerial as Lang.String, _pendingZones as Lang.Array);
        } else if (_pendingOp.equals("current_user")) {
            _client.getCurrentUser();
        } else {
            invokePendingCallback(null, "OrionAuth: unknown pending op after refresh");
        }
    }

    // ── OrionClient response dispatch ───────────────────────────────────

    function onClientResponse(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        if (_awaitingRefresh) {
            _awaitingRefresh = false;
            if (result == null || !(result instanceof Lang.Dictionary)) {
                System.println("OrionAuth: token refresh failed: " + (error != null ? error : "unknown"));
                invokePendingCallback(null, error);
                return;
            }
            persistTokens(result as Lang.Dictionary);
            dispatchPendingAction();
            return;
        }

        if (error == null) {
            if (_pendingOp.equals("verify_code") && result != null && result instanceof Lang.Dictionary) {
                persistTokens(result as Lang.Dictionary);
            } else if (_pendingOp.equals("validate_api_key") && result != null) {
                persistApiKey(_pendingApiKey as Lang.String);
            }
        }

        invokePendingCallback(result, error);
    }

    private function invokePendingCallback(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        var callback = _pendingCallback;
        _pendingCallback = null;
        if (callback != null) {
            (callback as Lang.Method).invoke(result, error);
        }
    }

    // ── Storage helpers ──────────────────────────────────────────────────

    private function restoreFromStorage(authMethodValue as Lang.Object or Null) as Void {
        var token = Application.Storage.getValue(STORAGE_ACCESS_TOKEN);
        if (token == null || !(token instanceof Lang.String) || (token as Lang.String).length() == 0) {
            return;
        }

        if (authMethodValue != null && authMethodValue instanceof Lang.String && (authMethodValue as Lang.String).equals("api_key")) {
            _client.setApiKey(token as Lang.String);
            System.println("OrionAuth: restored API key from Storage");
            return;
        }

        var refreshToken = Application.Storage.getValue(STORAGE_REFRESH_TOKEN);
        var expiresAt = Application.Storage.getValue(STORAGE_EXPIRES_AT);
        _client.setTokens(
            token as Lang.String,
            (refreshToken != null && refreshToken instanceof Lang.String) ? refreshToken as Lang.String : "",
            (expiresAt != null && expiresAt instanceof Lang.Number) ? expiresAt as Lang.Number : 0
        );
        System.println("OrionAuth: restored OTP session from Storage");
    }

    private function persistTokens(tokens as Lang.Dictionary) as Void {
        var accessToken = tokens.get("access_token");
        if (accessToken == null || !(accessToken instanceof Lang.String)) {
            System.println("OrionAuth: refused to persist tokens with no access_token");
            return;
        }
        var refreshToken = tokens.get("refresh_token");
        var expiresAt = tokens.get("expires_at");
        var refreshTokenStr = (refreshToken != null && refreshToken instanceof Lang.String) ? refreshToken as Lang.String : "";
        var expiresAtNum = (expiresAt != null && expiresAt instanceof Lang.Number) ? expiresAt as Lang.Number : 0;

        _client.setTokens(accessToken as Lang.String, refreshTokenStr, expiresAtNum);

        Application.Storage.setValue(STORAGE_AUTH_METHOD, "otp");
        Application.Storage.setValue(STORAGE_ACCESS_TOKEN, accessToken as Lang.String);
        Application.Storage.setValue(STORAGE_REFRESH_TOKEN, refreshTokenStr);
        Application.Storage.setValue(STORAGE_EXPIRES_AT, expiresAtNum);
        System.println("OrionAuth: persisted OTP session tokens");
    }

    private function persistApiKey(apiKey as Lang.String) as Void {
        Application.Storage.setValue(STORAGE_AUTH_METHOD, "api_key");
        Application.Storage.setValue(STORAGE_ACCESS_TOKEN, apiKey);
        Application.Storage.deleteValue(STORAGE_REFRESH_TOKEN);
        Application.Storage.deleteValue(STORAGE_EXPIRES_AT);
        System.println("OrionAuth: persisted API key");
    }
}

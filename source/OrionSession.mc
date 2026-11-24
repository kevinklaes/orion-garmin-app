// The part of Orion sign-in that the glance and the background refresh also
// need (oga-6bf): the Storage keys, the "signed in?" check, saving refreshed
// tokens, and reading tokens out of an auth reply. OrionAuth and OrionClient
// use these too, so each rule exists once.
//
// Annotations decide which process loads what. The glance loads only
// hasStoredToken() and its key. The background loads everything here. Keep
// it that way: anything added to the glance or the background costs memory
// on products with a 32 KB limit.
using Toybox.Application;
using Toybox.Lang;

module OrionSession {

    (:glance, :background) const KEY_ACCESS_TOKEN = "orion_access_token";
    (:background) const KEY_AUTH_METHOD = "orion_auth_method";
    (:background) const KEY_REFRESH_TOKEN = "orion_refresh_token";
    (:background) const KEY_EXPIRES_AT = "orion_expires_at";

    // Mirrors api.py's ensure_valid_token(margin_seconds=60).
    (:background) const REFRESH_MARGIN_SECONDS = 60;

    (:background) const BASE_URL = "https://api1.orionbed.com";

    // No network. An API key and an OTP access token share one key.
    (:glance, :background)
    function hasStoredToken() as Lang.Boolean {
        var token = Application.Storage.getValue(KEY_ACCESS_TOKEN);
        if (token != null && token instanceof Lang.String) {
            return (token as Lang.String).length() > 0;
        }
        return false;
    }

    // Saves a phone + code session. The order matters: a background run can
    // be killed between two writes. With the refresh token first and the
    // expiry last, a half-finished save still leaves a refresh token that
    // works and an expiry that makes the next call refresh again.
    //
    // An empty refresh token keeps the stored one: a refresh reply without
    // a new refresh token must not throw away the one that still works.
    // Sign-out (OrionAuth.clearStoredToken()) and API-key sign-in delete it.
    (:background)
    function saveOtpTokens(accessToken as Lang.String, refreshToken as Lang.String, expiresAt as Lang.Number) as Void {
        Application.Storage.setValue(KEY_AUTH_METHOD, "otp");
        if (refreshToken.length() > 0) {
            Application.Storage.setValue(KEY_REFRESH_TOKEN, refreshToken);
        }
        Application.Storage.setValue(KEY_ACCESS_TOKEN, accessToken);
        Application.Storage.setValue(KEY_EXPIRES_AT, expiresAt);
    }

    // Extracts {"access_token", "refresh_token", "expires_at"} from any of
    // the three known reply shapes (nested snake_case, flat camelCase, flat
    // snake_case), as api.py's _extract_tokens does. Null if none match.
    (:background)
    function extractTokens(data as Lang.Dictionary) as Lang.Dictionary or Null {
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

        if (data.get("access_token") != null) {
            return {
                "access_token" => data.get("access_token"),
                "refresh_token" => stringOrDefault(data.get("refresh_token"), ""),
                "expires_at" => numberOrDefault(data.get("expires_at"), 0)
            };
        }

        return null;
    }

    (:background)
    function stringOrDefault(value as Lang.Object or Null, fallback as Lang.String) as Lang.String {
        if (value != null && value instanceof Lang.String) {
            return value as Lang.String;
        }
        return fallback;
    }

    (:background)
    function numberOrDefault(value as Lang.Object or Null, fallback as Lang.Number) as Lang.Number {
        if (value != null && value instanceof Lang.Number) {
            return value as Lang.Number;
        }
        if (value != null && value instanceof Lang.Float) {
            return (value as Lang.Float).toNumber();
        }
        return fallback;
    }
}

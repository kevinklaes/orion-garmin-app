// Backend settings (oga-2cx): which server the app talks to, and the
// Ember & Tide address and key. The settings are `backend` (0 = Orion
// cloud, 1 = Ember & Tide), `et_url` and `et_key` in resources/settings.
// read() and the four functions above it are the only code that names
// those properties, and read() never throws, like DeviceModel.primaryZoneId().
// The pure functions below them take values and return values so
// (:test) code can call them.
//
// Uses Toybox.Application and Toybox.Lang only. The key is read from the
// settings on each app open and kept in memory; nothing is written to
// Application.Storage.
using Toybox.Application;
using Toybox.Lang;

module BackendConfig {

    const BACKEND_PROPERTY = "backend";
    const URL_PROPERTY = "et_url";
    const KEY_PROPERTY = "et_key";

    const MISSING_TEXT = "Set the server URL and key in Garmin Connect";
    const NOT_HTTPS_TEXT = "Server URL must start with https://";

    // ── Settings ────────────────────────────────────────────────────────

    function usesEmberTide() as Lang.Boolean {
        return isEmberTide(read(BACKEND_PROPERTY));
    }

    // The normalised address, or null when it is unusable.
    function url() as Lang.String or Null {
        return normalizeUrl(read(URL_PROPERTY));
    }

    // The trimmed key ("" when unset).
    function key() as Lang.String {
        return trim(read(KEY_PROPERTY));
    }

    // Why Ember & Tide mode cannot start, or null when it can.
    function problem() as Lang.String or Null {
        return setupProblem(read(URL_PROPERTY), read(KEY_PROPERTY));
    }

    function read(id as Lang.String) as Lang.Object or Null {
        try {
            return Application.Properties.getValue(id);
        } catch (e) {
            return null;
        }
    }

    // ── Pure functions ──────────────────────────────────────────────────

    // Only the number 1 means Ember & Tide (same shape as
    // DeviceModel.zoneIdForSide()). Null, 0, 2, -1, "1" and 1.0 mean Orion.
    function isEmberTide(value as Lang.Object or Null) as Lang.Boolean {
        return value != null && value instanceof Lang.Number && (value as Lang.Number) == 1;
    }

    // Strips spaces, tabs and line breaks from both ends. A non-string
    // gives "". Monkey C strings have no trim().
    function trim(value as Lang.Object or Null) as Lang.String {
        if (value == null || !(value instanceof Lang.String)) {
            return "";
        }
        var s = value as Lang.String;
        var chars = s.toCharArray();
        var start = 0;
        var end = chars.size();
        while (start < end && isSpace(chars[start])) {
            start += 1;
        }
        while (end > start && isSpace(chars[end - 1])) {
            end -= 1;
        }
        return s.substring(start, end) as Lang.String;
    }

    function isSpace(c as Lang.Char) as Lang.Boolean {
        return c == ' ' || c == '\t' || c == '\n' || c == '\r';
    }

    // Trims, removes every trailing "/", and accepts only "https://" (any
    // letter case) followed by something. A path prefix is kept. Returns
    // "https://" plus the rest as typed, or null.
    function normalizeUrl(value as Lang.Object or Null) as Lang.String or Null {
        var s = trim(value);
        while (s.length() > 0 && s.substring(s.length() - 1, s.length()).equals("/")) {
            s = s.substring(0, s.length() - 1) as Lang.String;
        }
        if (s.length() <= 8) {
            return null;
        }
        if (!(s.substring(0, 8) as Lang.String).toLower().equals("https://")) {
            return null;
        }
        return "https://" + s.substring(8, s.length());
    }

    // The set-up message for an address and key, or null when both are
    // usable.
    function setupProblem(urlValue as Lang.Object or Null, keyValue as Lang.Object or Null) as Lang.String or Null {
        if (trim(urlValue).length() == 0 || trim(keyValue).length() == 0) {
            return MISSING_TEXT;
        }
        if (normalizeUrl(urlValue) == null) {
            return NOT_HTTPS_TEXT;
        }
        return null;
    }
}

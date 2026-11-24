// Unit tests for the backend settings (oga-2cx): the backend choice, the
// URL check and the set-up messages in BackendConfig. Pure functions only;
// no test reads or writes a setting. Run with a --unit-test build and
// `monkeydo <prg> <device> -t`; see docs/TESTING.md.
using Toybox.Lang;
using Toybox.Test;

(:test)
module BackendConfigTest {

    (:test)
    function backendChoice(logger as Test.Logger) as Lang.Boolean {
        var ok = BackendConfig.isEmberTide(1);
        if (!ok) {
            logger.error("1 did not choose Ember & Tide");
        }
        var orion = [0, null, 2, -1, "1", 1.0] as Lang.Array;
        for (var i = 0; i < orion.size(); i += 1) {
            if (BackendConfig.isEmberTide(orion[i])) {
                logger.error("value #" + i + " chose Ember & Tide");
                ok = false;
            }
        }
        return ok;
    }

    function checkUrl(logger as Test.Logger, input as Lang.String, expected as Lang.String or Null) as Lang.Boolean {
        var actual = BackendConfig.normalizeUrl(input);
        var ok = (expected == null) ? (actual == null) : (actual != null && actual.equals(expected));
        if (!ok) {
            logger.error("'" + input + "': expected " + expected + ", got " + actual);
        }
        return ok;
    }

    (:test)
    function urlCheck(logger as Test.Logger) as Lang.Boolean {
        var ok = checkUrl(logger, "https://bed.example.com", "https://bed.example.com");
        ok = checkUrl(logger, " https://bed.example.com/ ", "https://bed.example.com") && ok;
        ok = checkUrl(logger, "HTTPS://bed.example.com/et", "https://bed.example.com/et") && ok;
        ok = checkUrl(logger, "https://bed.example.com//", "https://bed.example.com") && ok;
        ok = checkUrl(logger, "http://192.168.1.20:8790", null) && ok;
        ok = checkUrl(logger, "bed.example.com", null) && ok;
        ok = checkUrl(logger, "https://", null) && ok;
        ok = checkUrl(logger, "https:///", null) && ok;
        ok = checkUrl(logger, "", null) && ok;
        // Requests append "/api/…" to the normalised prefix.
        var prefix = BackendConfig.normalizeUrl("HTTPS://bed.example.com/et");
        if (prefix == null || !(prefix + "/api/snapshot").equals("https://bed.example.com/et/api/snapshot")) {
            logger.error("path prefix not kept");
            ok = false;
        }
        return ok;
    }

    function checkProblem(logger as Test.Logger, url as Lang.Object or Null, key as Lang.Object or Null, expected as Lang.String or Null) as Lang.Boolean {
        var actual = BackendConfig.setupProblem(url, key);
        var ok = (expected == null) ? (actual == null) : (actual != null && actual.equals(expected));
        if (!ok) {
            logger.error(url + " / key: expected " + expected + ", got " + actual);
        }
        return ok;
    }

    (:test)
    function setupProblems(logger as Test.Logger) as Lang.Boolean {
        var missing = "Set the server URL and key in Garmin Connect";
        var notHttps = "Server URL must start with https://";
        var ok = checkProblem(logger, "", "test-key", missing);
        ok = checkProblem(logger, null, "test-key", missing) && ok;
        ok = checkProblem(logger, "https://bed.example.com", "", missing) && ok;
        ok = checkProblem(logger, "https://bed.example.com", "  ", missing) && ok;
        ok = checkProblem(logger, "https://bed.example.com", null, missing) && ok;
        ok = checkProblem(logger, "http://example.com", "test-key", notHttps) && ok;
        ok = checkProblem(logger, "bed.example.com", "test-key", notHttps) && ok;
        ok = checkProblem(logger, "https://bed.example.com", "test-key", null) && ok;
        if (!BackendConfig.trim("\t test-key \n").equals("test-key")) {
            logger.error("trim");
            ok = false;
        }
        return ok;
    }
}

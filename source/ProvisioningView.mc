// Provisioning/auth UI (oga-2et) — shown on first launch (no stored token),
// hands off to DeviceListView (oga-8m6) on success. State machine mirrors
// config_flow.py's async_step_user: method picker -> API key path or phone+OTP path ->
// success/error, using GarminMerge's OAuthView/OAuthDelegate structure
// (state field + onUpdate rendering per state + BehaviorDelegate for
// retry/cancel/confirm) as the structural template.
//
// Native widgets over custom rendering: the method choice uses WatchUi.Menu2
// (matches GarminMerge's AuthMenuDelegate precedent in PRListDelegate.mc)
// and all on-device text/code entry uses WatchUi.TextPicker — both are
// always available given this app's minApiLevel (4.2.0), well above their
// own minimums (3.0.0 / 1.1.0), so no `WatchUi has :X` guards are needed.
//
// API key entry: typing a ~48-char os_live_ key on a 5-button watch is
// painful, so phone-side Application.Properties entry (Garmin Connect
// Mobile's per-app settings screen) is the recommended path -- if
// Properties already has a key we validate and skip straight past the
// picker (docs/DESIGN.md "Auth: dual provisioning paths"); otherwise we
// show a hint screen recommending phone-side entry before offering
// on-device TextPicker entry as a fallback.
//
// Phone entry: normalized to config_flow.py's `1XXXXXXXXXX` shape
// (_PHONE_RE) before calling requestAuthCode -- see normalizePhone().
using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

class ProvisioningView extends WatchUi.View {

    // method | checking_key | key_hint | key_entry | key_validating |
    // phone_entry | requesting_code | code_entry | verifying_code |
    // success | error
    private var _state as Lang.String;
    private var _message as Lang.String;
    private var _errorReturnState as Lang.String;
    private var _auth as OrionAuth;
    private var _phone as Lang.String;
    private var _pendingApiKey as Lang.String;

    function initialize() {
        View.initialize();
        _state = "method";
        _message = "";
        _errorReturnState = "method";
        _auth = new OrionAuth();
        _phone = ProvisioningView.getPropertyValue("phone");
        _pendingApiKey = "";
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onShow() as Void {
        if (_state.equals("method")) {
            beginFlow();
        }
    }

    // ── Flow entry ───────────────────────────────────────────────────────

    private function beginFlow() as Void {
        var storedKey = ProvisioningView.getPropertyValue("api_key");
        if (storedKey.length() > 0) {
            _state = "checking_key";
            _message = "Checking saved key…";
            WatchUi.requestUpdate();
            _auth.validateApiKey(storedKey, method(:onApiKeyValidated));
            return;
        }
        openMethodMenu();
    }

    private function openMethodMenu() as Void {
        var focus = 0;
        if (ProvisioningView.getPropertyValue("phone").length() > 0) {
            focus = 1;
        }
        var menu = new WatchUi.Menu2({ :title => "Sign in", :focus => focus });
        menu.addItem(new WatchUi.MenuItem("API Key", "Paste from phone settings", :api_key, null));
        menu.addItem(new WatchUi.MenuItem("Phone Number", "Text verification code", :phone, null));
        WatchUi.pushView(menu, new ProvisioningMethodMenuDelegate(self), WatchUi.SLIDE_LEFT);
    }

    function backToMethod() as Void {
        _state = "method";
        WatchUi.requestUpdate();
        openMethodMenu();
    }

    // ── Method selection (from ProvisioningMethodMenuDelegate) ─────────────

    function chooseApiKeyMethod() as Void {
        _pendingApiKey = ProvisioningView.getPropertyValue("api_key");
        _state = "key_hint";
        WatchUi.requestUpdate();
    }

    function choosePhoneMethod() as Void {
        _state = "phone_entry";
        WatchUi.requestUpdate();
        WatchUi.pushView(new WatchUi.TextPicker(_phone), new ProvisioningTextDelegate(self, "phone"), WatchUi.SLIDE_DOWN);
    }

    function beginApiKeyEntry() as Void {
        _state = "key_entry";
        WatchUi.pushView(new WatchUi.TextPicker(_pendingApiKey), new ProvisioningTextDelegate(self, "api_key"), WatchUi.SLIDE_DOWN);
    }

    // ── Confirm/back dispatch (from ProvisioningDelegate) ───────────────────

    function getState() as Lang.String {
        return _state;
    }

    function onConfirm() as Lang.Boolean {
        if (_state.equals("key_hint")) {
            beginApiKeyEntry();
            return true;
        }
        if (_state.equals("error")) {
            retryFromError();
            return true;
        }
        if (_state.equals("success")) {
            finish();
            return true;
        }
        return false;
    }

    function retryFromError() as Void {
        if (_errorReturnState.equals("phone_entry")) {
            choosePhoneMethod();
            return;
        }
        backToMethod();
    }

    function finish() as Void {
        var view = new DeviceListView();
        WatchUi.switchToView(view, new DeviceListDelegate(view), WatchUi.SLIDE_IMMEDIATE);
    }

    // ── Text entry results (from ProvisioningTextDelegate) ──────────────────

    function onTextEntered(field as Lang.String, text as Lang.String) as Void {
        if (field.equals("api_key")) {
            _pendingApiKey = text;
            _state = "key_validating";
            _message = "Validating key…";
            WatchUi.requestUpdate();
            _auth.validateApiKey(text, method(:onApiKeyValidated));
        } else if (field.equals("phone")) {
            var normalized = ProvisioningView.normalizePhone(text);
            if (normalized == null) {
                showError("Enter a valid 10-digit phone number", "method");
                return;
            }
            _phone = normalized;
            _state = "requesting_code";
            _message = "Sending code to " + _phone + "…";
            WatchUi.requestUpdate();
            _auth.requestAuthCode(_phone, method(:onAuthCodeRequested));
        } else if (field.equals("otp_code")) {
            _state = "verifying_code";
            _message = "Verifying code…";
            WatchUi.requestUpdate();
            _auth.verifyAuthCode(text, _phone, method(:onCodeVerified));
        }
    }

    function onTextCancelled(field as Lang.String) as Void {
        backToMethod();
    }

    // ── OrionAuth callbacks ──────────────────────────────────────────────

    function onApiKeyValidated(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        if (result != null) {
            _state = "success";
            WatchUi.requestUpdate();
            return;
        }
        showError(ProvisioningView.errorOrDefault(error, "Invalid or revoked API key"), "method");
    }

    function onAuthCodeRequested(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        if (error != null) {
            showError(ProvisioningView.errorOrDefault(error, "Could not send verification code"), "method");
            return;
        }
        if (result != null && result instanceof Lang.Boolean && !(result as Lang.Boolean)) {
            showError("Could not send verification code — check the phone number", "method");
            return;
        }
        _state = "code_entry";
        WatchUi.requestUpdate();
        WatchUi.pushView(new WatchUi.TextPicker(""), new ProvisioningTextDelegate(self, "otp_code"), WatchUi.SLIDE_DOWN);
    }

    function onCodeVerified(result as Lang.Object or Null, error as Lang.String or Null) as Void {
        if (result == null) {
            showError(ProvisioningView.errorOrDefault(error, "Invalid or expired code"), "phone_entry");
            return;
        }
        _state = "success";
        WatchUi.requestUpdate();
    }

    private function showError(message as Lang.String, returnState as Lang.String) as Void {
        System.println("ProvisioningView: error - " + message);
        _message = message;
        _errorReturnState = returnState;
        _state = "error";
        WatchUi.requestUpdate();
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private static function getPropertyValue(key as Lang.String) as Lang.String {
        try {
            var value = Application.Properties.getValue(key);
            if (value != null && value instanceof Lang.String) {
                return value as Lang.String;
            }
        } catch (e) {
            System.println("ProvisioningView: property read failed for " + key);
        }
        return "";
    }

    private static function errorOrDefault(error as Lang.String or Null, fallback as Lang.String) as Lang.String {
        if (error != null && error.length() > 0) {
            return error;
        }
        return fallback;
    }

    // Mirrors config_flow.py's `_PHONE_RE`: normalizes to `1XXXXXXXXXX`.
    // Accepts a bare 10-digit number (prepends country code "1") or an
    // already-prefixed 11-digit number starting with "1". Returns null if
    // the digit count doesn't match either shape.
    private static function normalizePhone(raw as Lang.String) as Lang.String or Null {
        var digits = "";
        var allowedDigits = "0123456789";
        for (var i = 0; i < raw.length(); i += 1) {
            var ch = raw.substring(i, i + 1);
            if (allowedDigits.find(ch) != null) {
                digits = digits + ch;
            }
        }
        if (digits.length() == 10) {
            return "1" + digits;
        }
        if (digits.length() == 11 && digits.substring(0, 1).equals("1")) {
            return digits;
        }
        return null;
    }

    // ── Rendering ────────────────────────────────────────────────────────

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 10, Graphics.FONT_MEDIUM, "Orion Sleep", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(10, 38, width - 10, 38);

        if (_state.equals("key_hint")) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            drawWrapped(dc, 16, 52, width - 32,
                "For a long API key, paste it via Garmin Connect Mobile's app settings instead of typing on-device.");
            drawFooter(dc, width, height, "SELECT type here · BACK menu");
            return;
        }

        if (_state.equals("success")) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2 - 20, Graphics.FONT_MEDIUM, "Signed in", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2 + 16, Graphics.FONT_XTINY, "Account connected", Graphics.TEXT_JUSTIFY_CENTER);
            drawFooter(dc, width, height, "ENTER continue");
            return;
        }

        if (_state.equals("error")) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            drawWrapped(dc, 16, 56, width - 32, _message);
            drawFooter(dc, width, height, "SELECT retry · BACK exit");
            return;
        }

        // In-flight / transient states (menu or TextPicker is usually
        // pushed on top of these almost immediately).
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var body = _message;
        if (body.length() == 0) {
            body = "Choose how to sign in…";
        }
        dc.drawText(width / 2, height / 2, Graphics.FONT_SMALL, body, Graphics.TEXT_JUSTIFY_CENTER);
        drawFooter(dc, width, height, "BACK exit");
    }

    private function drawFooter(dc as Graphics.Dc, width as Lang.Number, height as Lang.Number, text as Lang.String) as Void {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height - 22, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawWrapped(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, maxWidth as Lang.Number, text as Lang.String) as Void {
        var maxChars = (maxWidth / 8).toNumber();
        if (maxChars < 12) {
            maxChars = 12;
        }
        var remaining = text;
        var lineY = y;
        var lines = 0;
        while (remaining.length() > 0 && lines < 8) {
            if (remaining.length() <= maxChars) {
                dc.drawText(x, lineY, Graphics.FONT_SMALL, remaining, Graphics.TEXT_JUSTIFY_LEFT);
                break;
            }
            dc.drawText(x, lineY, Graphics.FONT_SMALL, remaining.substring(0, maxChars), Graphics.TEXT_JUSTIFY_LEFT);
            remaining = remaining.substring(maxChars, remaining.length());
            lineY += 22;
            lines += 1;
        }
    }
}

class ProvisioningDelegate extends WatchUi.BehaviorDelegate {

    private var _view as ProvisioningView;

    function initialize(view as ProvisioningView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onBack() as Lang.Boolean {
        if (_view.getState().equals("key_hint")) {
            _view.backToMethod();
            return true;
        }
        System.exit();
        return true;
    }

    function onSelect() as Lang.Boolean {
        return _view.onConfirm();
    }

    function onKey(evt as WatchUi.KeyEvent) as Lang.Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ESC) {
            return onBack();
        } else if (key == WatchUi.KEY_ENTER) {
            return _view.onConfirm();
        } else if (key == WatchUi.KEY_START || key == WatchUi.KEY_LAP) {
            return _view.onConfirm();
        }
        return false;
    }
}

// Handles the initial API-key-vs-phone choice (WatchUi.Menu2), matching
// GarminMerge's AuthMenuDelegate (PRListDelegate.mc) precedent for
// menu-based auth choices.
class ProvisioningMethodMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as ProvisioningView;

    function initialize(view as ProvisioningView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        if (id == :api_key) {
            _view.chooseApiKeyMethod();
        } else if (id == :phone) {
            _view.choosePhoneMethod();
        }
    }

    function onBack() as Void {
        System.exit();
    }
}

// Generic on-device text entry (WatchUi.TextPicker) shared by the API key,
// phone number, and OTP code entry steps -- `field` tells ProvisioningView
// which pending value was entered.
class ProvisioningTextDelegate extends WatchUi.TextPickerDelegate {

    private var _view as ProvisioningView;
    private var _field as Lang.String;

    function initialize(view as ProvisioningView, field as Lang.String) {
        TextPickerDelegate.initialize();
        _view = view;
        _field = field;
    }

    function onTextEntered(text as Lang.String, changed as Lang.Boolean) as Lang.Boolean {
        _view.onTextEntered(_field, text);
        return true;
    }

    function onCancel() as Lang.Boolean {
        _view.onTextCancelled(_field);
        return true;
    }
}

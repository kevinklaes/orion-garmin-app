// Orion Sleep — Connect IQ Device App entry point (oga-fsf).
//
// getInitialView() routes on stored-auth state: no token yet ->
// ProvisioningView (oga-2et's method picker / API-key / phone+OTP flow);
// already signed in -> DeviceListView (oga-8m6's device list + control UI)
// — see docs/DESIGN.md for the full plan and the file-by-file breakdown.
using Toybox.Application;
using Toybox.WatchUi;

class OrionSleepApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        if (OrionAuth.hasStoredToken()) {
            var view = new DeviceListView();
            return [view, new DeviceListDelegate(view)];
        }
        var view = new ProvisioningView();
        return [view, new ProvisioningDelegate(view)];
    }

    function onSettingsChanged() {
        WatchUi.requestUpdate();
    }
}

function getApp() as OrionSleepApp {
    return Application.getApp() as OrionSleepApp;
}

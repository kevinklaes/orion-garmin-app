// Orion Sleep — Connect IQ Device App entry point (oga-fsf).
//
// Scaffolding only: getInitialView() currently returns a placeholder status
// screen. Real screens (provisioning/auth, device list, device control) are
// implemented in follow-up beads — see docs/DESIGN.md for the full plan and
// the file-by-file breakdown.
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
        var view = new StatusView();
        var delegate = new StatusDelegate();
        return [view, delegate];
    }

    function onSettingsChanged() {
        WatchUi.requestUpdate();
    }
}

function getApp() as OrionSleepApp {
    return Application.getApp() as OrionSleepApp;
}

// Orion Sleep — Connect IQ Widget entry point (oga-fsf).
//
// getInitialView() first checks the backend setting (oga-2cx). In Ember &
// Tide mode it opens the control view straight on an EmberTideClient (one
// bed, no provisioning, no device list; the view is the root, so Back
// exits), or shows a set-up message when the address or key is unusable.
// That branch never touches the stored Orion sign-in, so switching back
// to the Orion cloud needs no new sign-in. Otherwise it routes on
// stored-auth state as before: no token yet -> ProvisioningView (oga-2et's
// method picker / API-key / phone+OTP flow); already signed in ->
// DeviceListView (oga-8m6's device list + control UI) — see
// docs/DESIGN.md for the full plan and the file-by-file breakdown.
// A changed setting takes effect the next time the app opens.
// getGlanceView() supplies the swipe-loop preview (OrionGlanceView);
// selecting it opens the same getInitialView() flow.
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
        if (BackendConfig.usesEmberTide()) {
            var problem = BackendConfig.problem();
            var url = BackendConfig.url();
            if (problem != null || url == null) {
                return [new MessageView("Ember & Tide", problem != null ? problem : BackendConfig.NOT_HTTPS_TEXT), new MessageDelegate()];
            }
            var etView = new DeviceControlView(new EmberTideClient(url, BackendConfig.key()));
            return [etView, new DeviceControlDelegate(etView, true)];
        }
        if (OrionAuth.hasStoredToken()) {
            var view = new DeviceListView();
            return [view, new DeviceListDelegate(view)];
        }
        var view = new ProvisioningView();
        return [view, new ProvisioningDelegate(view)];
    }

    function getGlanceView() {
        return [new OrionGlanceView()];
    }

    function onSettingsChanged() {
        WatchUi.requestUpdate();
    }
}

function getApp() as OrionSleepApp {
    return Application.getApp() as OrionSleepApp;
}

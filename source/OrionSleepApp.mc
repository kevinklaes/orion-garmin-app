// Orion Sleep — Connect IQ Widget entry point (oga-fsf).
//
// getInitialView() routes on stored-auth state: no token yet ->
// ProvisioningView (oga-2et's method picker / API-key / phone+OTP flow);
// already signed in -> DeviceListView (oga-8m6's device list + control UI)
// — see docs/DESIGN.md for the full plan and the file-by-file breakdown.
// getGlanceView() supplies the swipe-loop preview (OrionGlanceView);
// selecting it opens the same getInitialView() flow.
//
// Background refresh (oga-6bf): getInitialView() registers a 30-minute
// temporal event; getServiceDelegate() hands the system GlanceRefreshDelegate,
// which fetches the glance bed's live zones into GlanceCache. This class is
// loaded in all three processes (app, glance, background), so each entry
// point may only call code annotated for the process that calls it.
using Toybox.Application;
using Toybox.Background;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

(:glance, :background)
class OrionSleepApp extends Application.AppBase {

    // True in the background process, where Toybox.WatchUi does not exist.
    private var _inBackground as Lang.Boolean = false;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        registerGlanceRefresh();
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

    // Background process only: the delegate the system runs on each wake.
    function getServiceDelegate() as [System.ServiceDelegate] {
        _inBackground = true;
        return [new GlanceRefreshDelegate()];
    }

    // A background run that changed the saved state exits with `true`, and
    // the system calls this in the running app or glance. The state is
    // already in Storage; all that is left is to redraw.
    function onBackgroundData(data as Application.PersistableType) as Void {
        WatchUi.requestUpdate();
    }

    // Asks the system to wake GlanceRefreshDelegate every 30 minutes. One
    // registration per app; it survives the app closing. Registering again
    // with the same interval is skipped.
    private function registerGlanceRefresh() as Void {
        try {
            var reg = Background.getTemporalEventRegisteredTime();
            if (reg == null || !(reg instanceof Time.Duration)
                || (reg as Time.Duration).value() != GlanceCache.REFRESH_INTERVAL_SECONDS) {
                Background.registerForTemporalEvent(new Time.Duration(GlanceCache.REFRESH_INTERVAL_SECONDS));
            }
        } catch (e) {
            System.println("OrionSleepApp: could not register glance refresh");
        }
    }

    // Also called in the background process when settings change there,
    // where WatchUi does not exist.
    function onSettingsChanged() {
        if (_inBackground) {
            return;
        }
        WatchUi.requestUpdate();
    }
}

function getApp() as OrionSleepApp {
    return Application.getApp() as OrionSleepApp;
}

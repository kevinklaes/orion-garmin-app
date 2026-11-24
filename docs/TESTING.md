# Testing the app yourself

A small unit-test suite (`source/PrimarySideTest.mc`,
`source/GlanceCacheTest.mc`) covers the primary side logic and the glance's
text and saved state (see [Unit tests](#unit-tests)). Everything else is still
verified manually, via the Connect IQ simulator or a real device (Connect IQ
apps aren't easily unit-testable the way a typical backend service is). The
README's "Build" section only shows a raw `monkeyc` compile command, not how
to actually run and click through the app; this doc covers that.

## What you need

- **Connect IQ SDK** + a developer key (`.der` file) — same ones used for
  building (see [README.md](../README.md#build)). The SDK path is in
  `~/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg`;
  `monkeyc`, `monkeydo` and `connectiq` are in its `bin/`, which is not on
  `PATH`. Keep the key outside the repo and never commit it; write build
  output outside the repo or to `bin/` (ignored). There is no CI build
  (oga-zha): every build and test run is local.
- **A real Orion Sleep account** (API key, or a phone number you can
  receive an OTP text on). The app talks to the real production API at
  `https://api1.orionbed.com` — there's no mock/sandbox mode. Without real
  credentials you can still exercise the provisioning screens and error
  paths (invalid key, wrong OTP), but not the actual device list/control
  screens, since those need a real Orion account with a paired device.

## Running it in the simulator

Easiest path — VS Code with the Monkey C extension:

1. Open this repo in VS Code.
2. Command palette → **Monkey C: Run** (or the play button in the status
   bar). Pick a target device when prompted — `fenix7` and `venu3` are the
   two watches, `edge840`/`edge1040` are the two Edge bike computers (all
   four are declared in `manifest.xml`).
3. This launches the Connect IQ simulator with the app installed and
   running. The simulator boots to whatever `OrionSleepApp.getInitialView()`
   resolves to — the provisioning screen if no token is stored yet
   (`OrionAuth.hasStoredToken()` is false on a fresh simulator profile),
   otherwise straight to the device list.

Command-line alternative (what's actually being used under the hood, and
what CI-less verification passes have used so far — see oga-p8a):

```bash
monkeyc -f monkey.jungle -d fenix7 -o bin/OrionSleep.prg -y /path/to/developer_key.der
monkeydo bin/OrionSleep.prg fenix7
```

**Simulator gotcha**: `monkeydo` talks to a single shared simulator
instance on a fixed port (5-6 digit default around 1234), same as any
other Connect IQ project you might have building at the same time — if
you get a stale/blank simulator window or it doesn't seem to pick up a
fresh build, check whether another `monkeydo`/simulator process is already
running and holding that instance, and kill it before retrying.

## Unit tests

The tests are Connect IQ `(:test)` functions, built into a separate test
binary and run in the simulator:

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")bin"
"$SDK/monkeyc" -f monkey.jungle -d fenix7 -o bin/OrionSleep-test.prg -y /path/to/developer_key.der -w --unit-test
pgrep -f "ConnectIQ.app/Contents/MacOS/simulator" || "$SDK/connectiq" &
# wait about 10 seconds for the simulator to start
perl -e 'alarm 150; exec @ARGV' "$SDK/monkeydo" bin/OrionSleep-test.prg fenix7 -t
```

A passing run ends with `PASSED (passed=20, failed=0, errors=0)`. **Read the
result from that last output line, not from the exit code**: `monkeydo -t`
has been seen to exit 1 for passing and failing runs alike. The `perl alarm`
wrapper stops a hung run after 150 seconds.

The tests write no property, so the side they expect comes from whatever
`primary_side` the simulator currently has; they pass with either value.
Four `GlanceCacheTest` tests write the two glance Storage keys
(`glance_bed`, `glance_cache`) and put back what was there in a `finally`
block. The simulator's Storage is shared between test runs and app runs, so
a test run killed half way can leave a glance bed of `B1` or `SN`: opening a
real bed in the app, or deleting the app's data in the simulator, fixes it.

A test run also starts the app class, so `getInitialView()` registers the
30-minute background event in the simulator, and the simulator may fire
that event (and print `Background: GlanceRefresh: …` lines) during a later
test run. That is expected and does not affect the result.

## What to actually click through

1. **Provisioning** (`ProvisioningView.mc`, oga-2et) — method picker (API
   key vs. phone+OTP).
   - *API key path*: if the simulator's `Application.Properties` already
     has a key set (via the phone-side settings screen — Connect IQ
     simulator lets you edit these under Settings for the running app),
     it validates automatically and skips straight to the device list.
     Otherwise it prompts for on-device entry — expect this to be painful
     to type on a round watch face; that's a known, documented UX
     trade-off (see the bead), not a bug.
   - *Phone+OTP path*: enter a phone number, triggers a real OTP text via
     the Orion API, then enter the code on-device (numeric picker, not
     stored anywhere).
   - Try an invalid key / wrong OTP code to confirm the distinct error
     messages actually differ (invalid_api_key vs invalid_code vs
     cannot_connect) rather than one generic failure.
2. **Device list** (`DeviceListView.mc`, oga-8m6) — GET `/v1/devices`. If
   your account has exactly one paired device it may auto-select and skip
   straight to control.
3. **Device control** (`DeviceControlView.mc`, oga-8m6) — per-zone power
   toggle + temperature adjust. Uses PUT
   `/v1/devices/{serial_number}/live` — note it's the device's
   **serial_number**, not an internal UUID, as the path key (a gotcha
   called out in the REST client bead if anything looks like it's hitting
   the wrong device).
4. **Multi-device-family check** (oga-p8a, already verified once) — if you
   want to re-check yourself, repeat the above on both a watch target
   (`fenix7` or `venu3`, round screen, 5-button input) and an Edge target
   (`edge840`/`edge1040`, tall rectangular screen, button-only input, no
   touch) to confirm nothing clips or assumes touch input.
5. **Primary side** (`primary_side` setting) — change the setting in the
   simulator's App Settings Editor for the running app (on a real watch,
   in the app's settings in Garmin Connect). Needs a bed with two zones.
   - Set it to `1`, then open the bed: expect "Zone B" with the second page
     dot lit, both from the device list and from the single-device
     auto-select.
   - Still on `1`, switch to Zone A, refresh with START, then change the
     temperature: the focus stays on Zone A.
   - Set it back to `0` (or clear it): expect "Zone A" on the next open.
   - Change the setting while on the device list, then open the bed: it
     opens on the new side.

## Temperature batching (oga-23f)

On the control screen a temperature press only changes the number on
screen. One PUT with the final temperature goes out about a second
(`QUIET_PERIOD_MS`, 1000 ms) after the last press. Switching zone, a power
tap, Back and leaving the view send straight away. Only one request is on
the wire at a time; "Updating…" shows only while one is.

**Counting sends.** Every update prints
`OrionClient: PUT /v1/devices/<serial>/live` and every reply prints
`OrionClient: update_live response <code>` in the simulator console. Each
request line should be followed by its response line before the next
request line. To make sends fail, turn the simulator's connection off in
its Settings menu. The app talks to the production API, so keep changes to
a degree or two.

1. **Five quick UP presses.** The number steps 0.5° on every press. Exactly
   one PUT line, printed about a second (0.8–1.5 s) after the last press.
   The status line is empty until that PUT starts.
2. **Failed send.** Connection off, five UP presses. After the send fails
   the zone shows the value from before the first press (not one step
   below the last) and a red `Error: …`. The next UP press clears the
   error at once.
3. **Zone switch** (two-zone device). Three UP presses on zone A, then
   swipe to zone B at once. B appears at once and the PUT line prints at
   the swipe, not a second later. With the connection off, swiping back
   shows A at its old value; B is unchanged.
4. **Leave at once.** Three UP presses, then Back at once. With the view
   pushed from the device list, the PUT line prints as the view hides and
   nothing fires later. On a single-device account (control view is the
   root, Back exits the app) note whether the PUT line prints and whether
   a response line follows before exit.
5. **Temperature then power.** UP twice, then SELECT within a second. One
   PUT carrying both the new temperature and the toggled power. Refresh or
   reopen: the bed has both. SELECT with nothing waiting sends one PUT at
   once, as before.
6. **Press during "Updating…".** While a PUT is in flight, press UP again.
   The number changes at once, survives the reply, and one more PUT
   follows the first response line.

START/LAP (refresh) is ignored while a temperature change is waiting or a
request is in flight; press it again after the send finishes.

## Glance and background refresh (oga-6bf)

The glance's second line comes from saved state, never from the network
(see docs/DESIGN.md, "Glance state"):

| State | Second line |
| --- | --- |
| Signed out | `Sign in required` |
| Signed in, no saved state for the glance bed | `Tap to control` |
| Primary side on | `On · 19.5°` |
| Primary side off | `Off · Tap to control` |

Saved state older than 2 hours keeps its text but is marked old: dark gray
instead of light gray on colour screens, a dashed underline (same colour) on
the black-and-white Instinct products (`instinct3solar45mm`,
`instincte40mm`, `instincte45mm`).

**Simulator menus.** The SDK guide says a background temporal event can be
triggered from the simulator's **Simulation** menu, and that scheduled
events also fire on their own. The glance is started from the simulator's
glance/widget preview for a device that has glances. The exact menu item
names were **not** confirmed when this section was written (the
verification run was headless; see the oga-6bf implementation summary):
whoever first runs these checks with the simulator window in front of them
should replace this paragraph with the real names. Known simulator issue
(SDK guide): it may also run the background service of apps tested earlier,
even when another app is the one running.

**Console lines.** Every background request prints one line and every run
prints one outcome line, prefixed `Background:` in the console. Tokens are
never printed.

- Requests: `GlanceRefresh: POST /v1/auth/refresh` (only for a phone + code
  sign-in whose token expires within 60 s) and
  `GlanceRefresh: GET /v1/devices/<serial>/live`.
- Outcomes: `GlanceRefresh: updated`;
  `GlanceRefresh: skipped: signed out`, `skipped: no glance bed`,
  `skipped: no phone connection`, `skipped: the app saved newer state`;
  `GlanceRefresh: failed: <why>` (`refresh <code>`, `live <code>`,
  `no refresh token`, `refresh reply shape`, `no zones in reply`).

**Without an Orion account**, seed Storage with a temporary local change
that you do not commit, for example a few `Application.Storage.setValue`
lines at the top of `getGlanceView()` (keys `orion_access_token`,
`orion_auth_method`, `glance_bed`, `glance_cache`; see
`source/GlanceCache.mc` for the cache format). With a fake token a
background run prints the GET line and `failed: live 401`, and changes
nothing.

**Checks.**

1. **Glance starts.** On `fenix7` and `instinct3solar45mm` (32 KB glance),
   start the glance: both lines draw, no "Symbol Not Found", no
   out-of-memory error.
2. **Each state.** Signed out: `Sign in required`. Signed in, no saved
   state: `Tap to control`. Primary side on at 19.5: `On · 19.5°`. Off:
   `Off · Tap to control`.
3. **Old state.** Seed `at` three hours back. `fenix7`: visibly dimmer than
   a fresh line. `instinct3solar45mm`: same brightness, dashed underline.
   Check that `·` and `°` draw on the Instinct, and that
   `Off · Tap to control` fits on `instinct3solar45mm`, `fenix7` and
   `edge840`.
4. **Primary side.** With both zones saved, change `primary_side` in the App
   Settings Editor: the glance shows the other side, with no request line.
5. **Nothing to do.** Signed out, trigger the event:
   `skipped: signed out`, no request line. Signed in, no glance bed:
   `skipped: no glance bed`.
6. **32 KB background products.** On `edge840` and `instinct3solar45mm`,
   trigger the event with a token and a glance bed stored: an outcome line
   and no out-of-memory error. With a real account expect the GET line and
   `updated`. Note the peak memory the simulator shows for the background
   and the glance.
7. **Connection off.** Turn the simulator's connection off (its Settings
   menu, as for the temperature batching checks) and trigger:
   `skipped: no phone connection` or a `failed` line; glance text, saved
   state and tokens unchanged.
8. **Redraw.** `fenix7`, glance on screen, a run that succeeds: the glance
   shows the new state without being touched. If it does not, the state
   still shows the next time the glance is shown (oga-6bf risk R-2).
9. **Registration.** Start the app twice:
   `Background.getTemporalEventRegisteredTime()` is a 1800-second duration
   both times.
10. **With a real account.** Open the bed, press UP twice, wait for the
    PUT, go back to the glance: the new temperature. Toggle power:
    `Off · Tap to control`. The console shows the same requests in the same
    order as before oga-6bf, and checks 1 and 5 of
    [Temperature batching](#temperature-batching-oga-23f) still pass. Sign
    out: `Sign in required`.

## Known gaps (not bugs, just not built yet)

The 3 remaining P3 stretch beads (away-mode toggle, read-only sleep
insights, schedule temperature-offset sliders) aren't implemented — the
app only does power on/off + direct temperature control today.

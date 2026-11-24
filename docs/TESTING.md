# Testing the app yourself

A small unit-test suite covers the primary side logic, the backend
settings, the Ember & Tide parsing and the control view's batching through
a fake backend (see [Unit tests](#unit-tests)). Everything else is still
verified manually, via the Connect IQ simulator or a real device (Connect IQ
apps aren't easily unit-testable the way a typical backend service is). The
README's "Build" section only shows a raw `monkeyc` compile command, not how
to actually run and click through the app; this doc covers that.

## What you need

- **Connect IQ SDK** + a developer key (`.der` file) — same ones used for
  building (see [README.md](../README.md#build)).
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

The test files:

- `source/PrimarySideTest.mc` — the primary side setting (oga-ep7).
- `source/BackendViewTest.mc` — the control view through a fake
  `BedBackend`: opening on the home side, read-only sides, one call per
  batch, the first press with no set temperature, temperature before power,
  and `OrionBackend` reading Orion live JSON (oga-2cx).
- `source/BackendConfigTest.mc` — the backend choice, the URL check and the
  set-up messages (oga-2cx).
- `source/EmberTideTest.mc` — Ember & Tide headers, who is me, snapshot
  parsing (hand-written samples), adjust and tonight bodies, the power
  action, labels, units and error texts (oga-2cx).

A passing run ends with `PASSED (passed=33, failed=0, errors=0)`. **Read the
result from that last output line, not from the exit code**: `monkeydo -t`
has been seen to exit 1 for passing and failing runs alike. The `perl alarm`
wrapper stops a hung run after 150 seconds.

The tests never write a property, so the side they expect comes from
whatever `primary_side` the simulator currently has; they pass with either
value. The backend tests call pure functions only and pass whatever the
`backend` setting is.

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

## Ember & Tide mode (oga-2cx)

With the `backend` setting on Ember & Tide (1) the app skips the Orion
sign-in and the device list and opens the control screen on a self-hosted
Ember & Tide server (see the README's "Ember & Tide (advanced)" section).
Set `backend`, `et_url` and `et_key` in the simulator's App Settings Editor
for the running app, then restart the app: a changed setting takes effect
the next time the app opens. Every request prints
`EmberTideClient: <GET|POST> <path>` and every reply
`EmberTideClient: <operation> response <code>`; the key is never printed.

None of these checks needs a server, and none should be pointed at a real
one.

1. **Orion default.** `backend` 0 (or cleared): the app opens exactly as
   before (provisioning, or the device list when signed in). With an Orion
   account, repeat checks 1, 2 and 5 of
   [Temperature batching](#temperature-batching-oga-23f): the console still
   shows `OrionClient: PUT …` lines.
2. **Bad address.** `backend` 1, `et_url` `http://example.com`, any key: the
   watch shows "Server URL must start with https://". No `EmberTideClient:`
   line. Back exits.
3. **Missing key.** `backend` 1, a `https://` address, empty key: "Set the
   server URL and key in Garmin Connect". No request line.
4. **Unreachable or wrong server.** `backend` 1, `et_url`
   `https://example.com`, `et_key` `test`: one
   `EmberTideClient: GET /api/auth/state` line, then an error screen whose
   text is readable in full inside the round screen. SELECT sends the
   request again. Check `fenix7` and `epix2pro47mm`.
5. **Longest message.** On `fenix7`, with a temporary local edit (never
   committed) that makes `EmberTideModel.errorText()` return "This device
   key can't do that. Open the app instead.", check that the load-error
   screen shows all of it, then force it as a send error and check the
   status area shows all of it too.
6. **Switch back.** With an Orion sign-in stored, set `backend` 1 and open
   the app, then set it to 0 and open again: the Orion screens come back
   without a new sign-in.

### First run against a real server

For the owner of an Ember & Tide server, with a key made as the README
describes:

1. Open the app. The title is "Ember & Tide" and the first page is your
   name, set temperature, state and "Now …°" measured temperature. Compare
   them with the Ember & Tide app; the unit is your Ember & Tide unit.
2. Press UP five times quickly. The number steps 1° (°F) or 0.5° (°C) per
   press, and about a second after the last press the console shows one
   `EmberTideClient: POST /api/people/<you>/adjust` line and its response.
3. Press SELECT. One `…/tonight` line; the label becomes "Off tonight".
   Press SELECT again: the side resumes.
4. Swipe to your partner's page and press UP: "View only", and no request
   line.
5. Note which error texts appear on the real phone (whether Garmin Connect
   passes the server's `detail` text through).

## Known gaps (not bugs, just not built yet)

The 3 remaining P3 stretch beads (away-mode toggle, read-only sleep
insights, schedule temperature-offset sliders) aren't implemented — the
app only does power on/off + direct temperature control today.

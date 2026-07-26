# Testing the app yourself

There's no automated test suite for this project (Connect IQ apps aren't
easily unit-testable the way a typical backend service is) — verification
is manual, via the Connect IQ simulator or a real device. This doc didn't
exist before; the README's "Build" section only shows a raw `monkeyc`
compile command, not how to actually run and click through the app.

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

## Known gaps (not bugs, just not built yet)

The 3 remaining P3 stretch beads (away-mode toggle, read-only sleep
insights, schedule temperature-offset sliders) aren't implemented — the
app only does power on/off + direct temperature control today.

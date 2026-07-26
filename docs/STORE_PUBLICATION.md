# Connect IQ Store Publication (oga-qiv)

Checklist and drafted listing content for submitting Orion Sleep to the
Connect IQ App Store, per the SDK's [Publishing to the Connect IQ
Store](https://developer.garmin.com/connect-iq/core-topics/publishing-to-the-connect-iq-store/)
guide. Adapted from GarminMerge's `docs/STORE_PUBLICATION.md` + `PRIVACY.md`
pattern (see [docs/DESIGN.md](DESIGN.md#store-publication)).

## Pre-flight

- [ ] **Supported products declared in `manifest.xml`** — done: `fenix7`,
      `venu3`, `edge840`, `edge1040` under `<iq:products>`. Representative
      starter set spanning both device families (watch + Edge) and both
      display types (MIP + AMOLED); expand as needed, re-verifying product
      ids against the installed SDK's `Devices/` directory since Garmin
      adds/renames devices over time.
- [ ] **App type is correct** — `watch-app` (Device App), not `widget` (see
      the comment at the top of `manifest.xml` and
      [docs/DESIGN.md](DESIGN.md#app-type-device-app-not-widget) for why:
      bed control is an explicitly-launched bedtime action, not something
      that needs to be reachable mid-activity the way GarminMerge's
      PR-review widget does).
- [ ] **Launcher icon — NOT done, blocks submission.**
      `resources/drawables/launcher_icon.png` is currently a 40×40 plain
      placeholder circle. Per-device-family icon sizes needed before
      submission (per this project's own `monkeyc` build-verification
      warnings, recorded in [docs/DESIGN.md](DESIGN.md#build-verification)):
      at minimum a 70×70 asset for `venu3` and a 35×35 asset for `edge840`
      (`monkeyc` auto-scales the current placeholder and only warns, but the
      Store submission needs real branded artwork sized correctly per
      product, not a scaled placeholder). Re-check exact per-product sizes
      against the current SDK's device reference before finalizing.
- [ ] **Permissions justified** — `Communications` only, used for Orion REST
      API calls (`Communications.makeWebRequest` to `api1.orionbed.com`) to
      fetch device/live state and send power/temperature control commands.
      No Position, Sensor, or Sensor History permissions are requested.
- [ ] **Privacy policy** — required because the app uses `Communications` to
      handle an Orion account credential (API key or phone+OTP-derived
      access/refresh token) and live bed state. See
      [PRIVACY.md](../PRIVACY.md); host it at a public URL before
      submission and link it from the store listing.

## Export

1. In VS Code with the Monkey C extension: **Monkey C: Export Project**.
2. Choose an output folder; this produces the `.iq` file bundling binaries
   for every product listed in `<iq:products>` (`fenix7`, `venu3`,
   `edge840`, `edge1040`).
3. Sign with the same developer key used for device/simulator builds
   (`-y /path/to/developer_key.der` — see [README.md](../README.md#build)).

## Submit

1. Garmin Developer site → **Submit an App**.
2. Upload the `.iq` file; Garmin validates the manifest/binaries.
3. Fill in the listing using the drafted copy below.
4. Provide the privacy policy URL (GDPR — see PRIVACY.md and the SDK's GDPR
   guidance: any app using `Communications` to handle personal data needs
   one).
5. Submit for review. Typical turnaround is 72 hours (no ANT+ profiles used,
   so no extra ANT+ certification wait applies here).

## Drafted store listing

**Short description** (≤80 chars-ish, store-dependent limit):

> Control your Orion Sleep smart mattress topper from your wrist or bars.

**Long description:**

> Orion Sleep puts control of your smart mattress topper on your Garmin
> device. See your paired beds, check each zone's power and temperature,
> and adjust them without reaching for your phone.
>
> - Device list showing all beds paired to your Orion account, with a
>   quick on/off glance per bed
> - Per-zone control: toggle power and adjust temperature in real time
> - Works across watch and Edge devices — button or touch input, whichever
>   your device supports
> - Sign in with your Orion API key, or with your phone number and a
>   one-time verification code — no typing long tokens on the bezel
>
> Configure your Orion account once, then check and adjust your bed from
> your watch face or handlebars.

**Keywords:** smart mattress, sleep, bed control, temperature, home,
climate, iot

**Screenshots needed** (not yet captured — the control UI (oga-8m6) and
multi-device-family verification (oga-p8a) need to land first; see
[docs/DESIGN.md](DESIGN.md#screens)):
- Device list view (populated with real paired beds, not empty/loading
  state)
- Device control view showing a zone's power state and temperature
- Sign-in / provisioning view (method picker: API key vs. phone+OTP)
- OTP code-entry screen
- One watch-family screenshot (round display) and one Edge-family
  screenshot (rectangular display), to show the multi-device-family layout

## Versioning

The CIQ manifest format for this SDK version does not carry an app version
field — version numbers are tracked per-upload in the Developer Portal, not
in `manifest.xml`. Increment the version there on each store submission and
keep a matching note in this file or a CHANGELOG for traceability once
publishing begins.

# Orion Garmin App — Design (oga-fsf)

Connect IQ **Device App** (not a widget, not a data field) to control an
Orion Sleep smart mattress topper from a Garmin watch or Edge bike computer.
This document captures the exploration + design work done for oga-fsf, and
the implementation beads filed from it.

## Sources used

- **Orion Sleep API contract**: `home_assistant_orion_integration` repo
  (`git@github.com:kevinklaes/home-assistant-orion-integration.git`, local
  checkout `~/Sites/home_assistant_orion_integration/mayor/rig`) —
  `openapi.yaml` (full surface), `custom_components/orion_sleep/config_flow.py`
  (real dual-auth flow), `custom_components/orion_sleep/api.py` (real HTTP
  client, request/response shapes, error handling).
- **Connect IQ project-structure precedent**: `GarminMerge` repo
  (`git@github.com:kevinklaes/GarminMerge.git`, local checkout
  `~/Sites/GarminMerge/mayor/rig`) — a real, shipping, store-track Connect IQ
  project by the same author. `manifest.xml`/`monkey.jungle`,
  `docs/TRANSPORT.md`, `docs/STORE_PUBLICATION.md`, `PRIVACY.md`, and the
  `source/` file layout (App entry, REST client, auth view, model, list/
  delegate views).

## App type: Device App, not widget

GarminMerge deliberately uses `type="widget"` on Edge because its whole
value proposition is being reachable **mid-activity** (the Apps/Device-App
menu is unreachable while an activity is recording; the swipeable
widget/glance loop is). That constraint doesn't apply here: bed control is a
bedtime action, not something a rider needs mid-ride. `manifest.xml` in this
repo therefore declares `type="watch-app"` (Device App) — explicitly
launched from the Apps menu, which better matches "open the app, control the
bed, close it" than living in the glance swipe loop. If a future bead wants a
glance-style "bed is on / off" preview, that can be added the same way
GarminMerge added `getGlanceView()` without changing the base app type.

## Multi-device-family support (watch + Edge)

The manifest targets both watch and Edge products:

| Product | Family | Display | Resolution |
|---|---|---|---|
| `fenix7` | Watch | MIP | 260×260 |
| `venu3` | Watch | AMOLED | 454×454 |
| `edge840` | Edge | LCD | 246×322 |
| `edge1040` | Edge | LCD | 282×470 |

This is a representative starter set, not exhaustive — expand `manifest.xml`
as needed. **Verified for real**: the locally installed Connect IQ SDK
9.2.0 confirms all four support the `watchApp` appType this manifest
declares (checked each product's `compiler.json` under the SDK's `Devices/`
directory), and `monkeyc` **successfully built** the scaffolding in this
repo for all four (`fenix7`, `venu3`, `edge840`, `edge1040`) — see "Build
verification" below. Re-check product ids against the SDK's `Devices/`
listing periodically; Garmin adds/renames devices over time.

Because screen shapes/resolutions vary this much (square-ish round watch
faces vs. tall rectangular Edge screens) and touch support differs by
device, all views must lay out from `dc.getWidth()`/`dc.getHeight()` at
runtime rather than fixed coordinates (`StatusView.mc` already does this),
and all input must go through `WatchUi.BehaviorDelegate`'s
`onKey`/`onSelect`/`onTap`/`onSwipe` rather than device-specific branches —
exactly the pattern GarminMerge's `PRListView`/`PRListDelegate` already use
for Edge's button+touch mix.

### Build verification

```
SDK 9.2.0, monkeyc -f monkey.jungle -d <device> -y <throwaway dev key>
fenix7:   BUILD SUCCESSFUL
venu3:    BUILD SUCCESSFUL (launcher icon scaled — see below)
edge840:  BUILD SUCCESSFUL (launcher icon scaled — see below)
edge1040: BUILD SUCCESSFUL
```

The launcher icon (`resources/drawables/launcher_icon.png`) is a **plain
placeholder circle**, 40×40 — real branded artwork per device-family icon
size (venu3 wants 70×70, edge840 wants 35×35) is store-publication work, not
scaffolding; monkeyc auto-scales in the meantime and only warns.

## Auth: dual provisioning paths (mirrors `config_flow.py`)

Orion's real API supports three sign-in paths (`config_flow.py`
`async_step_user`); this app supports the two the bead calls for:

1. **API key** (`async_step_api_key` / `api.py: get_current_user`) — paste a
   long-lived key from `app.orionsleep.com/api-keys` (format
   `os_live_<opaque>`, ~48 chars per `openapi.yaml`'s `POST /v1/api-keys`
   doc). Validated by `GET /v1/auth/me`; a 401 means invalid/revoked.
2. **Phone + OTP** (`async_step_phone` → `async_step_verify` /
   `api.py: request_auth_code` + `verify_auth_code`) — `POST /v1/auth/code`
   sends a code, `POST /v1/auth/do` (falling back to the legacy
   `/v1/auth/verify` — `api.py` tries both) verifies it and returns
   `{access_token, refresh_token, expires_at}`. Phone numbers must be
   normalized to `1XXXXXXXXXX` (`config_flow.py`'s `_PHONE_RE`); the HA
   integration does NOT support email for pure API-key-or-phone flows in the
   sense this bead asks for, so email is out of scope here (phone + API key
   only, matching the bead description exactly).

**Where each piece of auth state lives** (mirrors GarminMerge's
Storage-vs-Properties split, adapted for Orion's needs):

| Data | Where | Why |
|---|---|---|
| API key (optional convenience paste) | `Application.Properties` (`resources/settings/properties.xml`: `api_key`) | Static, user-entered via Garmin Connect Mobile's per-app settings screen — same convention as GarminMerge's `github_token` property. Painful to type on a 5-button watch; phone-side paste is much better UX. |
| Phone number (optional convenience prefill) | `Application.Properties` (`phone`) | Static, rarely changes. |
| Active access token / refresh token / expires_at (OTP flow) | `Application.Storage` | Rotates continuously; `Application.Properties` is read-only from device code, so it cannot hold anything the app itself needs to update after a refresh. |
| Active API key actually in use, auth method flag | `Application.Storage` | Set once validation succeeds, read on every launch — same `Storage.getValue`-preferred-over-`Properties` pattern as `GitHubClient.getToken()`. |
| OTP verification code | **Nowhere persisted** | Ephemeral, single-use, requested live — always entered on-device in the provisioning flow, never a property. |

The on-device provisioning view (follow-up bead) is the authoritative code
path that calls the API; the phone-side settings fields are an optional
prefill/shortcut, not a separate implementation.

## Primary side setting

A bed has two zones, A and B, and each sleeper usually only cares about their
own. The `primary_side` setting picks the zone the control view opens on.

- **Where it lives**: `Application.Properties` as `primary_side`
  (`resources/settings/properties.xml`). `0` = side A (`zone_a`), `1` = side B
  (`zone_b`); the default is `0`. Any other value counts as A.
- **Who writes it**: the user, in the app's settings in Garmin Connect. The
  app never writes it (it is a property, not `Application.Storage`).
- **Who reads it**: only `DeviceModel.primaryZoneId()`. No other file reads
  the property key. `DeviceModel.primaryZoneIndex()` maps the id to an index
  in the bed's zone list and falls back to the first zone when the primary
  zone is missing (a single-zone bed, unknown zone ids).
- **When it applies**: the control view focuses the primary zone once per
  open, on its first successful load. After that a refresh or a temperature
  change keeps whatever zone the user switched to, and a changed setting takes
  effect on the next open.
- **Reuse**: the glance (oga-6bf) uses the same helper to pick the side it
  shows; `primaryZoneId()` and `zoneIdForSide()` are annotated `(:glance)` for
  that. The glance still reads the property only through the helper.

## Token refresh and the glance's background refresh

`api.py`'s `ensure_valid_token()` is called before every authenticated
request and refreshes synchronously if the token is expired/near-expiry;
API keys skip this (long-lived, no refresh flow — a revoked key just 401s).
The app mirrors that: refresh on demand, checked immediately before each
authenticated call, with the same 60-second margin (`_token_expired`).

**Earlier decision: no Background Service.** `Toybox.Background` costs an
extra manifest permission, a second execution context with a much smaller
API surface, and store-review scrutiny for battery use, and every screen of
the app already makes a live call when it opens.

**Reversed for the glance refresh only** (Kevin, 2026-11-23, oga-6bf). The
glance shows whether the user's side of the bed is on and what it is set to
(see [Glance state](#glance-state)). A glance cannot wait on the network,
so it reads saved state, and without a background refresh that state would
only be as new as the last time the app was opened. Nothing else in the app
uses the background process.

- **Interval**: a temporal event every 30 minutes
  (`GlanceCache.REFRESH_INTERVAL_SECONDS`, 1800). `OrionSleepApp` registers
  it in `getInitialView()`, so it starts once the app has been opened after
  the update is installed; it is not registered again when the same interval
  is already registered. The glance and the background never register it.
- **Battery**: up to 48 short wake-ups a day. Each makes one request through
  the phone (`GET /v1/devices/{serial_number}/live`), two when a phone +
  code token needs refreshing first. A run makes no request when signed out,
  when there is no glance bed, or when the watch reports no phone
  connection. The event is registered on every product, including the two
  with no glance (`etrextouch`, `gpsmaph1`): the only run-time signal,
  `DeviceSettings.isGlanceModeEnabled`, is documented in terms of key
  events, and a wrong `false` would silently stop the refresh on a product
  that has a glance. The cost is the wake-ups on those two handhelds.
- **How the background gets a valid token** (`source/GlanceRefresh.mc`): it
  reads the tokens the app stored. With an API key there is nothing to
  refresh. With phone + code, if the access token expires within 60 seconds
  (`OrionSession.REFRESH_MARGIN_SECONDS`, the app's margin) it sends
  `POST /v1/auth/refresh` first and saves the new tokens with
  `OrionSession.saveOtpTokens()` (in a fixed order: method, refresh token,
  access token, expiry, so a run killed between writes leaves a working
  refresh token; an empty refresh token in a reply keeps the stored one). It
  never shows UI and never asks the user anything. On any failure (refresh
  rejected, 401/403, no network, a reply too large or the wrong shape, the
  30-second limit) it changes nothing: not the cache, not the tokens. Saving
  the tokens from a successful refresh is its only token write.
- **The app after a background refresh**: `OrionAuth.startAuthenticatedCall()`
  reloads the tokens from Storage before it checks expiry, so a view that
  stayed open across a background run uses the new tokens and never sends a
  refresh token that the background already replaced. The app and the
  background refreshing in the same few seconds is a known, accepted gap: the
  user sees the normal error and a retry works.
- **Its own small fetcher**: the background does not load `OrionClient` or
  `OrionAuth`. The rules both sides need (Storage keys, margin, base URL,
  token parser, token save) live in `source/OrionSession.mc`. Sizes from
  `monkeyc --build-stats 0`, the same on `fenix7`, `venu3`, `edge840` and
  `instinct3solar45mm`:

  | Build | Background (code + data) | Glance (code + data) |
  | --- | --- | --- |
  | Before oga-6bf | none | whole app: 18,307 + 6,359 = 24,666 bytes |
  | Now | 2,963 + 1,811 = 4,774 bytes | 4,071 + 2,109 = 6,180 bytes |
  | `OrionClient` + `OrionAuth` in the background instead | 5,774 + 2,734 = 8,508 bytes before a delegate and the cache | not measured |

  The background budget is 32 KB on 13 products (`edge540`, `edge550`,
  `edge840`, `edge850`, `edge1040`, `edge1050`, `edgeexplore2`, `edgemtb`,
  `etrextouch`, `gpsmaph1`, `instinct3solar45mm`, `instincte40mm`,
  `instincte45mm`) and 64 KB elsewhere; the glance budget is 32 KB on the
  three Instinct products. The loaded code is only part of a run: the
  parsed `/live` reply also has to fit, and its size has not been measured.
  If it does not fit, the request callback gets a negative code and the run
  fails cleanly as above.

## Glance state

What the glance shows (`source/GlanceCache.mc`, `secondLine()`):

| State | Second line |
| --- | --- |
| Signed out | `Sign in required` |
| Signed in, nothing usable saved | `Tap to control` |
| Primary side on | `On · 19.5°` (the set temperature, formatted by `DeviceModel.tempText()` exactly as on the control screen: one decimal, no conversion, no unit letter) |
| Primary side off | `Off · Tap to control` |

The primary side comes from `DeviceModel.primaryZoneId()` with the same
first-zone fallback as the control view, read each time the glance draws.

**Storage keys** (`Application.Storage`):

- `glance_bed`: the serial number of the **glance bed**, the bed last opened
  in the app. `DeviceControlView.onShow()` stores it, both when the bed is
  opened from the device list and on the single-device auto-open, so an
  account with one bed gets it the first time the app opens after sign-in.
  With several beds and none opened yet there is no glance bed: the glance
  says `Tap to control` and background runs make no request.
- `glance_cache`: one dictionary, written whole so a run killed half way
  can never leave half a cache:
  `{"bed": serial, "at": epoch seconds, "zones": [{"id", "on", "temp"}, ...]}`.
  It holds every zone the bed reports, so changing the primary side needs no
  fetch. No unit is stored. Nothing in it is specific to Orion's reply
  format, so another backend can write it (oga-19od).

**Writers**, all through `GlanceCache.write()`, which writes only when the
serial is the glance bed and the zone list is not empty:

- the control view, after each successful live load and each successful
  update, from server-confirmed values only (never a temperature still
  waiting to be sent, never after a failed update);
- the device list, when it loads live state for the glance bed (other beds
  in the list are not written);
- the background refresh, every 30 minutes.

**Reader**: only the glance. A cache for a bed other than the glance bed, or
with no zones, counts as nothing saved. Switching to another bed therefore
shows `Tap to control` until that bed's state is saved.

**Old state**: a cache more than 2 hours old
(`GlanceCache.STALE_AFTER_SECONDS`) keeps its text but is marked old. On
screens with a gray the line is drawn in dark gray instead of light gray. On
the black-and-white Instinct products (`instinct3solar45mm`, `instincte40mm`,
`instincte45mm`) it keeps its colour and gets a dashed underline, which adds
no width; `monkey.jungle` picks one of the two `canDim()` versions per
product with `excludeAnnotations`. A fetch time in the future (the watch
clock was changed) counts as fresh.

**Newer wins**: a background run passes the second it started, and
`write()` keeps a cache fetched at or after that second. A change the user
made in the app while the run waited for its reply is not replaced by the
older reading.

**Redraw**: a run that changed the cache exits with `Background.exit(true)`;
`OrionSleepApp.onBackgroundData()` only calls `WatchUi.requestUpdate()`
(the state is already in Storage). Writes by the app need no redraw: the
glance is not on screen while the app is open.

**Sign-out** (`OrionAuth.clearStoredToken()`, which every sign-out path
uses) deletes both keys along with the tokens.

## Canonical control endpoints (from `api.py` / `openapi.yaml`)

- `GET /v1/devices` — list paired toppers (id, `serial_number`, name, zones,
  `temperature_range`, `temperature_scale`).
- `GET /v1/devices/{serial_number}/live` — current zone on/off + temp.
  **Path uses `serial_number`, not the device's UUID `id`** — using the UUID
  returns `403`. This is the single easiest mistake to make porting `api.py`
  to Monkey C; call it out loudly in the REST client bead.
- `PUT /v1/devices/{serial_number}/live` (`update_live_device_zones`) — the
  canonical bulk power/temp control primitive: `{"zones": [{"id": "zone_a",
  "on": true, "temp": 20.5}, ...]}`.
- `PUT /v1/devices/{serial_number}/live/zones/{zoneId}` — single-zone
  variant, useful for one zone's power toggle without resending the other.

These two endpoints are the MVP: **device list + per-zone power on/off and
temperature**, per the bead's "at minimum" instruction.

### Explicitly deferred (not MVP, filed as lower-priority follow-ups)

- **Away mode** (`POST /v1/sleep-configurations/user-away`) — presence
  override that also powers the mattress down.
- **Sleep schedule / temperature-offset sliders**
  (`PUT /v1/sleep-schedules`) — the HA integration's app-style -10…+10
  offset sliders, mapped through the device's non-linear
  `temperature_scale.relative` lookup table.
- **Sleep insights** (`GET /v2/insights`, `GET /v3/insights`) — read-only
  sleep score / HRV / trend display.

None of these are needed for "control the bed from your wrist/handlebars";
they're genuinely separable features the bead flagged as "worth exposing"
during design, not core control.

## Screens (follow-up beads implement these; scaffolding has only a
placeholder `StatusView`)

1. **Provisioning/auth view** — method picker (API key / phone+OTP) →
   API-key entry-or-detected-from-Properties, or phone entry (prefillable
   from Properties) → on-device OTP code entry → success/error, modeled
   directly on `config_flow.py`'s state machine and GarminMerge's
   `OAuthView`/`OAuthDelegate` structure (state field + `onUpdate` rendering
   per state + `BehaviorDelegate` for retry/cancel/confirm).
2. **Device list view** — one row per paired topper (name, model, quick
   on/off glyph), `GET /v1/devices`. If exactly one device, this bead's
   control-UI implementer may choose to skip straight to device control
   (still list-view-shaped code, just auto-selecting index 0) — a UX call,
   not a hard requirement here.
3. **Device control view** — per zone: power toggle + temperature
   (+/- adjust via UP/DOWN or touch, matching each device's actual input
   affordances), `GET`/`PUT .../live`. Confirmation before a destructive
   power-off is optional (GarminMerge requires confirmation for merge/
   request-changes since those are hard-to-undo GitHub actions; toggling a
   bed on/off is not, so a confirmation step is not required by this
   design, but Menu-based settings like GarminMerge's auth menu are a
   reasonable place for "sign out"/"re-authenticate").

## Store publication

Same shape as GarminMerge's `docs/STORE_PUBLICATION.md` + `PRIVACY.md`:
two permissions: `Communications` (`makeWebRequest` to the Orion REST API)
and, since oga-6bf, `Background` (the glance's 30-minute refresh, see
[above](#token-refresh-and-the-glances-background-refresh)); a privacy
policy is required
because the app handles account credentials (API key/OTP token) and bed
state. See [docs/STORE_PUBLICATION.md](STORE_PUBLICATION.md) (pre-flight
checklist + drafted listing copy) and [PRIVACY.md](../PRIVACY.md) (privacy
policy), drafted in oga-qiv now that the control UI (oga-8m6) is real.
Screenshots still block on multi-device-family verification (oga-p8a).

## Implementation beads filed from this design

See the bead list recorded on oga-fsf's notes/design fields and the beads
themselves (`oga-` prefix) for the concrete, decomposed follow-up work:
REST client module, on-device storage/token handling, provisioning/auth UI,
device list + control UI, multi-device-family testing, store-publication
prep, and the three explicitly-deferred stretch features (away mode,
schedule offsets, insights display).

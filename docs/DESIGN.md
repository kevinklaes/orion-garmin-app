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

## Token refresh vs. Background Service

`api.py`'s `ensure_valid_token()` is called before every authenticated
request and refreshes synchronously if the token is expired/near-expiry;
API keys skip this (long-lived, no refresh flow — a revoked key just 401s).
Connect IQ's `Toybox.Background` API exists for periodic low-power sync
(temporal/geofence/service-triggered), but adopting it here would mean an
extra manifest permission, a second execution context with a much smaller
API surface, and store-review scrutiny for battery impact — for a "check
bed status, maybe flip it on" app, none of that buys anything a user will
notice. **Decision: no Background Service.** Mirror `api.py` exactly:
refresh-on-demand, checked immediately before each authenticated call,
using the same margin-based expiry check (`_token_expired`). Re-auth-on-
launch is sufficient because every screen in this app already makes a live
network call when opened (there is no passive/ambient mode to keep fresh).

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
`Communications` is the only permission needed (already justified —
`makeWebRequest` to the Orion REST API); a privacy policy is required
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

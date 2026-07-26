# orion-garmin-app

Connect IQ **Device App** (not a widget, not a data field) to control an
[Orion Sleep](https://www.orionsleep.com/) smart mattress topper — turn it
on/off and set zone temperature — from a Garmin watch or Edge bike computer.

## Status

Exploration + design done (oga-fsf); scaffolding only so far:

- `manifest.xml` / `monkey.jungle` — Device App (`type="watch-app"`) targeting
  both watch (`fenix7`, `venu3`) and Edge (`edge840`, `edge1040`) product
  families. Verified building clean with Connect IQ SDK 9.2.0 for all four.
- `source/OrionSleepApp.mc` + `source/StatusView.mc` — app entry point and a
  placeholder screen only; real provisioning and device-control screens are
  follow-up beads (`oga-` prefix — see `bd ready`/`bd list`).
- `resources/settings/` — `api_key` and `phone` fields (phone-side settings
  convenience; the actual OTP verification code is always entered on-device,
  never stored as a static property).

See [docs/DESIGN.md](docs/DESIGN.md) for the full design: auth flow (API key
or phone+OTP, mirroring the sibling `home_assistant_orion_integration`
repo's `config_flow.py`), app-type reasoning, multi-device-family notes,
on-device storage plan, and the canonical `/v1/devices/{serial}/live`
control endpoints.

## Build

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
and a developer key.

```bash
monkeyc \
  -f monkey.jungle \
  -d fenix7 \
  -o bin/OrionSleep.prg \
  -y /path/to/developer_key.der
```

Or use the Monkey C VS Code extension: **Build for Device** → pick a target
from `manifest.xml`'s `<iq:products>`.

## Project layout

```
manifest.xml           # Device App, watch + Edge products, Communications permission
monkey.jungle
source/
  OrionSleepApp.mc      # App entry, getInitialView (placeholder StatusView for now)
  StatusView.mc         # Placeholder screen — real screens are follow-up beads
resources/
  strings/ strings.xml
  drawables/            # Placeholder launcher icon — replace before store submission
  settings/ properties.xml + settings.xml   # api_key / phone convenience fields
docs/
  DESIGN.md             # Full design doc from oga-fsf
```

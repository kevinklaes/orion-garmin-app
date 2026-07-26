# orion-garmin-app

Connect IQ **Device App** (not a widget, not a data field) to control an
[Orion Sleep](https://www.orionsleep.com/) smart mattress topper — turn it
on/off and set zone temperature — from a Garmin watch or Edge bike computer.

## Status

Core app complete: provisioning (API key or phone+OTP), device list, and
device control (power/temperature) all implemented and verified across
both watch and Edge device families. Remaining work is 3 optional stretch
features (away-mode toggle, sleep insights display, schedule temperature
-offset sliders — see `bd list`) and store submission
([docs/STORE_PUBLICATION.md](docs/STORE_PUBLICATION.md)).

- `manifest.xml` / `monkey.jungle` — Device App (`type="watch-app"`) targeting
  both watch (`fenix7`, `venu3`) and Edge (`edge840`, `edge1040`) product
  families.
- `source/OrionSleepApp.mc` — app entry point, routes to provisioning or
  device list based on `OrionAuth.hasStoredToken()`.
- `source/ProvisioningView.mc`, `source/DeviceListView.mc`,
  `source/DeviceControlView.mc` — the three real screens.
- `source/OrionClient.mc` — REST client against the live Orion Sleep API.
- `source/OrionAuth.mc` — on-device token storage + refresh.
- `resources/settings/` — `api_key` and `phone` fields (phone-side settings
  convenience; the actual OTP verification code is always entered on-device,
  never stored as a static property).

See [docs/DESIGN.md](docs/DESIGN.md) for the full design and
[docs/TESTING.md](docs/TESTING.md) for how to actually run and click
through the app yourself in the simulator.

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

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
- `source/BedBackend.mc` — the backend interface the control view talks to;
  `source/OrionBackend.mc` puts the Orion cloud behind it.
- `source/BackendConfig.mc` — reads the backend, Ember & Tide address and key
  settings and checks the address.
- `source/EmberTideModel.mc`, `source/EmberTideClient.mc` — the Ember & Tide
  backend: pure parsing and request building, and the requests themselves.
- `source/MessageView.mc` — the setup message screen and the wrapped message
  text.
- `source/BackendConfigTest.mc`, `source/EmberTideTest.mc`,
  `source/BackendViewTest.mc` — unit tests for the above.
- `resources/settings/` — `api_key` and `phone` fields (phone-side settings
  convenience; the actual OTP verification code is always entered on-device,
  never stored as a static property), plus `primary_side`, the side of the
  bed (A or B) the app opens on, and the Ember & Tide `backend`, `et_url`
  and `et_key` settings.

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

Builds are local only: there is no CI build. Build and upload to the Connect IQ
store from your own machine.

## Ember & Tide (advanced)

If your bed runs on a self-hosted Ember & Tide server instead of the Orion
cloud, the app can talk to that server. Orion cloud stays the default:
unless you choose Ember & Tide, nothing changes and your Orion sign-in is
kept. Switching back to Orion later does not need a new sign-in.

### Settings

In Garmin Connect on the phone, open the app's settings and find the
**Advanced** group:

| Setting | What to enter |
| --- | --- |
| Server | `Ember & Tide (advanced)`. Leave it on `Orion cloud` otherwise. |
| Ember & Tide address | Your server's address, starting with `https://`, for example `https://bed.example.com`. A path is kept (`https://example.com/bed` works). Spaces and trailing slashes are removed. |
| Ember & Tide key | A key for your own side of the bed (see below). It is a password field. |

A change takes effect the next time you open the app.

### Making the key

The watch needs a key that acts as **you**: a sleeper key tied to your own
person. The Ember & Tide web app cannot make one yet. Its "Full control" keys
have no person, and the watch refuses them with "This key has no side of the
bed". A watch device key can't be made from the web either.

Until that changes, make the key with this request. Open your Ember & Tide
page in a browser, signed in as the owner, open the browser console, and run
it once:

```js
const me = (await (await fetch("/api/auth/state")).json()).me.person;
const r = await fetch("/api/auth/tokens", {
  method: "POST",
  headers: {"Content-Type": "application/json", "X-Embertide": "1"},
  body: JSON.stringify({name: "Garmin watch", role: "sleeper", person: me}),
});
console.log((await r.json()).token);
```

It prints the key (it starts with `et_`). Paste it into the **Ember & Tide
key** setting. Treat it like a password.

This request was written from the Ember & Tide server source at commit
`c46accc`. It has not been run against a real server.

For your partner's watch, the owner runs the same request with the partner's
person id in `person` instead of `me`.

**Why not an owner key?** An owner key can change everything on the server.
That is too much to keep on a watch. A sleeper key can only read the bed and
change its own person's side.

### What the server needs

- **HTTPS with a publicly trusted certificate, reachable from the phone.**
  The watch does not talk to the server itself: Garmin Connect on the phone
  relays every request. A self-signed or private-CA certificate is refused,
  and plain `http://` is not supported, even at home.
- **Away from home** that means a public HTTPS address.
- **No login page in front of it.** A Cloudflare Access login page (or any
  other sign-in page) blocks the watch. A Cloudflare Access service-token
  header would get through, but the app does not support one.

### What the watch does

- It opens on **your** side of the bed. The primary-side setting is not used.
- **UP / DOWN** set your temperature for tonight. Quick presses are sent as
  one change about a second after the last press. With no set temperature
  yet, the first press starts from the measured temperature; a press on an
  idle side turns the bed on by hand until the schedule starts.
- **SELECT** turns your side off for tonight, or back on if you turned it
  off.
- **Swipe** to see your partner's side. It is view only: nothing you press
  there changes it.
- Temperatures are shown in your Ember & Tide unit: whole degrees in
  Fahrenheit, half degrees in Celsius.

### Messages on the watch

| Message | What it means / what to do |
| --- | --- |
| Set the server URL and key in Garmin Connect | The address or the key setting is empty. Fill in both. |
| Server URL must start with https:// | The address is not `https://…`. Plain `http://` and addresses without a scheme are not accepted. |
| Can't reach your server | The request did not get through. The phone is not connected, the address is wrong, the certificate is not publicly trusted, or a login page is answering instead of the server. |
| Key not accepted, make a new one | The server refused the key (unknown, revoked, or a view-only account). Make a new key as above. |
| This device key can't do that. Open the app instead. | The server's own text: the key is a device key that may not do this. Use a sleeper key as above. |
| This key has no side of the bed | The key is not tied to a person (for example a "Full control" key). Make a key with your `person`. |
| Your side is not on this bed | The key's person is not in the server's bed state. Check the person the key was made for. |
| Unexpected reply from your server | The server answered with something the app could not read. Check that the address points at Ember & Tide. |
| Reply too large for this watch | The server's reply did not fit in the watch's memory. Nothing to fix on the watch; tell the developer. |
| Sent. Reply too large to read. | Your change was sent and the server took it, but its reply was too large to show. Reopen the app to see the result. |
| View only | You pressed a button on your partner's side. |
| No temperature to change yet | Your side has no set or measured temperature, so there is nothing to start from. |
| Side is off. Temperature not set. | The server ignored the change because your side is off for now (out of bed, night done, away or missed). |
| Any other text, or `HTTP <code>` | The server refused the request and said why (for example a side lent to a guest, or a leak hold). Fix it in the Ember & Tide app. |

### Known limits

- The glance (the small summary in the watch's widget loop) still shows the
  Orion text in Ember & Tide mode. That is follow-up work (`oga-19od`).
- No hot or cold flash.
- Turning off after the night has ended applies to the **next** night, and
  the watch cannot show that: the label goes back to "Idle". In the wake phase
  turning off ends the night.

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

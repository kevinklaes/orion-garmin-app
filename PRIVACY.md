# Privacy Policy — Orion Sleep

Orion Sleep is a Connect IQ Device App for Garmin watches and Edge bike
computers that lets you view and control an Orion Sleep smart mattress
topper (power on/off, temperature) paired to your Orion account. This
document describes what data the app handles, and is intended to be hosted
at a public URL and linked from the Connect IQ Store listing (see
[docs/STORE_PUBLICATION.md](docs/STORE_PUBLICATION.md)).

This is a template drafted from the current implementation. Before
publishing, host it at a stable URL and fill in a real owner/contact.

## What data the app handles

| Data | Source | Stored where | Sent to |
|------|--------|---------------|---------|
| Orion API key | You paste it in device settings, or enter it on-device during sign-in | `Application.Storage` once validated (optional convenience copy in `Application.Properties` if entered via Garmin Connect Mobile settings) on-device | Orion's REST API (`api1.orionbed.com`), as an `Authorization: Bearer` credential on every request |
| Phone number | You enter it in device settings, or on-device during sign-in | `Application.Properties` on-device (convenience prefill only) | Orion's REST API, to request a one-time verification code |
| OTP verification code | You enter it on-device, once, per sign-in | Never persisted — used once to complete sign-in, then discarded | Orion's REST API, to exchange for an access/refresh token |
| Access token / refresh token (phone+OTP sign-in) | Returned by Orion's REST API after OTP verification | `Application.Storage` on-device; refreshed automatically before use when near expiry | Orion's REST API, as an `Authorization: Bearer` credential on every request |
| Live bed state (device list, per-zone power/temperature) | Fetched live from Orion's REST API | Held in memory on-device for display; not persisted | Not sent anywhere further — this is data *received* from Orion for display and control |

No data is sent to the app developer or any third party other than Orion's
own REST API. There is no analytics, crash reporting, or tracking SDK in
this app.

## Your controls

- **Sign out**: the app's MENU → sign-out option clears the stored access
  token, refresh token, expiry, and auth-method flag from
  `Application.Storage` on the device.
- **Revoke access**: revoking or regenerating your API key at
  `app.orionsleep.com/api-keys` invalidates it immediately, independent of
  on-device sign-out. For phone+OTP sign-in, on-device sign-out is the
  primary control since the access/refresh token pair is scoped to that
  sign-in session.
- **Uninstall**: uninstalling the app from the device (via Garmin Connect
  Mobile / Connect IQ Store) removes all locally stored settings and
  tokens.

## GDPR

Per Garmin's Connect IQ SDK guidance, apps that use the `Communications`
permission to handle personal data (here: your Orion account credential and
live bed state) are responsible for their own compliance with applicable
data protection law, including the GDPR. This app minimizes that surface
by:

- Never persisting live bed state — it's fetched live and held only in
  memory.
- Never sending your credential or bed state anywhere except Orion's own
  REST API.
- Never persisting the OTP verification code — it's ephemeral, entered
  once, and discarded after use.

If you have questions about this policy, contact: `<fill in before
publishing>`.

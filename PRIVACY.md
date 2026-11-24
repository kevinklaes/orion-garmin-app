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
| Primary side preference (bed side A or B the app opens on) | You choose it in the app's settings in Garmin Connect | `Application.Properties` on-device | Not sent anywhere by this app — it only decides which side of the bed the watch shows first |
| Live bed state shown in the app (device list, per-zone power/temperature) | Fetched live from Orion's REST API | Held in memory on-device while a screen shows it | Not sent anywhere further — this is data *received* from Orion for display and control |
| Last known bed state for the glance: each side's on/off state and set temperature for one bed (the one last opened in the app), that bed's serial number, and the time it was fetched | Saved by the app when it loads or changes the bed's state, and by the background refresh | `Application.Storage` on-device | Not sent anywhere — only the glance reads it |

While you are signed in, the app also contacts Orion's REST API in the
background about every 30 minutes (through your phone's connection) to
refresh the last known bed state for the glance. Each refresh reads the
state of the one bed last opened in the app, and refreshes the sign-in
token first when it is about to expire. Nothing is fetched while you are
signed out or before a bed has been opened.

No data is sent to the app developer or any third party other than Orion's
own REST API. There is no analytics, crash reporting, or tracking SDK in
this app.

## Your controls

- **Sign out**: the app's MENU → sign-out option clears the stored access
  token, refresh token, expiry, and auth-method flag from
  `Application.Storage` on the device, along with the stored bed state and
  bed serial number. Background refreshes stop making requests until you
  sign in again.
- **Revoke access**: revoking or regenerating your API key at
  `app.orionsleep.com/api-keys` invalidates it immediately, independent of
  on-device sign-out. For phone+OTP sign-in, on-device sign-out is the
  primary control since the access/refresh token pair is scoped to that
  sign-in session.
- **Uninstall**: uninstalling the app from the device (via Garmin Connect
  Mobile / Connect IQ Store) removes all locally stored settings, tokens
  and bed state.

## GDPR

Per Garmin's Connect IQ SDK guidance, apps that use the `Communications`
permission to handle personal data (here: your Orion account credential and
live bed state) are responsible for their own compliance with applicable
data protection law, including the GDPR. This app minimizes that surface
by:

- Storing only the minimum bed state the glance needs: each side's on/off
  state and set temperature for one bed, that bed's serial number and the
  fetch time, on the watch only. Sign-out and uninstall remove it.
- Never sending your credential or bed state anywhere except Orion's own
  REST API.
- Never persisting the OTP verification code — it's ephemeral, entered
  once, and discarded after use.

If you have questions about this policy, contact: `<fill in before
publishing>`.

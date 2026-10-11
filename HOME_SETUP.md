# HomeControl for Guy

A status-first Garmin Home Assistant widget, adapted for Enduro 3. This is a watch app, not a replacement for the Home Assistant mobile dashboard.

## Daily use

- Opens on three selectable groups: **Doors**, **Lights**, **Fans**, each showing current status and refresh age.
- Light home screen by default; **Dark home screen** in Connect IQ settings switches it to dark.
- Tap a group to open it. With buttons, Up/Down selects a group and Select opens it. **Lock all** or **Turn all off** appears first; scroll through individual devices. Back returns to the groups.
- Menu/long press opens refresh, settings and legacy views. The separate Home status menu item is removed.
- Unknown, unavailable and moving states are shown explicitly. A cached state is never a guarantee of current home status.
- The watch glance reads cached data only, clearly labelled. Open the widget and refresh for current status.

Counts refer to the entities imported into the Garmin group. If you import a Home Assistant light-group entity, it counts as one entity rather than each physical bulb. Import individual entities for per-device counts and availability. Door status covers only the imported lock entities; it does not establish whether the doors are physically closed.

## Home Assistant setup

Create a legacy Home Assistant `group` containing the locks, lights and fans you want the watch to show. For example, in `configuration.yaml` (replace these example IDs with yours; merge with any existing `group:` section):

```yaml
group:
  garmin:
    name: Garmin
    entities:
      - lock.front_door
      - light.living_room
      - light.kitchen
      - fan.living_room
```

Set the widget's **Group** to `garmin` or `group.garmin`. After signing in, open **Settings → Refresh entities** to import it. Use **Refresh status** to read existing entities again. Add entities in HA and re-import to change membership. No credentials or real entity IDs are bundled in this repository.

Each **Turn all off** action sends explicit `turn_off` commands sequentially to imported devices in that group only, even if cached states say off or unavailable. **Lock all** sends `lock` commands to imported locks only; it never bulk-unlocks. It excludes externally configured shortcuts, switches, locks, covers, scripts and automations. The operation stops on the first service failure; earlier devices may already have turned off, and remaining devices may still be on. It reads states back afterward, rather than treating HTTP success as proof of a physical state change.

## Sign-in and credential handling

Prefer the existing phone-mediated Home Assistant OAuth flow. Home Assistant performs login and any configured MFA; the watch never collects your password. Set **Host** to the HTTPS origin reachable by your phone, without paths or query strings. The same address is used for login and API calls.

Changes in this fork:

- A fresh cryptographically random OAuth `state` must match the phone callback.
- All requests waiting for token refresh are completed; callbacks added during completion wait for the next cycle.
- Logout clears OAuth storage and a configured long-lived-token property.
- Saved credentials are bound to the HA address. Changing the address clears credentials and imported entities. Enter a token again in a subsequent settings update if using that mode.
- Pending operations are cancelled on logout/account changes; late token responses cannot repopulate a new session.
- A rejected long-lived token is cleared; rejected OAuth access tokens can refresh on a subsequent request.
- Additional headers reload when settings change, cannot override Authorization, and null settings are handled.
- Token endpoint bodies are not logged.

Garmin app storage and settings are persistent storage, not an encrypted credential vault. Logout is local: revoke the watch's refresh token/long-lived token in your Home Assistant profile when needed, particularly if the watch is lost. The first run with previously unbound OAuth credentials requires signing in again. OAuth state/callback and real phone connectivity still require an on-device check with Garmin Connect Mobile.

## Build and install

The fork has a distinct application ID so it can coexist with upstream HassControl. The inherited device manifest remains available for local builds; the CI job specifically targets Enduro 3.

Use Garmin Connect IQ SDK 9.2.0 (or newer compatible SDK) and install device definitions using Garmin's SDK Manager. Generate your own developer signing key, then from `widget/`:

```sh
monkeyc -y /path/to/developer_key.der -f monkey.jungle -d enduro3 -w -o ../build/hasscontrol-enduro3.prg
monkeyc -y /path/to/developer_key.der -f monkey.jungle -d enduro3 -t -w -o ../build/hasscontrol-tests.prg
# With the Connect IQ simulator running:
monkeydo ../build/hasscontrol-tests.prg enduro3 -t
```

Create the `build` directory first. Copy the app PRG to `GARMIN/APPS` on the watch over USB to sideload. CI uploads an Enduro 3 PRG as an Actions artifact, using a temporary development key; keep your own stable signing key for ongoing personal builds. No private key is committed. CI inherits upstream's third-party device-definition mirror (`hatl.at`); local builds can use official SDK Manager downloads.

Regression tests cover domain identification, unavailable states, transitional lock states, token callback draining/reentrancy, and OAuth login correlation. CI compiles the tests; it does not execute the simulator suite.

## On-device acceptance check

1. Sign in on the paired phone, import your group, and compare status with HA.
2. Toggle a light/fan; confirm the widget reads the actual returned state.
3. Test a lock changing state; it must not immediately claim locked on command acceptance.
4. Use Lights & fans off; verify group membership and that switches/locks are unaffected.
5. Disconnect the phone or make an entity unavailable; verify failed/cached/unknown indicators.
6. Logout, relaunch, and confirm the old token is not reused. Change HA address and confirm re-login/import is required.
7. Verify light/dark appearance, tap, Select and Menu on Enduro 3.

# HomeControl for Garmin

A status-first Home Assistant widget for Garmin watches, adapted from [wroblisko/hasscontrol](https://github.com/wroblisko/hasscontrol). This fork is developed and tested on **Enduro 3**.

The default screen shows **Doors, Lights and Fans**. Open a group to use its bulk action first, then scroll through individual devices. The interface is deliberately simple for a watch screen, with light and dark home-screen options.

## Daily use

| Group | Summary | First control |
| --- | --- | --- |
| Doors | Locked, unlocked and unknown lock states | **Lock all** |
| Lights | Number on and number unknown | **Turn all off** |
| Fans | Number on and number unknown | **Turn all off** |

- **Tap a group**, or use **Up/Down → Select**, to open it.
- The first card is the group action. Scroll to individual devices and tap/press Select to control them.
- **Back** returns to the groups. **Menu/long press** opens refresh, settings and the legacy entity/scene views.
- **Refresh status** reads the devices already imported. **Settings → Refresh entities** updates group membership from Home Assistant.
- **Settings → Start View → Groups** restores the default view if you previously selected Entities or Scenes.

Bulk actions apply only to imported devices of that group’s type. Lights and fans receive explicit `turn_off` commands; locks receive `lock` commands. There is no bulk-unlock action or combined all-off menu item. Commands run sequentially and stop at the first failure, so an action can be partially completed. The widget reads states back afterward.

Door status represents **lock state**, not whether a door is physically closed. Counts refer to imported entities: a Home Assistant light-group entity counts as one, regardless of how many bulbs it contains. Import individual devices for individual controls and counts.

## Install this fork

The upstream Connect IQ Store listing installs upstream HassControl, **not this version**. This fork has a separate application ID and can coexist with it.

1. Open [GitHub Actions](https://github.com/GL-C/hasscontrol/actions/workflows/ci.yml) and choose a successful **Enduro 3 build**.
2. Download the **hasscontrol-enduro3** artifact and extract the ZIP.
3. Connect your Enduro 3 to your Windows PC by USB and copy `hasscontrol-enduro3.prg` into **GARMIN/APPS** on the watch.
4. Disconnect the watch and open HomeControl.

GitHub may require you to sign in to download artifacts. CI artifacts use a temporary development signing key; use your own stable key for ongoing personal builds. Other inherited device targets remain in the manifest, but this fork’s CI and on-device checks target Enduro 3.

## Connect to Home Assistant

You need a paired phone with Garmin Connect running and an HTTPS Home Assistant address that the phone can reach, with a trusted certificate. Network requests depend on that connection.

Configure the widget’s app settings through Garmin Connect/Connect IQ where available. For a personal sideload build, defaults can also be set in `widget/resources/properties.xml` before compiling; keep credentials out of committed source.

1. Set **Host** to your Home Assistant HTTPS origin, for example `https://ha.example.com`, without a path or query string.
2. Set **Group** to `garmin` or `group.garmin` for the example below.
3. Open **Menu → Login** on the watch and complete the Home Assistant sign-in on your paired phone. Opening a group while signed out also starts login.
4. Open **Settings → Refresh entities** to import the group.

### Create the import group

The widget imports a legacy Home Assistant `group` with an `entity_id` member list. Use YAML rather than a domain-specific light/fan group helper.

If `configuration.yaml` already contains `group: !include groups.yaml`, put this in `groups.yaml`:

```yaml
garmin:
  name: Garmin
  entities:
    - lock.front_door
    - light.living_room
    - light.kitchen
    - fan.living_room
```

Otherwise, add it under a `group:` key in `configuration.yaml`, merging with any existing group configuration:

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

Replace the example IDs with your own, reload groups or restart Home Assistant, then import again on the watch. See Home Assistant’s [legacy group documentation](https://www.home-assistant.io/integrations/group/#old-style-groups).

### Settings

| Setting | Purpose |
| --- | --- |
| Host | HTTPS origin used for login and API requests |
| Group | Home Assistant group used to import devices |
| Dark home screen | Off gives a light home screen; on gives dark |
| Refresh on show | Refresh states when opening the widget; uses more network and battery |
| Long-lived access token | Optional alternative to phone-mediated OAuth login |
| Scenes | Optional scene shortcuts, e.g. `movie=Movie,good_bye=Good Bye` |
| Close App after successful action | Close after supported successful individual actions |
| Auto-close after inactivity | Timeout in seconds; `0` disables it, maximum `300` |
| Entity ID to report battery level | Optional battery entity name, without `sensor.`; empty disables reporting |
| Additional HTTP(S) Header — Key/Value | Optional proxy header; cannot override Authorization |

## Authentication

Phone-mediated Home Assistant **OAuth is the preferred flow**. Home Assistant handles your password and configured MFA; the watch stores tokens rather than collecting your password. A Home Assistant long-lived access token can be configured instead.

This fork validates OAuth callbacks with a fresh random `state`, handles queued token-refresh callbacks, binds stored credentials to the configured host, and cancels pending work on logout/account changes. Changing Host clears credentials and imported devices. If using a long-lived token, save the new host first, then enter the token in a subsequent settings update.

**Settings → Logout** clears locally stored OAuth credentials and the configured long-lived-token setting. A rejected long-lived token is also cleared. Local logout does not revoke tokens at Home Assistant: revoke them in your HA profile when necessary. Garmin settings/storage are persistent storage, not an encrypted credential vault. Token endpoint bodies are not logged.

See [HOME_SETUP.md](HOME_SETUP.md) for implementation details and on-device checks.

## Status and troubleshooting

The home screen shows refresh age and identifies failed refreshes as cached data. The glance uses cached data only. Unavailable or transitional devices appear as unknown rather than being counted as safely off or locked.

| Symptom | What to check |
| --- | --- |
| **Not configured** | Authenticate, check Group, then use **Settings → Refresh entities**. That category may have no imported devices. |
| **Failed to refresh / cached status** | Check the paired phone, Garmin Connect and reachability of the HA address, then use **Refresh status**. Intermittent refresh failures are still being investigated through on-device testing. |
| **Refreshing status — Try again shortly** | A refresh or bulk action is already running; retry when it finishes. |
| **Check settings, invalid url** | Host must be an HTTPS origin without paths or query strings. |
| Certificate/network error | Use a trusted HTTPS certificate; self-signed certificates are not supported by this setup. |
| Missing devices | Check the group’s member IDs and supported entity types, reload HA groups and re-import. |
| Old state after another device changes it | Use **Refresh status**; the widget does not subscribe to live HA updates. |
| Sign-in required after changing Host | Expected: credentials and imports are bound to the previous address. Sign in and import again. |

A displayed cached state is not proof of current physical state. A successful service request is also not proof that a device has finished changing state.

## Additional entity support

The legacy **Entities**, **Scenes** and **Entities&Scenes** views remain available from the menu.

| Entity type | Supported action/display |
| --- | --- |
| `light`, `fan`, `switch`, `input_boolean`, `automation` | On/off; no brightness, colour or fan-speed control |
| `lock` | Lock/unlock individually; lock-only bulk action |
| `cover`, `valve` | Open/close |
| `scene`, `script` | Execute |
| `button`, `input_button` | Press |
| `binary_sensor` | Basic state display |
| `sensor` | Value display; icons depend on sensor type |

## Build and validation

Install the Garmin Connect IQ SDK **9.2.0** and Enduro 3 device definitions using SDK Manager. Generate your own developer signing key. From the repository root, with the SDK tools on your PATH:

```sh
mkdir -p build
python3 scripts/check_menu_constructors.py
cd widget
monkeyc -y /path/to/developer_key.der -f monkey.jungle -d enduro3 -w -o ../build/hasscontrol-enduro3.prg
monkeyc -y /path/to/developer_key.der -f monkey.jungle -d enduro3 -t -w -o ../build/hasscontrol-tests.prg
# With the Connect IQ simulator running:
monkeydo ../build/hasscontrol-tests.prg enduro3 -t
```

The directory-creation example uses a POSIX shell; on Windows, create `build` in Explorer or PowerShell and use your SDK/key paths for the compile commands.

CI checks menu constructor arguments, compiles the app and regression tests, and uploads the Enduro 3 app. **CI does not execute the simulator tests.** Its device-definition download uses the inherited `hatl.at` mirror; local builds can use official SDK Manager downloads.

Regression coverage includes domain identification, unknown/transitional states, group action targets, navigation offsets, OAuth callback correlation and token-refresh callback handling. See [VALIDATION.md](VALIDATION.md) for validation notes. Real phone connectivity, login and device behaviour still require watch testing.

## Upstream and licence

Based on [wroblisko/hasscontrol](https://github.com/wroblisko/hasscontrol), retaining its Home Assistant integration and legacy controls. See [LICENSE.md](LICENSE.md) for the licence.

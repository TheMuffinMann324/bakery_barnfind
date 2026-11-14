<h1 align="center">Bakery Barn Find</h1>

<p align="center"><strong>Find a forgotten classic. Restore it by hand. Drive it home.</strong></p>

<p align="center"><code>FiveM</code> · <code>OneSync</code> · <code>v0.3.0</code></p>

## From barn to garage

Discover a barn and open its doors to reveal a weathered vehicle from a weighted pool. Work through wheels, glass, oil and filter, bodywork, and ignition. Each enabled step can require inventory items. When the restoration is complete, the server registers ownership and hands over the keys through your configured integration.

- Custom streamed barns, animated doors, a skippable reveal, and in-world workshop interactions.
- Global finds for shared discovery or per-character finds for individual progression.
- Persistent locations, settings, cooldowns, and restoration progress in MySQL.
- An in-game admin tablet with a free-camera placement editor.

## Install

**Requirements** · FXServer with [OneSync](https://docs.fivem.net/docs/scripting-reference/onesync/), [ox_lib](https://github.com/overextended/ox_lib), [oxmysql](https://github.com/overextended/oxmysql), and a configured `kq_link`. Vehicle ownership has adapters for Qbox with `qbx_vehicles`, QBCore, and ESX. Inventory, interactions, notifications, and keys use the integrations configured in `kq_link`. The admin item picker gets suggestions from `ox_inventory` and also accepts item names manually.

1. Extract the release ZIP so the path under your resources folder is `bakery_barnfind/fxmanifest.lua`. The ZIP includes the built UI and streamed models.
2. Start your framework and its integrations before Barn Find. Add the resource and permission to `server.cfg`, starting each dependency once.

   ```cfg
   ensure oxmysql
   ensure ox_lib
   # Start your framework, garage, inventory and key resources here.
   ensure kq_link

   add_ace group.admin bakery_barnfind.admin allow
   ensure bakery_barnfind
   ```

3. Start the server, or run `refresh` and `ensure bakery_barnfind` from the server console. The resource creates its database tables. A fresh install starts with empty vehicle and barn lists.
4. In game, run `/barnadmin` and use **Cars → Add car** to build your vehicle pool. Select **Save**.
5. Open **Locations → New barn**. Position the barn, press **Enter**, then **Save** in the tablet. Approach the doors with your character to test the reveal.

### Upgrade from 0.2.x

Back up `barnfind_settings` and `barnfind_found`, then replace the resource folder and reapply local configuration. Existing saved cars, barns and restore progress load from the database. Grant `bakery_barnfind.admin` explicitly and put any custom ACE names or license entries under `Config.Admin` in [`config.lua`](config.lua).

## Admin tablet

| Page | Controls |
| --- | --- |
| **Overview** | Check discovery status and cooldowns. Reset a single barn or all finds. |
| **Cars** | Choose eligible vehicle models and adjust their weights. A model's chance is its share of the eligible weight. |
| **Locations** | Place, move, rename, enable, and delete barns. Limit a barn to a custom vehicle pool. |
| **Settings** | Configure discovery scope, cooldowns, distances, reveal, scenery, wreck condition, paint, and restoration requirements. |

In the placement editor, use **WASD** to fly, **Space/Ctrl** to change elevation, and **Left Alt** to toggle the mouse-driven gizmo. Use **Enter** to accept placement or **Esc** to cancel. Tablet changes take effect when you select **Save**.

A **global** barn has one active discovery across the server. In **per-character** mode, each character has a separate discovery. The finder is responsible for restoring their vehicle in either mode. The cooldown starts at discovery and applies to the entire find, including unfinished work. Set it to **Once only** to keep a find until an admin resets it.

[`config.lua`](config.lua) contains the admin command, keybind, access rules, and debug toggle. Use the tablet for gameplay settings, paint colours, the car pool, and barn locations. The **Defaults** button in Settings restores the built-in gameplay settings and paints.

## Build from source

Use Node.js 22.12+ or Node.js 24 and npm.

```sh
cd web
npm ci
npm audit
npm run build
```

Vite writes the production NUI to `web/dist`. Run `npm run dev` from `web/` to preview the tablet with sample data in a browser.

From the resource root, run `pwsh -File web/package-release.ps1` to build the install ZIP and checksum under `Desktop/releases/bakery_barnfind/`. Use `-OutputDirectory` to choose another destination. The ZIP version comes from `fxmanifest.lua`.

## Credits

See [asset attribution](ATTRIBUTION.md) for the barn textures and oil filter. The release includes the web dependency notices and Geist font license in `web/dist/`.

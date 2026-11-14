# Bakery Barn Find

A FiveM resource for discovering abandoned cars, restoring them by hand, and driving them out of the barn.

- **Discover** a weathered vehicle from a weighted pool, with animated barn doors and a skippable reveal.
- **Restore** the wheels, windows, oil and filter, bodywork, and ignition. Each step can require inventory items.
- **Claim** the finished car through your garage and vehicle-key integrations. Finds and restoration progress are saved in MySQL.

## Installation

Requires FXServer with OneSync, `ox_lib`, `oxmysql`, and a configured `kq_link`. Vehicle ownership supports Qbox with `qbx_vehicles`, QBCore, and ESX.

1. Extract the release ZIP into your server's resources folder so `bakery_barnfind/fxmanifest.lua` is present.
2. Add these lines to `server.cfg`. Start your framework, garage, inventory, and keys integrations before Barn Find.

   ```cfg
   ensure oxmysql
   ensure ox_lib
   ensure kq_link

   add_ace group.admin bakery_barnfind.admin allow
   ensure bakery_barnfind
   ```

3. In game, run `/barnadmin`. Add a vehicle under **Cars → Add car**, then select **Save**.
4. Open **Locations → New barn**, position it, press **Enter**, then select **Save**. Approach the doors to search the barn.

## Admin tablet

| Page | What you can manage |
| --- | --- |
| **Overview** | See who found what, check cooldowns, and reset finds. |
| **Cars** | Add vehicle models and adjust their relative chances. |
| **Locations** | Place, move, or disable barns and assign custom vehicle pools. |
| **Settings** | Set discovery scope, cooldowns, wreck condition, paints, and restoration requirements. |

Use **WASD** to move the placement camera, **Space/Ctrl** to change elevation, and **Left Alt** to toggle the gizmo. **Enter** accepts placement and **Esc** cancels it.

**Global** mode gives each barn one shared discovery. Nearby players can see the find and open or close the doors after discovery. Only the character who found the car can restore and claim it. **Per-character** mode gives each character their own discovery.

The cooldown starts when the barn is searched. **Once only** keeps each find until an admin resets it.

Edit [`config.lua`](config.lua) to change the admin command, keybind, access rules, or debug logging. Gameplay settings are saved through the tablet.

## Build the UI

Use Node.js 22.12+ or Node.js 24.

```sh
cd web
npm ci
npm run build
```

The built UI is written to `web/dist`. Run `npm run dev` to preview it with sample data.

## Credits

See [asset attribution](ATTRIBUTION.md) for the barn textures and oil filter. Web dependency and font notices are included in `web/dist/`.

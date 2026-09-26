# Infinite Ocean - module

Documentation, tutorial and API reference: **https://kashtheking.com/infinite-ocean/**

The open-source core of Infinite Ocean: an infinite Gerstner-wave sea for Roblox on
`EditableMesh`, synced between server and clients, with a weather API (named wave/colour sets
cross-faded in time and space), obstacles that calm the water, dry regions, water events and a
surface height query. MIT licensed: modify and distribute it freely, keeping the notice in `LICENSE`.

This repository is the module only. The **Infinite Ocean Studio plugin** (installer, live Edit-mode
preview, settings panel, presets, placeholders) and its **addons** (Buoyancy, Swimming, WaterSplash,
Weather, Zones, DevTools) are proprietary and are not distributed here: get the plugin from
KashTheKing and use it under its licence agreement.

## Use

Build `module.project.json` with Rojo (or sync `src/Ocean` in) so the module sits at
`ReplicatedStorage.Ocean`; its two bootstrap scripts call `Ocean.Init()` on each side. Settings are
attributes on the module (`src/Ocean/Settings.luau` is the spec). Without the plugin's Buoyancy
addon the sea is visuals only.

```lua
local Ocean = require(game.ReplicatedStorage.Ocean)
Ocean:CreateWeather("Rough", Ocean.Presets.Ocean["Pirate Seas"])
Ocean:SetWeather("Rough", 20)          -- server: cross-fade the whole sea over 20 s
Ocean:GetHeight(position)              -- either side: surface Y right now
```

Tag a part `OceanObstacle` to calm the water against it (`OceanShore`, `OceanCalmness`
attributes), `OceanDry` for an interior with no water, `OceanTrack` for water events.

## Support

Bug reports, feedback and support: **@KashTheKing** on Roblox, Discord, YouTube and X.

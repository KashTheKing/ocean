---
sidebar_position: 3
title: Advanced Guide
---

# Advanced Guide

For developers who script. Install the plugin, install the module, then drive the sea from code: this page walks through each core feature of the API.

## 1. Install the plugin (strongly recommended)

The plugin is not required to use the module, but it is the only way to get the **addons**: Buoyancy, Swimming, Drowning, WaterSplash, Weather effects, Zones, DevTools and AgentSupport are proprietary scripts the plugin installs next to the module. It also gives you the live Edit-mode preview, the presets and a panel for every setting.

1. Get [**Infinite Ocean**](https://create.roblox.com/store/asset/76752250508724/Infinite-Ocean) from the Creator Store and enable it in Studio's Plugins tab.
2. Open the panel from the toolbar and accept the licence agreement.

If you skip the plugin, the module gives you the animated sea, the settings, weather, zones, obstacles, dry regions, water queries and water events. Nothing floats and nobody swims until you write that yourself or install the plugin later.

## 2. Install the module

**With the plugin**: press **Install** in the panel (or run the **Quick Start**). That adds `ReplicatedStorage.Ocean` and the addon scripts you chose.

**Without the plugin**: the module is open source and MIT licensed at [github.com/KashTheKing/ocean](https://github.com/KashTheKing/ocean).

- With [Rojo](https://rojo.space), build `module.project.json` (`rojo build module.project.json -o Ocean.rbxm`) and drag the `.rbxm` into `ReplicatedStorage`, or `rojo serve module.project.json` to sync it.
- Or copy `src/Ocean` into your own Rojo project so it lands at `ReplicatedStorage.Ocean`.

Either way, what you end up with is:

- `ReplicatedStorage.Ocean`: one ModuleScript with two bootstrap scripts inside it (`OceanServer`, `OceanClient`) that call `Ocean.Init()` on the server and on every client. Every setting is an attribute on this ModuleScript.
- `ReplicatedStorage.Ocean<Addon>`: one script per addon the plugin installed (`OceanBuoyancy`, `OceanSwimming`, and so on). Their settings are attributes on those scripts.

Nothing else in the place changes. `EditableMesh` and `EditableImage` must be enabled for the experience for the sea to render in a published game; they always work in Studio.

From any script, server or client:

```lua
local Ocean = require(game.ReplicatedStorage.Ocean)
```

## 3. Settings

Every setting the panel shows is an attribute on the module. The server owns them; clients read the replicated values. Use `Ocean.Settings` to write them with validation, or set the attribute directly.

```lua
Ocean.Settings.Set("WaveHeight", 3)        -- validated and clamped against the spec; returns the stored value or nil
Ocean.Settings.Set("FoamStyle", "Solid")
print(Ocean.Settings.Get("SeaLevel"))      -- either side

Ocean.Settings.OnChanged(function(name)   -- fires on either side when a setting changes
	print(name, "is now", Ocean.Settings.Get(name))
end)
```

The spec the panel is generated from is `Ocean.Settings.List`: name, section, default, range and hint for every setting. The [settings reference](./settings.md) lists them all. Presets are plain tables of settings, so applying one from code is a loop:

```lua
for name, value in Ocean.Presets.Ocean["Oil Rig"] do
	Ocean.Settings.Set(name, value)
end
```

## 4. Where is the water?

The wave function is a pure function of the settings, the weather state and server time, so these return the same answer on the server and on every client, with no replication lag.

```lua
local y = Ocean:GetHeight(position)          -- world Y of the surface above or below the point
local depth = Ocean:GetDepth(position)       -- studs under the surface, negative above it
local under = Ocean:IsUnderWater(position)   -- false inside an OceanDry region
local dry = Ocean:IsDry(position)            -- inside a dry region
local normal = Ocean:GetSurfaceNormal(position)
```

`GetHeight` accounts for weather, zones, obstacles and `FlatSea`. It is cheap enough to call every frame for a handful of things; for hundreds of parts, sample every few frames. A minimal buoy that never uses the Buoyancy addon:

```lua
game:GetService("RunService").Heartbeat:Connect(function()
	local p = buoy.Position
	buoy.Position = Vector3.new(p.X, Ocean:GetHeight(p), p.Z)
end)
```

## 5. Water events

Player characters are tracked automatically. Anything else gets events when you tag it `OceanTrack` (or `OceanFloat`, which also floats it with the Buoyancy addon) or call `Ocean:Track(instance)`.

```lua
Ocean:Track(crate)

Ocean.EnteredWater:Connect(function(instance) end)   -- dry -> touching water
Ocean.ExitedWater:Connect(function(instance) end)    -- touching -> dry
Ocean.WentUnderWater:Connect(function(instance) end) -- fully submerged
Ocean.WentAboveWater:Connect(function(instance) end) -- surfaced

local state = Ocean:GetWaterState(crate)  -- { Touching, Under, Depth, Surface } or nil
if Ocean:IsInWater(crate) then end
for _, thing in Ocean:GetInstancesInWater() do end
```

Events fire on the side that simulates the instance; connect on the server for game logic and on the client for effects.

## 6. Weather

A weather is a named table of setting overrides. Presets are plain tables, so they double as weathers. Weather is **server only**: the state is one JSON attribute on the module, so late joiners get it for free, and the cross-fade is timed on server time so every client and the server's physics agree.

```lua
-- server
Ocean:CreateWeather("Storm", Ocean.Presets.Ocean["Pirate Seas"])
Ocean:CreateWeather("Glassy", { WaveHeight = 0.25, FoamOpacity = 0 })

Ocean:SetWeather("Storm", 30)      -- cross-fade the whole sea over 30 s
Ocean:SetWeather("Default")        -- back to the attribute values
print(Ocean:GetWeather())          -- the current weather name, either side
```

A storm that rolls in every few minutes is a loop:

```lua
while true do
	task.wait(120)
	Ocean:SetWeather("Storm", 30)
	task.wait(90)
	Ocean:SetWeather("Default", 30)
end
```

The Weather addon adds rain, lightning and thunder on top and can run a weather cycle for you; its settings are attributes on `ReplicatedStorage.OceanWeather`.

## 7. Zones

A zone gives part of the sea its own weather, blended into the surrounding water over `Blend` studs. Server only, like weather.

```lua
Ocean:CreateZone("Bay", { Position = Vector3.new(0, 0, 2000), Radius = 800, Blend = 200, Weather = "Glassy" })
Ocean:SetZoneWeather("Bay", "Storm", 10)   -- change just the bay, over 10 s
print(Ocean:GetZoneAt(position))           -- zone name or nil
print(Ocean:GetWeatherAt(position))        -- the weather a point is in
Ocean:RemoveZone("Bay")
```

Zones can also be built in Studio: tag a part `OceanZone`, and any setting written as an attribute on that part overrides the module inside it. The Zones addon draws them in the panel and handles Lighting on entering and leaving.

## 8. Obstacles, dry regions and floats

Tags shape the water around your map. Add them in the Explorer, from the panel's **Tags** section, or from code:

```lua
Ocean:AddObstacle(island)      -- waves calm down around it; tune with OceanShore and OceanCalmness attributes
Ocean:AddDryRegion(interior)   -- no water inside its box; the surface sinks under it
Ocean:AddFloat(hull)           -- floats with the Buoyancy addon; tune with OceanBuoyancy and OceanDrag
Ocean:Track(buoy)              -- water events only

Ocean:RemoveObstacle(island)   -- and RemoveDryRegion, RemoveFloat, Untrack
```

The tag names follow the `FloatTag`, `ObstacleTag`, `DryTag`, `TrackTag` and `ZoneTag` settings; `Ocean.Tags.Float`, `.Obstacle`, `.Dry` and `.Track` give the current names, so `part:AddTag(Ocean.Tags.Float)` is the same as `Ocean:AddFloat(part)`. See [Tags](./tags.md) for every attribute.

## 9. Addons from code

Each addon's settings are attributes on its script, so you configure them the same way as the module:

```lua
game.ReplicatedStorage.OceanDevTools:SetAttribute("Everyone", true)     -- debug panel for every player
game.ReplicatedStorage.OceanDrowning:SetAttribute("Mode", "Damage")     -- drowning hurts instead of blacking out
game.ReplicatedStorage.OceanSwimming:SetAttribute("CanJump", false)
```

The names are listed per addon in [Addons](./addons.md).

## 10. Automating the plugin

In Studio, the plugin exposes `shared.InfiniteOcean` to the command bar and to MCP agents: `Install()`, `Preset("Ocean", "Pirate Seas")`, `Set("WaveHeight", 2)`, `Addon("Swimming", true)`, `Preview(true)`, `Tag(...)`, `Hull(...)` and more. The AgentSupport addon's README documents every command.

## Under the hood

The [API reference](/api/Ocean) covers every public method and the lower-level classes: [Waves](/api/Waves) (the wave function, obstacles, the synced clock), [Weather](/api/Weather) (the replicated state), [Regions](/api/Regions) (dry boxes), [Zones](/api/Zones) and [Tracker](/api/Tracker). [Performance](./performance.md) explains how the renderer keeps its frame rate and what each setting costs.

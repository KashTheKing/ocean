---
sidebar_position: 6
title: Scripting
---

# Scripting

The module is one ModuleScript, `ReplicatedStorage.Ocean`, that works on the server and on every client. Its two child scripts start it; you only `require` it.

```lua
local Ocean = require(game.ReplicatedStorage.Ocean)
```

The full list of methods, properties and events is in the [API reference](/api/Ocean). This page shows the patterns.

## Where is the surface?

Works on both sides, and always agrees between them: the wave function is a pure function of the settings, the weather state and server time.

```lua
local y = Ocean:GetHeight(position)          -- world Y of the surface above/below the point
local depth = Ocean:GetDepth(position)       -- studs under the surface, negative above
local under = Ocean:IsUnderWater(position)   -- false inside an OceanDry region
local normal = Ocean:GetSurfaceNormal(position)
```

`GetHeight` accounts for weather, zones, obstacles and `FlatSea`. It is cheap enough to call per frame for a handful of things; for hundreds of parts, sample every few frames.

## Water events

Player characters are tracked automatically. Tag anything else `OceanTrack` (or `OceanFloat`, which also floats it) or call `Ocean:Track(instance)`.

```lua
Ocean.EnteredWater:Connect(function(instance) end)   -- dry -> wet
Ocean.ExitedWater:Connect(function(instance) end)    -- wet -> dry
Ocean.WentUnderWater:Connect(function(instance) end) -- fully submerged
Ocean.WentAboveWater:Connect(function(instance) end) -- surfaced

local state = Ocean:GetWaterState(instance) -- { Touching, Under, Depth, Surface } or nil
for _, thing in Ocean:GetInstancesInWater() do end
```

A server Script gets server-side events, a LocalScript client-side ones.

## Weather

A weather is a named table of setting overrides. Only [weather settings](./settings.md) count (waves, colours, foam, spray, the underwater tint); other keys are ignored, which is why a preset can be passed straight in. Server only.

```lua
Ocean:CreateWeather("Storm", Ocean.Presets.Ocean["Pirate Seas"])
Ocean:CreateWeather("Glassy", { WaveHeight = 0.25, FoamOpacity = 0 })

Ocean:SetWeather("Storm", 30)    -- cross-fade the whole sea over 30 s
Ocean:SetWeather("Default")      -- back to the module's own attribute values, instantly
print(Ocean:GetWeather())        -- "Default"
```

The state lives in one attribute on the module, so late joiners get it for free, and the fade is timed on server time so nothing drifts.

### Scripted zones

A disc of sea with its own weather, blended into the surroundings across its rim:

```lua
Ocean:CreateZone("Bay", { Position = Vector3.new(0, 0, 2000), Radius = 800, Blend = 200, Weather = "Glassy" })
Ocean:SetZoneWeather("Bay", "Storm", 10)
Ocean:RemoveZone("Bay")
print(Ocean:GetWeatherAt(position)) -- the weather with the most influence there
```

For zones built in Studio, tag a part `OceanZone` instead: see [Tags](./tags.md). Those can carry any setting, not only weather ones, and the Zones addon handles Lighting for them.

## Settings from code

Settings are attributes on the module. On the server, either write them directly or through the validated setter:

```lua
local Settings = Ocean.Settings
Settings.Set("WaveHeight", 1.4)                -- clamped to the spec; returns the value stored, or nil
Ocean:SetAttribute("FoamStyle", "Solid")       -- also fine
Settings.OnChanged(function(name) end)         -- fires on either side

for _, entry in Settings.List do               -- the spec the plugin panel is built from
	print(entry.Name, entry.Section, entry.Default, entry.Hint)
end
```

On a client, `Settings.SetLocalOverride(name, value)` makes that client use a value without replicating it (the Zones addon uses this to give a player inside a zone that zone's look).

## Tags from code

The tag helpers are plain CollectionService tags underneath, so `instance:AddTag("OceanFloat")` does the same thing.

```lua
Ocean:AddFloat(part)                  -- floats (Buoyancy addon)
Ocean:AddObstacle(pier)               -- calms the water around it (OceanShore, OceanCalmness attributes)
Ocean:AddDryRegion(submarineInterior) -- no water inside its box
Ocean:Track(buoy)                     -- events only
```

The tag names follow the `FloatTag`, `ObstacleTag`, `DryTag`, `TrackTag` and `ZoneTag` settings; `Ocean.Tags.Float` and friends give the current names.

## Driving the plugin

In Studio, the plugin exposes `shared.InfiniteOcean` from the command bar and from MCP agents: `Install()`, `Preset("Pirate Seas")`, `Set("WaveHeight", 1.2)`, `Addon("Swimming", true)`, `Preview(true)` and more. The AgentSupport addon's README lists every command.

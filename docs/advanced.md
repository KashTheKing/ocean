---
sidebar_position: 3
title: Advanced Guide
---

# Advanced Guide

For developers who script. Install with the plugin (it is the only way to get the module and its addons into a place), then drive everything from code.

## What the plugin installs

- `ReplicatedStorage.Ocean`: one ModuleScript, MIT licensed, with two bootstrap scripts that call `Ocean.Init()` on the server and on every client. Every setting is an attribute on it.
- `ReplicatedStorage.Ocean<Addon>`: one script per addon you chose (`OceanBuoyancy`, `OceanSwimming`, and so on). Their settings are attributes on those scripts.
- `OceanAgentSupport`: a README StringValue for MCP agents and command-bar automation, if you added that addon.

Nothing else in the place changes. Uninstall removes exactly those.

## Settings from code

Settings are attributes on the module and the server owns them; the client reads replicated values. Two ways to write:

```lua
local Ocean = require(game.ReplicatedStorage.Ocean)

Ocean.Settings.Set("WaveHeight", 3)        -- validated and clamped against the spec, returns the stored value or nil
Ocean:SetAttribute("FoamStyle", "Solid")   -- plain attribute write, no validation

Ocean.Settings.OnChanged(function(name)   -- either side
	print(name, "is now", Ocean.Settings.Get(name))
end)
```

The spec the panel is built from is `Ocean.Settings.List`: name, section, default, range, hint. The [settings reference](./settings.md) is generated from it.

## Weather and zones

A weather is a named table of setting overrides. Presets are plain tables, so they double as weathers. Server only; the state is one JSON attribute on the module, so late joiners get it for free and the cross-fade is timed on server time.

```lua
Ocean:CreateWeather("Storm", Ocean.Presets.Ocean["Pirate Seas"])
Ocean:CreateWeather("Glassy", { WaveHeight = 0.25, FoamOpacity = 0 })
Ocean:SetWeather("Storm", 30)      -- fade the whole sea over 30 s
Ocean:SetWeather("Default")        -- back to the attribute values

Ocean:CreateZone("Bay", { Position = Vector3.new(0, 0, 2000), Radius = 800, Blend = 200, Weather = "Glassy" })
Ocean:SetZoneWeather("Bay", "Storm", 10)
Ocean:RemoveZone("Bay")
```

For zones built in Studio, tag a part `OceanZone`; any setting set as an attribute on that part overrides the module inside it, and the Zones addon handles Lighting on entering and leaving.

## Water queries and events

```lua
local y = Ocean:GetHeight(position)          -- surface Y, both sides, any time
local d = Ocean:GetDepth(position)           -- studs under the surface, negative above
local n = Ocean:GetSurfaceNormal(position)
local under = Ocean:IsUnderWater(position)   -- false inside an OceanDry region

Ocean.EnteredWater:Connect(function(instance) end)
Ocean.ExitedWater:Connect(function(instance) end)
Ocean.WentUnderWater:Connect(function(instance) end)
Ocean.WentAboveWater:Connect(function(instance) end)

Ocean:Track(buoy)                   -- events for something that should not float
local state = Ocean:GetWaterState(character) -- { Touching, Under, Depth, Surface } or nil
```

Characters are tracked automatically; anything tagged `OceanFloat` or `OceanTrack` is too.

## Tags from code

```lua
Ocean:AddFloat(hull)               -- part:AddTag("OceanFloat") does the same
Ocean:AddObstacle(island)          -- OceanShore and OceanCalmness attributes tune it
Ocean:AddDryRegion(interior)
```

Tag names follow the `FloatTag`, `ObstacleTag`, `DryTag`, `TrackTag` and `ZoneTag` settings; `Ocean.Tags.Float` and friends give the current names.

## Addon settings from code

Each addon's settings are attributes on its script. For example, to open the DevTools panel to every player in a showcase place, or to make drowning use damage:

```lua
game.ReplicatedStorage.OceanDevTools:SetAttribute("Everyone", true)
game.ReplicatedStorage.OceanDrowning:SetAttribute("Mode", "Damage")
```

The names are listed per addon in [Addons](./addons.md).

## Automating the plugin

In Studio, the plugin exposes `shared.InfiniteOcean` to the command bar and to MCP agents: `Install()`, `Preset("Ocean", "Pirate Seas")`, `Set("WaveHeight", 2)`, `Addon("Swimming", true)`, `Preview(true)`, `Tag(...)`, `Hull(...)` and more. The AgentSupport addon's README documents every command.

## Under the hood

The [API reference](/api/Ocean) covers every public method and the lower-level classes: [Waves](/api/Waves) (the wave function, obstacles, the synced clock), [Weather](/api/Weather) (the replicated state), [Regions](/api/Regions) (dry boxes), [Zones](/api/Zones) and [Tracker](/api/Tracker). [Performance](./performance.md) explains how the renderer keeps its frame rate and what each setting costs.

# Infinite Ocean

Infinite Gerstner-wave ocean for Roblox, built on `EditableMesh`. Server and clients run the same
wave function off `workspace:GetServerTimeNow()`, so physics and visuals stay in phase and only
settings ever replicate. It is *just the ocean*: no lighting, no weather effects. It exposes a
weather **API** so your own systems can drive the sea state.

- Camera-following mesh with distance LOD (each wave fades out where the grid can't resolve it)
- Flat water tinted per vertex by wave height, darker at night (reads the sun, never sets it)
- A faint white Neon "film" on the surface (`FilmOpacity`) so anything crossing it shows a clear waterline
- Animated foam-ring texture (a baked `EditableImage` flipbook) on high crests near the camera only
- Buoyancy via `ApplyImpulseAtPosition` for parts tagged `OceanFloat`, on whichever side simulates them
- Characters swim (forced `Swimming` state + a damped float), crest spray, optional underwater tint
- Weather types and weather **zones**, cross-faded in time and space, deterministic on both sides
- `Quality` setting: Fast (a quarter of the vertices, no film, stepped foam), Regular, Realistic
- `WaterMaterial`, `WaterTexture` and `FoamTexture` settings: any material, and your own tiled
  image assets for the water and the crest foam (blank foam = the built-in animated rings)

> `EditableMesh` / `EditableImage` need the experience to have those APIs enabled to run in a
> published game. They always work in Studio.

## Install

**Rojo** - `rojo serve` (or `npm run serve`) syncs `src/Ocean` to `ReplicatedStorage.Ocean`.
`npm run build` produces a standalone `build/Ocean.rbxm`. Its bootstrap scripts live *inside*
the module (`OceanServer`, RunContext Server and `OceanClient`, RunContext Client) and call
`Ocean.Init()` for you.

> Looking for the Studio plugin (install button, live preview, settings panel, presets)? It's a
> separate, paid product built on this module.

## API

```lua
local Ocean = require(ReplicatedStorage.Ocean)
Ocean.Init() -- once per side; the bundled bootstrap scripts already do this

-- Weather: server only. A weather type is a named set of overrides for the weather settings
-- (waves, colours, foam, spray). "Default" always exists and is the module's attribute values.
Ocean:CreateWeather("Storm", Ocean.Presets.Storm)          -- Presets: Flat, Storm, "Deep Sea"
Ocean:CreateWeather("Murk", { DeepColor = Color3.fromRGB(30, 50, 60), Wave1Steepness = 0.2 })
Ocean:SetWeather("Storm", 20)                              -- whole ocean, cross-faded over 20 s

-- Zones: a disc of ocean with its own weather, blended in across its rim (Blend studs).
Ocean:CreateZone("Bay", { Position = Vector3.new(0, 0, 2000), Radius = 800, Weather = "Flat" })
Ocean:SetZoneWeather("Bay", "Storm", 10)
Ocean:RemoveZone("Bay")

-- Queries: either side.
Ocean:GetHeight(position)     -- world Y of the surface there, right now
Ocean:GetWeatherAt(position)  -- dominant weather name there
Ocean:GetWeather()            -- global weather name
```

### Water events and queries

```lua
Ocean.EnteredWater:Connect(function(instance) end)   -- dry -> touching water (part, model or character)
Ocean.ExitedWater:Connect(function(instance) end)
Ocean.WentUnderWater:Connect(function(instance) end) -- fully submerged
Ocean.WentAboveWater:Connect(function(instance) end)

Ocean:GetWaterHeight(point)  Ocean:GetDepth(point)  Ocean:GetSurfaceNormal(point)
Ocean:IsUnderWater(point)    Ocean:IsAboveWater(point)  Ocean:IsDry(point)
Ocean:GetWaterState(instance) -> { Touching, Under, Depth, Surface }
Ocean:IsInWater(instance)    Ocean:GetInstancesInWater()
Ocean:Track(instance) / :Untrack   Ocean:AddFloat(part) / :RemoveFloat
Ocean:AddObstacle(x) / :RemoveObstacle   Ocean:AddDryRegion(x) / :RemoveDryRegion
```

Events fire for everything tagged `OceanFloat` or `OceanTrack` and for every player character, on the
side you connect from. All tags are plain CollectionService tags (`Ocean.Tags`), so existing gameplay
can add or remove them however it likes. The names are settings (`FloatTag`, `ObstacleTag`, `DryTag`,
`TrackTag`) - rename them in the plugin (double-click a tag's title) to match tags your game already uses.

Dry regions (**experimental** - the cut-out can still show seams at corners): tag a part or model `OceanDry` (a submarine interior, an underwater room) and there is
no water inside it - the surface mesh sinks out of the box, the underwater tint stays off for a
camera inside, characters don't swim, and events treat it as air. Floats inside it get no lift, but a
region never dries its own vehicle (same model or welded assembly), so a submarine's hull still floats
around its interior while cargo inside stays put.

With `workspace.StreamingEnabled`, the server only simulates floats within streaming range of a
player and anchors the rest (`OceanParked` attribute) until someone comes near. Streaming off:
everything is simulated.

Buoyancy fades with depth (`BuoyancyFalloffDepth`, `DeepBuoyancy`), so a submarine with a
near-neutral `OceanBuoyancy` holds depth but still bobs up at the surface.

Wind: turn on `UseWind` and the waves follow `workspace.GlobalWind` - the configured wave angles
become offsets around the wind direction, on both server and client (GlobalWind replicates).

Obstacles: tag a `BasePart` or `Model` with `OceanObstacle` and the sea goes idle against it instead
of washing through - islands, piers, hulls. `OceanShore` (attribute, studs, default 40) is how far
out the calming starts; a foam line forms across it. Same damping drives physics and visuals.

Floating: tag any unanchored `BasePart` with `OceanFloat`. Per-part attributes `OceanBuoyancy` and
`OceanDrag` (default 1) scale lift and drag - e.g. `0.3` sinks, `2` rides high.

Settings are attributes on the module (spec in `src/Ocean/Settings.luau`); the server owns them.
`BuoyancyEnabled` and `SwimEnabled` toggle the physics. If a `ColorCorrectionEffect` named
`OceanUnderwater` exists in Lighting, the module enables it while the camera is under the surface
(every plugin vibe creates one).

In Studio, with [Iris](https://github.com/SirMallard/Iris) at `ReplicatedStorage.Packages.Iris`, a
debug window appears in play mode (toggle it with the `DebugMenu` setting, live): every setting, weather/zone buttons, spawnable test floats, a
surface probe and render stats. No Iris, no menu - the ocean still runs.

## How weather blending works

Each weather compiles to a full wave set. The sea at a point is a weighted **sum of whole sets**
(layers), never a blend of wave parameters - blending wavelengths across space would scramble the
phase. Layers are the zones covering the point plus the global weather for the remaining weight;
anything mid-transition contributes two. Fades are a pure function of server time. The renderer
culls zones once per frame and only vertices actually inside a zone pay for their own blend.

## Development

Tools are pinned in `rokit.toml` (`rokit install`).

```
npm run format  # stylua
npm run lint    # stylua --check, selene, luau-lsp
```

`luau-lsp` needs `globalTypes.d.luau` in the repo root (not committed).
`require(ReplicatedStorage.Ocean.Waves).SelfTest()` checks the height inverse and layer weights.

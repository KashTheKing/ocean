---
sidebar_position: 6
title: Settings reference
---

# Settings reference

Every setting is an attribute on `ReplicatedStorage.Ocean`. The plugin panel edits them; scripts can too (server side): `Ocean:SetAttribute("WaveHeight", 1.5)` or, with validation and clamping, [`Settings.Set`](/api/Settings#Set). Settings marked *weather* can be overridden per weather (see [Scripting](./scripting.md)); settings marked *rebuilds mesh* rebuild the surface when changed.

## General Physics

| Setting | Type | Default | Range | What it does |
|---|---|---|---|---|
| `SeaLevel` | number | 0 | -500 to 500 | World Y of the resting surface |
| `FlatSea` | boolean | false |  | No waves at all: the surface lies flat at SeaLevel with the same look (colours, film, foam style, tint). Buoyancy, swimming and water events work on that flat surface |
| `SeafloorHeight` | number | -436 | -10000 to 10000 | World Y of the seafloor slab the plugin places (Placeholders). Kept under the deepest wave trough and that much above the fallen-parts height |

## Wave Physics

| Setting | Type | Default | Range | What it does |
|---|---|---|---|---|
| `WaveGravity` | number | 60 | 5 to 400 | Wave speed: higher is faster *(weather)* |
| `WaveHeight` | number | 1 | 0 to 2.5 | Overall wave height: every wave's amplitude times this *(weather)* |
| `TimeScale` | number | 1 | 0 to 3 | Overall wave speed: the wave clock runs this many times faster |
| `UseWind` | boolean | false |  | Waves follow workspace.GlobalWind: the Wave angles become offsets from the wind direction |

## Buoyancy Physics

These need the Buoyancy addon.

| Setting | Type | Default | Range | What it does |
|---|---|---|---|---|
| `BuoyancyEnabled` | boolean | true |  | Floats parts tagged "OceanFloat" |
| `WaterDensity` | number | 1 | 0.1 to 5 | Density of the water: parts denser than this sink, lighter ones float |
| `LinearDrag` | number | 1.5 | 0 to 10 | Resistance to floating parts moving through the water |
| `AngularDrag` | number | 2 | 0 to 10 | Resistance to floating parts turning |
| `MaxLift` | number | 1.3 | 1 to 6 | Cap on total lift, as a multiple of the part's weight |
| `BuoyancyFalloffDepth` | number | 40 | 1 to 500 | Lift fades from full at the surface to DeepBuoyancy this many studs down (submarines) |
| `DeepBuoyancy` | number | 0.7 | 0 to 1 | Lift multiplier once deeper than the falloff depth |

## Visuals

| Setting | Type | Default | Range | What it does |
|---|---|---|---|---|
| `ShallowColor` | colour | rgb(20, 110, 160) |  | Crests *(weather)* |
| `DeepColor` | colour | rgb(12, 84, 131) |  | Troughs *(weather)* |
| `FoamColor` | colour | rgb(255, 255, 255) |  | Colour of the crest foam *(weather)* |
| `NightBrightness` | number | 0.55 | 0 to 1 | Colour multiplier once the sun is down |
| `UnderwaterEnabled` | boolean | true |  | Tint the view while the camera is under the surface |
| `UnderwaterTint` | colour | rgb(12, 84, 131) |  | Underwater tint colour *(weather)* |
| `UnderwaterOpacity` | number | 0.6 | 0 to 1 | How strongly the underwater tint covers the view (0 = none) *(weather)* |
| `Reflectance` | number | 0.05 | 0 to 1 | How much of the sky the surface mirrors |
| `FoamStyle` | choice | Animated | Animated, Texture, Solid, None | Crest foam: Animated = the built-in moving rings; Texture = your FoamTexture image; Solid = plain FoamColor; None = no foam layer *(rebuilds mesh)* |
| `FoamStart` | number | 0.45 | -1 to 1 | Crest height (0 to 1 of the tallest crest) where foam begins *(weather)* |
| `FoamFull` | number | 0.9 | -1 to 1 | Crest height where the foam is fully opaque *(weather)* |
| `FoamOpacity` | number | 0.35 | 0 to 1 | Opacity of the crest foam *(weather)* |
| `WebOpacity` | number | 0 | 0 to 1 | Faint foam web on all water (0 = only on crests) *(weather)* |
| `SplashRate` | number | 2 | 0 to 40 | Crest spray bursts per second near the camera (drawn by the WaterSplash addon) *(weather)* |
| `SplashHeight` | number | 0.4 | 0 to 1 | Crest height (0 to 1 of the tallest crest) a wave must reach to throw spray *(weather)* |
| `FilmOpacity` | number | 0.05 | 0 to 1 | Translucent skin on the surface in the water's colour: things crossing it get a clear waterline *(weather)* |
| `WaterMaterial` | string | SmoothPlastic |  | A material name (SmoothPlastic, Foil, Glass, Ice...) or one of the place's MaterialVariants; an unknown name lands on the closest |
| `WaterTexture` | string | (blank) |  | Image asset id tiled over the water (multiplies the colour), or blank for none |
| `FoamTexture` | string | (blank) |  | Image asset id for the crest foam (white with alpha), used when FoamStyle is Texture |

## Performance

| Setting | Type | Default | Range | What it does |
|---|---|---|---|---|
| `Quality` | choice | Regular | Fast, Regular, Realistic | Fast, Regular or Realistic: how many vertices animate and how often foam and film update *(rebuilds mesh)* |
| `StaticWaves` | boolean | false |  | The waves hold still: the wave clock stops, so the surface (and everything floating on it) is built once and left |
| `DynamicLighting` | boolean | true |  | The water darkens with the sun (NightBrightness) as the day passes; off keeps daytime colours |
| `DynamicColors` | boolean | true |  | The crest foam follows the waves every update; off writes it once |
| `Lit` | boolean | true |  | The scene lights the water: shadows and the sun's highlights fall on it. Off draws it in flat colour |
| `Highlights` | boolean | true |  | The translucent skin layer over the near water: the surface sheen and the waterline on things crossing it *(rebuilds mesh)* |
| `UpdateRate` | number | 60 | 15 to 240 | How many times per second the surface mesh is updated |
| `CellSize` | number | 8 | 2 to 32 | Finest quad size (studs) *(rebuilds mesh)* |
| `InnerCells` | number | 24 | 4 to 44 | Full-detail cells each side (inner + outer at most 49) *(rebuilds mesh)* |
| `OuterCells` | number | 25 | 4 to 45 | Coarser cells past the inner ring, each Growth times larger than the last *(rebuilds mesh)* |
| `Growth` | number | 1.2 | 1.02 to 1.6 | How much larger each outer cell is than the one before it *(rebuilds mesh)* |
| `RenderDistance` | number | 40000 | 2000 to 100000 | How far the sea is drawn from the camera (studs): the flat horizon skirt reaches this far *(rebuilds mesh)* |

## Tags

The tag names the module listens for. Rename them to match tags your game already uses.

| Setting | Type | Default | What it does |
|---|---|---|---|
| `FloatTag` | string | OceanFloat | Tag: unanchored parts float |
| `ObstacleTag` | string | OceanObstacle | Tag: the sea goes idle against it |
| `DryTag` | string | OceanDry | Tag: the surface sinks under it |
| `TrackTag` | string | OceanTrack | Tag: water events only |
| `ZoneTag` | string | OceanZone | Tag: an area with its own sea, physics and lighting |

## Wave1 to Wave6

The sea is the sum of six Gerstner waves. Each has three settings, all of them weather settings.

| Setting | Type | Range | What it does |
|---|---|---|---|
| `Wave{i}Angle` | number | -180 to 180 | Direction this wave travels (degrees) |
| `Wave{i}Length` | number | 10 to 1000 | Distance between crests (studs) |
| `Wave{i}Steepness` | number | 0 to 0.5 | How peaked this wave is (0 = flat) |

Defaults (angle, length, steepness):

| Wave | Angle | Length | Steepness |
|---|---|---|---|
| 1 | 15° | 320 | 0.1 |
| 2 | -30° | 190 | 0.12 |
| 3 | 50° | 120 | 0.15 |
| 4 | -65° | 80 | 0.15 |
| 5 | 100° | 56 | 0.12 |
| 6 | -10° | 48 | 0.1 |

Keep the sum of the steepness values (times `WaveHeight`) under about 1, or crests fold over into loops. Wavelengths shorter than about six times `CellSize` are smoothed away by the mesh, though the physics still feels them.

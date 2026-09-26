---
sidebar_position: 9
title: Performance
---

# Performance

The sea is built to hold a high frame rate on ordinary clients. This page explains what costs what, so you can spend where it shows.

## How it is drawn

- The surface near the camera is a small set of **skinned `EditableMesh` tiles**. Each vertex hangs on a bone, and the module moves bones every update; moving a bone is far cheaper than rewriting the mesh.
- The camera sits at the corner of a 32-cell block, so only **four tiles** are ever animated, and the mesh never has to move when you walk: a root bone carries the re-centring.
- Past the animated ring, one **static mesh** with a flat skirt runs out to `RenderDistance`.
- **Foam** is a fine plain mesh over the inner area with a soft edge; the **film** is one translucent skinned mesh. Both are optional layers.
- The wave function is Gerstner math with fixed-size arrays and no allocation in the hot loop.

Everything updates at `UpdateRate` (60 per second by default), not at the render rate, so a 240 fps client does no more mesh work than a 60 fps one.

## What to turn

| Want | Turn |
|---|---|
| The biggest single saving | `Quality` = Fast (fewer animated vertices, no film, foam every fourth update) |
| Fewer updates per second | `UpdateRate` (30 is fine for slow seas) |
| Smaller animated area | `InnerCells` down, or `CellSize` up |
| No foam | `FoamStyle` = None |
| No film | `Highlights` off |
| Flat lighting | `Lit` off draws the water unlit |
| A still sea | `StaticWaves` builds the surface once and stops the clock; `FlatSea` removes the waves entirely |

Ocean presets set sensible values for their look; Island (the default) is the balanced one.

## Streaming

When streaming loads a new area, Roblox rebuilds every skinned mesh it finds. The module keeps its meshes small and few so that rebuild stays at a few tens of milliseconds rather than a stall.

## Client budget

A client can hold only a handful of `EditableMesh` and `EditableImage` objects at once, and the sea uses most of them (four tiles, the static mesh, foam, film and the animated foam image). If a build is refused, the module retries with fewer layers: first without the film, then without foam, then with a single tile, and warns in the Output which level it landed on. Other systems that create EditableMesh or EditableImage objects share that budget with the sea.

## Physics side

Buoyancy samples the surface at up to eight points per floating part every physics step; hundreds of floating parts are fine, thousands are not. Water events are checked once per tracked instance per frame. Obstacles, dry regions and zones are re-read twice a second, so tagging a moving ship as an obstacle costs nothing extra.

## Measuring

The **Performance** section shows live stats while a preview or playtest runs: frames per second, milliseconds per mesh update, animated and moved vertex counts. The `OceanSurface` model (under `Terrain` at runtime, under the Camera in a preview) carries the same numbers as attributes: `UpdateMs`, `Animated`, `Bones`, `Tiles`, `Hitches`, `WorstMs`.

---
sidebar_position: 2
title: No Scripting Guide
---

# No Scripting Guide

Everything here happens in the plugin panel. No scripts, no attributes typed by hand.

## 1. Install

1. Get [**Infinite Ocean**](https://create.roblox.com/store/asset/76752250508724/Infinite-Ocean) from the Creator Store and enable it in Studio's Plugins tab.
2. Open the panel and accept the licence agreement.
3. Press **Dynamic Ocean**. The Quick Start walks you through the rest. If the panel says EditableMesh is not enabled, either turn it on in the experience's settings and press Dynamic Ocean again, or press **Continue** to use a Flat Ocean.

![Quick Start step 1](./img/ui-quickstart-1.png)

## 2. Pick a physics, a look and your addons

- **Physics**: Calm (the defaults), Rough, Huge, Tsunami or Still. Pressing one applies it and moves on.
- **Look**: Classic, Cartoony, Stylized or Realistic.
- **Addons**: install what you need. For most games that is **Buoyancy** (things float), **Swimming** (players swim) and **Drowning** if you want breath to matter. **DevTools** gives you a debug panel in playtests.
- **Finish** starts the Edit-mode preview: the sea appears around the camera. It is not saved into the place and Team Create teammates never see it.

## 3. Choose an ocean preset

Open **Presets** and press one of the Ocean presets. Each sets the waves, the look, and the place's Lighting and Atmosphere in one go: Island, Pirate Seas, Oil Rig, Great Flood or Blank. They are starting points; everything they set is a slider you can move afterwards.

![Presets](./img/ui-main.png)

## 4. Make the sea respect your map

Open **Tags**, select something in the workspace, and press **Tag selection** under the tag you want:

| Want | Tag |
|---|---|
| Waves calm down around an island, pier or breakwater | `OceanObstacle` |
| A boat that floats and rocks | `OceanFloat` on its hull (or **Make hull for selected boat**) |
| A submarine interior or underwater room with no water inside | `OceanDry` |
| A bay with its own calmer, differently coloured sea | Install the Zones addon and press **+ New zone** |

![Tags](./img/ui-tags.png)

## 5. Tune it

- **Physics > General Physics**: sea level, flat sea, seafloor height.
- **Physics > Wave Physics**: overall wave size and speed, then each of the six waves.
- **Appearance > Visuals**: colours, foam, film, underwater tint, material and textures.
- **Appearance > Lighting and Atmosphere**: one-click lighting looks and your own saved ones.
- **Appearance > Performance**: quality tier, update rate and mesh size, with live stats.

Every control has a hint under it and a tooltip. **Save current** in any Presets section keeps what you made.

## 6. Test

Press Play. With DevTools installed, press **F8** or type `/ocean` in chat to open the debug panel: change any setting live, switch weather, spawn crates and rafts, watch water events.

That is the whole loop. When you want a storm to roll in on a timer, or a script to ask where the surface is, move on to the [Advanced Guide](./advanced.md).

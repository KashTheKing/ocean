-- Ready-made overrides, plain data. Three kinds:
--   Presets.Physics  - waves and buoyancy: Calm (the module defaults), Rough, Huge, Tsunami, Still
--   Presets.Visual   - the look: Classic (the module defaults, like Roblox water), Cartoony, Stylized, Realistic
--   Presets.Ocean    - a whole sea = one physics + one look: Island, Pirate Seas, Oil Rig, Great Flood, Blank
-- Each carries only its own keys and applies on top of whatever is set. The plugin lists them by
-- kind; weathers take an Ocean preset: Ocean:CreateWeather("Pirate Seas", Ocean.Presets.Ocean["Pirate Seas"]).
-- Weather ignores non-weather keys (materials, textures, physics).
local Presets = {}

local function waves(list: { { number } }, into: { [string]: any }): { [string]: any }
	for i, wave in list do
		into[`Wave{i}Angle`], into[`Wave{i}Length`], into[`Wave{i}Steepness`] = wave[1], wave[2], wave[3]
	end
	return into
end

local function merge(...: { [string]: any }): { [string]: any }
	local into = {}
	for _, layer in { ... } do
		for key, value in layer do
			into[key] = value
		end
	end
	return into
end

-- An Ocean preset by name, old names included.
function Presets.Find(name: string): { [string]: any }?
	return Presets.Ocean[name] or Presets.Ocean[Presets.Aliases[name]]
end

Presets.Physics = {
	-- the module defaults, spelled out so applying it always lands on them
	Calm = waves({
		{ 15, 320, 0.1 },
		{ -30, 190, 0.12 },
		{ 50, 120, 0.15 },
		{ -65, 80, 0.15 },
		{ 100, 56, 0.12 },
		{ -10, 48, 0.1 },
	}, { WaveGravity = 60 }),
	Rough = waves({
		{ 25, 420, 0.14 },
		{ -20, 260, 0.16 },
		{ 60, 160, 0.16 },
		{ -55, 100, 0.14 },
		{ 110, 64, 0.11 },
		{ 5, 48, 0.09 },
	}, { WaveGravity = 90 }),
	Huge = waves({
		{ 10, 900, 0.14 }, -- long, slow open-ocean swell
		{ -25, 600, 0.14 },
		{ 40, 320, 0.12 },
		{ -60, 160, 0.1 },
		{ 95, 80, 0.06 },
		{ -5, 48, 0.04 },
	}, { WaveGravity = 45 }),
	Tsunami = waves({
		{ 0, 1000, 0.3 }, -- one wall of water
		{ 8, 1000, 0.2 },
		{ 30, 240, 0.06 },
		{ -40, 120, 0.05 },
		{ 100, 64, 0.04 },
		{ -10, 48, 0.03 },
	}, { WaveGravity = 30 }),
	Still = waves({
		{ 15, 320, 0 },
		{ -30, 190, 0 },
		{ 50, 120, 0 },
		{ -65, 80, 0 },
		{ 100, 56, 0 },
		{ -10, 48, 0 },
	}, {}),
}

Presets.Visual = {
	-- like Roblox's own water: its blue, a touch of reflection, faint crest foam
	Classic = {
		ShallowColor = Color3.fromRGB(20, 110, 160),
		DeepColor = Color3.fromRGB(12, 84, 131),
		FoamColor = Color3.fromRGB(255, 255, 255),
		UnderwaterTint = Color3.fromRGB(12, 84, 131),
		UnderwaterOpacity = 0.6,
		Reflectance = 0.05,
		FoamStyle = "Animated",
		FoamStart = 0.45,
		FoamFull = 0.9,
		FoamOpacity = 0.35,
		FilmOpacity = 0.05,
		SplashRate = 2,
		WaterMaterial = "SmoothPlastic",
		WaterTexture = "",
		FoamTexture = "",
	},
	-- a flat cartoon water build: a matte Slate slab in sky blue under a deeper-blue film with a
	-- faint tiled pattern
	Cartoony = {
		ShallowColor = Color3.fromRGB(4, 175, 236),
		DeepColor = Color3.fromRGB(9, 137, 207),
		FoamColor = Color3.fromRGB(255, 255, 255),
		UnderwaterTint = Color3.fromRGB(9, 137, 207),
		UnderwaterOpacity = 0.5,
		Reflectance = 0,
		FoamStyle = "None",
		FilmOpacity = 0.25,
		SplashRate = 8,
		WaterMaterial = "Slate",
		WaterTexture = "rbxassetid://6126332496",
		FoamTexture = "",
	},
	-- bright flat bands with solid white foam
	Stylized = {
		ShallowColor = Color3.fromRGB(40, 190, 220),
		DeepColor = Color3.fromRGB(20, 120, 190),
		FoamColor = Color3.fromRGB(255, 255, 255),
		UnderwaterTint = Color3.fromRGB(20, 120, 190),
		UnderwaterOpacity = 0.5,
		Reflectance = 0,
		FoamStyle = "Solid",
		FoamStart = 0.2,
		FoamFull = 0.5,
		FoamOpacity = 1,
		FilmOpacity = 0.2,
		SplashRate = 6,
		WaterMaterial = "Slate",
		WaterTexture = "",
		FoamTexture = "",
	},
	Realistic = {
		ShallowColor = Color3.fromRGB(38, 118, 148),
		DeepColor = Color3.fromRGB(10, 52, 92),
		FoamColor = Color3.fromRGB(236, 244, 246),
		UnderwaterTint = Color3.fromRGB(10, 52, 92),
		UnderwaterOpacity = 0.7,
		Reflectance = 0.35,
		FoamStyle = "Animated",
		FoamStart = 0.3,
		FoamFull = 0.7,
		FoamOpacity = 0.8,
		FilmOpacity = 0.03,
		SplashRate = 4,
		WaterMaterial = "Snow",
		WaterTexture = "",
		FoamTexture = "",
	},
}

-- names from before the presets were reduced, for weather lists and zones saved with them
Presets.Aliases = { Storm = "Pirate Seas", ["Deep Sea"] = "Oil Rig", Flat = "Blank", Calm = "Island" }

Presets.Ocean = {
	-- the default: a calm sea around an island or landmass
	Island = merge(Presets.Physics.Calm, Presets.Visual.Classic),
	["Pirate Seas"] = merge(Presets.Physics.Rough, Presets.Visual.Stylized),
	["Oil Rig"] = merge(Presets.Physics.Huge, Presets.Visual.Realistic),
	["Great Flood"] = merge(Presets.Physics.Tsunami, Presets.Visual.Realistic),
	-- still water and the plainest look, to build your own from
	Blank = merge(Presets.Physics.Still, Presets.Visual.Classic, {
		FoamStyle = "None",
		FilmOpacity = 0,
		SplashRate = 0,
		Reflectance = 0,
	}),
}

return Presets

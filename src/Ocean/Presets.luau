-- Ready-made overrides: Ocean:CreateWeather("Storm", Ocean.Presets.Storm).
-- Plain data - nothing registers these for you (the Studio debug menu does, for testing).
-- The plugin splits each into an Ocean preset (waves/physics) and a Visual preset (look) by section;
-- Cartoony / Realistic / Minimal are look-only, Floaty / Heavy Seas / Submarine are physics-only.
-- Weather ignores non-weather keys (materials, textures, physics).
local Presets = {}

local function waves(list: { { number } }, into: { [string]: any }): { [string]: any }
	for i, wave in list do
		into[`Wave{i}Angle`], into[`Wave{i}Length`], into[`Wave{i}Steepness`] = wave[1], wave[2], wave[3]
	end
	return into
end

Presets.Storm = waves({
	{ 25, 420, 0.14 },
	{ -20, 260, 0.16 },
	{ 60, 160, 0.16 },
	{ -55, 100, 0.14 },
	{ 110, 64, 0.11 },
	{ 5, 48, 0.09 },
}, {
	WaveGravity = 90,
	ShallowColor = Color3.fromRGB(86, 128, 138),
	DeepColor = Color3.fromRGB(34, 62, 78),
	FoamColor = Color3.fromRGB(226, 234, 236),
	FoamStart = 0.05,
	FoamFull = 0.4,
	SplashRate = 18,
	SplashHeight = 0.28,
})

Presets.Flat = waves({
	{ 15, 320, 0.015 },
	{ -30, 190, 0.015 },
	{ 50, 120, 0.01 },
	{ -65, 80, 0.01 },
	{ 100, 56, 0 },
	{ -10, 48, 0 },
}, {
	ShallowColor = Color3.fromRGB(70, 150, 170),
	DeepColor = Color3.fromRGB(44, 116, 146),
	FoamOpacity = 0,
	SplashRate = 0,
})

Presets["Deep Sea"] = waves({
	{ 10, 600, 0.08 }, -- long, slow open-ocean swell
	{ -25, 380, 0.08 },
	{ 40, 200, 0.07 },
	{ -60, 120, 0.06 },
	{ 95, 70, 0.05 },
	{ -5, 48, 0.04 },
}, {
	WaveGravity = 45,
	ShallowColor = Color3.fromRGB(30, 110, 150),
	DeepColor = Color3.fromRGB(8, 40, 80),
	FoamColor = Color3.fromRGB(220, 235, 240),
	FoamStart = 0.35,
	FoamFull = 0.85,
	SplashRate = 1,
})

Presets.Cartoony = {
	ShallowColor = Color3.fromRGB(90, 214, 232),
	DeepColor = Color3.fromRGB(28, 140, 205),
	FoamColor = Color3.fromRGB(255, 255, 255),
	Reflectance = 0,
	FoamStart = 0.15,
	FoamFull = 0.5,
	FoamOpacity = 1,
	FilmOpacity = 0.1,
	SplashRate = 8,
	WaterMaterial = "SmoothPlastic",
	WaterTexture = "",
	FoamTexture = "",
}

Presets.Realistic = {
	ShallowColor = Color3.fromRGB(38, 118, 148),
	DeepColor = Color3.fromRGB(10, 52, 92),
	FoamColor = Color3.fromRGB(236, 244, 246),
	Reflectance = 0.35,
	FoamStart = 0.3,
	FoamFull = 0.7,
	FoamOpacity = 0.8,
	FilmOpacity = 0.03,
	SplashRate = 4,
	WaterMaterial = "Snow",
	WaterTexture = "",
	FoamTexture = "",
}

Presets.Minimal = {
	ShallowColor = Color3.fromRGB(72, 152, 190),
	DeepColor = Color3.fromRGB(58, 132, 176),
	Reflectance = 0,
	FoamOpacity = 0,
	FilmOpacity = 0,
	SplashRate = 0,
	WaterMaterial = "SmoothPlastic",
	WaterTexture = "",
	FoamTexture = "",
}

-- physics-only looks (Weather ignores these keys; the plugin shows them as Physics presets)
Presets.Floaty = { WaterDensity = 1.4, LinearDrag = 1, MaxLift = 2, SwimSpring = 45 }
Presets["Heavy Seas"] = { WaterDensity = 0.9, LinearDrag = 3, AngularDrag = 4, MaxLift = 1.2, SwimIdleDrag = 4 }
Presets.Submarine = { BuoyancyFalloffDepth = 20, DeepBuoyancy = 0.5, LinearDrag = 2.5, AngularDrag = 3 }

return Presets

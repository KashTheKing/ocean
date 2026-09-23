--[[
	Every tunable is an attribute on the Ocean ModuleScript (the "host"). The server writes them,
	so they replicate; the Studio plugin and the debug menu are both generated from Settings.List.

	Entries marked Weather = true are what a weather type may override (see Weather.luau); the
	attribute values themselves are the "Default" weather.
]]
local Settings = {}

Settings.WAVE_COUNT = 6

export type Entry = {
	Name: string,
	Default: number | boolean | Color3 | string,
	Section: string,
	Min: number?,
	Max: number?,
	Step: number?,
	Weather: boolean?,
	Rebuild: boolean?, -- changing it rebuilds the mesh
	Options: { string }?, -- string settings with a fixed set of choices
	Hint: string?,
}

local function num(name, default, min, max, step, section, extra): Entry
	local entry = { Name = name, Default = default, Min = min, Max = max, Step = step, Section = section }
	for key, value in extra or {} do
		entry[key] = value
	end
	return entry
end

local W = { Weather = true }

Settings.List = {
	-- Physics: everything the surface height itself depends on lives here, not under Visuals
	num("SeaLevel", 0, -500, 500, 1, "Physics"),
	num("WaveGravity", 60, 5, 400, 1, "Physics", { Weather = true, Hint = "Only drives wave speed: c = sqrt(g / k)" }),
	num("TimeScale", 1, 0, 3, 0.05, "Physics", { Hint = "Wave clock speed. Changing it jumps the phase." }),
	{
		Name = "UseWind",
		Default = false,
		Section = "Physics",
		Hint = "Waves follow workspace.GlobalWind: the Wave angles become offsets from the wind direction",
	},
	{ Name = "BuoyancyEnabled", Default = true, Section = "Physics", Hint = 'Floats parts tagged "OceanFloat"' },
	num("WaterDensity", 1, 0.1, 5, 0.05, "Physics", { Hint = "Plastic is 0.7, so it floats ~70% submerged" }),
	num("LinearDrag", 1.5, 0, 10, 0.1, "Physics"),
	num("AngularDrag", 2, 0, 10, 0.1, "Physics"),
	num("MaxLift", 1.3, 1, 6, 0.05, "Physics", {
		Hint = "Cap on total lift, x the part's weight. Stops a dunked raft launching itself into the air",
	}),
	num("BuoyancyFalloffDepth", 40, 1, 500, 1, "Physics", {
		Hint = "Lift fades from full at the surface to DeepBuoyancy this many studs down (submarines)",
	}),
	num("DeepBuoyancy", 0.7, 0, 1, 0.01, "Physics", { Hint = "Lift multiplier once deeper than the falloff depth" }),
	{ Name = "SwimEnabled", Default = true, Section = "Physics", Hint = "Characters swim in the ocean" },
	num("SwimSpring", 30, 5, 120, 1, "Physics", { Hint = "How stiffly a swimmer is held at the surface" }),
	num("SwimIdleDrag", 3, 0, 10, 0.1, "Physics"),

	{
		Name = "Quality",
		Default = "Regular",
		Options = { "Fast", "Regular", "Realistic" },
		Section = "Visuals",
		Rebuild = true,
		Hint = "Fast: a quarter of the vertices, no film. Regular: lighter mesh, colours at half rate. Realistic: full mesh, everything every frame.",
	},
	{
		Name = "ShallowColor",
		Default = Color3.fromRGB(40, 140, 165),
		Section = "Visuals",
		Weather = true,
		Hint = "Crests",
	},
	{
		Name = "DeepColor",
		Default = Color3.fromRGB(14, 72, 118),
		Section = "Visuals",
		Weather = true,
		Hint = "Troughs",
	},
	{ Name = "FoamColor", Default = Color3.fromRGB(255, 255, 255), Section = "Visuals", Weather = true },
	num("NightBrightness", 0.55, 0, 1, 0.01, "Visuals", { Hint = "Colour multiplier once the sun is down" }),
	num("Reflectance", 0.2, 0, 1, 0.01, "Visuals"),
	-- heights below are fractions of the tallest possible crest (sum of wave amplitudes)
	num("FoamStart", 0.2, -1, 1, 0.01, "Visuals", W),
	num("FoamFull", 0.55, -1, 1, 0.01, "Visuals", W),
	num("FoamOpacity", 0.95, 0, 1, 0.01, "Visuals", W),
	num(
		"WebOpacity",
		0,
		0,
		1,
		0.01,
		"Visuals",
		{ Weather = true, Hint = "Faint foam web on all water (0 = only on crests)" }
	),
	num(
		"SplashRate",
		5,
		0,
		40,
		1,
		"Visuals",
		{ Weather = true, Hint = "Crest spray bursts per second near the camera" }
	),
	num("SplashHeight", 0.4, 0, 1, 0.01, "Visuals", W),
	num("FilmOpacity", 0.06, 0, 1, 0.01, "Visuals", {
		Weather = true,
		Hint = "Translucent white skin on the surface: things crossing it get a clear waterline",
	}),
	{
		Name = "WaterMaterial",
		Default = "SmoothPlastic",
		Section = "Visuals",
		Hint = "Any Enum.Material name: SmoothPlastic (flat), Foil (wet glints), Glass, Ice...",
	},
	{
		Name = "WaterTexture",
		Default = "",
		Section = "Visuals",
		Hint = "Image asset id tiled over the water (multiplies the colour), or blank for none",
	},
	{
		Name = "FoamTexture",
		Default = "",
		Section = "Visuals",
		Hint = "Image asset id for the crest foam (white with alpha), or blank for the built-in animated rings",
	},

	num("CellSize", 8, 2, 32, 1, "Advanced", { Rebuild = true, Hint = "Finest quad size (studs)" }),
	num(
		"InnerCells",
		24,
		4,
		44,
		1,
		"Advanced",
		{ Rebuild = true, Hint = "Full-detail cells each side (inner + outer <= 49)" }
	),
	num("OuterCells", 25, 4, 45, 1, "Advanced", { Rebuild = true, Hint = "LOD cells each side, each Growth x larger" }),
	num("Growth", 1.2, 1.02, 1.6, 0.01, "Advanced", { Rebuild = true }),
	num("HorizonDistance", 40000, 2000, 100000, 1000, "Advanced", { Rebuild = true }),
	{
		Name = "DebugMenu",
		Default = true,
		Section = "Advanced",
		Hint = "Show the Iris debug window in Studio playtests (needs ReplicatedStorage.Packages.Iris)",
	},
	-- the CollectionService tag names; rename to match tags your game already uses
	{ Name = "FloatTag", Default = "OceanFloat", Section = "Advanced", Hint = "Tag: unanchored parts float" },
	{
		Name = "ObstacleTag",
		Default = "OceanObstacle",
		Section = "Advanced",
		Hint = "Tag: the sea goes idle against it",
	},
	{ Name = "DryTag", Default = "OceanDry", Section = "Advanced", Hint = "Tag: no water inside it (experimental)" },
	{ Name = "TrackTag", Default = "OceanTrack", Section = "Advanced", Hint = "Tag: water events only" },
}

-- angle (deg), wavelength (studs), steepness. Keep the steepness sum well under 1 or crests pinch
-- into loops, and keep wavelengths >= 6 x CellSize or the mesh (not the physics) smooths them away.
local waveDefaults = {
	{ 15, 320, 0.1 }, -- long swell
	{ -30, 190, 0.12 },
	{ 50, 120, 0.15 }, -- peaky mid-size chop does most of the "rough sea" look
	{ -65, 80, 0.15 },
	{ 100, 56, 0.12 },
	{ -10, 48, 0.1 },
}
for i, wave in waveDefaults do
	table.insert(Settings.List, num(`Wave{i}Angle`, wave[1], -180, 180, 1, "Advanced", W))
	table.insert(Settings.List, num(`Wave{i}Length`, wave[2], 10, 1000, 1, "Advanced", W))
	table.insert(Settings.List, num(`Wave{i}Steepness`, wave[3], 0, 0.5, 0.01, "Advanced", W))
end

Settings.Defaults = {}
Settings.Spec = {} :: { [string]: Entry }
for _, entry in Settings.List do
	Settings.Defaults[entry.Name] = entry.Default
	Settings.Spec[entry.Name] = entry
end

local host: Instance = script.Parent

-- The plugin's edit-mode preview runs a clone of the module but reads the installed one's attributes.
function Settings.SetHost(instance: Instance)
	host = instance
end

function Settings.GetHost(): Instance
	return host
end

function Settings.Get(name: string): any
	local value = host:GetAttribute(name)
	if value == nil then
		return Settings.Defaults[name]
	end
	return value
end

-- Clamps/validates against the spec; returns the value stored, or nil if rejected.
function Settings.Set(name: string, value: any): any
	local entry = Settings.Spec[name]
	if not entry or typeof(value) ~= typeof(entry.Default) or value ~= value then
		return nil
	end
	if typeof(value) == "number" then
		value = math.clamp(value, entry.Min :: number, entry.Max :: number)
	end
	host:SetAttribute(name, value)
	return value
end

function Settings.OnChanged(fn: (name: string) -> ()): RBXScriptConnection
	return host.AttributeChanged:Connect(fn)
end

-- Server: make every setting a real attribute so it shows in Properties and replicates.
function Settings.PublishDefaults()
	for name, default in Settings.Defaults do
		if host:GetAttribute(name) == nil then
			host:SetAttribute(name, default)
		end
	end
end

function Settings.Reset()
	for name, default in Settings.Defaults do
		host:SetAttribute(name, default)
	end
end

return Settings

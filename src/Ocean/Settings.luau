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
	Snaps: { number }?, -- number settings whose slider lands on these values only
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
	num("SeaLevel", 0, -500, 500, 1, "General Physics"),
	{
		Name = "FlatSea",
		Default = false,
		Section = "General Physics",
		Hint = "No waves at all: the surface lies flat at SeaLevel with the same look (colours, film, foam style, tint). Buoyancy, swimming and water events work on that flat surface",
	},
	num("SeafloorHeight", -436, -10000, 10000, 1, "General Physics", {
		Hint = "World Y of the seafloor slab the plugin places (Placeholders). Kept under the deepest wave trough and that much above the fallen-parts height",
	}),
	num(
		"WaveGravity",
		60,
		5,
		400,
		1,
		"Wave Physics",
		{ Weather = true, Hint = "Only drives wave speed: c = sqrt(g / k)" }
	),
	num("WaveHeight", 1, 0, 2.5, 0.05, "Wave Physics", {
		Weather = true,
		Hint = "Overall wave height: every wave's amplitude times this (past ~1.5 crests can pinch into loops)",
	}),
	num(
		"TimeScale",
		1,
		0,
		3,
		0.05,
		"Wave Physics",
		{ Hint = "Overall wave speed: the wave clock runs this many times faster. Changing it jumps the phase" }
	),
	{
		Name = "UseWind",
		Default = false,
		Section = "Wave Physics",
		Hint = "Waves follow workspace.GlobalWind: the Wave angles become offsets from the wind direction",
	},
	{
		Name = "BuoyancyEnabled",
		Default = true,
		Section = "Buoyancy Physics",
		Hint = 'Floats parts tagged "OceanFloat"',
	},
	num("WaterDensity", 1, 0.1, 5, 0.05, "Buoyancy Physics", { Hint = "Plastic is 0.7, so it floats ~70% submerged" }),
	num("LinearDrag", 1.5, 0, 10, 0.1, "Buoyancy Physics"),
	num("AngularDrag", 2, 0, 10, 0.1, "Buoyancy Physics"),
	num("MaxLift", 1.3, 1, 6, 0.05, "Buoyancy Physics", {
		Hint = "Cap on total lift, as a multiple of the part's weight",
	}),
	num("BuoyancyFalloffDepth", 40, 1, 500, 1, "Buoyancy Physics", {
		Hint = "Lift fades from full at the surface to DeepBuoyancy this many studs down (submarines)",
	}),
	num(
		"DeepBuoyancy",
		0.7,
		0,
		1,
		0.01,
		"Buoyancy Physics",
		{ Hint = "Lift multiplier once deeper than the falloff depth" }
	),

	{
		Name = "Quality",
		Default = "Regular",
		Options = { "Fast", "Regular", "Realistic" },
		Section = "Performance",
		Rebuild = true,
		Hint = "Fast: fewer animated vertices, no film layer, foam every fourth update. Regular: medium count, foam every other update. Realistic: full count, everything every update.",
	},
	{
		Name = "ShallowColor",
		Default = Color3.fromRGB(20, 110, 160),
		Section = "Visuals",
		Weather = true,
		Hint = "Crests",
	},
	{
		Name = "DeepColor",
		Default = Color3.fromRGB(12, 84, 131),
		Section = "Visuals",
		Weather = true,
		Hint = "Troughs",
	},
	{ Name = "FoamColor", Default = Color3.fromRGB(255, 255, 255), Section = "Visuals", Weather = true },
	num("NightBrightness", 0.55, 0, 1, 0.01, "Visuals", { Hint = "Colour multiplier once the sun is down" }),
	-- the underwater tint: a full-screen frame the module owns, shown while the camera is under
	{
		Name = "UnderwaterEnabled",
		Default = true,
		Section = "Visuals",
		Hint = "Tint the view while the camera is under the surface",
	},
	{
		Name = "UnderwaterTint",
		Default = Color3.fromRGB(12, 84, 131),
		Section = "Visuals",
		Weather = true,
		Hint = "Underwater tint colour",
	},
	num("UnderwaterOpacity", 0.6, 0, 1, 0.01, "Visuals", {
		Weather = true,
		Hint = "How strongly the underwater tint covers the view (0 = none)",
	}),
	num("Reflectance", 0.05, 0, 1, 0.01, "Visuals"),
	{
		Name = "FoamStyle",
		Default = "Animated",
		Options = { "Animated", "Texture", "Solid", "None" },
		Section = "Visuals",
		Rebuild = true,
		Hint = "Crest foam: Animated = the built-in moving rings; Texture = your FoamTexture image; Solid = plain FoamColor; None = no foam layer",
	},
	-- heights below are fractions of the tallest possible crest (sum of wave amplitudes)
	num("FoamStart", 0.45, -1, 1, 0.01, "Visuals", W),
	num("FoamFull", 0.9, -1, 1, 0.01, "Visuals", W),
	num("FoamOpacity", 0.35, 0, 1, 0.01, "Visuals", W),
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
		2,
		0,
		40,
		1,
		"Visuals",
		{ Weather = true, Hint = "Crest spray bursts per second near the camera (drawn by the WaterSplash addon)" }
	),
	num("SplashHeight", 0.4, 0, 1, 0.01, "Visuals", W),
	num("FilmOpacity", 0.05, 0, 1, 0.01, "Visuals", {
		Weather = true,
		Hint = "Translucent skin on the surface in the water's colour: things crossing it get a clear waterline",
	}),
	{
		Name = "WaterMaterial",
		Default = "SmoothPlastic",
		Section = "Visuals",
		Material = true,
		Hint = "A material name (SmoothPlastic, Foil, Glass, Ice...) or one of the place's MaterialVariants; an unknown name lands on the closest",
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
		Hint = "Image asset id for the crest foam (white with alpha), used when FoamStyle is Texture",
	},

	{
		Name = "StaticWaves",
		Default = false,
		Section = "Performance",
		Hint = "The waves hold still: the wave clock stops, so the surface (and everything floating on it) is built once and left",
	},
	{
		Name = "DynamicLighting",
		Default = true,
		Section = "Performance",
		Hint = "The water darkens with the sun (NightBrightness) as the day passes; off keeps daytime colours",
	},
	{
		Name = "DynamicColors",
		Default = true,
		Section = "Performance",
		Hint = "The crest foam follows the waves every update; off writes it once",
	},
	{
		Name = "Lit",
		Default = true,
		Section = "Performance",
		Hint = "The scene lights the water: shadows from parts and terrain and the sun's highlights fall on it. Off draws it unlit (Neon), flat colour only",
	},
	{
		Name = "Highlights",
		Default = true,
		Section = "Performance",
		Rebuild = true,
		Hint = "The translucent skin layer over the near water: the surface sheen and the waterline on things crossing it",
	},
	num("UpdateRate", 60, 15, 240, 1, "Performance", {
		Snaps = { 15, 24, 30, 45, 60, 72, 90, 120, 144, 165, 240 }, -- the slider lands on these; type anything else
		Hint = "How many times per second the surface mesh is updated",
	}),
	num("CellSize", 8, 2, 32, 1, "Performance", { Rebuild = true, Hint = "Finest quad size (studs)" }),
	num(
		"InnerCells",
		24,
		4,
		44,
		1,
		"Performance",
		{ Rebuild = true, Hint = "Full-detail cells each side (inner + outer at most 49)" }
	),
	num(
		"OuterCells",
		25,
		4,
		45,
		1,
		"Performance",
		{ Rebuild = true, Hint = "LOD cells each side, each Growth x larger" }
	),
	num("Growth", 1.2, 1.02, 1.6, 0.01, "Performance", { Rebuild = true }),
	num("RenderDistance", 40000, 2000, 100000, 1000, "Performance", {
		Rebuild = true,
		Hint = "How far the sea is drawn from the camera (studs): the flat horizon skirt reaches this far",
	}),
	-- the CollectionService tag names; rename to match tags your game already uses
	{ Name = "FloatTag", Default = "OceanFloat", Section = "Tags", Hint = "Tag: unanchored parts float" },
	{ Name = "ObstacleTag", Default = "OceanObstacle", Section = "Tags", Hint = "Tag: the sea goes idle against it" },
	{ Name = "DryTag", Default = "OceanDry", Section = "Tags", Hint = "Tag: the surface sinks under it" },
	{ Name = "TrackTag", Default = "OceanTrack", Section = "Tags", Hint = "Tag: water events only" },
	{
		Name = "ZoneTag",
		Default = "OceanZone",
		Section = "Tags",
		Hint = "Tag: an area with its own sea, physics and lighting",
	},
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
	table.insert(Settings.List, num(`Wave{i}Angle`, wave[1], -180, 180, 1, `Wave{i}`, W))
	table.insert(Settings.List, num(`Wave{i}Length`, wave[2], 10, 1000, 1, `Wave{i}`, W))
	table.insert(Settings.List, num(`Wave{i}Steepness`, wave[3], 0, 0.5, 0.01, `Wave{i}`, W))
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

-- Client-local overrides: values this client uses instead of the host's, for everything that
-- reads Settings.Get (the Zones addon sets the zone's look here for a player inside it, so the
-- whole sea takes that look for them). Never replicated, never written to the host.
local overrides: { [string]: any } = {}
local changed = Instance.new("BindableEvent")

function Settings.LocalOverride(name: string): any
	return overrides[name]
end

function Settings.SetLocalOverride(name: string, value: any)
	if overrides[name] == value then
		return
	end
	overrides[name] = value
	changed:Fire(name)
end

function Settings.Get(name: string): any
	local value = overrides[name]
	if value == nil then
		value = host:GetAttribute(name)
	end
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

export type Connection = { Disconnect: (self: Connection) -> () }

-- Fires for host attribute changes and for local overrides alike.
function Settings.OnChanged(fn: (name: string) -> ()): Connection
	local a = host.AttributeChanged:Connect(fn)
	local b = changed.Event:Connect(fn)
	return {
		Disconnect = function(_self)
			a:Disconnect()
			b:Disconnect()
		end,
	}
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

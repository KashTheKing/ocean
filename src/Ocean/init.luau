--[[
	Ocean: infinite EditableMesh Gerstner ocean, synced server/client. Just the ocean - no lighting,
	no weather effects. It exposes a weather API so other systems can drive the sea state.

		local Ocean = require(ReplicatedStorage.Ocean)
		Ocean.Init()   -- once on the server and once on each client (OceanServer/OceanClient do this)

	Weather (server only; replicates, and server physics + client visuals stay in step):
		Ocean:CreateWeather("Storm", Ocean.Presets.Storm)   -- a named set of setting overrides
		Ocean:SetWeather("Storm", 20)                       -- whole ocean, cross-faded over 20 s
		Ocean:CreateZone("Bay", { Position = Vector3.new(0, 0, 2000), Radius = 800, Weather = "Calm" })
		Ocean:SetZoneWeather("Bay", "Storm", 10)
		Ocean:RemoveZone("Bay")

	Queries (either side):
		Ocean:GetHeight(position) -> world Y of the surface above/below that point, right now
		Ocean:GetWeatherAt(position) -> name of the dominant weather there

	Settings are attributes on this ModuleScript (defaults in Ocean.Settings); the server owns them.
	Tags (CollectionService - add them from scripts, the plugin, or the Tag Editor):
		OceanFloat     unanchored BasePart floats (OceanBuoyancy / OceanDrag attributes tune it)
		OceanObstacle  part/model the sea goes idle against (OceanShore attribute = ring width)
		OceanDry       part/model with no water inside: submarine interiors, underwater rooms
		OceanTrack     just get water events for it
	Events (Ocean.EnteredWater / ExitedWater / WentUnderWater / WentAboveWater, each (instance)) fire
	for tagged instances and player characters. Queries: GetWaterHeight, GetDepth, IsUnderWater,
	IsAboveWater, IsDry, GetSurfaceNormal, GetWaterState, IsInWater, GetInstancesInWater.
	Characters swim automatically.
]]
local RunService = game:GetService("RunService")

local Ocean = {
	Settings = require(script.Settings),
	Waves = require(script.Waves),
	Weather = require(script.Weather),
	Presets = require(script.Presets),
	Regions = require(script.Regions),
	Tracker = require(script.Tracker),
}
-- Ocean.Tags.Float / .Obstacle / .Dry / .Track: the current tag names (FloatTag etc. settings)
Ocean.Tags = setmetatable({}, {
	__index = function(_, key: string)
		return Ocean.Settings.Get(key .. "Tag")
	end,
})
-- Signals: Ocean.EnteredWater:Connect(function(instance) ... end)
Ocean.EnteredWater = Ocean.Tracker.EnteredWater
Ocean.ExitedWater = Ocean.Tracker.ExitedWater
Ocean.WentUnderWater = Ocean.Tracker.WentUnderWater
Ocean.WentAboveWater = Ocean.Tracker.WentAboveWater

local started = false

function Ocean.Init()
	if started then
		return
	end
	started = true

	if RunService:IsServer() then
		Ocean.Settings.PublishDefaults()
	end
	Ocean.Waves.Init()
	Ocean.Regions.Init()
	Ocean.Tracker.Init()
	require(script.Buoyancy).Init() -- runs on both sides; each side only pushes parts it simulates

	if RunService:IsServer() and RunService:IsStudio() then
		require(script.Debug).InitServer()
	end

	if RunService:IsClient() then
		require(script.Renderer).Init()
		require(script.Splash).Init()
		require(script.Swim).Init()
		if RunService:IsStudio() then
			require(script.Debug).InitClient()
		end
	end
end

function Ocean:CreateWeather(name: string, overrides: { [string]: any })
	Ocean.Weather.Create(name, overrides)
end

function Ocean:SetWeather(name: string, transition: number?)
	Ocean.Weather.Set(name, transition)
end

function Ocean:GetWeather(): string
	return Ocean.Weather.State.Global.Current
end

function Ocean:CreateZone(name: string, zone: { Position: Vector3, Radius: number, Blend: number?, Weather: string })
	Ocean.Weather.CreateZone(name, zone)
end

function Ocean:SetZoneWeather(name: string, weatherName: string, transition: number?)
	Ocean.Weather.SetZone(name, weatherName, transition)
end

function Ocean:RemoveZone(name: string)
	Ocean.Weather.RemoveZone(name)
end

function Ocean:GetHeight(position: Vector3): number
	return Ocean.Waves.Height(position.X, position.Z)
end

---------------------------------------------------------------------------------------------
-- Water queries and events. Everything below works on both sides.
---------------------------------------------------------------------------------------------

-- Surface height (world Y) above/below the point right now. Alias of GetHeight.
function Ocean:GetWaterHeight(position: Vector3): number
	return Ocean.Waves.Height(position.X, position.Z)
end

-- How far under the surface the point is (negative = above). Ignores dry regions.
function Ocean:GetDepth(position: Vector3): number
	return Ocean.Waves.Height(position.X, position.Z) - position.Y
end

function Ocean:IsUnderWater(position: Vector3): boolean
	return position.Y < Ocean.Waves.Height(position.X, position.Z) and not Ocean.Regions.IsDry(position)
end

function Ocean:IsAboveWater(position: Vector3): boolean
	return not Ocean:IsUnderWater(position)
end

-- Inside an "OceanDry" region (submarine interior, underwater room)?
function Ocean:IsDry(position: Vector3): boolean
	return Ocean.Regions.IsDry(position)
end

-- Surface normal at the point (for aligning boats, spray, decals): sampled from the height field.
function Ocean:GetSurfaceNormal(position: Vector3): Vector3
	local d = 2
	local hx = Ocean.Waves.Height(position.X + d, position.Z) - Ocean.Waves.Height(position.X - d, position.Z)
	local hz = Ocean.Waves.Height(position.X, position.Z + d) - Ocean.Waves.Height(position.X, position.Z - d)
	return Vector3.new(-hx, 2 * d, -hz).Unit
end

-- Touching / Under / Depth for a tracked instance (tagged, or a character), or nil if not tracked.
function Ocean:GetWaterState(instance: Instance)
	return Ocean.Tracker.GetState(instance)
end

function Ocean:IsInWater(instance: Instance): boolean
	local state = Ocean.Tracker.GetState(instance)
	return state ~= nil and state.Touching
end

function Ocean:GetInstancesInWater(): { Instance }
	return Ocean.Tracker.GetInWater()
end

-- Tag helpers. Plain CollectionService tags underneath, so you can also just :AddTag yourself.
function Ocean:AddFloat(part: BasePart)
	part:AddTag(Ocean.Tags.Float)
end

function Ocean:RemoveFloat(part: BasePart)
	part:RemoveTag(Ocean.Tags.Float)
end

function Ocean:AddObstacle(instance: Instance)
	instance:AddTag(Ocean.Tags.Obstacle)
end

function Ocean:RemoveObstacle(instance: Instance)
	instance:RemoveTag(Ocean.Tags.Obstacle)
end

function Ocean:AddDryRegion(instance: Instance)
	instance:AddTag(Ocean.Tags.Dry)
end

function Ocean:RemoveDryRegion(instance: Instance)
	instance:RemoveTag(Ocean.Tags.Dry)
end

-- Get water events for something without floating it.
function Ocean:Track(instance: Instance)
	instance:AddTag(Ocean.Tags.Track)
end

function Ocean:Untrack(instance: Instance)
	instance:RemoveTag(Ocean.Tags.Track)
end

function Ocean:GetWeatherAt(position: Vector3): string
	local waves = Ocean.Waves
	local count = waves.Gather(waves.ZonesNear(), position.X, position.Z, workspace:GetServerTimeNow())
	local best, bestWeight = Ocean.Weather.DEFAULT, 0
	for i = 1, count do
		if waves.LayerWeights[i] > bestWeight then
			best, bestWeight = waves.LayerSets[i].Name, waves.LayerWeights[i]
		end
	end
	return best
end

-- Studio plugin: render the ocean in Edit mode. `host` is the installed module whose attributes to
-- read (this copy is a throwaway clone); the mesh lives under `into` (the Camera: never saved).
function Ocean.Preview(host: Instance, into: Instance)
	Ocean.Settings.SetHost(host)
	Ocean.Waves.Init()
	Ocean.Regions.Init()
	require(script.Renderer).Init(into)
end

function Ocean.StopPreview()
	require(script.Renderer).Stop()
	Ocean.Waves.Stop()
	Ocean.Regions.Stop()
end

return Ocean

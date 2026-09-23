--!native
--!optimize 2
--[[
	Gerstner wave math shared by the renderer (client) and the physics (both sides).
	Deterministic in (settings, weather state, server time), so only those ever replicate.

	Each weather type compiles to a "set": flat wave arrays plus its look (colours, foam). The sea at
	a point is a weighted sum of whole sets - "layers" - never a blend of wave parameters (blending
	wavelengths across space would scramble the phase). Layers = the zones covering that point
	(cross-fading at their rims) + the global weather for whatever weight is left, and each of those
	is two layers while it is transitioning.
]]
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Settings = require(script.Parent.Settings)
local Weather = require(script.Parent.Weather)

local Waves = {}

local N = Settings.WAVE_COUNT

export type Set = {
	Name: string,
	Length: { number },
	DirX: { number },
	DirZ: { number },
	Kx: { number },
	Kz: { number },
	Omega: { number },
	Amp: { number },
	MaxAmp: number, -- tallest possible crest (all waves in phase)
	Look: { [string]: any }, -- the non-wave weather settings, resolved
}

Waves.Sets = {} :: { [string]: Set }
Waves.SeaLevel = 0
Waves.MaxLength = 1 -- longest wavelength in any set (the renderer's "can this vertex move at all" bound)
Waves.Version = 0 -- bumps on every Refresh

-- Scratch output of Gather: layer i is LayerSets[i] at LayerWeights[i]. Reused, never allocate per call.
Waves.LayerSets = {} :: { Set }
Waves.LayerWeights = {} :: { number }

local timeScale = 1
local zones = {} :: { any } -- compiled: { X, Z, Radius, Inner, State = Weather.Zone }

local function buildSet(name: string): Set
	local look = Weather.Resolve(name)
	local set = {
		Name = name,
		Length = table.create(N, 1),
		DirX = table.create(N, 1),
		DirZ = table.create(N, 0),
		Kx = table.create(N, 0),
		Kz = table.create(N, 0),
		Omega = table.create(N, 0),
		Amp = table.create(N, 0),
		MaxAmp = 0,
		Look = look,
	}
	local g = look.WaveGravity
	-- UseWind: the configured angles become offsets around the wind direction (0 wind = as configured)
	local windAngle = 0
	if Settings.Get("UseWind") then
		local wind = workspace.GlobalWind
		if wind.X ~= 0 or wind.Z ~= 0 then
			windAngle = math.atan2(wind.Z, wind.X)
		end
	end
	for i = 1, N do
		local angle = math.rad(look[`Wave{i}Angle`]) + windAngle
		local length = look[`Wave{i}Length`]
		local k = 2 * math.pi / length
		local dx, dz = math.cos(angle), math.sin(angle)
		set.Length[i] = length
		set.DirX[i], set.DirZ[i] = dx, dz
		set.Kx[i], set.Kz[i] = k * dx, k * dz
		set.Omega[i] = math.sqrt(g * k) -- deep-water dispersion
		set.Amp[i] = look[`Wave{i}Steepness`] / k
		set.MaxAmp += set.Amp[i]
	end
	set.MaxAmp = math.max(set.MaxAmp, 1e-3)
	return set
end

function Waves.Refresh()
	Weather.Decode()
	table.clear(Waves.Sets)
	Waves.MaxLength = 1
	for _, name in Weather.Names() do
		local set = buildSet(name)
		Waves.Sets[name] = set
		Waves.MaxLength = math.max(Waves.MaxLength, table.unpack(set.Length))
	end

	table.clear(zones)
	for _, zone in Weather.State.Zones do
		table.insert(
			zones,
			{ X = zone.X, Z = zone.Z, Radius = zone.Radius, Inner = zone.Radius - zone.Blend, State = zone }
		)
	end

	Waves.SeaLevel = Settings.Get("SeaLevel")
	timeScale = Settings.Get("TimeScale")
	Waves.Version += 1
end

---------------------------------------------------------------------------------------------
-- Obstacles: tag a BasePart or Model "OceanObstacle" and the sea goes idle against it instead
-- of washing through. Each is a disc in XZ (its bounding circle); waves fade from full at
-- `OceanShore` studs out (attribute, default 40) to nothing inside. Same function on both sides,
-- so floats and swimmers calm down at the shore too.
-- Discs, refreshed twice a second. Good for islands, piers and slow ships; a long thin
-- breakwater gets a circle around it. Add an oriented-box branch if that ever matters.
---------------------------------------------------------------------------------------------

local DEFAULT_SHORE = 40
local obstacles = {} :: { any } -- { X, Z, Radius, Shore }
local obstacleTimer = 0

function Waves.RefreshObstacles()
	table.clear(obstacles)
	for _, instance in CollectionService:GetTagged(Settings.Get("ObstacleTag")) do
		if not instance:IsDescendantOf(workspace) then
			continue
		end
		local cframe, size
		if instance:IsA("Model") then
			cframe, size = instance:GetBoundingBox()
		elseif instance:IsA("BasePart") then
			cframe, size = instance.CFrame, instance.Size
		else
			continue
		end
		-- XZ extent of the rotated box, as a circle
		local right, look = cframe.RightVector, cframe.LookVector
		local ex = math.abs(right.X) * size.X + math.abs(cframe.UpVector.X) * size.Y + math.abs(look.X) * size.Z
		local ez = math.abs(right.Z) * size.X + math.abs(cframe.UpVector.Z) * size.Y + math.abs(look.Z) * size.Z
		local shore = instance:GetAttribute("OceanShore")
		table.insert(obstacles, {
			X = cframe.Position.X,
			Z = cframe.Position.Z,
			Radius = math.sqrt(ex * ex + ez * ez) / 2,
			Shore = math.max(if typeof(shore) == "number" then shore else DEFAULT_SHORE, 1),
		})
	end
end

-- Obstacles whose calming ring touches the circle (x, z, radius); nothing = all of them.
function Waves.ObstaclesNear(x: number?, z: number?, radius: number?): { any }
	if not x then
		return obstacles
	end
	local near = {}
	for _, o in obstacles do
		local dx, dz = o.X - x, o.Z - (z :: number)
		local reach = o.Radius + o.Shore + (radius :: number)
		if dx * dx + dz * dz < reach * reach then
			table.insert(near, o)
		end
	end
	return near
end

-- 1 = open water, 0 = inside an obstacle; smooth in between across the shore ring.
function Waves.Damp(list: { any }, x: number, z: number): number
	local factor = 1
	for _, o in list do
		local dx, dz = x - o.X, z - o.Z
		local d = math.sqrt(dx * dx + dz * dz) - o.Radius
		if d < o.Shore then
			local s = math.clamp(d / o.Shore, 0, 1)
			factor = math.min(factor, s * s * (3 - 2 * s))
			if factor <= 0 then
				break
			end
		end
	end
	return factor
end

local function tickObstacles(dt: number)
	obstacleTimer += dt
	if obstacleTimer >= 0.5 then
		obstacleTimer = 0
		Waves.RefreshObstacles()
	end
end

local connections: { RBXScriptConnection } = {}

function Waves.Init()
	Waves.Refresh()
	Waves.RefreshObstacles()
	table.insert(connections, Settings.OnChanged(Waves.Refresh)) -- any setting, or the replicated weather state
	table.insert(connections, RunService.Heartbeat:Connect(tickObstacles))
	table.insert(connections, workspace:GetPropertyChangedSignal("GlobalWind"):Connect(Waves.Refresh))
end

function Waves.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

-- Synced wave clock. (Weather fades use unscaled server time.)
function Waves.Time(): number
	return workspace:GetServerTimeNow() * timeScale
end

-- Zones whose disc touches the circle (x, z, radius): the renderer culls once per frame so its
-- per-vertex Gather only ever walks the few zones on screen. Pass nothing to get them all.
-- Linear scan. It runs once per frame, not per vertex, so it is fine into the thousands
-- of zones; drop an octree in here if you ever really have that many.
function Waves.ZonesNear(x: number?, z: number?, radius: number?): { any }
	if not x then
		return zones
	end
	local near = {}
	for _, zone in zones do
		local dx, dz = zone.X - x, zone.Z - (z :: number)
		local reach = zone.Radius + (radius :: number)
		if dx * dx + dz * dz < reach * reach then
			table.insert(near, zone)
		end
	end
	return near
end

function Waves.IsBlending(now: number): boolean
	return Weather.Alpha(Weather.State.Global, now) < 1
end

local function push(count: number, blend: any, weight: number, now: number): number
	local alpha = Weather.Alpha(blend, now)
	local sets, weights = Waves.LayerSets, Waves.LayerWeights
	local current = Waves.Sets[blend.Current] or Waves.Sets[Weather.DEFAULT]
	if alpha < 1 then
		count += 1
		sets[count] = Waves.Sets[blend.Previous] or current
		weights[count] = weight * (1 - alpha)
	end
	count += 1
	sets[count] = current
	weights[count] = weight * alpha
	return count
end

-- Fills LayerSets/LayerWeights for the point and returns the layer count. Weights sum to 1.
function Waves.Gather(zoneList: { any }, x: number, z: number, now: number): number
	local count, covered = 0, 0
	for _, zone in zoneList do
		local dx, dz = x - zone.X, z - zone.Z
		local d2 = dx * dx + dz * dz
		if d2 < zone.Radius * zone.Radius then
			local t = math.clamp((math.sqrt(d2) - zone.Inner) / (zone.Radius - zone.Inner), 0, 1)
			local weight = 1 - t * t * (3 - 2 * t)
			covered += weight
			count = push(count, zone.State, weight, now)
		end
	end
	if covered > 1 then -- overlapping zones: share the point between them
		for i = 1, count do
			Waves.LayerWeights[i] /= covered
		end
	elseif covered < 1 then
		count = push(count, Weather.State.Global, 1 - covered, now)
	end
	return count
end

local function displaceSet(set: Set, x: number, z: number, t: number): (number, number, number)
	local ox, oy, oz = 0, 0, 0
	local kx, kz, omega, amp, dirX, dirZ = set.Kx, set.Kz, set.Omega, set.Amp, set.DirX, set.DirZ
	for i = 1, N do
		local f = kx[i] * x + kz[i] * z - omega[i] * t
		local a = amp[i]
		local c = math.cos(f) * a
		ox += dirX[i] * c
		oz += dirZ[i] * c
		oy += math.sin(f) * a
	end
	return ox, oy, oz
end

-- Displacement of the rest-position surface point (x, z).
function Waves.Displace(x: number, z: number, t: number?, now: number?): (number, number, number)
	local clock = now or workspace:GetServerTimeNow()
	local time = t or clock * timeScale
	local count = Waves.Gather(zones, x, z, clock)
	local ox, oy, oz = 0, 0, 0
	for i = 1, count do
		local weight = Waves.LayerWeights[i]
		local dx, dy, dz = displaceSet(Waves.LayerSets[i], x, z, time)
		ox += dx * weight
		oy += dy * weight
		oz += dz * weight
	end
	if #obstacles > 0 then
		local damp = Waves.Damp(obstacles, x, z)
		ox, oy, oz = ox * damp, oy * damp, oz * damp
	end
	return ox, oy, oz
end

-- World-space surface height above (x, z). Gerstner waves shove points sideways, so we
-- fixed-point iterate to find which rest point landed on (x, z). 3 rounds is sub-0.25 stud.
function Waves.Height(x: number, z: number, t: number?, now: number?): number
	local clock = now or workspace:GetServerTimeNow()
	local time = t or clock * timeScale
	local px, pz = x, z
	local dy = 0
	for _ = 1, 3 do
		local dx, y, dz = Waves.Displace(px, pz, time, clock)
		px, pz, dy = x - dx, z - dz, y
	end
	return Waves.SeaLevel + dy
end

-- One weather setting blended at a point (numbers only), e.g. Waves.LookNumber("SplashRate", x, z).
function Waves.LookNumber(name: string, x: number, z: number): number
	local count = Waves.Gather(zones, x, z, workspace:GetServerTimeNow())
	local value = 0
	for i = 1, count do
		local set = Waves.LayerSets[i]
		value += (if name == "MaxAmp" then set.MaxAmp else set.Look[name]) * Waves.LayerWeights[i]
	end
	return value
end

-- Self-check: `require(game.ReplicatedStorage.Ocean.Waves).SelfTest()` in the command bar.
function Waves.SelfTest(): string
	Waves.Refresh()
	local t = 1234.5
	for _ = 1, 200 do
		local x, z = math.random(-5000, 5000), math.random(-5000, 5000)
		local dx, dy, dz = Waves.Displace(x, z, t)
		-- the surface point that started at (x, z) sits at (x + dx, z + dz); Height() must find it again
		local h = Waves.Height(x + dx, z + dz, t)
		assert(math.abs(h - (Waves.SeaLevel + dy)) < 0.4, `Height() inverse off by {h - Waves.SeaLevel - dy}`)
	end
	for _ = 1, 50 do -- layer weights must always sum to 1, zones or not
		local count =
			Waves.Gather(zones, math.random(-5000, 5000), math.random(-5000, 5000), workspace:GetServerTimeNow())
		local sum = 0
		for i = 1, count do
			sum += Waves.LayerWeights[i]
		end
		assert(math.abs(sum - 1) < 1e-6, `layer weights sum to {sum}`)
	end
	return "Waves.SelfTest ok"
end

return Waves

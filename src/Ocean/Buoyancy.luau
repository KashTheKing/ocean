--!native
--[[
	Floats every unanchored BasePart tagged "OceanFloat" on the synced Gerstner surface.

	Runs on server AND clients; each side only pushes parts it is simulating (ReceiveAge == 0),
	so network ownership just works: server-owned crates are pushed by the server, a boat a
	player owns is pushed by that player's client. Same wave function everywhere.

	Model: the part's box is cut into 8 octants. Each octant centre is a sample point that is
	pushed up (ApplyImpulseAtPosition) by the weight of water its octant displaces - rises into
	the crest, drops into the trough, and uneven submersion gives the righting torque - plus drag
	while wet.

	Lift fades with depth (BuoyancyFalloffDepth / DeepBuoyancy) so submarines can hold a depth with
	a per-part OceanBuoyancy near neutral, yet still bob up at the surface.

	With workspace.StreamingEnabled the server parks (anchors, attribute OceanParked) floats that are
	outside every player's StreamingTargetRadius and wakes them when someone comes near. Streaming
	off = every float is simulated.

	Per-part overrides (attributes on the part):
		OceanBuoyancy  number  lift multiplier (default 1; 0 sinks, 2 rides high)
		OceanDrag      number  drag multiplier (default 1)
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Regions = require(script.Parent.Regions)
local Settings = require(script.Parent.Settings)
local Waves = require(script.Parent.Waves)

local Buoyancy = {}

local SPEED_DRAG = 0.2 -- extra drag per stud/s of speed

local lifts = table.create(8, 0) -- scratch, per part
local points = table.create(8, Vector3.zero)

local OCTANTS = {}
for _, x in { -0.25, 0.25 } do
	for _, y in { -0.25, 0.25 } do
		for _, z in { -0.25, 0.25 } do
			table.insert(OCTANTS, Vector3.new(x, y, z))
		end
	end
end

local function step(dt: number)
	if not Settings.Get("BuoyancyEnabled") then
		return
	end
	local now = workspace:GetServerTimeNow()
	local t = Waves.Time()
	local density = Settings.Get("WaterDensity")
	local linearDrag = Settings.Get("LinearDrag")
	local angularDrag = Settings.Get("AngularDrag")
	local falloffDepth = Settings.Get("BuoyancyFalloffDepth")
	local deepBuoyancy = Settings.Get("DeepBuoyancy")
	local maxLift = Settings.Get("MaxLift")
	local gravity = workspace.Gravity
	local hasDry = #Regions.List() > 0

	-- StreamingEnabled: the server only simulates floats within streaming range of a player and
	-- anchors the rest (parked), so an ocean full of debris costs nothing until someone gets close.
	local focuses: { Vector3 }? = nil
	local reach = 0
	if RunService:IsServer() and workspace.StreamingEnabled then
		local list: { Vector3 } = {}
		-- StreamingTargetRadius isn't readable from scripts in every Studio build; fall back to its default
		local ok, radius = pcall(function()
			return (workspace :: any).StreamingTargetRadius
		end)
		reach = math.max(if ok and typeof(radius) == "number" then radius else 1024, 256)
		for _, player in Players:GetPlayers() do
			local focus = player.ReplicationFocus or (player.Character and player.Character.PrimaryPart)
			if focus and focus:IsA("BasePart") then
				table.insert(list, focus.Position)
			end
		end
		focuses = list
	end

	for _, part in CollectionService:GetTagged(Settings.Get("FloatTag")) do
		if not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
			continue
		end
		if focuses then
			local near = false
			local position = part.Position
			for _, focus in focuses :: { Vector3 } do
				if (focus - position).Magnitude < reach then
					near = true
					break
				end
			end
			if not near then
				if not part.Anchored then
					part.Anchored = true
					part:SetAttribute("OceanParked", true)
				end
				continue
			elseif part:GetAttribute("OceanParked") then
				part:SetAttribute("OceanParked", nil)
				part.Anchored = false
			end
		end
		if part.Anchored or part.ReceiveAge ~= 0 then
			continue
		end
		local cf, size = part.CFrame, part.Size
		local liftScale = part:GetAttribute("OceanBuoyancy") or 1
		local dragScale = part:GetAttribute("OceanDrag") or 1
		-- Box volume; wedges/meshes/hollow hulls float as if solid boxes. Tune those with
		-- the OceanBuoyancy attribute rather than teaching this about real hull volume.
		local octantVolume = size.X * size.Y * size.Z / 8
		local octantMass = part.Mass / 8 -- own mass, so multi-part assemblies don't double-count drag
		-- world-space vertical extent of one octant, whatever the part's orientation
		local octantHeight = (
			math.abs(cf.RightVector.Y) * size.X
			+ math.abs(cf.UpVector.Y) * size.Y
			+ math.abs(cf.LookVector.Y) * size.Z
		) / 2
		-- drag grows with speed (real water is quadratic): a raft hitting at 100 studs/s sheds most of
		-- it in the first frames instead of diving 30 studs and launching back out
		local speed = part.AssemblyLinearVelocity.Magnitude
		local drag = math.min((linearDrag + SPEED_DRAG * speed) * dragScale * dt, 1)

		-- Archimedes: lift is the weight of displaced water, so a light part (Wood is 0.35) gets up to
		-- 3x its weight when fully dunked and launches. MaxLift caps the total at a multiple of the
		-- part's own weight; the per-corner split (and so the righting torque) is kept.
		local wet, total = 0, 0
		for i, offset in OCTANTS do
			local p = cf:PointToWorldSpace(offset * size)
			local lift = 0
			if not (hasDry and Regions.IsDryFor(p, part)) then -- dry region: no water on this corner
				local depth = Waves.Height(p.X, p.Z, t, now) - p.Y
				local submerged = math.clamp(depth / octantHeight + 0.5, 0, 1)
				if submerged > 0 then
					wet += submerged / 8
					-- less lift the deeper you go: a pushed-under hull stays down, then bobs up near the top
					local depthScale = deepBuoyancy + (1 - deepBuoyancy) * math.clamp(1 - depth / falloffDepth, 0, 1)
					lift = density * liftScale * depthScale * octantVolume * submerged * gravity * dt
					part:ApplyImpulseAtPosition(part:GetVelocityAtPosition(p) * (-drag * octantMass * submerged), p)
				end
			end
			lifts[i], points[i] = lift, p
			total += lift
		end
		local cap = maxLift * part.Mass * gravity * dt
		local scale = if total > cap then cap / total else 1
		for i = 1, 8 do
			if lifts[i] > 0 then
				part:ApplyImpulseAtPosition(Vector3.new(0, lifts[i] * scale, 0), points[i])
			end
		end
		if wet > 0 then
			-- mass * size^2 / 6 stands in for the inertia tensor; it's a damper, exactness is moot
			local inertia = part.Mass * size.Magnitude ^ 2 / 6
			part:ApplyAngularImpulse(
				part.AssemblyAngularVelocity * (-math.min(angularDrag * dragScale * dt, 1) * inertia * wet)
			)
		end
	end
end

function Buoyancy.Init()
	RunService.PreSimulation:Connect(step)
end

return Buoyancy

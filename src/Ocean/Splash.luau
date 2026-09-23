-- Client-only: occasional smoke-puff spray on wave crests near the camera.
-- Rolls random surface points each frame; the ones riding high enough (SplashHeight, as a
-- fraction of the tallest possible crest) get a burst. Rate/height follow the weather at the
-- camera. Purely cosmetic, so not synced.
local RunService = game:GetService("RunService")

local Waves = require(script.Parent.Waves)

local POOL = 10
local MIN_RADIUS, MAX_RADIUS = 30, 320
local TRIES = 5 -- random points tested per wanted splash; most points aren't crests

local Splash = {}

local emitters: { ParticleEmitter } = {}
local nextIndex = 1
local budget = 0
local rng = Random.new()

local function makeEmitter(): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = "OceanSplash"
	attachment.Archivable = false
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false -- burst only, via :Emit()
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(240, 250, 255))
	e.LightEmission = 0.25
	e.LightInfluence = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 10) })
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.9, 1.7)
	e.Speed = NumberRange.new(9, 20)
	e.SpreadAngle = Vector2.new(40, 40)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, -30, 0)
	e.Drag = 2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Parent = attachment
	attachment.Parent = workspace.Terrain -- Terrain is the stock anchor for free-floating attachments
	return e
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local focus = camera.CFrame.Position
	budget = math.min(budget + Waves.LookNumber("SplashRate", focus.X, focus.Z) * dt, 3)
	if budget < 1 then
		return
	end
	local threshold = Waves.LookNumber("SplashHeight", focus.X, focus.Z) * Waves.LookNumber("MaxAmp", focus.X, focus.Z)
	local now = workspace:GetServerTimeNow()
	local t = Waves.Time()

	while budget >= 1 do
		budget -= 1
		for _ = 1, TRIES do
			local angle = rng:NextNumber(0, 2 * math.pi)
			local radius = rng:NextNumber(MIN_RADIUS, MAX_RADIUS)
			local x, z = focus.X + math.cos(angle) * radius, focus.Z + math.sin(angle) * radius
			local dx, dy, dz = Waves.Displace(x, z, t, now)
			if dy > threshold then
				local emitter = emitters[nextIndex]
				nextIndex = nextIndex % POOL + 1
				local attachment = emitter.Parent :: Attachment
				attachment.WorldPosition = Vector3.new(x + dx, Waves.SeaLevel + dy, z + dz)
				emitter:Emit(rng:NextInteger(5, 9))
				break
			end
		end
	end
end

function Splash.Init()
	for i = 1, POOL do
		emitters[i] = makeEmitter()
	end
	RunService.Heartbeat:Connect(step)
end

return Splash

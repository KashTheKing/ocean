--[[
	Client-only: the local character (which this client simulates) swims in the ocean.

	In the water -> GettingUp/Freefall/FallingDown/Ragdoll disabled + Humanoid forced into Swimming
	(the stock swim controls and animation then just work). But a forced Swimming state has no
	actual water around it: nothing holds the character up, and nothing slows it down, so a nudge
	would glide or spin it forever. We supply all of that: a critically damped float that rides the
	synced wave surface, water drag when there's no input, and spin damping.
	Out of the water (or standing on something in the shallows) -> states restored + GettingUp.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Regions = require(script.Parent.Regions)
local Settings = require(script.Parent.Settings)
local Waves = require(script.Parent.Waves)

-- depth = water surface minus root centre. > 0 means the water is above the waist.
local ENTER_DEPTH, EXIT_DEPTH = 0.5, -1.5 -- free-floating; the gap stops flicker at the boundary
local ENTER_DEPTH_GROUNDED, EXIT_DEPTH_GROUNDED = 1.25, 0.5 -- feet on something: wade until chest-deep
local REST_DEPTH = 1 -- float with the root this far under the surface (head out)
local SPIN_DRAG = 6 -- 1/s

local DISABLED_WHILE_SWIMMING = {
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
}

local Swim = {}
Swim.Swimming = false

local lastSurface: number? = nil
local recovering = false
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function setSwimming(humanoid: Humanoid, on: boolean)
	Swim.Swimming = on
	for _, state in DISABLED_WHILE_SWIMMING do
		humanoid:SetStateEnabled(state, not on)
	end
	-- GettingUp (not Freefall) on the way out: it stands the character back upright
	humanoid:ChangeState(if on then Enum.HumanoidStateType.Swimming else Enum.HumanoidStateType.GettingUp)
end

local function step(dt: number)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	local enabled = Settings.Get("SwimEnabled")
	if not (enabled and character and humanoid and root) or humanoid.Health <= 0 or humanoid.SeatPart then
		if Swim.Swimming and humanoid and humanoid.Health > 0 then
			setSwimming(humanoid, false)
		end
		Swim.Swimming, lastSurface = false, nil
		return
	end

	local position = root.Position
	local surface = Waves.Height(position.X, position.Z)
	local depth = surface - position.Y
	if Regions.IsDry(position) then
		depth = -math.huge -- inside a submarine / underwater room: no water here
	end

	rayParams.FilterDescendantsInstances = { character }
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 0.75
	local grounded = workspace:Raycast(position, Vector3.new(0, -reach, 0), rayParams) ~= nil

	local threshold
	if grounded then
		threshold = if Swim.Swimming then EXIT_DEPTH_GROUNDED else ENTER_DEPTH_GROUNDED
	else
		threshold = if Swim.Swimming then EXIT_DEPTH else ENTER_DEPTH
	end
	if (depth > threshold) ~= Swim.Swimming then
		setSwimming(humanoid, not Swim.Swimming)
	end
	if not Swim.Swimming then
		lastSurface = nil
		return
	end

	local state = humanoid:GetState()
	if
		state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.PlatformStanding
	then
		-- Ragdolled in the water: the engine only leaves Ragdoll/FallingDown through GettingUp, which
		-- we disabled, so a straight ChangeState(Swimming) is refused. Let it get up for one frame,
		-- then go back to swimming with the states locked down again.
		humanoid.PlatformStand = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		recovering = true
		root.AssemblyAngularVelocity = Vector3.zero
		return
	elseif recovering then
		recovering = false
		humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	elseif state ~= Enum.HumanoidStateType.Swimming and state ~= Enum.HumanoidStateType.Jumping then
		humanoid:ChangeState(Enum.HumanoidStateType.Swimming) -- engine still drops to Freefall after a jump, etc.
	end

	local mass = root.AssemblyMass
	local velocity = root.AssemblyLinearVelocity

	-- Float: spring toward REST_DEPTH under the surface, damped against the surface's own vertical
	-- speed (so we ride the swell instead of bobbing against it). Critically damped: c = 2 sqrt(k).
	local surfaceVelocity = if lastSurface then (surface - lastSurface) / dt else 0
	lastSurface = surface
	local k = Settings.Get("SwimSpring")
	local errorY = (surface - REST_DEPTH) - position.Y
	local wet = math.clamp((errorY + 2) / 2, 0, 1) -- fades out as we leave the water (jumping)
	local accel = workspace.Gravity + k * errorY - 2 * math.sqrt(k) * (velocity.Y - surfaceVelocity)
	accel = math.clamp(accel, 0, 3 * workspace.Gravity) * wet -- 0 = free fall; water never pulls you under

	-- Water drag the Swimming state doesn't have: stop gliding once the keys are released.
	local horizontal = Vector3.zero
	if humanoid.MoveDirection.Magnitude < 0.05 then
		horizontal = Vector3.new(velocity.X, 0, velocity.Z) * -math.min(Settings.Get("SwimIdleDrag") * dt, 1)
	end

	root:ApplyImpulseAtPosition((Vector3.new(0, accel * dt, 0) + horizontal) * mass, root.AssemblyCenterOfMass)
	-- mass * 2 stands in for the real inertia tensor; it's a damper, exactness is moot
	root:ApplyAngularImpulse(root.AssemblyAngularVelocity * (-math.min(SPIN_DRAG * dt, 1) * mass * 2))
end

function Swim.Init()
	RunService.PreSimulation:Connect(step)
end

return Swim

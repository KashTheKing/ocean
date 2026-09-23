-- Studio-only Iris debug menu. Ocean.Init() only requires this when RunService:IsStudio().
-- Edits go client -> server -> attribute / weather state, so every client and the server follow.
-- Iris is a soft dependency (ReplicatedStorage.Packages.Iris): no Iris, no menu, ocean still runs.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Presets = require(script.Parent.Presets)
local Settings = require(script.Parent.Settings)
local Waves = require(script.Parent.Waves)
local Weather = require(script.Parent.Weather)

local REMOTE_NAME = "DebugRemote"
local SPAWN_FOLDER = "OceanDebugSpawned"

local Debug = {}

local sections = {} -- ordered { Name, Entries }
for _, entry in Settings.List do
	local last = sections[#sections]
	if not last or last.Name ~= entry.Section then
		last = { Name = entry.Section, Entries = {} }
		table.insert(sections, last)
	end
	table.insert(last.Entries, entry)
end

---------------------------------------------------------------------------------------------
-- Server
---------------------------------------------------------------------------------------------

local SPAWNABLE = {
	-- Density: Roblox Wood is 0.35 and flings; these sit like loaded cargo (water is 1)
	{
		Name = "Crate",
		Size = Vector3.new(6, 6, 6),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 105, 60),
		Density = 0.8,
	},
	{
		Name = "Raft",
		Size = Vector3.new(28, 2, 18),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(120, 85, 50),
		Density = 0.75,
	},
	{
		Name = "Buoy",
		Size = Vector3.new(4, 12, 4),
		Material = Enum.Material.Plastic,
		Color = Color3.fromRGB(230, 60, 40),
		Density = 0.45,
	},
}

function Debug.InitServer()
	for name, overrides in Presets do -- so there is something to switch between while testing
		if not Weather.Exists(name) then
			Weather.Create(name, overrides)
		end
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Archivable = false
	remote.Parent = script.Parent

	local zoneCount = 0
	remote.OnServerEvent:Connect(function(_player, action, a, b)
		if action == "Set" then
			Settings.Set(a, b) -- validates name, type and range
		elseif action == "Reset" then
			Settings.Reset()
		elseif action == "Weather" then
			if typeof(a) == "string" and Weather.Exists(a) then
				Weather.Set(a, if typeof(b) == "number" then b else 0)
			end
		elseif action == "Zone" then
			if typeof(a) == "string" and Weather.Exists(a) and typeof(b) == "Vector3" then
				zoneCount += 1
				Weather.CreateZone(`Debug{zoneCount}`, { Position = b, Radius = 500, Weather = a })
			end
		elseif action == "ClearZones" then
			Weather.ClearZones()
		elseif action == "Spawn" then
			local def = nil
			for _, candidate in SPAWNABLE do
				if candidate.Name == a then
					def = candidate
				end
			end
			if def and typeof(b) == "Vector3" then
				local folder = workspace:FindFirstChild(SPAWN_FOLDER) or Instance.new("Folder")
				folder.Name = SPAWN_FOLDER
				folder.Parent = workspace
				local part = Instance.new("Part")
				part.Name = a
				part.Size, part.Material, part.Color = def.Size, def.Material, def.Color
				part.CustomPhysicalProperties = PhysicalProperties.new(def.Density, 0.4, 0.3)
				part.Position = b
				part:AddTag("OceanFloat")
				part.Parent = folder
			end
		elseif action == "Clear" then
			local folder = workspace:FindFirstChild(SPAWN_FOLDER)
			if folder then
				folder:ClearAllChildren()
			end
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------------

function Debug.InitClient()
	local packages = ReplicatedStorage:FindFirstChild("Packages")
	local irisModule = packages and packages:FindFirstChild("Iris")
	if not irisModule then
		print("[Ocean] Iris not found at ReplicatedStorage.Packages.Iris - debug menu disabled")
		return
	end
	local Iris = require(irisModule) :: any
	local Renderer = require(script.Parent.Renderer)
	local SurfaceTexture = require(script.Parent.SurfaceTexture)
	local remote = script.Parent:WaitForChild(REMOTE_NAME)

	local probe: any = nil
	-- Iris sizes buttons to its text metrics, which come out narrow here: give them twice the room
	local function button(label: string)
		return Iris.Button({ label, UDim2.fromOffset(math.max(70, #label * 12), 22) })
	end
	local eventLog = {}
	local Tracker = require(script.Parent.Tracker)
	for _, name in { "EnteredWater", "ExitedWater", "WentUnderWater", "WentAboveWater" } do
		Tracker[name]:Connect(function(instance)
			table.insert(eventLog, 1, `{name}: {instance.Name}`)
			if #eventLog > 5 then
				table.remove(eventLog)
			end
		end)
	end

	local function commit(name: string, value: any)
		Settings.Set(name, value) -- local echo so the widget doesn't fight the round trip
		remote:FireServer("Set", name, value)
	end

	local function settingWidget(entry)
		local name = entry.Name
		local current = Settings.Get(name)
		if typeof(current) == "number" then
			local slider = Iris.SliderNum({ name, entry.Step, entry.Min, entry.Max }, { number = Iris.State(current) })
			if slider.numberChanged() then
				commit(name, slider.state.number:get())
			elseif slider.state.number:get() ~= current then
				slider.state.number:set(current) -- changed elsewhere (reset, plugin, Properties panel)
			end
		elseif typeof(current) == "boolean" then
			local box = Iris.Checkbox({ name }, { isChecked = Iris.State(current) })
			if box.checked() or box.unchecked() then
				commit(name, box.state.isChecked:get())
			elseif box.state.isChecked:get() ~= current then
				box.state.isChecked:set(current)
			end
		elseif typeof(current) == "string" and entry.Options then
			Iris.Text({ name .. ": " .. current })
			Iris.SameLine()
			for _, option in entry.Options do
				if Iris.Button({ option }).clicked() then
					commit(name, option)
				end
			end
			Iris.End()
		elseif typeof(current) == "string" then
			local input = Iris.InputText({ name }, { text = Iris.State(current) })
			if input.textChanged() then
				commit(name, input.state.text:get())
			elseif input.state.text:get() ~= current then
				input.state.text:set(current)
			end
		elseif typeof(current) == "Color3" then
			local input = Iris.InputColor3({ name }, { color = Iris.State(current) })
			if input.numberChanged() then
				commit(name, input.state.color:get())
			elseif input.state.color:get() ~= current then
				input.state.color:set(current)
			end
		end
	end

	local function aheadOfCamera(): Vector3
		local cf = workspace.CurrentCamera.CFrame
		local p = cf.Position + cf.LookVector * Vector3.new(1, 0, 1) * 60
		return Vector3.new(p.X, Waves.Height(p.X, p.Z), p.Z)
	end

	Iris.Init(nil, nil, true)
	-- smaller text: at Iris' default 13 px the button labels overflow their frames in this menu
	Iris.UpdateGlobalConfig({ TextSize = 11, FramePadding = Vector2.new(6, 3), ItemSpacing = Vector2.new(6, 3) })
	Iris:Connect(function()
		if not Settings.Get("DebugMenu") then
			return -- toggled off (attribute / plugin): the window simply isn't drawn
		end
		Iris.Window(
			{ "Ocean Debug" },
			{ size = Iris.State(Vector2.new(400, 560)), position = Iris.State(Vector2.new(20, 120)) }
		)

		local stats = Renderer.Stats
		local cam = workspace.CurrentCamera.CFrame.Position
		Iris.Text({ `verts {stats.Vertices} ({stats.Active} animated)  tris {stats.Triangles}` })
		Iris.Text({
			string.format(
				"mesh %.2f ms  foam bake %d%%  surface y=%.1f",
				stats.UpdateMs,
				SurfaceTexture.BakeProgress * 100,
				Waves.Height(cam.X, cam.Z)
			),
		})
		Iris.Text({ `floating parts: {#CollectionService:GetTagged("OceanFloat")}` })

		Iris.CollapsingHeader({ "Weather", true })
		do
			local zones = 0
			for _ in Weather.State.Zones do
				zones += 1
			end
			local layers = if stats.Layers < 0
				then `per-vertex ({-stats.Layers} zones near)`
				else `{stats.Layers} uniform`
			Iris.Text({ `global: {Weather.State.Global.Current}   zones: {zones}   layers: {layers}` })
			local transition = Iris.SliderNum({ "Transition (s)", 1, 0, 60 }, { number = Iris.State(8) })
			for _, name in Weather.Names() do
				Iris.SameLine()
				if button(`Set {name}`).clicked() then
					remote:FireServer("Weather", name, transition.state.number:get())
				end
				if button(`Zone of {name} ahead`).clicked() then
					local cf = workspace.CurrentCamera.CFrame
					remote:FireServer("Zone", name, cf.Position + cf.LookVector * Vector3.new(1, 0, 1) * 700)
				end
				Iris.End()
			end
			if button("Clear zones").clicked() then
				remote:FireServer("ClearZones")
			end
		end
		Iris.End()

		Iris.CollapsingHeader({ "Water events (client side)" })
		if #eventLog == 0 then
			Iris.Text({ "none yet - walk into the water or spawn a float" })
		end
		for _, line in eventLog do
			Iris.Text({ line })
		end
		Iris.End()

		Iris.CollapsingHeader({ "Tools" })
		do
			Iris.SameLine()
			for _, kind in { "Crate", "Raft", "Buoy" } do
				if button(`Spawn {kind}`).clicked() then
					remote:FireServer("Spawn", kind, aheadOfCamera() + Vector3.new(0, 25, 0))
				end
			end
			Iris.End()
			Iris.SameLine()
			if button("Clear spawned").clicked() then
				remote:FireServer("Clear")
			end
			if button("Reset settings").clicked() then
				remote:FireServer("Reset")
			end
			Iris.End()

			-- A neon ball riding Waves.Height(): if it sits on the rendered surface, math == mesh.
			local probeBox = Iris.Checkbox({ "Surface probe (60 studs ahead)" })
			if probeBox.state.isChecked:get() then
				if not probe then
					local ball = Instance.new("Part")
					ball.Name = "OceanProbe"
					ball.Shape = Enum.PartType.Ball
					ball.Size = Vector3.one * 3
					ball.Material = Enum.Material.Neon
					ball.Color = Color3.fromRGB(255, 60, 200)
					ball.Anchored, ball.CanCollide, ball.CanQuery = true, false, false
					ball.Parent = workspace
					probe = ball
				end
				probe.Position = aheadOfCamera()
			elseif probe then
				probe:Destroy()
				probe = nil
			end
		end
		Iris.End()

		for _, section in sections do
			Iris.CollapsingHeader({ section.Name })
			for _, entry in section.Entries do
				settingWidget(entry)
			end
			Iris.End()
		end

		Iris.End()
	end)
end

return Debug

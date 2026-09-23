--!native
--!optimize 2
--[[
	Client-only. One EditableMesh that follows the camera = infinite ocean in every direction.

	LOD: the grid is uniform (CellSize) for InnerCells around the camera, then every cell outward
	is Growth x bigger, and the last one stretches to HorizonDistance. Each wave is faded out on
	vertices whose local spacing can't resolve its wavelength (< 6 cells per wave -> fading,
	< 3 -> gone), so the distance never aliases/shimmers. Vertices no wave can reach are static
	and skipped entirely each frame.

	The mesh snaps in whole texture tiles (a multiple of CellSize), so near vertices sit on a fixed
	world lattice and the foam texture lines up after every snap (no swimming).

	Meshes cap at 2048 studs only at creation, so we create it shrunk and move the verts after.

	Look: two MeshParts share the one live EditableMesh (same verts, zero extra animation cost).
	  base: flat SmoothPlastic x a per-vertex colour from wave height. No texture: a tiled pattern
	        always reads as a tiled pattern.
	  foam: animated foam-ring texture a hair above it; per-vertex ALPHA is the foam amount, so
	        rings exist only on the highest crests (FoamStart..FoamFull), and since the crests
	        travel while the texture stays put in the world, the foam keeps re-forming as waves pass.
	  film: a third, separate small mesh (the full-detail area only) of translucent white at FilmOpacity:
	        a faint bright skin on the surface, so anything crossing it gets a clear waterline.
	        Separate mesh because the shared one's vertex colours are the water tint, not white.
	Vertex alpha is only honoured on parts with Transparency > 0, hence FOAM_TRANSPARENCY; the base
	stays at exactly 0 (opaque = depth-sorted properly, no seeing far waves through near ones).

	Weather: with no zone near the camera every vertex shares the same 1-2 layers (fast path);
	otherwise layers are gathered per vertex so zones cross-fade in space. See Waves.luau.
]]
local AssetService = game:GetService("AssetService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Regions = require(script.Parent.Regions)
local Settings = require(script.Parent.Settings)
local SurfaceTexture = require(script.Parent.SurfaceTexture)
local Waves = require(script.Parent.Waves)

local Renderer = {}
Renderer.Stats = { Vertices = 0, Active = 0, Triangles = 0, UpdateMs = 0, Layers = 0 }

local BIND_NAME = "OceanSurface"
local FOAM_MATERIAL = Enum.Material.SmoothPlastic
local DEFAULT_MATERIAL = Enum.Material.SmoothPlastic
local TEXTURE_TILE = 32 -- studs per foam texture repeat
local FOAM_TRANSPARENCY = 0.02
local FOAM_LIFT = 0.1 -- studs above the base, to avoid z-fighting; the film sits above the foam
local FOAM_RADIUS = 640 -- studs from the camera; beyond this no foam / web is drawn at all
local FILM_LIFT = 0.35
local DRY_REFRESH = 0.25 -- s between re-evaluations of which vertices/quads a dry region takes
-- Not Neon: emissive glow ignores transparency and washes the whole near field white at any opacity.
local FILM_MATERIAL = Enum.Material.SmoothPlastic
local UNDERWATER_EFFECT = "OceanUnderwater" -- optional ColorCorrectionEffect in Lighting, enabled while the camera is under
local MAX_CELLS_PER_SIDE = 49
local BEHIND_MARGIN = 48 -- studs behind the camera plane before a vertex counts as "behind"
local BEHIND_EVERY = 4 -- behind-camera vertices update every Nth frame (they still exist for turns)

-- Quality tiers, applied on top of the Advanced mesh settings. Vertex count is what the frame
-- cost scales with (every animated vertex is a SetPosition + a mesh re-upload), so Fast quarters it.
local QUALITY = {
	Fast = {
		CellScale = 2,
		InnerScale = 0.5,
		OuterScale = 0.5,
		Film = false,
		SmoothFoam = false,
		ColorEvery = 4,
		FarEvery = 3,
	},
	Regular = {
		CellScale = 1.25,
		InnerScale = 0.8,
		OuterScale = 0.8,
		Film = true,
		SmoothFoam = true,
		ColorEvery = 2,
		FarEvery = 2,
	},
	Realistic = {
		CellScale = 1,
		InnerScale = 1,
		OuterScale = 1,
		Film = true,
		SmoothFoam = true,
		ColorEvery = 1,
		FarEvery = 1,
	},
}
local quality = QUALITY.Regular
local qCell, qInner, qOuter = 8, 24, 25 -- the tier-scaled mesh settings in force
local N = Settings.WAVE_COUNT
local NO_ZONES = {}

local mesh: EditableMesh? = nil
local part: MeshPart? = nil
local foamPart: MeshPart? = nil
local filmMesh: EditableMesh? = nil
local filmPart: MeshPart? = nil
local filmIds: { number } = {} -- surface vertex index -> film vertex id (full-detail area only)
local parent: Instance = workspace
local buildToken = 0
local running = false
local connection: RBXScriptConnection? = nil

-- per-vertex flat arrays
local ids: { number } = {}
local colorIds: { number } = {}
local alphas: { number } = {} -- last alpha written per vertex
local baseX: { number } = {}
local baseZ: { number } = {}
local invSpacing: { number } = {} -- 1 / (3 x largest adjacent cell): wavelength x this - 1 = LOD weight
local near: { number } = {} -- full-detail vertices some wave can move: updated every frame
local far: { number } = {} -- LOD-ring vertices: updated every other frame, all together
local static: { number } = {}
local colorKeys: { number } = {} -- quantised tint last written per vertex
local uvIds: { number } = {}
local gridN = 0
-- Dry regions cut the mesh: a vertex resting inside a box is pinned to its wall (at surface
-- height, so the water meets the wall cleanly), and a quad with all four corners inside has its
-- two faces removed from the mesh. Re-evaluated on re-centre and every DRY_REFRESH.
local TRIS = { { 1, 3, 2 }, { 1, 4, 3 } } -- the two triangles of a quad, as corner indices a b c d
local quadFaces: { { number | false } } = {} -- quad -> its two face ids, false while cut
local filmQuadFaces: { { number | false }? } = {}
local filmQuadVerts: { { number }? } = {} -- quad -> the four film vertex ids (near area only)
local filmQuadColors: { { number }? } = {}
local pinned: { { number }? } = {} -- vertex -> { dx, dz, topY } offset that puts it on the wall, and the box top
local dryTimer = 0
local dryCount = -1
local frame = 0
local lastOx, lastOz = math.huge, math.huge
local snap = 32
-- Continuous LOD: the fade of each wave depends on distance from the TRUE camera position, via
-- the grid's own spacing law spacing(d) = cell + (d - innerRadius) * (growth - 1) / growth, not on
-- which ring a vertex happens to sit in. Ring-based weights jumped every time the mesh re-centred,
-- which read as waves popping in/out while moving.
local lodCell, lodInner, lodSlope = 8, 0, 0
local animatedRadius = 0
local seenVersion = -1
local seenNight = -1

-- blended look for the current vertex / frame (flat, to stay allocation-free in the hot loop)
local lookMaxAmp, lookFoamStart, lookFoamFull, lookFoamOpacity, lookWebOpacity = 1, 0, 1, 1, 0
local deepR, deepG, deepB, shallowR, shallowG, shallowB, foamR, foamG, foamB = 0, 0, 0, 0, 0, 0, 1, 1, 1

local function lcm(a: number, b: number): number
	local x, y = a, b
	while y ~= 0 do
		x, y = y, x % y
	end
	return a * b / x
end

local function applyQuality()
	quality = QUALITY[Settings.Get("Quality")] or QUALITY.Regular
	qCell = Settings.Get("CellSize") * quality.CellScale
	local inner = math.floor(Settings.Get("InnerCells") * quality.InnerScale)
	local outer = math.floor(Settings.Get("OuterCells") * quality.OuterScale)
	-- EditableMesh caps at 20k triangles = 100x100 quads = 50 cells per side, one of which is the skirt.
	-- Single mesh; split into a few MeshParts if you ever need more than 49 cells a side.
	qInner = math.clamp(inner, 2, MAX_CELLS_PER_SIDE - 1)
	qOuter = math.clamp(outer, 1, MAX_CELLS_PER_SIDE - qInner)
	SurfaceTexture.SetSmooth(quality.SmoothFoam)
end

local function buildAxis(): ({ number }, { number })
	local cell, inner, outer = qCell, qInner, qOuter
	local growth = Settings.Get("Growth")

	local half = { 0 } -- coordinates from the centre outward
	local sizes = {} -- sizes[i] = cell between half[i] and half[i + 1]
	local size = cell
	for i = 1, inner + outer do
		if i > inner then
			size *= growth
		end
		sizes[i] = size
		half[i + 1] = half[i] + size
	end
	-- horizon skirt: one giant cell, flat (no wave survives that spacing). Always at least 4x the
	-- animated area, whatever HorizonDistance says, so the skirt is never a thin animated rim.
	local horizon = math.max(Settings.Get("HorizonDistance"), half[#half] * 4)
	table.insert(sizes, horizon - half[#half])
	table.insert(half, horizon)

	local coords, space = {}, {}
	for i = #half, 2, -1 do
		table.insert(coords, -half[i])
		table.insert(space, sizes[i] or sizes[i - 1]) -- the larger (outer) neighbour cell
	end
	table.insert(coords, 0)
	table.insert(space, sizes[1])
	for i = 2, #half do
		table.insert(coords, half[i])
		table.insert(space, sizes[i] or sizes[i - 1])
	end
	return coords, space
end

-- Blend the look of the first `count` gathered layers into the look* locals.
local function blendLook(count: number)
	local sets, weights = Waves.LayerSets, Waves.LayerWeights
	lookMaxAmp, lookFoamStart, lookFoamFull, lookFoamOpacity, lookWebOpacity = 0, 0, 0, 0, 0
	deepR, deepG, deepB, shallowR, shallowG, shallowB, foamR, foamG, foamB = 0, 0, 0, 0, 0, 0, 0, 0, 0
	for i = 1, count do
		local set, w = sets[i], weights[i]
		local look = set.Look
		local deep, shallow, foam = look.DeepColor, look.ShallowColor, look.FoamColor
		lookMaxAmp += set.MaxAmp * w
		lookFoamStart += look.FoamStart * w
		lookFoamFull += look.FoamFull * w
		lookFoamOpacity += look.FoamOpacity * w
		lookWebOpacity += look.WebOpacity * w
		deepR += deep.R * w
		deepG += deep.G * w
		deepB += deep.B * w
		shallowR += shallow.R * w
		shallowG += shallow.G * w
		shallowB += shallow.B * w
		foamR += foam.R * w
		foamG += foam.G * w
		foamB += foam.B * w
	end
end

-- 1 by day, NightBrightness once the sun is down. The ocean only READS the sky; it never sets it.
-- "123456" / "rbxassetid://..." -> Content, "" -> nil
local function contentFrom(id: string): Content?
	local trimmed = (id:match("^%s*(.-)%s*$") :: string) or ""
	if trimmed:match("^%d+$") then
		return Content.fromUri("rbxassetid://" .. trimmed)
	elseif trimmed:match("^rbx") then
		return Content.fromUri(trimmed)
	end
	return nil
end

-- Material and textures from the settings; cheap, so re-run on any Visuals change.
local function applyLook()
	local base, foam = part, foamPart
	if not (base and foam) then
		return
	end
	local material = (Enum.Material :: any)[Settings.Get("WaterMaterial")]
	base.Material = if typeof(material) == "EnumItem" then material else DEFAULT_MATERIAL
	base.Reflectance = Settings.Get("Reflectance")
	base.TextureContent = contentFrom(Settings.Get("WaterTexture")) or Content.none
	foam.TextureContent = contentFrom(Settings.Get("FoamTexture")) or SurfaceTexture.Get()
end

local function nightFactor(): number
	local sun = math.clamp((Lighting:GetSunDirection().Y + 0.1) / 0.35, 0, 1)
	local night = Settings.Get("NightBrightness")
	return night + (1 - night) * sun * sun * (3 - 2 * sun)
end

local function refreshActive()
	local em = mesh
	if not em then
		return
	end
	table.clear(near)
	table.clear(far)
	table.clear(static)
	table.clear(colorKeys)
	animatedRadius = 0
	local fine = 1 / (3 * qCell) - 1e-9
	local active = 0
	for v = 1, #ids do
		-- a wave still moves this vertex if wavelength * invSpacing - 1 > 0
		if Waves.MaxLength * invSpacing[v] > 1 then
			active += 1
			if invSpacing[v] >= fine then
				table.insert(near, v)
			else
				table.insert(far, v)
			end
			animatedRadius = math.max(animatedRadius, math.abs(baseX[v]), math.abs(baseZ[v]))
		else
			table.insert(static, v)
			em:SetPosition(ids[v], Vector3.new(baseX[v], 0, baseZ[v]))
			em:SetColorAlpha(colorIds[v], 0)
			alphas[v] = 0
		end
	end
	Renderer.Stats.Active = active
	seenNight = -1 -- force a static recolour
end

local function recolourStatic(night: number)
	local em = mesh
	if not em then
		return
	end
	blendLook(Waves.Gather(NO_ZONES, 0, 0, workspace:GetServerTimeNow())) -- far water: global weather, calm height
	local colour =
		Color3.new((deepR + shallowR) / 2 * night, (deepG + shallowG) / 2 * night, (deepB + shallowB) / 2 * night)
	for _, v in static do
		em:SetColor(colorIds[v], colour)
	end
end

local function build()
	buildToken += 1
	local token = buildToken

	applyQuality()
	local coords, space = buildAxis()
	lodCell = qCell
	lodInner = qCell * qInner
	local growth = Settings.Get("Growth")
	lodSlope = (growth - 1) / growth
	local n = #coords
	local shrink = 1000 / coords[n] -- fit inside the 2048 creation cap; real positions are set right after
	local tile = lcm(qCell, TEXTURE_TILE)

	local em = AssetService:CreateEditableMesh()
	local newIds, bx, bz, inv = {}, {}, {}, {}
	local newColors, uvs = {}, {}
	for zi = 1, n do
		for xi = 1, n do
			local v = (zi - 1) * n + xi
			bx[v], bz[v] = coords[xi], coords[zi]
			inv[v] = 1 / (3 * math.max(space[xi], space[zi]))
			newIds[v] = em:AddVertex(Vector3.new(coords[xi] * shrink, 0, coords[zi] * shrink))
			newColors[v] = em:AddColor(Color3.new(1, 1, 1), 0)
			uvs[v] = em:AddUV(Vector2.new(coords[xi] / TEXTURE_TILE, coords[zi] / TEXTURE_TILE))
		end
	end
	local newQuadFaces = {}
	for zi = 1, n - 1 do
		for xi = 1, n - 1 do
			local a, b = (zi - 1) * n + xi, (zi - 1) * n + xi + 1
			local c, d = zi * n + xi + 1, zi * n + xi
			local faces: { number | false } = {}
			for _, tri in { { a, c, b }, { a, d, c } } do
				local face = em:AddTriangle(newIds[tri[1]], newIds[tri[2]], newIds[tri[3]])
				em:SetFaceColors(face, { newColors[tri[1]], newColors[tri[2]], newColors[tri[3]] })
				em:SetFaceUVs(face, { uvs[tri[1]], uvs[tri[2]], uvs[tri[3]] })
				table.insert(faces, face)
			end
			newQuadFaces[(zi - 1) * (n - 1) + xi] = faces
		end
	end

	-- film: the full-detail lattice only (|coord| <= inner radius), its own mesh
	local fm = AssetService:CreateEditableMesh()
	local newFilmIds = {}
	local innerIndex = {} -- xi -> position in the film grid
	local m = 0
	for xi = 1, n do
		if math.abs(coords[xi]) <= lodInner + 1e-3 then
			m += 1
			innerIndex[xi] = m
		end
	end
	local filmGrid = {} -- (row - 1) * m + col -> film vertex id
	local filmColors = {} -- same key -> colour id; alpha fades out over the outer third so the edge never shows
	local fadeStart = lodInner * 0.6
	for zi = 1, n do
		local row = innerIndex[zi]
		if row then
			for xi = 1, n do
				local col = innerIndex[xi]
				if col then
					local id = fm:AddVertex(Vector3.new(coords[xi], 0, coords[zi]))
					local edge = math.max(math.abs(coords[xi]), math.abs(coords[zi]))
					local t = math.clamp((edge - fadeStart) / (lodInner - fadeStart), 0, 1)
					filmGrid[(row - 1) * m + col] = id
					filmColors[(row - 1) * m + col] = fm:AddColor(Color3.new(1, 1, 1), 1 - t * t * (3 - 2 * t))
					newFilmIds[(zi - 1) * n + xi] = id
				end
			end
		end
	end
	local newFilmQuadFaces, newFilmQuadVerts, newFilmQuadColors = {}, {}, {}
	local rowOf = {} -- film row/col -> surface xi/zi
	for xi, col in innerIndex do
		rowOf[col] = xi
	end
	for row = 1, m - 1 do
		for col = 1, m - 1 do
			local a, b = (row - 1) * m + col, (row - 1) * m + col + 1
			local c, d = row * m + col + 1, row * m + col
			local faces: { number | false } = {}
			for _, tri in { { a, c, b }, { a, d, c } } do
				local face = fm:AddTriangle(filmGrid[tri[1]], filmGrid[tri[2]], filmGrid[tri[3]])
				fm:SetFaceColors(face, { filmColors[tri[1]], filmColors[tri[2]], filmColors[tri[3]] })
				table.insert(faces, face)
			end
			local q = (rowOf[row] - 1) * (n - 1) + rowOf[col] -- the surface quad this film quad sits on
			newFilmQuadFaces[q] = faces
			newFilmQuadVerts[q] = { filmGrid[a], filmGrid[b], filmGrid[c], filmGrid[d] }
			newFilmQuadColors[q] = { filmColors[a], filmColors[b], filmColors[c], filmColors[d] }
		end
	end

	local newPart = AssetService:CreateMeshPartAsync(Content.fromObject(em)) -- yields
	local newFoam = AssetService:CreateMeshPartAsync(Content.fromObject(em)) -- same live mesh
	local newFilm: MeshPart? = if quality.Film then AssetService:CreateMeshPartAsync(Content.fromObject(fm)) else nil
	if token ~= buildToken or not running then -- a newer build started (or we were stopped) while we yielded
		newPart:Destroy()
		newFoam:Destroy()
		if newFilm then
			newFilm:Destroy()
		end
		em:Destroy()
		fm:Destroy()
		return
	end

	for _, p in { newPart, newFoam, newFilm } do
		p.Anchored = true
		p.Locked = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Archivable = false -- never saved into the place, even when previewing in Edit mode
		p.Color = Color3.new(1, 1, 1) -- all tint comes from vertex colours
	end
	newPart.Name = "OceanSurface"
	newPart.DoubleSided = true -- visible from below too
	newFoam.Name = "OceanFoam"
	newFoam.Material = FOAM_MATERIAL
	newFoam.Transparency = FOAM_TRANSPARENCY
	newFoam.Parent = newPart
	if newFilm then
		newFilm.Name = "OceanFilm"
		newFilm.Material = FILM_MATERIAL
		newFilm.DoubleSided = true
		newFilm.Transparency = 1 - Settings.Get("FilmOpacity")
		newFilm.Parent = newPart
	end

	if part then
		part:Destroy()
	end
	if mesh then
		mesh:Destroy()
	end
	if filmMesh then
		filmMesh:Destroy()
	end
	mesh, part, foamPart = em, newPart, newFoam
	filmMesh, filmPart, filmIds = fm, newFilm, if newFilm then newFilmIds else {}
	applyLook()
	ids, baseX, baseZ, invSpacing = newIds, bx, bz, inv
	uvIds, gridN, quadFaces = uvs, n, newQuadFaces
	filmQuadFaces, filmQuadVerts, filmQuadColors = newFilmQuadFaces, newFilmQuadVerts, newFilmQuadColors
	table.clear(pinned)
	dryCount = -1
	colorIds, snap = newColors, tile
	table.clear(alphas)
	table.clear(colorKeys)
	Renderer.Stats.Vertices = n * n
	Renderer.Stats.Triangles = (n - 1) * (n - 1) * 2

	refreshActive()
	seenVersion = Waves.Version
	newPart.Parent = parent
end

-- Recompute which vertices a dry region pins and which quads it cuts, for the mesh centred at (ox, oz).
local function refreshDry(ox: number, oz: number)
	local em, fm = mesh, filmMesh
	if not em then
		return
	end
	local boxes = Regions.List()
	table.clear(pinned)
	if #boxes > 0 then
		for v = 1, #ids do
			local wx, wz = ox + baseX[v], oz + baseZ[v]
			for _, box in boxes do
				local bx, bz = wx - box.X, wz - box.Z
				if bx * bx + bz * bz < box.Reach * box.Reach then -- cheap prefilter, then the real box test
					-- corner snap radius = two cells: then no two grid-adjacent vertices can be pinned to
					-- different walls, so no triangle can bridge two walls across the interior
					local px, pz, inside = Regions.PushOut(box, wx, wz, 2 / (3 * invSpacing[v]))
					if inside then
						pinned[v] = { px - wx, pz - wz, box.Top }
						break
					end
				end
			end
		end
	end
	-- cut / restore quads whose four corners are all pinned (those would span the interior)
	local n = gridN
	for zi = 1, n - 1 do
		for xi = 1, n - 1 do
			local q = (zi - 1) * (n - 1) + xi
			local a, b = (zi - 1) * n + xi, (zi - 1) * n + xi + 1
			local c, d = zi * n + xi + 1, zi * n + xi
			-- per FACE: a triangle whose three corners are all pinned would span the interior (at a
			-- corner, two walls + the corner point still make a triangle inside), so it goes
			local faces = quadFaces[q]
			local filmFaces = filmQuadFaces[q]
			local fv, fc = filmQuadVerts[q], filmQuadColors[q]
			for i, tri in ipairs(TRIS) do
				local va, vb, vc = tri[1] == 1 and a or (tri[1] == 2 and b or (tri[1] == 3 and c or d)), 0, 0
				vb = tri[2] == 1 and a or (tri[2] == 2 and b or (tri[2] == 3 and c or d))
				vc = tri[3] == 1 and a or (tri[3] == 2 and b or (tri[3] == 3 and c or d))
				local cut = pinned[va] ~= nil and pinned[vb] ~= nil and pinned[vc] ~= nil
				if cut and faces[i] then
					em:RemoveFace(faces[i] :: number)
					faces[i] = false
					if fm and filmFaces and filmFaces[i] then
						fm:RemoveFace(filmFaces[i] :: number)
						filmFaces[i] = false
					end
				elseif not cut and not faces[i] then
					local face = em:AddTriangle(ids[va], ids[vb], ids[vc])
					em:SetFaceColors(face, { colorIds[va], colorIds[vb], colorIds[vc] })
					em:SetFaceUVs(face, { uvIds[va], uvIds[vb], uvIds[vc] })
					faces[i] = face
					if fm and filmFaces and fv and fc and not filmFaces[i] then
						local filmFace = fm:AddTriangle(fv[tri[1]], fv[tri[2]], fv[tri[3]])
						fm:SetFaceColors(filmFace, { fc[tri[1]], fc[tri[2]], fc[tri[3]] })
						filmFaces[i] = filmFace
					end
				end
			end
		end
	end
end

local function update()
	local em, mp, camera = mesh, part, workspace.CurrentCamera
	if not (em and mp and camera) then
		return
	end
	local started = os.clock()

	if seenVersion ~= Waves.Version then
		seenVersion = Waves.Version
		refreshActive() -- wavelengths may have changed which vertices can move
	end

	local focus = camera.CFrame.Position
	local fx, fz = focus.X, focus.Z
	local look = camera.CFrame.LookVector
	local lookX, lookZ = look.X, look.Z
	local lookLen = math.sqrt(lookX * lookX + lookZ * lookZ)
	if lookLen > 1e-3 then
		lookX, lookZ = lookX / lookLen, lookZ / lookLen
	else
		lookX, lookZ = 0, 0 -- straight down: nothing is "behind"
	end
	local ox = math.round(focus.X / snap) * snap
	local oz = math.round(focus.Z / snap) * snap
	local moved = ox ~= lastOx or oz ~= lastOz
	lastOx, lastOz = ox, oz
	local seaLevel = Waves.SeaLevel
	mp.CFrame = CFrame.new(ox, seaLevel, oz)
	if foamPart then
		foamPart.CFrame = CFrame.new(ox, seaLevel + FOAM_LIFT, oz)
	end
	local fm = filmMesh
	if filmPart then
		filmPart.CFrame = CFrame.new(ox, seaLevel + FILM_LIFT, oz)
	end

	local now = workspace:GetServerTimeNow()
	local t = Waves.Time()

	local tint = Lighting:FindFirstChild(UNDERWATER_EFFECT)
	if tint and tint:IsA("PostEffect") then
		tint.Enabled = focus.Y < Waves.Height(focus.X, focus.Z, t, now) and not Regions.IsDry(focus)
	end

	local night = nightFactor()
	if math.abs(night - seenNight) > 0.01 then
		seenNight = night
		recolourStatic(night)
	end

	-- Zones near the mesh force per-vertex layer gathering; otherwise gather once for everyone.
	local zones = Waves.ZonesNear(ox, oz, animatedRadius * 1.5)
	local obstacles = Waves.ObstaclesNear(ox, oz, animatedRadius * 1.5)
	local hasObstacles = #obstacles > 0
	local dry = Regions.Near(ox, oz, animatedRadius * 1.5)
	local hasDry = #dry > 0
	dryTimer += 1 / 60
	if moved or dryTimer >= DRY_REFRESH or #Regions.List() ~= dryCount then
		dryTimer = 0
		dryCount = #Regions.List()
		refreshDry(ox, oz)
	end
	local perVertex = #zones > 0
	local count = Waves.Gather(NO_ZONES, ox, oz, now) -- the global weather's layers
	blendLook(count)
	local globalLoaded = true
	Renderer.Stats.Layers = if perVertex then -#zones else count

	local sets, weights = Waves.LayerSets, Waves.LayerWeights
	local cos, sin, clamp, floor = math.cos, math.sin, math.clamp, math.floor
	local nightKey = floor(night * 100) * 4096
	local foamRadius2 = FOAM_RADIUS * FOAM_RADIUS

	frame += 1
	local colorPass = moved or frame % quality.ColorEvery == 0
	local updated = 0
	local behindPass = moved or frame % BEHIND_EVERY == 0
	-- Near vertices every frame; the coarser LOD ring at a lower rate, all of it on the same frames
	-- (staggering neighbours onto different frames shows as corrugation at grazing angles).
	-- The mesh just re-centred: every vertex must be placed against the new origin THIS frame, or the
	-- half-rate ring sits 32 studs off for a frame (the "chop" when moving fast).
	for _, list in { near, if moved or frame % quality.FarEvery == 0 then far else NO_ZONES } do
		for _, v in list do
			local lx, lz = baseX[v], baseZ[v]
			local wx, wz = ox + lx, oz + lz
			-- vertices behind the camera can't be seen: keep them alive at a low rate for when it turns
			if not behindPass and (wx - fx) * lookX + (wz - fz) * lookZ < -BEHIND_MARGIN then
				continue
			end
			updated += 1
			local ddx, ddz = wx - fx, wz - fz
			local inv = 1 / (3 * (lodCell + math.max(math.sqrt(ddx * ddx + ddz * ddz) - lodInner, 0) * lodSlope))
			if perVertex then
				-- only vertices actually inside a zone pay for their own blend; the rest share the global one
				local zoned = false
				for _, zone in zones do
					local zx, zz = wx - zone.X, wz - zone.Z
					if zx * zx + zz * zz < zone.Radius * zone.Radius then
						zoned = true
						break
					end
				end
				if zoned then
					count = Waves.Gather(zones, wx, wz, now)
					blendLook(count)
					globalLoaded = false
				elseif not globalLoaded then
					count = Waves.Gather(NO_ZONES, wx, wz, now)
					blendLook(count)
					globalLoaded = true
				end
			end

			-- A vertex pinned to a dry region's wall samples the waves AT the wall point, so every vertex
			-- collapsed onto the same wall point gets the same height (no vertical slivers) and the rim
			-- follows the real water line along the wall.
			local pin = pinned[v]
			local sx, sz = wx, wz
			if pin then
				sx, sz = wx + pin[1], wz + pin[2]
			end
			local dx, dy, dz = 0, 0, 0
			for i = 1, count do
				local set, layerWeight = sets[i], weights[i]
				local length, kx, kz, omega, amp, dirX, dirZ =
					set.Length, set.Kx, set.Kz, set.Omega, set.Amp, set.DirX, set.DirZ
				for w = 1, N do
					local lod = length[w] * inv - 1
					if lod > 0 then
						local f = kx[w] * sx + kz[w] * sz - omega[w] * t
						local a = amp[w] * layerWeight * (if lod > 1 then 1 else lod)
						local c = cos(f) * a
						dx += dirX[w] * c
						dz += dirZ[w] * c
						dy += sin(f) * a
					end
				end
			end
			local shore = 0 -- 0..1 how much this vertex is in an obstacle's calming ring
			if hasObstacles then
				local damp = Waves.Damp(obstacles, wx, wz)
				if damp < 1 then
					dx, dy, dz = dx * damp, dy * damp, dz * damp
					shore = damp * (1 - damp) * 4 -- peaks halfway across the ring: the "breaking" line
				end
			end
			if pin then
				-- rests inside a dry region: sits on the wall (faces fully inside are cut), never above
				-- the box top - a crest taller than the interior would open a window onto empty space
				dx, dz = pin[1], pin[2]
				dy = math.min(dy, pin[3] - seaLevel)
			elseif hasDry then
				-- outside, but the Gerstner shove would carry it in: clamp to the wall, with the same
				-- two-cell corner snap as pinned vertices (two shoved neighbours landing on different
				-- walls at a corner would otherwise bridge the interior)
				for _, box in dry do
					local cx, cz, shoved = Regions.PushOut(box, wx + dx, wz + dz, 2 / (3 * inv))
					if shoved then
						dx, dz = cx - wx, cz - wz
						break
					end
				end
			end
			local placed = Vector3.new(lx + dx, dy, lz + dz)
			em:SetPosition(ids[v], placed)
			local fid = filmIds[v]
			if fid and fm then
				fm:SetPosition(fid, placed)
			end

			if not colorPass then
				continue
			end
			-- waves are rarely all in phase, so real crests top out around 0.6 x MaxAmp
			local h = clamp(dy / lookMaxAmp * 0.85 + 0.5, 0, 1) -- 0 trough .. 1 crest
			local nearCamera = lx * lx + lz * lz < foamRadius2
			local foam = 0
			if nearCamera then -- foam and its web only near the camera
				foam = clamp((dy / lookMaxAmp - lookFoamStart) / math.max(lookFoamFull - lookFoamStart, 1e-3), 0, 1)
				foam = math.max(foam, shore * 0.6) -- wash against obstacles
			end
			-- colours are quantised to 64 steps and only written when the step changes: the mesh
			-- upload is the expensive part, and most frames the tint step is unchanged
			local key = nightKey + floor(h * 63) * 64 + floor(foam * 63)
			if key ~= colorKeys[v] then
				colorKeys[v] = key
				local r = deepR + (shallowR - deepR) * h
				local g = deepG + (shallowG - deepG) * h
				local b = deepB + (shallowB - deepB) * h
				local lighten = foam * 0.35 -- water under the foam goes a little pale; the rings do the rest
				em:SetColor(
					colorIds[v],
					Color3.new(
						(r + (foamR - r) * lighten) * night,
						(g + (foamG - g) * lighten) * night,
						(b + (foamB - b) * lighten) * night
					)
				)
				local alpha = if nearCamera then lookWebOpacity + (lookFoamOpacity - lookWebOpacity) * foam else 0
				if alpha ~= alphas[v] then
					alphas[v] = alpha
					em:SetColorAlpha(colorIds[v], alpha)
				end
			end
		end
	end

	Renderer.Stats.UpdateMs = (os.clock() - started) * 1000
	if frame % 30 == 0 then -- readable from anywhere (Properties panel, command bar) without a require
		mp:SetAttribute("UpdateMs", math.round(Renderer.Stats.UpdateMs * 100) / 100)
		mp:SetAttribute("Animated", Renderer.Stats.Active)
		mp:SetAttribute("Updated", updated)
	end
end

-- `into` lets the Studio plugin preview under the Camera (which is never saved with the place).
function Renderer.Init(into: Instance?)
	if running then
		return
	end
	running = true
	parent = into or workspace
	connection = Settings.OnChanged(function(name)
		local entry = Settings.Spec[name]
		if entry and entry.Rebuild then
			task.spawn(build)
		elseif name == "Reflectance" or name == "WaterMaterial" or name == "WaterTexture" or name == "FoamTexture" then
			applyLook()
		elseif name == "FilmOpacity" and filmPart then
			filmPart.Transparency = 1 - Settings.Get("FilmOpacity")
		elseif name == "NightBrightness" then
			seenNight = -1
		end
	end)
	task.spawn(build)
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, update)
end

function Renderer.Stop()
	if not running then
		return
	end
	running = false
	buildToken += 1
	RunService:UnbindFromRenderStep(BIND_NAME)
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if part then
		part:Destroy()
	end
	if mesh then
		mesh:Destroy()
	end
	if filmMesh then
		filmMesh:Destroy()
	end
	mesh, part, foamPart, filmMesh, filmPart = nil, nil, nil, nil, nil
	SurfaceTexture.Stop()
end

return Renderer

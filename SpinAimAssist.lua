--[[
	Spin + Aim Assist — 從 Modern client 抽出的獨立版
	只有這兩個模組，內建迷你 UI。

	快捷鍵:
		RightShift  顯示 / 隱藏面板
		X           切換 Spin
		C           切換 Aim Assist
]]

local Players = cloneref(game:GetService('Players'))
local RunService = cloneref(game:GetService('RunService'))
local UserInputService = cloneref(game:GetService('UserInputService'))
local TextService = cloneref(game:GetService('TextService'))
local GuiService = cloneref(game:GetService('GuiService'))
local CoreGui = cloneref(game:GetService('CoreGui'))

local lplr = Players.LocalPlayer
local gameCamera = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera')
RunService:GetPropertyChangedSignal('CurrentCamera'):Connect(function()
	gameCamera = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera')
end)

repeat task.wait() until game:IsLoaded()

--// ========================================================================
--// Entity library（原版抽換掉廣告 payload）
--// ========================================================================
local entitylib = {
	isAlive = false,
	character = {},
	List = {},
	Connections = {},
	PlayerConnections = {},
	EntityThreads = {},
	Running = false,
	Events = setmetatable({}, {
		__index = function(self, ind)
			self[ind] = {
				Connections = {},
				Connect = function(rself, func)
					table.insert(rself.Connections, func)
					return {
						Disconnect = function()
							local rind = table.find(rself.Connections, func)
							if rind then
								table.remove(rself.Connections, rind)
							end
						end
					}
				end,
				Fire = function(rself, ...)
					for _, v in rself.Connections do
						task.spawn(v, ...)
					end
				end,
				Destroy = function(rself)
					table.clear(rself.Connections)
					table.clear(rself)
				end
			}
			return self[ind]
		end
	})
}

local playersService = Players
local inputService = UserInputService

local function getMousePosition()
	if inputService.TouchEnabled then
		return gameCamera.ViewportSize / 2
	end
	return inputService:GetMouseLocation()
end

local function loopClean(tbl)
	for i, v in tbl do
		if type(v) == 'table' then
			loopClean(v)
		end
		tbl[i] = nil
	end
end

local function waitForChildOfType(obj, name, timeout, prop)
	local checktick = tick() + timeout
	local returned
	repeat
		returned = prop and obj[name] or obj:FindFirstChildOfClass(name)
		if returned or checktick < tick() then break end
		task.wait()
	until false
	return returned
end

entitylib.targetCheck = function(ent)
	if ent.TeamCheck then
		return ent:TeamCheck()
	end
	if ent.NPC then return true end
	if not lplr.Team then return true end
	if not ent.Player.Team then return true end
	if ent.Player.Team ~= lplr.Team then return true end
	return #ent.Player.Team:GetPlayers() == #playersService:GetPlayers()
end

entitylib.getUpdateConnections = function(ent)
	local hum = ent.Humanoid
	return {
		hum:GetPropertyChangedSignal('Health'),
		hum:GetPropertyChangedSignal('MaxHealth')
	}
end

entitylib.isVulnerable = function(ent)
	return ent.Health > 0 and not ent.Character:FindFirstChildWhichIsA('ForceField')
end

entitylib.getEntityColor = function(ent)
	ent = ent.Player
	return ent and tostring(ent.TeamColor) ~= 'White' and ent.TeamColor.Color or nil
end

entitylib.IgnoreObject = RaycastParams.new()
entitylib.IgnoreObject.RespectCanCollide = true
entitylib.Wallcheck = function(origin, position, ignoreobject)
	if typeof(ignoreobject) ~= 'Instance' then
		local ignorelist = {gameCamera, lplr.Character}
		for _, v in entitylib.List do
			if v.Targetable then
				table.insert(ignorelist, v.Character)
			end
		end
		if typeof(ignoreobject) == 'table' then
			for _, v in ignoreobject do
				table.insert(ignorelist, v)
			end
		end

		ignoreobject = entitylib.IgnoreObject
		ignoreobject.FilterDescendantsInstances = ignorelist
	end
	return workspace:Raycast(origin, (position - origin), ignoreobject)
end

entitylib.EntityMouse = function(entitysettings)
	if entitylib.isAlive then
		local mouseLocation, sortingTable = entitysettings.MouseOrigin or getMousePosition(), {}
		for _, v in entitylib.List do
			if not entitysettings.Players and v.Player then continue end
			if not entitysettings.NPCs and v.NPC then continue end
			if not v.Targetable then continue end
			local position, vis = gameCamera:WorldToViewportPoint(v[entitysettings.Part].Position)
			if not vis then continue end
			local mag = (mouseLocation - Vector2.new(position.X, position.Y)).Magnitude
			if mag > entitysettings.Range then continue end
			if entitysettings.ignoreVulnerable or entitylib.isVulnerable(v) then
				table.insert(sortingTable, {
					Entity = v,
					Magnitude = v.Target and -1 or mag
				})
			end
		end

		table.sort(sortingTable, entitysettings.Sort or function(a, b)
			return a.Magnitude < b.Magnitude
		end)

		for _, v in sortingTable do
			if entitysettings.Wallcheck then
				if entitylib.Wallcheck(entitysettings.Origin, v.Entity[entitysettings.Part].Position, entitysettings.Wallcheck) then continue end
			end
			table.clear(entitysettings)
			table.clear(sortingTable)
			return v.Entity
		end
		table.clear(sortingTable)
	end
	table.clear(entitysettings)
end

entitylib.getEntity = function(char)
	for i, v in entitylib.List do
		if v.Player == char or v.Character == char then
			return v, i
		end
	end
end

entitylib.addEntity = function(char, plr, teamfunc)
	if not char then return end
	entitylib.EntityThreads[char] = task.spawn(function()
		local hum = waitForChildOfType(char, 'Humanoid', 10)
		local humrootpart = hum and waitForChildOfType(hum, 'RootPart', workspace.StreamingEnabled and 9e9 or 10, true)
		local head = char:WaitForChild('Head', 10) or humrootpart

		if hum and humrootpart then
			local entity = {
				Connections = {},
				Character = char,
				Health = hum.Health,
				Head = head,
				Humanoid = hum,
				HumanoidRootPart = humrootpart,
				HipHeight = hum.HipHeight + (humrootpart.Size.Y / 2) + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0),
				MaxHealth = hum.MaxHealth,
				NPC = plr == nil,
				Player = plr,
				RootPart = humrootpart,
				TeamCheck = teamfunc
			}

			if plr == lplr then
				entitylib.character = entity
				entitylib.isAlive = true
				entitylib.Events.LocalAdded:Fire(entity)
			else
				entity.Targetable = entitylib.targetCheck(entity)

				for _, v in entitylib.getUpdateConnections(entity) do
					table.insert(entity.Connections, v:Connect(function()
						entity.Health = hum.Health
						entity.MaxHealth = hum.MaxHealth
						entitylib.Events.EntityUpdated:Fire(entity)
					end))
				end

				table.insert(entitylib.List, entity)
				entitylib.Events.EntityAdded:Fire(entity)
			end
		end
		entitylib.EntityThreads[char] = nil
	end)
end

entitylib.removeEntity = function(char, localcheck)
	if localcheck then
		if entitylib.isAlive then
			entitylib.isAlive = false
			for _, v in entitylib.character.Connections do
				v:Disconnect()
			end
			table.clear(entitylib.character.Connections)
			entitylib.Events.LocalRemoved:Fire(entitylib.character)
		end
		return
	end

	if char then
		if entitylib.EntityThreads[char] then
			task.cancel(entitylib.EntityThreads[char])
			entitylib.EntityThreads[char] = nil
		end

		local entity, ind = entitylib.getEntity(char)
		if ind then
			for _, v in entity.Connections do
				v:Disconnect()
			end
			table.clear(entity.Connections)
			table.remove(entitylib.List, ind)
			entitylib.Events.EntityRemoved:Fire(entity)
		end
	end
end

entitylib.refreshEntity = function(char, plr)
	entitylib.removeEntity(char)
	entitylib.addEntity(char, plr)
end

entitylib.addPlayer = function(plr)
	if plr.Character then
		entitylib.refreshEntity(plr.Character, plr)
	end
	entitylib.PlayerConnections[plr] = {
		plr.CharacterAdded:Connect(function(char)
			entitylib.refreshEntity(char, plr)
		end),
		plr.CharacterRemoving:Connect(function(char)
			entitylib.removeEntity(char, plr == lplr)
		end),
		plr:GetPropertyChangedSignal('Team'):Connect(function()
			for _, v in entitylib.List do
				if v.Targetable ~= entitylib.targetCheck(v) then
					entitylib.refreshEntity(v.Character, v.Player)
				end
			end

			if plr == lplr then
				entitylib.start()
			else
				entitylib.refreshEntity(plr.Character, plr)
			end
		end)
	}
end

entitylib.removePlayer = function(plr)
	if entitylib.PlayerConnections[plr] then
		for _, v in entitylib.PlayerConnections[plr] do
			v:Disconnect()
		end
		table.clear(entitylib.PlayerConnections[plr])
		entitylib.PlayerConnections[plr] = nil
	end
	entitylib.removeEntity(plr)
end

entitylib.start = function()
	if entitylib.Running then
		entitylib.stop()
	end
	table.insert(entitylib.Connections, playersService.PlayerAdded:Connect(function(v)
		entitylib.addPlayer(v)
	end))
	table.insert(entitylib.Connections, playersService.PlayerRemoving:Connect(function(v)
		entitylib.removePlayer(v)
	end))
	for _, v in playersService:GetPlayers() do
		entitylib.addPlayer(v)
	end
	table.insert(entitylib.Connections, workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()
		gameCamera = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera')
	end))
	entitylib.Running = true
end

entitylib.stop = function()
	for _, v in entitylib.Connections do
		v:Disconnect()
	end
	for _, v in entitylib.PlayerConnections do
		for _, v2 in v do
			v2:Disconnect()
		end
		table.clear(v)
	end
	entitylib.removeEntity(nil, true)
	local cloned = table.clone(entitylib.List)
	for _, v in cloned do
		entitylib.removeEntity(v.Character)
	end
	for _, v in entitylib.EntityThreads do
		task.cancel(v)
	end
	table.clear(entitylib.PlayerConnections)
	table.clear(entitylib.EntityThreads)
	table.clear(entitylib.Connections)
	table.clear(cloned)
	entitylib.Running = false
end

entitylib.start()

--// ========================================================================
--// UI 素材函式（同名版本在 UI_functions.txt）
--// ========================================================================
local function getfontsize(text, size, font, bounds)
	local pt = TextService:GetTextSize(text, size, font, bounds or Vector2.new(100000, 100000))
	return Vector2.new(pt.X, pt.Y)
end

local function addCorner(parent, radius)
	local corner = Instance.new('UICorner')
	corner.CornerRadius = radius or UDim.new(0, 5)
	corner.Parent = parent
	return corner
end

local function addRoundedShadow(parent)
	local shadow = Instance.new('ImageLabel')
	shadow.Name = 'Shadow'
	shadow.Size = UDim2.new(1, 18, 1, 18)
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.5)
	shadow.BackgroundTransparency = 1
	shadow.Image = 'rbxassetid://85528155206269'
	shadow.ScaleType = Enum.ScaleType.Slice
	shadow.ImageTransparency = 0.5
	shadow.SliceCenter = Rect.new(36, 36, 900, 50)
	shadow.SliceScale = 0.5
	shadow.ZIndex = -100
	shadow.Parent = parent
	return shadow
end

--// ========================================================================
--// 設定
--// ========================================================================
local Config = {
	Spin = {
		Enabled = false,
		Mode = 'CFrame', -- CFrame / RotVelocity / BodyMover
		Speed = 40,
		AxisX = false,
		AxisY = true,
		AxisZ = false,
	},
	Aim = {
		Enabled = false,
		Part = 'RootPart', -- RootPart / Head
		FOV = 100,
		Speed = 15,
		RequireRightClick = false,
		Circle = true,
	},
}

local SPIN_KEY = Enum.KeyCode.X
local AIM_KEY = Enum.KeyCode.C
local MENU_KEY = Enum.KeyCode.RightShift

--// ========================================================================
--// Spin
--// ========================================================================
local spinConnection
local spinBody

local function setSpinEnabled(on)
	Config.Spin.Enabled = on
	if on then
		spinConnection = RunService.PreSimulation:Connect(function()
			if not entitylib.isAlive then return end
			local char = entitylib.character
			local root = char.RootPart
			local cfg = Config.Spin

			if cfg.Mode == 'RotVelocity' then
				local rv = root.RotVelocity
				char.Humanoid.AutoRotate = false
				root.RotVelocity = Vector3.new(
					cfg.AxisX and cfg.Speed or rv.X,
					cfg.AxisY and cfg.Speed or rv.Y,
					cfg.AxisZ and cfg.Speed or rv.Z
				)
			elseif cfg.Mode == 'CFrame' then
				-- tick()*20*speed 讓角度持續累加，取模 360 避免精度流失
				local val = math.rad((tick() * (20 * cfg.Speed)) % 360)
				local x, y, z = root.CFrame:ToOrientation()
				root.CFrame = CFrame.new(root.Position) * CFrame.Angles(
					cfg.AxisX and val or x,
					cfg.AxisY and val or y,
					cfg.AxisZ and val or z
				)
			else
				if not spinBody then
					spinBody = Instance.new('BodyAngularVelocity')
					spinBody.Name = 'SpinAV'
				end
				spinBody.Parent = root
				spinBody.MaxTorque = Vector3.new(
					cfg.AxisX and math.huge or 0,
					cfg.AxisY and math.huge or 0,
					cfg.AxisZ and math.huge or 0
				)
				spinBody.AngularVelocity = Vector3.new(cfg.Speed, cfg.Speed, cfg.Speed)
			end
		end)
	else
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
		if entitylib.isAlive and Config.Spin.Mode == 'RotVelocity' then
			entitylib.character.Humanoid.AutoRotate = true
		end
		if spinBody then
			spinBody.Parent = nil
		end
	end
end

--// ========================================================================
--// Aim Assist
--// ========================================================================
local aimConnection
local fovCircle
local rightClicked = not Config.Aim.RequireRightClick

local moveConst = Vector2.new(1, 0.77) * math.rad(0.5)

local function wrapAngle(num)
	num = num % math.pi
	num -= num >= (math.pi / 2) and math.pi or 0
	num += num < -(math.pi / 2) and math.pi or 0
	return num
end

local function newDrawing(class)
	local ok, obj = pcall(Drawing.new, class)
	if not ok and setthreadidentity then
		pcall(setthreadidentity, 8)
		ok, obj = pcall(Drawing.new, class)
	end
	if ok then return obj end
	return nil
end

local function updateCircle()
	if not fovCircle then return end
	fovCircle.Position = UserInputService:GetMouseLocation()
	fovCircle.Radius = Config.Aim.FOV
	fovCircle.Visible = Config.Aim.Enabled and Config.Aim.Circle
end

local function createCircle()
	if fovCircle or not Config.Aim.Circle then return end
	fovCircle = newDrawing('Circle')
	if not fovCircle then return end
	fovCircle.Filled = false
	fovCircle.Color = Color3.fromRGB(255, 255, 255)
	fovCircle.Position = UserInputService:GetMouseLocation()
	fovCircle.Radius = Config.Aim.FOV
	fovCircle.NumSides = 100
	fovCircle.Transparency = 0.7
	fovCircle.Visible = Config.Aim.Enabled
end

local function destroyCircle()
	if not fovCircle then return end
	pcall(function()
		fovCircle.Visible = false
		fovCircle:Remove()
	end)
	fovCircle = nil
end

local function getMouseSensitivity()
	local ok, sens = pcall(function()
		return UserSettings():GetService('UserGameSettings').MouseSensitivity
	end)
	if ok and type(sens) == 'number' and sens > 0 then
		return sens
	end
	return 0.5
end

local function setAimEnabled(on)
	Config.Aim.Enabled = on
	rightClicked = not Config.Aim.RequireRightClick
	updateCircle()

	if on then
		if Config.Aim.Circle then
			createCircle()
		end
		aimConnection = RunService.RenderStepped:Connect(function(dt)
			updateCircle()
			if not rightClicked then return end
			if not mousemoverel then return end

			local cfg = Config.Aim
			local ent = entitylib.EntityMouse({
				Range = cfg.FOV,
				Part = cfg.Part,
				Players = true,
				NPCs = false,
				Wallcheck = true,
				Origin = gameCamera.CFrame.Position,
			})
			if not ent then return end

			local facing = gameCamera.CFrame.LookVector
			local new = (ent[cfg.Part].Position - gameCamera.CFrame.Position).Unit
			new = new == new and new or Vector3.zero
			if new == Vector3.zero then return end

			local diffYaw = wrapAngle(math.atan2(facing.X, facing.Z) - math.atan2(new.X, new.Z))
			local diffPitch = math.asin(facing.Y) - math.asin(new.Y)
			local angle = Vector2.new(diffYaw, diffPitch) / (moveConst * getMouseSensitivity())
			angle *= math.min(cfg.Speed * dt, 1)

			pcall(mousemoverel, angle.X, angle.Y)
		end)
	else
		if aimConnection then
			aimConnection:Disconnect()
			aimConnection = nil
		end
		destroyCircle()
	end
end

--// ========================================================================
--// 迷你 UI
--// ========================================================================
local screenGui = Instance.new('ScreenGui')
screenGui.Name = 'SpinAimAssist'
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if not pcall(function() screenGui.Parent = CoreGui end) then
	screenGui.Parent = lplr:WaitForChild('PlayerGui')
end

local PANEL_W = 250
local ROW_H = 24
local ROW_GAP = 4
local HEADER_H = 30
local PAD = 6

local panel = Instance.new('Frame')
panel.Name = 'Panel'
panel.Size = UDim2.fromOffset(PANEL_W, HEADER_H + PAD)
panel.Position = UDim2.fromOffset(20, 120)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true
panel.Parent = screenGui
addCorner(panel, UDim.new(0, 8))
addRoundedShadow(panel)

local stroke = Instance.new('UIStroke')
stroke.Color = Color3.fromRGB(60, 60, 70)
stroke.Transparency = 0.4
stroke.Thickness = 1
stroke.Parent = panel

local header = Instance.new('Frame')
header.Name = 'Header'
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
header.BorderSizePixel = 0
header.Parent = panel
addCorner(header, UDim.new(0, 8))
-- 底部兩角補回方形，避免圓角蓋到內容
local headerFix = Instance.new('Frame')
headerFix.Size = UDim2.new(1, 0, 0, 10)
headerFix.Position = UDim2.new(0, 0, 1, -10)
headerFix.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new('TextLabel')
title.Size = UDim2.new(1, -10, 1, 0)
title.Position = UDim2.fromOffset(10, 0)
title.BackgroundTransparency = 1
title.Text = 'Spin + Aim Assist   [RightShift]'
title.TextColor3 = Color3.fromRGB(235, 235, 240)
title.TextSize = 13
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local rowsFrame = Instance.new('Frame')
rowsFrame.Name = 'Rows'
rowsFrame.Size = UDim2.new(1, 0, 0, 0)
rowsFrame.Position = UDim2.new(0, 0, 0, HEADER_H + PAD)
rowsFrame.BackgroundTransparency = 1
rowsFrame.Parent = panel

local rowsLayout = Instance.new('UIListLayout')
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Padding = UDim.new(0, ROW_GAP)
rowsLayout.Parent = rowsFrame

local refreshers = {}
local function makeRow(order)
	local row = Instance.new('Frame')
	row.Size = UDim2.new(1, -PAD * 2, 0, ROW_H)
	row.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = rowsFrame
	addCorner(row, UDim.new(0, 5))
	return row
end

local function makeLabel(parent, text)
	local label = Instance.new('TextLabel')
	label.Size = UDim2.new(1, -70, 1, 0)
	label.Position = UDim2.fromOffset(9, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(210, 210, 218)
	label.TextSize = 12
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function addToggleRow(order, label, get, set)
	local row = makeRow(order)
	makeLabel(row, label)
	local box = Instance.new('Frame')
	box.Size = UDim2.fromOffset(34, 16)
	box.Position = UDim2.new(1, -43, 0.5, -8)
	box.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	box.BorderSizePixel = 0
	box.Parent = row
	addCorner(box, UDim.new(1, 0))
	local knob = Instance.new('Frame')
	knob.Size = UDim2.fromOffset(12, 12)
	knob.Position = UDim2.fromOffset(2, 2)
	knob.BackgroundColor3 = Color3.fromRGB(200, 200, 208)
	knob.BorderSizePixel = 0
	knob.Parent = box
	addCorner(knob, UDim.new(1, 0))

	local button = Instance.new('TextButton')
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ''
	button.Parent = row
	button.Activated:Connect(function()
		set(not get())
	end)

	table.insert(refreshers, function()
		local on = get()
		box.BackgroundColor3 = on and Color3.fromRGB(90, 200, 130) or Color3.fromRGB(60, 60, 70)
		knob.Position = on and UDim2.new(1, -14, 0, 2) or UDim2.fromOffset(2, 2)
	end)
	return row
end

local function addDropdownRow(order, label, options, get, set)
	local row = makeRow(order)
	makeLabel(row, label)
	local value = Instance.new('TextLabel')
	value.Size = UDim2.new(0, 110, 1, 0)
	value.Position = UDim2.new(1, -119, 0, 0)
	value.BackgroundTransparency = 1
	value.Text = ''
	value.TextColor3 = Color3.fromRGB(140, 200, 255)
	value.TextSize = 12
	value.Font = Enum.Font.Gotham
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = row

	local button = Instance.new('TextButton')
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ''
	button.Parent = row
	button.Activated:Connect(function()
		local idx = table.find(options, get()) or 1
		idx = idx % #options + 1
		set(options[idx])
	end)

	table.insert(refreshers, function()
		value.Text = tostring(get())
	end)
	return row
end

local function addSliderRow(order, label, min, max, get, set)
	local row = makeRow(order)
	row.Size = UDim2.new(1, -PAD * 2, 0, ROW_H + 8)
	makeLabel(row, label)
	local valueText = Instance.new('TextLabel')
	valueText.Size = UDim2.new(0, 60, 0, ROW_H)
	valueText.Position = UDim2.new(1, -69, 0, 0)
	valueText.BackgroundTransparency = 1
	valueText.Text = ''
	valueText.TextColor3 = Color3.fromRGB(140, 200, 255)
	valueText.TextSize = 12
	valueText.Font = Enum.Font.Gotham
	valueText.TextXAlignment = Enum.TextXAlignment.Right
	valueText.Parent = row

	local track = Instance.new('Frame')
	track.Size = UDim2.new(1, -18, 0, 4)
	track.Position = UDim2.new(0, 9, 1, -10)
	track.BackgroundColor3 = Color3.fromRGB(55, 55, 64)
	track.BorderSizePixel = 0
	track.Parent = row
	addCorner(track, UDim.new(1, 0))
	local fill = Instance.new('Frame')
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(140, 200, 255)
	fill.BorderSizePixel = 0
	fill.Parent = track
	addCorner(fill, UDim.new(1, 0))

	local dragging = false
	local function applyFromX(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		set(math.floor(min + rel * (max - min) + 0.5))
	end

	local button = Instance.new('TextButton')
	button.Size = UDim2.new(1, 0, 1, 0)
	button.BackgroundTransparency = 1
	button.Text = ''
	button.Parent = row
	button.MouseButton1Down:Connect(function(x)
		dragging = true
		applyFromX(x)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			applyFromX(input.Position.X)
		end
	end)

	table.insert(refreshers, function()
		local v = get()
		valueText.Text = tostring(v)
		fill.Size = UDim2.fromScale(math.clamp((v - min) / math.max(max - min, 1), 0, 1), 1)
	end)
	return row
end

-- row order: Spin 區塊 1-5，Aim 區塊 10-15
addToggleRow(1, 'Spin  [X]', function() return Config.Spin.Enabled end, setSpinEnabled)
addDropdownRow(2, 'Mode', {'CFrame', 'RotVelocity', 'BodyMover'},
	function() return Config.Spin.Mode end,
	function(v)
		if Config.Spin.Enabled then setSpinEnabled(false) end
		Config.Spin.Mode = v
		if Config.Spin.Enabled then setSpinEnabled(true) end
	end)
addSliderRow(3, 'Speed', 1, 100, function() return Config.Spin.Speed end, function(v) Config.Spin.Speed = v end)
addToggleRow(4, 'Axis X', function() return Config.Spin.AxisX end, function(v) Config.Spin.AxisX = v end)
addToggleRow(5, 'Axis Y', function() return Config.Spin.AxisY end, function(v) Config.Spin.AxisY = v end)
addToggleRow(6, 'Axis Z', function() return Config.Spin.AxisZ end, function(v) Config.Spin.AxisZ = v end)

addToggleRow(10, 'Aim Assist  [C]', function() return Config.Aim.Enabled end, setAimEnabled)
addDropdownRow(11, 'Part', {'RootPart', 'Head'},
	function() return Config.Aim.Part end,
	function(v) Config.Aim.Part = v end)
addSliderRow(12, 'FOV', 10, 800, function() return Config.Aim.FOV end, function(v) Config.Aim.FOV = v end)
addSliderRow(13, 'Speed', 1, 60, function() return Config.Aim.Speed end, function(v) Config.Aim.Speed = v end)
addToggleRow(14, 'Require Right Click', function() return Config.Aim.RequireRightClick end, function(v)
	Config.Aim.RequireRightClick = v
	rightClicked = not v
end)
addToggleRow(15, 'FOV Circle', function() return Config.Aim.Circle end, function(v)
	Config.Aim.Circle = v
	if v then
		createCircle()
	else
		destroyCircle()
	end
	updateCircle()
end)

-- 依照列數重算面板高度
local function resizePanel()
	local rows = rowsFrame:GetChildren()
	local bottom = HEADER_H + PAD
	for _, v in rows do
		if v:IsA('Frame') then
			bottom = math.max(bottom, v.Position.Y.Offset + v.Size.Y.Offset + PAD)
		end
	end
	panel.Size = UDim2.fromOffset(PANEL_W, bottom)
end
rowsLayout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(resizePanel)
resizePanel()

--// ========================================================================
--// 輸入
--// ========================================================================
UserInputService.InputBegan:Connect(function(input, gpe)
	if UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 and Config.Aim.RequireRightClick then
		rightClicked = true
		return
	end
	if gpe then return end

	if input.KeyCode == MENU_KEY then
		screenGui.Enabled = not screenGui.Enabled
	elseif input.KeyCode == SPIN_KEY then
		setSpinEnabled(not Config.Spin.Enabled)
	elseif input.KeyCode == AIM_KEY then
		setAimEnabled(not Config.Aim.Enabled)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightClicked = not Config.Aim.RequireRightClick
	end
end)

RunService.RenderStepped:Connect(function()
	for _, v in refreshers do
		v()
	end
end)

print('[SpinAimAssist] loaded — RightShift = menu, X = spin, C = aim')

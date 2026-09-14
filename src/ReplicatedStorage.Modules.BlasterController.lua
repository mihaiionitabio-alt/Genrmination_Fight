--[========[
Revision 4 engineering reference | 13 September 2026
Authority: ReplicatedStorage.Modules.BlasterController
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Input/camera/pose
Future change: Fix one measured fault at a time; retain cached base transforms and deterministic update ownership.
Preserve dependencies: Shared casting, Tool grip metadata, HUD rectangles, rig joints.
Acceptance cases: Idle/walk/recoil, mouse pitch/yaw, mobile swipe, hybrid input, ADS restore, GUI click suppression.
This revision changes documentation only in this source; executable input/aiming behavior is preserved.
]========]
-- BlasterController
-- Local Tool controller: ContextActionService input, mobile controls, ADS,
-- touch aim damping, camera recoil, crosshair, and weapon bob.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Blaster = require(script.Parent:WaitForChild("Blaster"))
local localPlayer = Players.LocalPlayer

local BlasterController = {}
BlasterController.__index = BlasterController

local controllers = setmetatable({}, {__mode = "k"})
local nextControllerId = 0

local function touchControlsActive()
	if UserInputService.TouchEnabled then return true end
	local okTouchScreen, touchScreen = pcall(function()
		return UserInputService.TouchScreenEnabled
	end)
	if okTouchScreen and touchScreen then return true end
	local okPreferred, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if okPreferred and tostring(preferred):find("Touch") then return true end
	local okControls, controls = pcall(function()
		return GuiService.TouchControlsEnabled
	end)
	if okControls and controls then return true end

	-- Studio can retain desktop input flags when a phone preset is selected
	-- after the client starts. Recognize the simulator's compact landscape
	-- viewport so the weapon does not silently lose its mobile camera/buttons.
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	return RunService:IsStudio()
		and viewport ~= nil
		and viewport.Y <= 450
		and viewport.X / math.max(1, viewport.Y) >= 1.45
end

local function pointInside(button, point)
	if not button or not button.Visible then return false end
	local p = button.AbsolutePosition
	local s = button.AbsoluteSize
	return point.X >= p.X and point.X <= p.X + s.X
		and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

-- Hardware support does not identify the active input on an emulator/hybrid.
local function touchAimActive()
	local input = UserInputService:GetLastInputType()
	if input == Enum.UserInputType.Touch then return true end
	if input == Enum.UserInputType.MouseMovement
		or input == Enum.UserInputType.MouseButton1
		or input == Enum.UserInputType.MouseButton2
		or input == Enum.UserInputType.MouseButton3
		or input == Enum.UserInputType.MouseWheel
		or input == Enum.UserInputType.Keyboard then
		return false
	end
	return touchControlsActive()
end

local function rotationBetween(from, to)
	local dot = math.clamp(from:Dot(to), -1, 1)
	local axis = from:Cross(to)
	if axis.Magnitude < 0.00001 then
		if dot > 0 then return CFrame.identity end
		axis = from:Cross(Vector3.yAxis)
		if axis.Magnitude < 0.00001 then axis = from:Cross(Vector3.xAxis) end
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function makeCrosshair(hudName)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild(hudName)
	if old then old:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = hudName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
	gui.DisplayOrder = 12
	gui.Enabled = false
	gui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Crosshair"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(30, 30)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = Color3.fromRGB(120, 235, 255)
	dot.BorderSizePixel = 0
	dot.Parent = root
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color = Color3.fromRGB(6, 15, 22)
	dotStroke.Transparency = 0.15
	dotStroke.Thickness = 1.5
	dotStroke.Parent = dot

	for index, data in ipairs({
		{UDim2.new(0.5, -1, 0, 1), UDim2.fromOffset(2, 8)},
		{UDim2.new(0.5, -1, 1, -9), UDim2.fromOffset(2, 8)},
		{UDim2.new(0, 1, 0.5, -1), UDim2.fromOffset(8, 2)},
		{UDim2.new(1, -9, 0.5, -1), UDim2.fromOffset(8, 2)},
	}) do
		local line = Instance.new("Frame")
		line.Name = "Line" .. index
		line.Position = data[1]
		line.Size = data[2]
		line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		line.BackgroundTransparency = 0.08
		line.BorderSizePixel = 0
		line.Parent = root
	end

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0.5, 25)
	status.Size = UDim2.fromOffset(210, 24)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.Text = ""
	status.TextColor3 = Color3.fromRGB(220, 232, 242)
	status.TextSize = 13
	status.TextStrokeTransparency = 0.5
	status.Parent = gui

	return gui, root, status, dot
end

function BlasterController:_ensureHUD()
	if self.hud and self.hud.Parent and self.crosshair and self.crosshair.Parent == self.hud
		and self.reticleDot and self.reticleDot.Parent == self.crosshair then return false end
	if self.hud then self.hud:Destroy() end
	self.fallbackShootButton = nil
	self.fallbackAimButton = nil
	self.hud, self.crosshair, self.statusLabel, self.reticleDot = makeCrosshair("BlasterHUD_" .. self.id)
	self.hud.Enabled = self.enabled
	return true
end

function BlasterController.new(tool, overrides)
	assert(RunService:IsClient(), "BlasterController must be required on the client")
	assert(tool and tool:IsA("Tool"), "BlasterController.new expects a Tool")

	nextControllerId = nextControllerId + 1
	local self = setmetatable({}, BlasterController)
	self.tool = tool
	self.overrides = overrides or {}
	self.id = nextControllerId
	self.actionPrefix = "Blaster_" .. nextControllerId .. "_"
	self.connections = {}
	self.enabled = false
	self.aiming = false
	self.triggerHeld = false
	self.fireLoopRunning = false
	self.sequence = 0
	self.nextLocalShot = 0
	self.baseGrip = tool.Grip
	self.recoilPitch = 0
	self.recoilYaw = 0
	self.touchInput = nil
	self.touchLastPosition = nil
	self.hiddenParts = {}
	self.shoulderOffset = Vector3.zero

	self.connections.equipped = tool.Equipped:Connect(function()
		self:Enable()
	end)
	self.connections.unequipped = tool.Unequipped:Connect(function()
		self:Disable()
	end)
	self.connections.destroying = tool.Destroying:Connect(function()
		self:Destroy()
	end)
	self.connections.ancestry = tool.AncestryChanged:Connect(function()
		if self.enabled and tool.Parent ~= localPlayer.Character then
			self:Disable()
		end
	end)
	-- Tool.Activated is Roblox's device-independent activation path. ContextActionService
	-- remains the primary input layer, while this fallback covers touch/controller layouts
	-- that route their built-in Tool button directly to Activated.
	self.connections.activated = tool.Activated:Connect(function()
		if self.enabled then self:_beginFiring() end
	end)
	self.connections.deactivated = tool.Deactivated:Connect(function()
		self.triggerHeld = false
	end)

	if localPlayer.Character and tool.Parent == localPlayer.Character then
		task.defer(function() self:Enable() end)
	end

	return self
end

function BlasterController:_button(actionName)
	local ok, button = pcall(function()
		return ContextActionService:GetButton(actionName)
	end)
	return ok and button or nil
end

function BlasterController:_fallbackTouchButton(kind, title)
	local field = kind == "Shoot" and "fallbackShootButton" or "fallbackAimButton"
	local existing = self[field]
	if existing and existing.Parent then return existing end
	if not self.hud then return nil end

	local button = Instance.new("TextButton")
	button.Name = "Fallback" .. kind
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(35, 48, 60)
	button.BorderSizePixel = 0
	button.Text = title
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.fromRGB(245, 250, 255)
	button.TextStrokeColor3 = Color3.fromRGB(5, 8, 12)
	button.TextStrokeTransparency = 0.25
	button.TextScaled = false
	button.ZIndex = 20
	button.Parent = self.hud
	self[field] = button

	if kind == "Shoot" then
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:_shootAction(nil, Enum.UserInputState.Begin)
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:_shootAction(nil, Enum.UserInputState.End)
			end
		end)
	else
		button.Activated:Connect(function()
			if self.enabled then self:SetAiming(not self.aiming) end
		end)
	end
	return button
end

function BlasterController:_styleTouchButtons()
	if not touchControlsActive() then return end
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	local diameter = math.clamp(math.floor(math.min(viewport.X, viewport.Y) * 0.13), 52, 80)
	if jump and jump.AbsoluteSize.X > 0 then
		diameter = math.clamp(math.floor(math.min(jump.AbsoluteSize.X, jump.AbsoluteSize.Y) * 0.85), 48, 80)
	end

	-- Own the visuals/hit targets; CAS still binds desktop/controller actions.
	local shootButton = self:_fallbackTouchButton("Shoot", "FIRE")
	local aimButton = self:_fallbackTouchButton("Aim", "AIM")
	for _, action in ipairs({"Shoot", "Aim"}) do
		local casButton = self:_button(self.actionPrefix .. action)
		if casButton then casButton.Visible = false end
	end
	for _, button in ipairs({shootButton, aimButton}) do
		if button then
			button.Visible = true
			button.Size = UDim2.fromOffset(diameter, diameter)
			button.TextSize = math.floor(diameter * 0.25)
			button.BackgroundTransparency = 0.18
			if button:IsA("ImageButton") then
				button.ImageTransparency = 0.08
				button.ImageColor3 = Color3.fromRGB(35, 48, 60)
			end
			local corner = button:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = button
			local stroke = button:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(220, 235, 245)
			stroke.Transparency = 0.25
			stroke.Thickness = 2
			stroke.Parent = button
			local title = button:FindFirstChild("ActionTitle")
			if title and title:IsA("TextLabel") then
				title.Font = Enum.Font.GothamBold
				title.TextColor3 = Color3.fromRGB(245, 250, 255)
				title.TextStrokeColor3 = Color3.fromRGB(5, 8, 12)
				title.TextStrokeTransparency = 0.25
				title.TextScaled = true
			end
		end
	end

	-- GUI absolute coordinates include the simulator's safe-area translation.
	-- Anchor to Roblox's real JUMP rectangle, never an estimated viewport point.
	local gap = math.max(12, math.floor(diameter * 0.22))
	local jumpSize = jump and jump.AbsoluteSize or Vector2.new(diameter, diameter)
	local jumpPoint = jump and jump.AbsolutePosition
		or (self.hud.AbsolutePosition + self.hud.AbsoluteSize - jumpSize - Vector2.new(28, 28))
	local shootPoint = Vector2.new(jumpPoint.X + (jumpSize.X - diameter) * 0.5, jumpPoint.Y - diameter - gap)
	local aimPoint = Vector2.new(jumpPoint.X - diameter - gap, jumpPoint.Y + (jumpSize.Y - diameter) * 0.5)
	local function place(button, point)
		if not button or not button.Parent then return end
		button.AnchorPoint = Vector2.zero
		local origin = button.Parent.AbsolutePosition
		button.Position = UDim2.fromOffset(
			math.floor(point.X - origin.X + 0.5),
			math.floor(point.Y - origin.Y + 0.5)
		)
	end
	place(shootButton, shootPoint)
	place(aimButton, aimPoint)
	self.lastJumpPosition = jump and jump.AbsolutePosition
end

function BlasterController:_getAimScreenPoint(camera)
	if not camera then return nil end
	if touchAimActive() then
		-- Mobile aims along the Scriptable camera's true forward vector. In the
		-- Studio phone simulator, ViewportPointToRay(viewportCenter) is offset by
		-- the asymmetric safe-area canvas and can land several degrees above the
		-- visible centre marker.
		return nil
	end
	local point = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	-- Clicking an on-screen action must not pull the target onto that button.
	if pointInside(self.fallbackShootButton, point) or pointInside(self.fallbackAimButton, point) then
		return self.lastPointerAim or camera.ViewportSize * 0.5
	end
	self.lastPointerAim = point
	return Vector2.new(
		math.clamp(point.X, 0, camera.ViewportSize.X),
		math.clamp(point.Y, 0, camera.ViewportSize.Y)
	)
end

function BlasterController:_updateAimReticle(camera)
	if not self.hud or not self.crosshair or not camera then return end
	local rayScreenPoint = self:_getAimScreenPoint(camera)
	local screenPoint = rayScreenPoint
	local character = localPlayer.Character
	local solution = character and Blaster.GetAimSolution(self.tool, camera, {
		character,
		self.tool,
		camera,
	}, rayScreenPoint)

	if rayScreenPoint == nil then
		-- The shot uses Camera.CFrame.LookVector. Project that same forward
		-- vector with WorldToScreenPoint so the marker lands in the exact CoreUI
		-- coordinate space used by this ScreenGui, including notches/top bars.
		local projected = camera:WorldToScreenPoint(
			camera.CFrame.Position + camera.CFrame.LookVector * 100
		)
		screenPoint = Vector2.new(projected.X, projected.Y)
	elseif not screenPoint then
		screenPoint = camera.ViewportSize * 0.5
	end

	if solution then
		if self.reticleDot then
			self.reticleDot.BackgroundColor3 = solution.result
				and Color3.fromRGB(255, 224, 105)
				or Color3.fromRGB(120, 235, 255)
		end
	end

	-- ScreenGui's simulated-device canvas can be larger than Camera.ViewportSize
	-- and begin at a negative absolute position. Counter that offset so this
	-- marker identifies the muzzle-checked world hit on every device.
	local origin = self.hud.AbsolutePosition
	local center = screenPoint - origin
	self.crosshair.Position = UDim2.fromOffset(
		math.floor(center.X + 0.5),
		math.floor(center.Y + 0.5)
	)
end

function BlasterController:_setLocalHeadHidden(hidden)
	local character = localPlayer.Character
	if not character then return end
	if hidden then
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") and (descendant.Name == "Head" or descendant.Parent:IsA("Accessory")) then
				if self.hiddenParts[descendant] == nil then
					self.hiddenParts[descendant] = descendant.LocalTransparencyModifier
				end
				descendant.LocalTransparencyModifier = 1
			end
		end
	else
		for part, transparency in pairs(self.hiddenParts) do
			if part.Parent then part.LocalTransparencyModifier = transparency end
		end
		table.clear(self.hiddenParts)
	end
end

function BlasterController:_beginTouchCamera()
	if not touchAimActive() or self.mobileCameraActive then return end
	local camera = workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not camera or not humanoid then return end

	local look = camera.CFrame.LookVector
	self.touchPitch = math.asin(math.clamp(look.Y, -1, 1))
	self.touchYaw = math.atan2(-look.X, -look.Z)
	self.savedCameraType = camera.CameraType
	self.mobileCameraActive = true
	humanoid.AutoRotate = false
	camera.CameraType = Enum.CameraType.Scriptable
	self:_setLocalHeadHidden(true)
end

function BlasterController:_endTouchCamera()
	if not self.mobileCameraActive then return end
	local camera = workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and self.savedCameraType then camera.CameraType = self.savedCameraType end
	self.mobileCameraActive = false
	self.touchInput = nil
	self.touchLastPosition = nil
	self:_setLocalHeadHidden(false)
end

function BlasterController:SetAiming(aiming)
	if not self.enabled then aiming = false end
	if self.aiming == aiming then return end
	self.aiming = aiming

	local camera = workspace.CurrentCamera
	if not camera then return end
	local config = Blaster.GetWeaponConfig(self.tool)
	local targetFov = aiming and config.adsFov or (self.hipFov or 70)
	if self.fovTween then self.fovTween:Cancel() end
	self.fovTween = TweenService:Create(camera, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = targetFov,
	})
	self.fovTween:Play()

	if touchAimActive() then
		-- Mobile weapons keep the camera active in hip-fire too, so the right
		-- half of the screen always steers the reticle like a dedicated FPS.
		self:_beginTouchCamera()
	elseif aiming then
			self.savedMouseSensitivity = UserInputService.MouseDeltaSensitivity
			UserInputService.MouseDeltaSensitivity = self.savedMouseSensitivity * 0.62
	else
		if self.savedMouseSensitivity then
			UserInputService.MouseDeltaSensitivity = self.savedMouseSensitivity
			self.savedMouseSensitivity = nil
		end
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and not self.mobileCameraActive then
		humanoid.CameraOffset = aiming
			and Vector3.new(1.25, 0.55, 0)
			or self.shoulderOffset
	end

	if self.statusLabel then
		self.statusLabel.Text = aiming and "ADS" or ""
	end
end

function BlasterController:_fireOnce()
	if not self.enabled or self.tool.Parent ~= localPlayer.Character then return end
	local config = Blaster.GetWeaponConfig(self.tool)
	local now = os.clock()
	if now < self.nextLocalShot then return end
	self.nextLocalShot = now + config.cooldown
	self.sequence = self.sequence + 1

	local camera = workspace.CurrentCamera
	Blaster.Fire(self.tool, camera, self.sequence, self:_getAimScreenPoint(camera))
	local recoilScale = self.aiming and 0.55 or 1
	self.recoilPitch = self.recoilPitch + math.rad(0.75 * recoilScale)
	self.recoilYaw = self.recoilYaw + math.rad((math.random() - 0.5) * 0.55 * recoilScale)
end

function BlasterController:_beginFiring()
	if os.clock() < (self.ignoreGuiFireUntil or 0) then return end
	self.triggerHeld = true
	if self.fireLoopRunning then return end
	self.fireLoopRunning = true
	task.spawn(function()
		repeat
			self:_fireOnce()
			local config = Blaster.GetWeaponConfig(self.tool)
			if not config.automatic then break end
			task.wait(config.cooldown)
		until not self.triggerHeld or not self.enabled
		self.fireLoopRunning = false
	end)
end

function BlasterController:_shootAction(_, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin and inputObject and inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
		local hud=localPlayer.PlayerGui:FindFirstChild("GWAPHUD")
		local point=UserInputService:GetMouseLocation()
		for _,object in ipairs(localPlayer.PlayerGui:GetGuiObjectsAtPosition(point.X,point.Y)) do
			if hud and object:IsDescendantOf(hud) then
				self.ignoreGuiFireUntil=os.clock()+.15
				return Enum.ContextActionResult.Pass
			end
		end
	end
	if not self.enabled then return Enum.ContextActionResult.Pass end
	if inputState == Enum.UserInputState.Begin and inputObject
		and inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
		local point = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		if pointInside(self.fallbackAimButton, point) then return Enum.ContextActionResult.Pass end
	end
	if inputState == Enum.UserInputState.Begin then
		self:_beginFiring()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self.triggerHeld = false
	end
	return Enum.ContextActionResult.Sink
end

function BlasterController:_aimAction(_, inputState, inputObject)
	if not self.enabled then return Enum.ContextActionResult.Pass end
	local isTouch = inputObject and inputObject.UserInputType == Enum.UserInputType.Touch
	if isTouch then
		if inputState == Enum.UserInputState.Begin then
			self:SetAiming(not self.aiming)
		end
	elseif inputState == Enum.UserInputState.Begin then
		self:SetAiming(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self:SetAiming(false)
	end
	return Enum.ContextActionResult.Sink
end

function BlasterController:_touchPanAction(_, inputState, inputObject)
	if not self.enabled or not touchControlsActive() then
		return Enum.ContextActionResult.Pass
	end

	local point = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	point = point - inset

	if inputState == Enum.UserInputState.Begin then
		local shootButton = self.fallbackShootButton or self:_button(self.actionPrefix .. "Shoot")
		local aimButton = self.fallbackAimButton or self:_button(self.actionPrefix .. "Aim")
		local touchGui = localPlayer.PlayerGui:FindFirstChild("TouchGui")
		local jumpButton = touchGui and touchGui:FindFirstChild("JumpButton", true)
		if point.X < viewport.X * 0.42 or pointInside(shootButton, point)
			or pointInside(aimButton, point) or pointInside(jumpButton, point) then
			return Enum.ContextActionResult.Pass
		end
		self.touchInput = inputObject
		self:_beginTouchCamera()
		self.touchLastPosition = point
		return Enum.ContextActionResult.Sink
	end

	if inputObject ~= self.touchInput then return Enum.ContextActionResult.Pass end
	if inputState == Enum.UserInputState.Change and self.touchLastPosition then
		local delta = point - self.touchLastPosition
		self.touchLastPosition = point
		local sensitivity = self.aiming
			and (self.tool:GetAttribute("BlasterADSTouchSensitivity") or 0.42)
			or (self.tool:GetAttribute("BlasterHipTouchSensitivity") or 0.72)
		sensitivity = math.clamp(sensitivity, 0.15, 1.2)
		self.touchYaw = self.touchYaw - delta.X * 0.0031 * sensitivity
		self.touchPitch = math.clamp(self.touchPitch - delta.Y * 0.0027 * sensitivity, math.rad(-78), math.rad(78))
		return Enum.ContextActionResult.Sink
	end

	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self.touchInput = nil
		self.touchLastPosition = nil
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

function BlasterController:_updateArmPose(targetPosition, dt)
	local character = localPlayer.Character
	local handle = self.tool:FindFirstChild("Handle")
	if not character or not handle or not targetPosition then return end
	if not self.aimJoint or not self.aimJoint.Parent then
		local joints = {}
		for _, joint in ipairs(character:GetDescendants()) do
			if (joint:IsA("JointInstance") or joint:IsA("AnimationConstraint")) and joint.Part0 and joint.Part1 then
				joints[joint.Part1] = joint
			end
		end
		local chain = {}
		local part = handle
		for _ = 1, 8 do
			local joint = joints[part]
			if not joint then return end
			table.insert(chain, 1, joint)
			if joint.Name == "Right Shoulder" or joint.Name == "RightShoulder" then
				self.aimJoint = joint
				self.aimBaseC0 = joint.C0
				self.aimChain = chain
				break
			end
			part = joint.Part0
		end
	end
	local shoulder = self.aimJoint
	if not shoulder or not shoulder.Part0 then return end
	-- Rebuild from the untouched joint/grip and the current animation each frame.
	-- This preserves R6/R15 rest rotations and avoids accumulating aim offsets.
	local jointWorld = shoulder.Part0.CFrame * self.aimBaseC0
	local predicted = shoulder.Part0.CFrame
	for _, joint in ipairs(self.aimChain) do
		if not joint.Parent then return end
		local c0 = joint == shoulder and self.aimBaseC0 or joint.C0
		local animation = CFrame.identity -- armed arm chain is isolated from idle/walk animation
		predicted = predicted * c0 * animation * joint.C1:Inverse()
	end
	local forward = self.tool:GetAttribute("BlasterBarrelDirection")
	if typeof(forward) ~= "Vector3" or forward.Magnitude < 0.1 then
		-- Imported Weapons Kit meshes face +Z; procedural barrels face -Z.
		forward = self.tool:GetAttribute("LabSidearm") and Vector3.zAxis or -Vector3.zAxis
	end
	local turn = CFrame.identity
	local pivot = jointWorld.Position
	for _ = 1, 4 do
		local delta = targetPosition - predicted.Position
		if delta.Magnitude < 0.1 then break end
		local correction = rotationBetween(predicted:VectorToWorldSpace(forward.Unit), delta.Unit)
		predicted = CFrame.new(pivot) * correction * CFrame.new(-pivot) * predicted
		turn = correction * turn
	end
	local pose = shoulder.Part0.CFrame:ToObjectSpace(CFrame.new(pivot) * turn * jointWorld.Rotation)
	self.smoothedArmPose = (self.smoothedArmPose or pose):Lerp(pose, 1 - math.exp(-math.min(dt or 1/60, .1) * 24))
	pose = self.smoothedArmPose
	if shoulder:IsA("AnimationConstraint") then
		shoulder.Attachment0.CFrame = pose
	else
		shoulder.C0 = pose
	end
end

function BlasterController:_render(dt)
	if not self.enabled then return end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local camera = workspace.CurrentCamera
	if not humanoid or not camera then return end
	local hudRebuilt = self:_ensureHUD()
	local touchMode = touchControlsActive()
	local touchAim = touchAimActive()
	if touchAim and not self.mobileCameraActive then
		self:_beginTouchCamera()
	elseif not touchAim and self.mobileCameraActive then
		self:_endTouchCamera()
	end
	local touchGui = localPlayer.PlayerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if touchMode and (hudRebuilt or self.lastTouchViewport ~= camera.ViewportSize
		or (jump and jump.AbsolutePosition ~= self.lastJumpPosition)) then
		self.lastTouchViewport = camera.ViewportSize
		task.defer(function()
			if self.enabled then self:_styleTouchButtons() end
		end)
	end
	-- Keep the inventory grip fixed: no idle or walking weapon bob.

	self.recoilPitch = self.recoilPitch * math.exp(-dt * 14)
	self.recoilYaw = self.recoilYaw * math.exp(-dt * 16)
	if self.mobileCameraActive and head and root then
		self.touchPitch = math.clamp(self.touchPitch - self.recoilPitch * dt * 7, math.rad(-78), math.rad(78))
		self.touchYaw = self.touchYaw + self.recoilYaw * dt * 7
		local rotation = CFrame.fromOrientation(self.touchPitch, self.touchYaw, 0)
		local focus = root.Position + Vector3.new(0, self.stableHeadHeight or 1.5, 0)
		local desired = focus - rotation.LookVector * 0.18 + rotation.RightVector * 0.08
		local cameraResult = workspace:Raycast(focus, desired - focus, Blaster.NewRaycastParams({character, self.tool}))
		local position = cameraResult and (cameraResult.Position + cameraResult.Normal * 0.1) or desired
		camera.CFrame = CFrame.new(position) * rotation
		camera.Focus = CFrame.new(focus + rotation.LookVector * 12)

	elseif math.abs(self.recoilPitch) > 0.00001 or math.abs(self.recoilYaw) > 0.00001 then
		camera.CFrame = camera.CFrame * CFrame.Angles(-self.recoilPitch * dt * 7, self.recoilYaw * dt * 7, 0)
	end
	local config = Blaster.GetWeaponConfig(self.tool)
	local cast = Blaster.CastFromCamera(camera, config.range, {character, self.tool, camera}, self:_getAimScreenPoint(camera))
	if cast then
		self:_updateArmPose(cast.position, dt)
	end
	self:_updateAimReticle(camera)
end

local activeController
function BlasterController:Enable()
	if self.enabled or self.tool.Parent ~= localPlayer.Character then return end
	if activeController and activeController ~= self then activeController:Disable() end
	activeController = self
	self.enabled = true
	self.baseGrip = self.tool.Grip
	local rootPart = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	local headPart = localPlayer.Character and localPlayer.Character:FindFirstChild("Head")
	self.stableHeadHeight = rootPart and headPart and (headPart.Position.Y - rootPart.Position.Y + .12) or 1.5
	self.hipFov = self.tool:GetAttribute("BlasterHipFOV") or (workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView) or 70

	self:_ensureHUD()
	self.hud.Enabled = true

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self.savedAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false
		self.savedCameraOffset = humanoid.CameraOffset
		self.shoulderOffset = Vector3.new(
			self.tool:GetAttribute("BlasterShoulderOffsetX") or 2.2,
			self.tool:GetAttribute("BlasterShoulderOffsetY") or 0.65,
			0
		)
		humanoid.CameraOffset = self.shoulderOffset
	end
	if touchAimActive() then self:_beginTouchCamera() end

	local shootName = self.actionPrefix .. "Shoot"
	local aimName = self.actionPrefix .. "Aim"
	local panName = self.actionPrefix .. "TouchPan"
	local priority = Enum.ContextActionPriority.High.Value

	ContextActionService:BindActionAtPriority(shootName, function(...)
		return self:_shootAction(...)
	end, true, priority + 2, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority(aimName, function(...)
		return self:_aimAction(...)
	end, true, priority + 2, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	ContextActionService:BindActionAtPriority(panName, function(...)
		return self:_touchPanAction(...)
	end, false, priority + 1, Enum.UserInputType.Touch)

	ContextActionService:SetTitle(shootName, "FIRE")
	ContextActionService:SetTitle(aimName, "AIM")
	task.delay(0.1, function()
		if self.enabled then self:_styleTouchButtons() end
	end)

	-- Rotate once, before the camera reads the character. Using camera heading
	-- removes the shoulder-offset/nearby-hit feedback loop that caused oscillation.
	self.bodyRenderName = self.actionPrefix .. "Body"
	RunService:BindToRenderStep(self.bodyRenderName, Enum.RenderPriority.Camera.Value - 1, function()
		if not self.enabled then return end
		local char = localPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local body = char and char:FindFirstChild("HumanoidRootPart")
		local cam = workspace.CurrentCamera
		if not hum or hum.Sit or not body or not cam then return end
		local direction = self.mobileCameraActive and CFrame.fromOrientation(0, self.touchYaw, 0).LookVector or cam.CFrame.LookVector
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude > .01 then body.CFrame = CFrame.lookAt(body.Position, body.Position + flat.Unit) end
	end)
	-- Animator writes Transform before PreSimulation. Reset only the armed chain,
	-- preserving locomotion animation everywhere else.
	self.armAnimationConnection = RunService.PreSimulation:Connect(function()
		if not self.enabled or not self.aimChain then return end
		for _,joint in ipairs(self.aimChain) do if joint.Parent and joint:IsA("Motor6D") then joint.Transform = CFrame.identity end end
		local char=localPlayer.Character
		if char then
			self.torsoAnimationJoints=self.torsoAnimationJoints or {}
			if #self.torsoAnimationJoints==0 then for _,joint in ipairs(char:GetDescendants()) do
				if joint:IsA("Motor6D") and (joint.Name=="Waist" or joint.Name=="RootJoint" or joint.Name=="Root") then table.insert(self.torsoAnimationJoints,joint) end
			end end
			for _,joint in ipairs(self.torsoAnimationJoints) do if joint.Parent then joint.Transform=CFrame.identity end end
		end
	end)
	self.renderName = self.actionPrefix .. "Render"
	RunService:BindToRenderStep(self.renderName, Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:_render(dt)
	end)
end

function BlasterController:Disable()
	if not self.enabled then return end
	self.triggerHeld = false
	self:SetAiming(false)
	self.enabled = false
	if activeController == self then activeController = nil end
	self.smoothedArmPose = nil
	self.torsoAnimationJoints = nil
	if self.armAnimationConnection then self.armAnimationConnection:Disconnect(); self.armAnimationConnection = nil end
	if self.bodyRenderName then RunService:UnbindFromRenderStep(self.bodyRenderName) end

	ContextActionService:UnbindAction(self.actionPrefix .. "Shoot")
	ContextActionService:UnbindAction(self.actionPrefix .. "Aim")
	ContextActionService:UnbindAction(self.actionPrefix .. "TouchPan")
	if self.renderName then RunService:UnbindFromRenderStep(self.renderName) end
	if self.hud then self.hud.Enabled = false end
	if self.tool.Parent then self.tool.Grip = self.baseGrip end
	if self.aimJoint and self.aimJoint.Parent then
		if self.aimJoint:IsA("AnimationConstraint") then
			self.aimJoint.Attachment0.CFrame = self.aimBaseC0
		else
			self.aimJoint.C0 = self.aimBaseC0
		end
	end
	self.aimJoint, self.aimBaseC0, self.aimChain = nil, nil, nil

	local camera = workspace.CurrentCamera
	if camera and self.hipFov then camera.FieldOfView = self.hipFov end
	self:_endTouchCamera()
	if self.savedMouseSensitivity then
		UserInputService.MouseDeltaSensitivity = self.savedMouseSensitivity
		self.savedMouseSensitivity = nil
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and self.savedAutoRotate ~= nil then humanoid.AutoRotate = self.savedAutoRotate end
	self.savedAutoRotate = nil
	if humanoid and self.savedCameraOffset then
		humanoid.CameraOffset = self.savedCameraOffset
	end
	self.savedCameraOffset = nil
	self.lastTouchViewport = nil
end

function BlasterController:Destroy()
	self:Disable()
	for _, connection in pairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.hud then self.hud:Destroy() end
	controllers[self.tool] = nil
end

function BlasterController.BindTool(tool, overrides)
	if controllers[tool] then return controllers[tool] end
	local controller = BlasterController.new(tool, overrides)
	controllers[tool] = controller
	Blaster.StartReplication()
	return controller
end

function BlasterController.GetController(tool)
	return controllers[tool]
end

function BlasterController.AutoBind()
	local binder = {connections = {}}

	local function consider(instance)
		if instance:IsA("Tool") and (instance:GetAttribute("BlasterWeapon") or instance:GetAttribute("LabSidearm")) then
			BlasterController.BindTool(instance)
		end
	end

	local function watch(container)
		if not container then return end
		for _, descendant in ipairs(container:GetDescendants()) do consider(descendant) end
		table.insert(binder.connections, container.DescendantAdded:Connect(consider))
	end

	watch(localPlayer:WaitForChild("Backpack"))
	watch(localPlayer.Character)
	table.insert(binder.connections, localPlayer.CharacterAdded:Connect(watch))
	Blaster.StartReplication()

	function binder:Destroy()
		for _, connection in ipairs(self.connections) do connection:Disconnect() end
		table.clear(self.connections)
	end

	return binder
end

return BlasterController

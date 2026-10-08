-- StudioServiceが存在するかチェック（存在したらエラーで検出）
if pcall(game.GetService, game, "StudioService") then error('detected') end

-- GitHubリポジトリのURL（Obsidianライブラリ本体）
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
-- ライブラリ本体とアドオン（テーマ管理・保存管理）を読み込み
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

-- 各種サービスを取得
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

-- ローカルプレイヤーとキャラクター関連の変数
local Player = Players.LocalPlayer
local Character
local CharacterEvents = ReplicatedStorage:WaitForChild("CharacterEvents", 5)
local RagdollRemote = CharacterEvents and CharacterEvents:WaitForChild("RagdollRemote", 5)

-- 有効/無効フラグと各種タスク・接続
local enabled = false
local ragdollTask
local renderConnection
local renderStepName = "YUZAMAI_DETACHED_ARMS"
local inputConnection
local keyboardEndedConnection
local keyboardArmKeys = {}
local characterConnection
local touchGui
local antiBlobmanActive = false
local antiBlobmanTask
local originalCFrame
local savedCameraType
local savedCameraSubject
local cameraStateSaved = false
local cameraLocked = false
local cameraLockConnection
local lockedHumanoid

-- 腕・体の状態管理用テーブル
local arms = {}
local armParts = {}
local armPhysicsState = {}
local armNoCollisionConstraints = {}
local armBoundaryJointState = {}
local armState = {}
local bodyState = {}
local headState
local legState = {}
local armPhysicsConnection
local armNetworkSyncConnection
local walkTime = 0
local standingPosition
local standingYaw = 0
local selectedNames = {"Left", "Right"}
local statusLabel

-- 移動関連の定数
local MOVE_SPEED = 16
local ROOT_RETURN_SPEED = 9
local ROOT_DRIFT_SNAP_DISTANCE = 1.0
local ARM_REACH_SCALE = 0.88
local ARM_LERP_SPEED = 7

-- 安定性調整：どのパーツもアンカーせずに物理フィードバックを減らす
local ARM_MASSLESS = true
local BODY_POSE_LERP_SPEED = 30
local CAMERA_TARGET_LERP_SPEED = 24
local VELOCITY_EPSILON = 0.02

-- JSONスタイルの腕の配置（HumanoidRootPartからの相対位置）
-- Robloxではローカルの-Zが前方
local DETACHED_ARM_FORWARD = 2.00
local DETACHED_ARM_HEIGHT = 0.40
-- 腕を左右に開いて中央から離す
local DETACHED_ARM_SIDE = 1.15
-- 腕を肩から離し、前方かつ少し低い位置に配置する
local ARM_REACH_RADIUS = 2.35
local ARM_PIVOT_FORWARD = -1.00
local ARM_PIVOT_HEIGHT = 0.45
local ARM_PIVOT_FORWARD_SHIFT = 0.35
local ARM_UPWARD_POSITION_OFFSET = 0.65
local ARM_CENTER_RATIO = 0.70
local ARM_INPUT_RESPONSE = 1.25

-- 初期ポーズの腕を少し下向きにする
local ARM_NEUTRAL_PITCH = math.rad(-28)
-- 初期ポーズでは左右の腕を少し外側へ向ける
local ARM_NEUTRAL_SPLAY = math.rad(12)
-- 脚を元の位置から少し高くする
local HEAD_HEIGHT_OFFSET = 0.25
local ARM_INPUT_SMOOTHING = 8
local ARM_POSE_LERP_SPEED = 11
local ARM_DOWN_HAND_ROLL = math.rad(90)
local DETACHED_ARM_LERP_SPEED = 18

-- 意図的なHumanoidの動きを保持しつつ、腕の反動ドリフトを打ち消す
local BODY_REACTION_CORRECTION = 1
local TURN_SPEED = 12
local sprintHeld = false
local NORMAL_MOVE_SPEED = MOVE_SPEED

-- Shiftを押して移動している時だけナルト走りに切り替える
local NARUTO_BODY_LEAN = math.rad(12)
local NARUTO_ARM_BACK = 1.90
local NARUTO_ARM_DROP = -0.08
local NARUTO_ARM_SPLAY = math.rad(8)
local NARUTO_ARM_SWING = 0
local WALK_CYCLE_SPEED = 10
local NORMAL_WALK_CYCLE_SPEED = WALK_CYCLE_SPEED
local SPRINT_WALK_CYCLE_SPEED = WALK_CYCLE_SPEED * 1.28
local LEG_SWING_ANGLE = math.rad(65)

-- 足が地面から離れないよう、足全体の上下リフトは無効化する
local LEG_LIFT_HEIGHT = 0
local LEG_LERP_SPEED = 28
local UPRIGHT_LERP_SPEED = 14

-- 手動カメラ操作関連
local manualCameraConnection
local manualCameraInputConnection
local manualCameraTouchStartConnection
local manualCameraTouchEndConnection
local manualCameraPinchConnection
local manualCameraInputBeganConnection
local manualCameraInputEndedConnection
local manualCameraTouch
local manualCameraTouchLastPosition
local manualCameraMouseDragging = false
local manualCameraActive = false
local manualCameraMouseButton
local savedMouseBehavior
local cameraRecoveryConnection

-- カメラ復元・死亡・キャラクター削除関連
local restoreCamera
local deathConnection
local characterRemovingConnection

-- 手動カメラの角度・距離
local cameraYaw = 0
local cameraPitch = math.rad(-12)
local cameraDistance = 12
local cameraTargetOffset = Vector3.new(0, 2, 0)

-- 体の固定関連
local hardBodyLock = true
local fixedBodyCFrame
-- 胴体と脚だけを地面下へ退避し、頭と腕は元の位置に残す
local detachedBodyCFrame
-- 地面に埋れる程度の深さ。深すぎると物理判定が重くなりやすい
local DETACHED_BODY_HEIGHT = -50

-- 水平方向だけで動かすようフライト調整。Y座標は変更しない
local FLIGHT_MAX_SPEED = 22
local FLIGHT_ACCELERATION = 8
local FLIGHT_DECELERATION = 12
local SPRINT_SPEED = FLIGHT_MAX_SPEED * 1.12
local flightVelocity = Vector3.zero
local flightArmPhase = 0
local flightArmIntensity = 0
local smoothedCameraTarget
local jumpDone = false

-- 蛇モード関連
local snakeEnabled = false
local snakePose = {}
local applySnakePose
local stopSnake
local snakePathHistory = {}
local snakeRopePositions = {}
local snakeJointAngles = {}
local snakeOriginalSizes = {}
local snakePathTime = 0
local snakeLastUpdate = nil
local snakeWasMoving = false
local snakeRestHeadAngle = 0
local SNAKE_VERTICAL_OFFSET = -3.8
local SNAKE_LIMB_LENGTH_SCALE = 1.35

-- 体全体が頭の軌跡を参照する基準速度。値を上げて間隔を詰める
local SNAKE_HISTORY_SPEED = 20
-- 停止時だけ、蛇の各点を頭の少し後ろへ置く距離
local SNAKE_REST_TRAIL = 1.0

-- 通知を出す関数
local function notify(title, text)
    Library:Notify({Title = title, Description = text, Duration = 3})
end

-- キャラクターから指定側の腕パーツを取得
local function getPart(character, side)
    local names = side == "Left" and {"LeftUpperArm", "Left Arm", "LeftLowerArm", "LeftHand"} or {"RightUpperArm", "Right Arm", "RightLowerArm", "RightHand"}
    for _, name in ipairs(names) do
        local part = character and character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            return part
        end
    end
end

-- キャラクター情報を再取得して状態を更新
local function refreshCharacter()
    Character = Player.Character or Player.CharacterAdded:Wait()
    local character = Character
    local root = character:FindFirstChild("HumanoidRootPart")

    arms.Left = getPart(character, "Left")
    arms.Right = getPart(character, "Right")

    armParts = {}
    for _, side in ipairs({"Left", "Right"}) do
        local names = side == "Left" and {"LeftUpperArm", "Left Arm", "LeftLowerArm", "LeftHand"} or {"RightUpperArm", "Right Arm", "RightLowerArm", "RightHand"}
        armParts[side] = {}
        for _, name in ipairs(names) do
            local armPart = character:FindFirstChild(name)
            if armPart and armPart:IsA("BasePart") then
                armParts[side][#armParts[side] + 1] = armPart
            end
        end
    end

    if root then
        standingPosition = root.Position
        standingYaw = select(2, root.CFrame:ToOrientation())
        bodyState = {}
        legState = {}
        walkTime = 0

        local head = character:FindFirstChild("Head")
        headState = head and head:IsA("BasePart") and (root.CFrame:ToObjectSpace(head.CFrame) * CFrame.new(0, HEAD_HEIGHT_OFFSET, 0)) or nil

        -- 胴体パーツの相対位置を保存
        for _, name in ipairs({"Torso", "UpperTorso", "LowerTorso"}) do
            local bodyPart = character:FindFirstChild(name)
            if bodyPart and bodyPart:IsA("BasePart") then
                bodyState[name] = root.CFrame:ToObjectSpace(bodyPart.CFrame)
            end
        end

        -- 脚パーツの相対位置を保存
        for _, side in ipairs({"Left", "Right"}) do
            local legNames = side == "Left" and {"LeftUpperLeg", "Left Leg", "LeftLowerLeg", "LeftFoot"} or {"RightUpperLeg", "Right Leg", "RightLowerLeg", "RightFoot"}
            local parts = {}
            for _, name in ipairs(legNames) do
                local leg = character:FindFirstChild(name)
                if leg and leg:IsA("BasePart") then
                    parts[#parts + 1] = {
                        part = leg,
                        base = root.CFrame:ToObjectSpace(leg.CFrame),
                    }
                end
            end
            legState[side] = {root = root, parts = parts}
        end

        -- 腕の状態を保存
        for _, side in ipairs({"Left", "Right"}) do
            local part = arms[side]
            if part then
                armState[side] = {
                    root = root,
                    base = root.CFrame:ToObjectSpace(part.CFrame),
                    partBases = (function()
                        local bases = {}
                        for _, armPart in ipairs(armParts[side] or {}) do
                            bases[armPart] = part.CFrame:ToObjectSpace(armPart.CFrame)
                        end
                        return bases
                    end)(),
                    pivotLocal = (root.CFrame:ToObjectSpace(part.CFrame) * CFrame.new(0, part.Size.Y / 2, 0)).Position,
                    move = Vector3.zero,
                    rotate = Vector3.zero,
                    depth = 0,
                    roll = 0,
                    input = Vector2.zero,
                    previousTargets = {},
                }
            end
        end
    end
    return character, root
end

-- ラグドール状態をサーバーに通知
local function fireRagdoll(value)
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if RagdollRemote and root then
        pcall(function()
            RagdollRemote:FireServer(root, value and 1 or 0)
        end)
    end
end

-- 点がGUI内にあるか判定
local function pointInsideGui(point, guiObject)
    if not guiObject or not guiObject.Visible then return false end
    local position = guiObject.AbsolutePosition
    local size = guiObject.AbsoluteSize
    return point.X >= position.X and point.X <= position.X + size.X and point.Y >= position.Y and point.Y <= position.Y + size.Y
end

-- 点が腕のジョイスティック内にあるか判定
local function pointInsideArmJoystick(point)
    if not touchGui then return false end
    return pointInsideGui(point, touchGui:FindFirstChild("LeftArmPanel")) or pointInsideGui(point, touchGui:FindFirstChild("RightArmPanel"))
end

-- 手動カメラ操作を停止
local function stopManualBlobmanCamera()
    manualCameraActive = false
    if cameraRecoveryConnection then cameraRecoveryConnection:Disconnect(); cameraRecoveryConnection = nil end
    if manualCameraConnection then manualCameraConnection:Disconnect(); manualCameraConnection = nil end
    if manualCameraInputConnection then manualCameraInputConnection:Disconnect(); manualCameraInputConnection = nil end
    if manualCameraTouchStartConnection then manualCameraTouchStartConnection:Disconnect(); manualCameraTouchStartConnection = nil end
    if manualCameraTouchEndConnection then manualCameraTouchEndConnection:Disconnect(); manualCameraTouchEndConnection = nil end
    if manualCameraPinchConnection then manualCameraPinchConnection:Disconnect(); manualCameraPinchConnection = nil end
    if manualCameraInputBeganConnection then manualCameraInputBeganConnection:Disconnect(); manualCameraInputBeganConnection = nil end
    if manualCameraInputEndedConnection then manualCameraInputEndedConnection:Disconnect(); manualCameraInputEndedConnection = nil end
    manualCameraTouch = nil
    manualCameraTouchLastPosition = nil
    manualCameraMouseDragging = false
    manualCameraMouseButton = nil
    if savedMouseBehavior then
        UserInputService.MouseBehavior = savedMouseBehavior
        savedMouseBehavior = nil
    end
end

-- 手動カメラ操作を開始
local function startManualBlobmanCamera(humanoid, root)
    local camera = Workspace.CurrentCamera
    if not camera or not humanoid or not root then return end

    stopManualBlobmanCamera()

    local target = (fixedBodyCFrame and fixedBodyCFrame.Position or root.Position) + cameraTargetOffset
    smoothedCameraTarget = target

    local relative = camera.CFrame.Position - target
    if relative.Magnitude > 0.1 then
        cameraDistance = math.clamp(relative.Magnitude, 5, 40)
        cameraYaw = math.atan2(relative.X, relative.Z)
        cameraPitch = math.clamp(math.asin(relative.Unit.Y), math.rad(-75), math.rad(55))
    end

    camera.CameraType = Enum.CameraType.Scriptable
    manualCameraActive = true

    -- カメラ復帰監視
    cameraRecoveryConnection = RunService.Heartbeat:Connect(function()
        if not manualCameraActive then return end
        local currentCamera = Workspace.CurrentCamera
        if not currentCamera or not currentCamera.Parent or not root or not root.Parent or not Player.Character or not root:IsDescendantOf(Player.Character) then
            restoreCamera()
        end
    end)

    -- マウスホイール・タッチでの操作
    manualCameraInputConnection = UserInputService.InputChanged:Connect(function(input)
        if not manualCameraActive then return end
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            cameraDistance = math.clamp(cameraDistance - input.Position.Z * 1.5, 5, 40)
        elseif input.UserInputType == Enum.UserInputType.Touch and input == manualCameraTouch and manualCameraTouchLastPosition then
            local delta = input.Position - manualCameraTouchLastPosition
            cameraYaw = cameraYaw - delta.X * 0.006
            cameraPitch = math.clamp(cameraPitch - delta.Y * 0.006, math.rad(-75), math.rad(55))
            manualCameraTouchLastPosition = input.Position
        end
    end)

    -- 右クリックでカメラドラッグ開始
    manualCameraInputBeganConnection = UserInputService.InputBegan:Connect(function(input)
        if not manualCameraActive then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 and not pointInsideArmJoystick(input.Position) then
            manualCameraMouseDragging = true
            manualCameraMouseButton = input.UserInputType
            if not savedMouseBehavior then
                savedMouseBehavior = UserInputService.MouseBehavior
            end
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        end
    end)

    manualCameraInputEndedConnection = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == manualCameraMouseButton then
            manualCameraMouseDragging = false
            manualCameraMouseButton = nil
            if savedMouseBehavior then
                UserInputService.MouseBehavior = savedMouseBehavior
                savedMouseBehavior = nil
            end
        end
    end)

    -- タッチ開始
    manualCameraTouchStartConnection = UserInputService.TouchStarted:Connect(function(input)
        if not manualCameraActive then return end
        if input.UserInputType == Enum.UserInputType.Touch and not pointInsideArmJoystick(input.Position) then
            manualCameraTouch = input
            manualCameraTouchLastPosition = input.Position
        end
    end)

    manualCameraTouchEndConnection = UserInputService.TouchEnded:Connect(function(input)
        if input == manualCameraTouch then
            manualCameraTouch = nil
            manualCameraTouchLastPosition = nil
        end
    end)

    -- ピンチでズーム
    manualCameraPinchConnection = UserInputService.TouchPinch:Connect(function(_, scale, _, state)
        if manualCameraTouch and state == Enum.UserInputState.Change then
            cameraDistance = math.clamp(cameraDistance / math.max(scale, 0.01), 5, 40)
        end
    end)

    -- 毎フレームのカメラ更新
    manualCameraConnection = RunService.RenderStepped:Connect(function(dt)
        if not manualCameraActive then return end
        if not camera or not camera.Parent or not root or not root.Parent then return end

        if manualCameraMouseDragging then
            local delta = UserInputService:GetMouseDelta()
            cameraYaw = cameraYaw - delta.X * 0.004
            cameraPitch = math.clamp(
                cameraPitch - delta.Y * 0.004,
                math.rad(-75),
                math.rad(55)
            )
        end

        local targetPosition = (fixedBodyCFrame and fixedBodyCFrame.Position or root.Position) + cameraTargetOffset
        local targetAlpha = 1 - math.exp(-CAMERA_TARGET_LERP_SPEED * dt)
        smoothedCameraTarget = smoothedCameraTarget and smoothedCameraTarget:Lerp(targetPosition, targetAlpha) or targetPosition
        local currentTarget = smoothedCameraTarget

        local rotation = CFrame.Angles(0, cameraYaw, 0) * CFrame.Angles(cameraPitch, 0, 0)
        local offset = rotation:VectorToWorldSpace(Vector3.new(0, 0, cameraDistance))
        local position = currentTarget + offset
        camera.CFrame = CFrame.lookAt(position, currentTarget)
        camera.Focus = CFrame.new(currentTarget)
    end)
end

-- カメラをロック
local function lockCamera(humanoid)
    local character = humanoid and humanoid.Parent
    local root = character and character:FindFirstChild("HumanoidRootPart")
    startManualBlobmanCamera(humanoid, root)
end

-- カメラ状態を保存
local function saveCamera()
    if cameraStateSaved then return end
    local camera = Workspace.CurrentCamera
    if camera then
        savedCameraType = camera.CameraType
        savedCameraSubject = camera.CameraSubject
        cameraStateSaved = true
    end
end

-- カメラを復元
restoreCamera = function()
    stopManualBlobmanCamera()
    cameraLocked = false
    lockedHumanoid = nil
    if cameraLockConnection then
        cameraLockConnection:Disconnect(); cameraLockConnection = nil
    end
    if not cameraStateSaved then return end
    local camera = Workspace.CurrentCamera
    if camera then
        camera.CameraType = savedCameraType
        local subject = savedCameraSubject
        if not subject or not subject.Parent then
            local currentCharacter = Player.Character
            subject = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
        end
        camera.CameraSubject = subject
    end
    savedCameraType = nil
    savedCameraSubject = nil
    cameraStateSaved = false
end

-- Blobmanを取得
local function getBlobman()
    local folder = Workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
    return folder and folder:FindFirstChild("CreatureBlobman")
end

-- Blobmanを生成
local function spawnBlobman()
    if getBlobman() then return true end
    local toys = ReplicatedStorage:FindFirstChild("MenuToys")
    local remote = toys and toys:FindFirstChild("SpawnToyRemoteFunction")
    if not remote then return false end
    local ok = pcall(function()
        remote:InvokeServer("CreatureBlobman", CFrame.new(0, 100000, 0), Vector3.zero)
    end)
    return ok and getBlobman() ~= nil
end

-- Blobmanに座る
local function sitOnBlobman()
    local blob = getBlobman()
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not blob or not humanoid or not root then return false end
    local seat = blob:FindFirstChild("VehicleSeat")
    if not seat then
        for _, child in ipairs(blob:GetChildren()) do
            if child:IsA("VehicleSeat") then seat = child; break end
        end
    end
    if not seat then return false end

    saveCamera()
    lockCamera(humanoid)

    originalCFrame = root.CFrame
    root.CFrame = seat.CFrame + Vector3.new(0, 0.5, 0)
    pcall(function() seat:Sit(humanoid) end)

    task.wait(0.01)

    -- Blobmanに座り続けるための監視タスク
    antiBlobmanActive = true
    antiBlobmanTask = task.spawn(function()
        while antiBlobmanActive do
            local char = Player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                hum.Sit = true
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
            task.wait()
        end
    end)

    task.wait(0.5)
    if originalCFrame and root.Parent then
        root.CFrame = originalCFrame
    end
    return true
end

-- 参照用ラグドール開始（Blobmanに座らせる）
local function startReferenceRagdoll()
    if not spawnBlobman() then
        notify("ゆずまいR", "Blobmanを生成できませんでした")
        return false
    end
    task.wait(0.5)
    if not sitOnBlobman() then
        notify("ゆずまいR", "BlobmanのVehicleSeatを検出できませんでした")
        return false
    end
    return true
end

-- 参照用ラグドール停止
local function stopReferenceRagdoll()
    antiBlobmanActive = false
    if antiBlobmanTask then task.cancel(antiBlobmanTask); antiBlobmanTask = nil end
    restoreCamera()
    if originalCFrame then
        local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = originalCFrame
        end
    end
    local blob = getBlobman()
    local toys = ReplicatedStorage:FindFirstChild("MenuToys")
    local destroy = toys and toys:FindFirstChild("DestroyToy")
    if blob and destroy then
        pcall(function() destroy:FireServer(blob) end)
    end
    originalCFrame = nil
end

-- ジョイスティックUIを作成
local function makeJoystick(parent, side, title)
    local panel = Instance.new("Frame")
    panel.Name = side .. "ArmPanel"
    panel.AnchorPoint = Vector2.new(0.5, 1)
    panel.Position = side == "Left" and UDim2.new(0, 115, 1, -18) or UDim2.new(1, -115, 1, -18)
    panel.Size = UDim2.fromOffset(210, 205)
    panel.BackgroundTransparency = 1
    panel.Parent = parent

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 0, 28)
    label.Text = title .. " (位置 + 回転)"
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = panel

    local stick = Instance.new("Frame")
    stick.AnchorPoint = Vector2.new(0.5, 0.5)
    stick.Position = UDim2.new(0.5, 0, 0.52, 0)
    stick.Size = UDim2.fromOffset(150, 150)
    stick.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
    stick.BackgroundTransparency = 0.22
    stick.Parent = panel
    stick.Active = true

    local stickCorner = Instance.new("UICorner")
    stickCorner.CornerRadius = UDim.new(1, 0)
    stickCorner.Parent = stick

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.fromScale(0.5, 0.5)
    knob.Size = UDim2.fromOffset(62, 62)
    knob.BackgroundColor3 = side == "Left" and Color3.fromRGB(65, 145, 255) or Color3.fromRGB(255, 105, 105)
    knob.Parent = stick
    knob.Active = false

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local state = {active = nil, vector = Vector2.zero, mouseDragging = false}

    local function update(inputPosition)
        local center = stick.AbsolutePosition + stick.AbsoluteSize / 2
        local radius = math.min(stick.AbsoluteSize.X, stick.AbsoluteSize.Y) / 2 - knob.AbsoluteSize.X / 2
        local delta = Vector2.new(inputPosition.X, inputPosition.Y) - center
        if delta.Magnitude > radius then
            delta = delta.Unit * radius
        end
        state.vector = delta / radius
        knob.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)
    end

    local function release()
        state.active = nil
        state.vector = Vector2.zero
        knob.Position = UDim2.fromScale(0.5, 0.5)
    end

    stick.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            state.active = input
            update(input.Position)
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            state.mouseDragging = true
            update(input.Position)
        end
    end)

    UserInputService.TouchMoved:Connect(function(input)
        if input == state.active then
            update(input.Position)
        end
    end)

    UserInputService.TouchEnded:Connect(function(input)
        if input == state.active then
            release()
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if state.mouseDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            update(input.Position)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input == state.active then
            release()
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            state.mouseDragging = false
            state.vector = Vector2.zero
            knob.Position = UDim2.fromScale(0.5, 0.5)
        end
    end)

    return state
end

-- 数値を範囲内にクランプ
local function clampNumber(value, low, high)
    return math.max(low, math.min(high, value))
end

-- スティック入力にデッドゾーンを適用
local function naturalStick(v)
    local deadZone = 0.12
    local magnitude = v.Magnitude
    if magnitude <= deadZone then return Vector2.zero end
    local remapped = clampNumber((magnitude - deadZone) / (1 - deadZone), 0, 1)
    return v.Unit * remapped
end

-- キーボードによる腕操作ベクトルを取得
local function getKeyboardArmVector(side)
    local keys = side == "Left" and {up = Enum.KeyCode.T, down = Enum.KeyCode.G, left = Enum.KeyCode.F, right = Enum.KeyCode.H} or {up = Enum.KeyCode.I, down = Enum.KeyCode.K, left = Enum.KeyCode.J, right = Enum.KeyCode.L}
    local x = (keyboardArmKeys[keys.right] and 1 or 0) - (keyboardArmKeys[keys.left] and 1 or 0)
    local y = (keyboardArmKeys[keys.down] and 1 or 0) - (keyboardArmKeys[keys.up] and 1 or 0)
    local vector = Vector2.new(x, y)
    return vector.Magnitude > 1 and vector.Unit or vector
end

-- 腕のローカルCFrameを計算（切り離し腕の目標位置）
local function getDetachedArmLocalCFrame(side, stickVector)
    local v = naturalStick(stickVector)
    v = Vector2.new(
        math.sign(v.X) * (math.abs(v.X) ^ ARM_INPUT_RESPONSE),
        math.sign(v.Y) * (math.abs(v.Y) ^ ARM_INPUT_RESPONSE)
    )
    local sideSign = side == "Left" and -1 or 1
    local shoulderForward = ARM_PIVOT_FORWARD - math.abs(v.Y) * ARM_PIVOT_FORWARD_SHIFT
    local shoulder = Vector3.new(
        sideSign * DETACHED_ARM_SIDE,
        ARM_PIVOT_HEIGHT,
        shoulderForward
    )
    local yaw = sideSign * ARM_NEUTRAL_SPLAY + math.clamp(v.X, -1, 1) * math.rad(100)
    local pitch = math.clamp(
        ARM_NEUTRAL_PITCH + math.clamp(-v.Y, -1, 1) * math.rad(100),
        math.rad(-80),
        math.rad(80)
    )
    local direction = Vector3.new(
        math.sin(yaw) * math.cos(pitch),
        math.sin(pitch),
        -math.cos(yaw) * math.cos(pitch)
    )
    if direction.Magnitude < 0.001 then
        direction = Vector3.new(0, 0, -1)
    end
    direction = direction.Unit
    local position = shoulder + direction * (ARM_REACH_RADIUS * ARM_CENTER_RATIO)
    position = position + Vector3.new(0, math.max(0, -v.Y) * ARM_UPWARD_POSITION_OFFSET, 0)

    local armYAxis = -direction
    -- sideSignを横軸の基準にすると、入力の僅かな差で腕の軸が反転する
    -- ワールド方向を基準にして、入力差で連続する動きを作る
    local worldUp = Vector3.new(0, 1, 0)
    local armRight = worldUp:Cross(armYAxis)
    if armRight.Magnitude < 0.05 then
        -- ピッチ方向では通常発生しないが、念のためフォールバック
        armRight = Vector3.new(1, 0, 0):Cross(armYAxis)
    end
    armRight = armRight.Unit
    local downRoll = math.max(0, v.Y) * ARM_DOWN_HAND_ROLL
    if math.abs(downRoll) > 0.001 then
        armRight = CFrame.fromAxisAngle(armYAxis, downRoll):VectorToWorldSpace(armRight).Unit
    end
    local armBack = armRight:Cross(armYAxis).Unit
    return CFrame.fromMatrix(position, armRight, armYAxis, armBack)
end

-- 腕の物理状態を元に戻す
local function restoreArmPhysics()
    for joint, wasEnabled in pairs(armBoundaryJointState) do
        if joint and joint.Parent then
            pcall(function() joint.Enabled = wasEnabled end)
        end
    end
    armBoundaryJointState = {}
    for _, noCollision in ipairs(armNoCollisionConstraints) do
        if noCollision and noCollision.Parent then
            noCollision:Destroy()
        end
    end
    armNoCollisionConstraints = {}
    for part, state in pairs(armPhysicsState) do
        if part and part.Parent then
            part.CanCollide = state.CanCollide
            part.CanTouch = state.CanTouch
            part.CanQuery = state.CanQuery
            part.Massless = state.Massless
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end
    armPhysicsState = {}
end

-- 腕の物理設定を強制（衝突なし・Massless）
local function enforceArmPhysics()
    for _, side in ipairs({"Left", "Right"}) do
        for _, part in ipairs(armParts[side] or {}) do
            if part and part.Parent then
                part.CanCollide = false
                part.CanTouch = false
                part.CanQuery = false
                part.Massless = ARM_MASSLESS
            end
        end
    end
end

-- 腕物理ガード開始
local function startArmPhysicsGuard()
    if armPhysicsConnection then
        armPhysicsConnection:Disconnect()
    end
    armPhysicsConnection = RunService.Heartbeat:Connect(function()
        if enabled then enforceArmPhysics() end
    end)
end

-- 腕物理ガード停止
local function stopArmPhysicsGuard()
    if armPhysicsConnection then
        armPhysicsConnection:Disconnect()
        armPhysicsConnection = nil
    end
end

-- タッチGUIを破棄
local function destroyTouchGui()
    if touchGui then
        touchGui:Destroy()
        touchGui = nil
    end
end

-- タッチGUIを作成
local function createTouchGui()
    destroyTouchGui()
    touchGui = Instance.new("ScreenGui")
    touchGui.Name = "YuzamaiVRTouch"
    touchGui.IgnoreGuiInset = true
    touchGui.ResetOnSpawn = false
    touchGui.DisplayOrder = 1000
    touchGui.Parent = CoreGui
    local leftState = makeJoystick(touchGui, "Left", "LEFT ARM")
    local rightState = makeJoystick(touchGui, "Right", "RIGHT ARM")
    return leftState, rightState
end

-- 停止処理
local function stop()
    enabled = false

    -- 蛇モードのパーツサイズを元に戻す
    for part, originalSize in pairs(snakeOriginalSizes) do
        if part and part.Parent then
            part.Size = originalSize
        end
    end
    snakeOriginalSizes = {}
    snakeEnabled = false
    snakePose = {}
    snakePathHistory = {}
    snakeRopePositions = {}
    snakeJointAngles = {}
    snakePathTime = 0
    snakeLastUpdate = nil

    sprintHeld = false

    if renderConnection then
        RunService:UnbindFromRenderStep(renderStepName)
        renderConnection = nil
    end
    if ragdollTask then
        task.cancel(ragdollTask)
        ragdollTask = nil
    end
    if armNetworkSyncConnection then
        armNetworkSyncConnection:Disconnect()
        armNetworkSyncConnection = nil
    end
    if inputConnection then
        inputConnection:Disconnect()
        inputConnection = nil
    end
    if keyboardEndedConnection then
        keyboardEndedConnection:Disconnect()
        keyboardEndedConnection = nil
    end
    keyboardArmKeys = {}
    destroyTouchGui()
    stopArmPhysicsGuard()
    restoreArmPhysics()
    stopReferenceRagdoll()

    -- 体の位置を元に戻す
    if fixedBodyCFrame and Character then
        local rootPart = Character:FindFirstChild("HumanoidRootPart")
        if rootPart and rootPart:IsA("BasePart") then
            rootPart.CFrame = fixedBodyCFrame
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
        end

        for name, localCFrame in pairs(bodyState) do
            local bodyPart = Character:FindFirstChild(name)
            if bodyPart and bodyPart:IsA("BasePart") then
                bodyPart.CFrame = fixedBodyCFrame * localCFrame
                bodyPart.AssemblyLinearVelocity = Vector3.zero
                bodyPart.AssemblyAngularVelocity = Vector3.zero
            end
        end

        local head = Character:FindFirstChild("Head")
        if head and head:IsA("BasePart") and headState then
            head.CFrame = fixedBodyCFrame * headState
            head.AssemblyLinearVelocity = Vector3.zero
            head.AssemblyAngularVelocity = Vector3.zero
        end

        for _, state in pairs(legState) do
            for _, entry in ipairs(state.parts or {}) do
                local leg = entry.part
                if leg and leg.Parent then
                    leg.CFrame = fixedBodyCFrame * entry.base
                    leg.AssemblyLinearVelocity = Vector3.zero
                    leg.AssemblyAngularVelocity = Vector3.zero
                end
            end
        end
    end

    fixedBodyCFrame = nil
    detachedBodyCFrame = nil
    headState = nil
    flightVelocity = Vector3.zero
    flightArmPhase = 0
    flightArmIntensity = 0
    smoothedCameraTarget = nil
    jumpDone = false

    fireRagdoll(false)

    -- ③の制御（解除処理）に移動・回転を引き継ぎ、立ち上がりステートを適用
    local humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.AutoRotate = true
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end

    if statusLabel then
        statusLabel:SetText("Status: OFF")
    end
end

-- 開始処理
local function start()
    if enabled then return end
    local _, root = refreshCharacter()
    if not root or not arms.Left or not arms.Right then
        notify("ゆずまいR", "左右の腕を検出できません。R6/R15の腕名を確認してください")
        return
    end

    enabled = true
    jumpDone = false
    fixedBodyCFrame = root.CFrame
    detachedBodyCFrame = fixedBodyCFrame + Vector3.new(0, DETACHED_BODY_HEIGHT, 0)
    flightVelocity = Vector3.zero
    flightArmPhase = 0
    flightArmIntensity = 0
    smoothedCameraTarget = root.Position + cameraTargetOffset

    fireRagdoll(true)
    ragdollTask = task.spawn(function()
        local startTime = tick()
        while enabled do
            fireRagdoll(true)
            local humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
            if humanoid and not jumpDone and tick() - startTime >= 0.1 then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                jumpDone = true
            end
            task.wait(0.1)
        end
    end)

    local referenceStarted = startReferenceRagdoll()
    if not referenceStarted then
        enabled = false
        destroyTouchGui()
        restoreArmPhysics()
        stopReferenceRagdoll()
        fireRagdoll(false)
        return
    end

    task.wait(0.25)
    local leftStick, rightStick = createTouchGui()
    keyboardArmKeys = {}

    inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
            sprintHeld = true
            return
        end
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.T or input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.H or input.KeyCode == Enum.KeyCode.I or input.KeyCode == Enum.KeyCode.J or input.KeyCode == Enum.KeyCode.K or input.KeyCode == Enum.KeyCode.L then
            keyboardArmKeys[input.KeyCode] = true
        end
    end)

    keyboardEndedConnection = UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
            sprintHeld = false
        end
        keyboardArmKeys[input.KeyCode] = nil
    end)

    if statusLabel then
        statusLabel:SetText("Status: ON / JSON ARMS / VIRTUAL MOVEMENT")
    end

    -- 毎フレームのメイン処理
    RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Character.Value + 2, function(dt)
        if not enabled then return end

        local rootPart = armState.Left and armState.Left.root or armState.Right and armState.Right.root
        local bodyPositionBeforeArms
        local bodyVelocityBeforeArms
        local bodyRotationBeforeArms
        if rootPart and rootPart.Parent then
            local humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
            local moveDirection = humanoid and humanoid.MoveDirection or Vector3.zero
            local camera = Workspace.CurrentCamera

            if hardBodyLock and fixedBodyCFrame then
                -- Humanoidの移動速度をそのまま使わず、水平速度を滑らかに加減速する
                -- Yは常に現在値を維持するため、上下移動の発生しない
                local move = Vector3.new(moveDirection.X, 0, moveDirection.Z)
                local targetVelocity = Vector3.zero
                local sprinting = sprintHeld and move.Magnitude > 0.05
                local currentMoveSpeed = sprinting and SPRINT_SPEED or NORMAL_MOVE_SPEED
                if move.Magnitude > 0.05 then
                    targetVelocity = move.Unit * currentMoveSpeed
                end
                local response = targetVelocity.Magnitude > flightVelocity.Magnitude and FLIGHT_ACCELERATION or FLIGHT_DECELERATION
                local blend = 1 - math.exp(-response * dt)
                flightVelocity = flightVelocity:Lerp(targetVelocity, blend)

                local horizontalVelocity = Vector3.new(flightVelocity.X, 0, flightVelocity.Z)
                local speedRatio = math.clamp(horizontalVelocity.Magnitude / FLIGHT_MAX_SPEED, 0, 1)

                -- 向きは移動方向のまま。ナルト走りの前傾だけを姿勢へ加える
                local leanAmount = (sprintHeld and horizontalVelocity.Magnitude > 0.05) and math.clamp(speedRatio, 0, 1) * NARUTO_BODY_LEAN or 0
                local bodyRotation = CFrame.Angles(0, standingYaw, 0) * CFrame.Angles(-leanAmount, 0, 0)

                if horizontalVelocity.Magnitude > 0.05 and not snakeEnabled then
                    local targetYaw = math.atan2(-horizontalVelocity.X, -horizontalVelocity.Z)
                    local yawDelta = math.atan2(
                        math.sin(targetYaw - standingYaw),
                        math.cos(targetYaw - standingYaw)
                    )
                    standingYaw = standingYaw + yawDelta * (1 - math.exp(-TURN_SPEED * dt))
                    bodyRotation = CFrame.Angles(0, standingYaw, 0) * CFrame.Angles(-leanAmount, 0, 0)
                    fixedBodyCFrame = CFrame.new(
                        fixedBodyCFrame.Position + horizontalVelocity * dt
                    ) * bodyRotation
                    standingPosition = fixedBodyCFrame.Position
                elseif horizontalVelocity.Magnitude > 0.05 then
                    -- 蛇モードでは胴体の向きを変えず、位置だけを移動
                    -- 曲がりは脚のワールド軌跡を復元パスが追って表現する
                    fixedBodyCFrame = CFrame.new(
                        fixedBodyCFrame.Position + horizontalVelocity * dt
                    ) * CFrame.Angles(0, standingYaw, 0)
                    standingPosition = fixedBodyCFrame.Position
                elseif flightVelocity.Magnitude > 0.05 then
                    fixedBodyCFrame = CFrame.new(
                        fixedBodyCFrame.Position + horizontalVelocity * dt
                    ) * bodyRotation
                    standingPosition = fixedBodyCFrame.Position
                else
                    fixedBodyCFrame = CFrame.new(fixedBodyCFrame.Position) * CFrame.Angles(0, standingYaw, 0)
                end

                detachedBodyCFrame = CFrame.new(
                    fixedBodyCFrame.Position + Vector3.new(0, DETACHED_BODY_HEIGHT, 0)
                ) * (fixedBodyCFrame - fixedBodyCFrame.Position)

                if not hardBodyLock then
                    rootPart.CFrame = fixedBodyCFrame
                    local rootVelocity = rootPart.AssemblyLinearVelocity
                    if rootVelocity.Magnitude > VELOCITY_EPSILON then
                        rootPart.AssemblyLinearVelocity = Vector3.zero
                    end
                    if rootPart.AssemblyAngularVelocity.Magnitude > VELOCITY_EPSILON then
                        rootPart.AssemblyAngularVelocity = Vector3.zero
                    end
                end
            end

            local forward = camera and camera.CFrame.LookVector or rootPart.CFrame.LookVector
            local right = camera and camera.CFrame.RightVector or rootPart.CFrame.RightVector
            forward = Vector3.new(forward.X, 0, forward.Z)
            right = Vector3.new(right.X, 0, right.Z)
            if forward.Magnitude > 0.001 and right.Magnitude > 0.001 then
                forward = forward.Unit
                right = right.Unit

                if not hardBodyLock then
                    local desiredVelocity = Vector3.new(moveDirection.X, 0, moveDirection.Z) * MOVE_SPEED
                    local currentY = rootPart.AssemblyLinearVelocity.Y
                    rootPart.AssemblyLinearVelocity = Vector3.new(desiredVelocity.X, currentY, desiredVelocity.Z)
                end
            end

            local isWalking = moveDirection.Magnitude > 0.05
            if isWalking and not hardBodyLock then
                local horizontalMove = Vector3.new(moveDirection.X, 0, moveDirection.Z)
                if horizontalMove.Magnitude > 0.001 then
                    horizontalMove = horizontalMove.Unit
                    local targetYaw = math.atan2(-horizontalMove.X, -horizontalMove.Z)
                    local yawDelta = math.atan2(
                        math.sin(targetYaw - standingYaw),
                        math.cos(targetYaw - standingYaw)
                    )
                    standingYaw = standingYaw + yawDelta * (1 - math.exp(-TURN_SPEED * dt))
                end
                standingPosition = rootPart.Position
            elseif standingPosition and not hardBodyLock then
                local anchor = Vector3.new(standingPosition.X, rootPart.Position.Y, standingPosition.Z)
                local offset = anchor - rootPart.Position
                if offset.Magnitude < ROOT_DRIFT_SNAP_DISTANCE then
                    local velocity = rootPart.AssemblyLinearVelocity
                    rootPart.AssemblyLinearVelocity = Vector3.new(
                        velocity.X + offset.X * ROOT_RETURN_SPEED,
                        velocity.Y,
                        velocity.Z + offset.Z * ROOT_RETURN_SPEED
                    )
                else
                    local velocity = rootPart.AssemblyLinearVelocity
                    rootPart.AssemblyLinearVelocity = Vector3.new(
                        velocity.X * 0.5,
                        velocity.Y,
                        velocity.Z * 0.5
                    )
                end
            end
        end

        if not rootPart or not rootPart.Parent then return end

        -- 蛇モードでは、このRenderStepの通常腕動作を適用しない
        -- 後段の専用配置が上フレームを上書きされるのを防ぐ
        if snakeEnabled then return end

        local horizontalVelocity = Vector3.new(
            rootPart.AssemblyLinearVelocity.X,
            0,
            rootPart.AssemblyLinearVelocity.Z
        )
        local currentHumanoid = Character and Character:FindFirstChildOfClass("Humanoid")
        local inputMagnitude = currentHumanoid and currentHumanoid.MoveDirection.Magnitude or 0
        local moving = horizontalVelocity.Magnitude > 1 or inputMagnitude > 0.05
        local sprinting = sprintHeld and inputMagnitude > 0.05
        local gaitMagnitude = hardBodyLock and inputMagnitude or horizontalVelocity.Magnitude / NORMAL_MOVE_SPEED
        local narutoActive = moving and sprinting
        local speedRatio = math.clamp(gaitMagnitude, 0.35, 1.5)

        if moving then
            local cycleSpeed = narutoActive and SPRINT_WALK_CYCLE_SPEED or NORMAL_WALK_CYCLE_SPEED
            walkTime = walkTime + dt * cycleSpeed * speedRatio
        end

        local stride = moving and math.clamp(gaitMagnitude, 0.35, 1) or 0

        -- ナルト走りの腕の強度
        local flightSpeed = Vector3.new(flightVelocity.X, 0, flightVelocity.Z).Magnitude
        local targetArmIntensity = narutoActive and math.clamp(flightSpeed / SPRINT_SPEED, 0, 1) or 0
        local armIntensityAlpha = 1 - math.exp(-8 * dt)
        flightArmIntensity = flightArmIntensity + (targetArmIntensity - flightArmIntensity) * armIntensityAlpha
        if flightArmIntensity > 0.01 then
            flightArmPhase = flightArmPhase + dt * (7 + 5 * flightArmIntensity)
        end

        -- 左右で同じ振り子係数を共有し、両腕を同時に後方へ移動させる
        local narutoPoseAlpha = math.clamp(flightArmIntensity * 1.5, 0, 1)

        if rootPart and rootPart.Parent then
            bodyPositionBeforeArms = rootPart.Position
            local preArmVelocity = rootPart.AssemblyLinearVelocity
            bodyVelocityBeforeArms = Vector3.new(preArmVelocity.X, 0, preArmVelocity.Z)
            bodyRotationBeforeArms = rootPart.CFrame - rootPart.Position
        end

        -- 左右の腕を個別に処理
        for _, side in ipairs({"Left", "Right"}) do
            local stick = side == "Left" and leftStick or rightStick
            local part = arms[side]
            local s = armState[side]
            if part and part.Parent and s and s.root and s.root.Parent then
                local inputAlpha = 1 - math.exp(-ARM_INPUT_SMOOTHING * dt)
                local combinedInput = stick.vector + getKeyboardArmVector(side)
                if combinedInput.Magnitude > 1 then
                    combinedInput = combinedInput.Unit
                end
                s.input = s.input:Lerp(combinedInput, inputAlpha)

                -- 移動開始の際、移動中は左右のスティック入力を無視
                -- 入力差動を潰し、出発点にすると、腕が揃って・遠・に戻るため
                -- 左右対称のニュートラル動作を強制し、出発点にする
                -- 腕のスティック/キー操作を補完する
                -- 停止中は入力したポーズ、移動中は左右同期したナルト姿勢を使う
                -- 移動中の揺れを動かニュートラルから抑えることで、左右の差をそろえる
                local armInputTarget = getDetachedArmLocalCFrame(
                    side,
                    narutoActive and Vector2.zero or s.input
                )

                -- ナルト走りの、「肩から手までを一直線」にする
                -- 左右の幅を広く取り、移動中も最も腕幅を維持する
                local sideSign = side == "Left" and -1 or 1
                local handDirection = Vector3.new(
                    sideSign * math.sin(NARUTO_ARM_SPLAY),
                    0,
                    math.cos(NARUTO_ARM_SPLAY)
                ).Unit
                local shoulderPosition = Vector3.new(
                    sideSign * 1.35,
                    NARUTO_ARM_DROP,
                    0.10
                )
                local armPosition = shoulderPosition + handDirection * NARUTO_ARM_BACK
                local armYAxis = -handDirection
                -- 左右で同じ+X基準を使い、回転軸を完全にそろえる
                local sharedRightReference = Vector3.new(1, 0, 0)
                local armRight = sharedRightReference - armYAxis * sharedRightReference:Dot(armYAxis)
                if armRight.Magnitude < 0.05 then
                    armRight = Vector3.new(0, 1, 0) - armYAxis * Vector3.new(0, 1, 0):Dot(armYAxis)
                end
                armRight = armRight.Unit
                local armBack = armRight:Cross(armYAxis).Unit
                local narutoArmTarget = CFrame.fromMatrix(
                    armPosition,
                    armRight,
                    armYAxis,
                    armBack
                )

                -- 左右で完全に同じ係数を使い、片腕だけが後ろへ行かないようにする
                local armLocalTarget = armInputTarget:Lerp(
                    narutoArmTarget,
                    narutoPoseAlpha
                )

                local armBaseCFrame = (hardBodyLock and fixedBodyCFrame) or s.root.CFrame
                for _, attachedPart in ipairs(armParts[side] or {}) do
                    if attachedPart and attachedPart.Parent then
                        local baseOffset = s.partBases and s.partBases[attachedPart]
                        if baseOffset then
                            local target = armBaseCFrame * armLocalTarget * baseOffset
                            local previousTarget = s.previousTargets[attachedPart]
                            if previousTarget then
                                local delta = previousTarget:ToObjectSpace(target)
                                local _, angle = delta:ToAxisAngle()
                                if delta.Position.Magnitude < 0.002 and angle < math.rad(0.15) then
                                    target = previousTarget
                                else
                                    local poseAlpha = 1 - math.exp(-ARM_POSE_LERP_SPEED * dt)
                                    target = previousTarget:Lerp(target, poseAlpha)
                                end
                            end
                            s.previousTargets[attachedPart] = target
                            attachedPart.CFrame = target
                            attachedPart.AssemblyLinearVelocity = Vector3.zero
                            attachedPart.AssemblyAngularVelocity = Vector3.zero
                        end
                    end
                end
            end
        end

        -- 体の位置固定・脚の歩行アニメーション
        if hardBodyLock and fixedBodyCFrame and detachedBodyCFrame and rootPart and rootPart.Parent then
            -- ルートと胴体のみを地面下へ退避
            rootPart.CFrame = detachedBodyCFrame
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero

            for name, localCFrame in pairs(bodyState) do
                local bodyPart = Character and Character:FindFirstChild(name)
                if bodyPart and bodyPart:IsA("BasePart") then
                    bodyPart.CFrame = detachedBodyCFrame * localCFrame
                    bodyPart.AssemblyLinearVelocity = Vector3.zero
                    bodyPart.AssemblyAngularVelocity = Vector3.zero
                end
            end

            -- 頭は元の位置に固定
            local head = Character and Character:FindFirstChild("Head")
            if head and head:IsA("BasePart") and headState then
                head.CFrame = fixedBodyCFrame * headState
                head.AssemblyLinearVelocity = Vector3.zero
                head.AssemblyAngularVelocity = Vector3.zero
            end

            -- 脚の歩行アニメーション
            for _, side in ipairs({"Left", "Right"}) do
                local state = legState[side]
                local phase = walkTime + (side == "Left" and 0 or math.pi)
                local forward = math.sin(phase)
                local swing = forward * LEG_SWING_ANGLE * stride
                local lift = math.max(0, forward) * LEG_LIFT_HEIGHT * stride

                if state and state.parts then
                    for _, entry in ipairs(state.parts) do
                        local leg = entry.part
                        if leg and leg.Parent then
                            local target = detachedBodyCFrame * entry.base * CFrame.new(0, 0, 0) * CFrame.Angles(swing, 0, 0)
                            -- 目標CFrameへ滑らかに同期し、物理挙動の流れによる揺れを防ぐ
                            leg.CFrame = target
                            leg.AssemblyLinearVelocity = Vector3.zero
                            leg.AssemblyAngularVelocity = Vector3.zero
                        end
                    end
                end
            end
        end
    end)

    -- ネットワーク同期用のHeartbeat（後追い同期）
    armNetworkSyncConnection = RunService.Heartbeat:Connect(function()
        if not enabled then return end

        for _, side in ipairs({"Left", "Right"}) do
            local state = armState[side]
            if state and state.previousTargets then
                for _, attachedPart in ipairs(armParts[side] or {}) do
                    local target = state.previousTargets[attachedPart]
                    if attachedPart and attachedPart.Parent and target then
                        attachedPart.CFrame = target
                        attachedPart.AssemblyLinearVelocity = Vector3.zero
                        attachedPart.AssemblyAngularVelocity = Vector3.zero
                    end
                end
            end
        end

        if snakeEnabled then
            applySnakePose()
            return
        end

        if fixedBodyCFrame and detachedBodyCFrame and Character then
            local rootPart = Character:FindFirstChild("HumanoidRootPart")
            if rootPart and rootPart.Parent then
                rootPart.CFrame = detachedBodyCFrame
                rootPart.AssemblyLinearVelocity = Vector3.zero
                rootPart.AssemblyAngularVelocity = Vector3.zero
            end

            for name, localCFrame in pairs(bodyState) do
                local bodyPart = Character:FindFirstChild(name)
                if bodyPart and bodyPart:IsA("BasePart") then
                    bodyPart.CFrame = detachedBodyCFrame * localCFrame
                    bodyPart.AssemblyLinearVelocity = Vector3.zero
                    bodyPart.AssemblyAngularVelocity = Vector3.zero
                end
            end

            -- Heartbeatでも位置を固定し、物理ステップで地面から押し戻されるのを防ぐ
            for _, state in pairs(legState) do
                for _, entry in ipairs(state.parts or {}) do
                    local leg = entry.part
                    if leg and leg.Parent then
                        leg.CFrame = detachedBodyCFrame * entry.base
                        leg.AssemblyLinearVelocity = Vector3.zero
                        leg.AssemblyAngularVelocity = Vector3.zero
                    end
                end
            end

            local head = Character:FindFirstChild("Head")
            if head and head:IsA("BasePart") and headState then
                head.CFrame = fixedBodyCFrame * headState
                head.AssemblyLinearVelocity = Vector3.zero
                head.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end)

    renderConnection = true
    notify("ゆずまいR", "JSON方式で腕を前方配置しました")
end

-- 蛇モードのポーズを再構築
local function rebuildSnakePose()
    snakePose = {}
    local z = 0
    -- 脚と次のパーツを実際の端同士で接続し、空きを作らない
    local gap = 0
    local axisY = 1.35
    local forwardRotation = CFrame.Angles(math.rad(90), 0, 0)

    -- 各パーツの長軸を実際から取得し、余分な長さも接続する
    -- 脚は動きの方向、胴体の脚・腕の縦長のY軸を蛇のZ軸へ回す
    local function add(part, length, rotation, y, x, extend)
        if not part then return end
        if extend then
            if not snakeOriginalSizes[part] then
                snakeOriginalSizes[part] = part.Size
            end
            part.Size = Vector3.new(
                snakeOriginalSizes[part].X,
                snakeOriginalSizes[part].Y * SNAKE_LIMB_LENGTH_SCALE,
                snakeOriginalSizes[part].Z
            )
            length = snakeOriginalSizes[part].Y * SNAKE_LIMB_LENGTH_SCALE
        end
        local half = length * 0.5
        z = z + half
        snakePose[#snakePose + 1] = {
            part = part,
            length = length,
            rotation = rotation,
            offset = Vector3.new(x or 0, y, z),
        }
        z = z + half + gap
    end

    local head = Character and Character:FindFirstChild("Head")
    if head then
        -- Headの前後方向を蛇の進行方向にする
        add(head, math.max(head.Size.Z, 0.8), CFrame.new(), axisY, 0)
    end

    -- 胴体を使わず、頭の直後から足を接続する
    for _, side in ipairs({"Left", "Right"}) do
        local state = legState[side]
        for _, entry in ipairs(state and state.parts or {}) do
            local part = entry.part
            add(part, math.max(part.Size.Y, 0.5), forwardRotation, axisY, 0, true)
        end
    end

    -- 腕も接続して蛇を長くする
    for _, side in ipairs({"Left", "Right"}) do
        local state = armState[side]
        for _, part in ipairs(armParts[side] or {}) do
            if state and state.partBases and state.partBases[part] then
                add(part, math.max(part.Size.Y, 0.5), forwardRotation, axisY, 0, true)
            end
        end
    end
end

-- 蛇ポーズを毎フレーム適用
applySnakePose = function()
    if not fixedBodyCFrame or not detachedBodyCFrame then return end
    local humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    local inputAmount = humanoid and humanoid.MoveDirection.Magnitude or 0
    local flightAmount = Vector3.new(flightVelocity.X, 0, flightVelocity.Z).Magnitude
    local movingAmount = math.clamp(math.max(inputAmount, flightAmount / math.max(FLIGHT_MAX_SPEED, 1)), 0, 1)
    local isMoving = movingAmount > 0.05

    if isMoving then
        snakeWasMoving = true
    elseif snakeWasMoving then
        -- 停止へ切り替わった瞬間、頭の角度を保存する
        snakeRestHeadAngle = snakeJointAngles[1] or 0
        snakeWasMoving = false
    end

    local headOffset = snakePose[1] and snakePose[1].offset or Vector3.zero

    -- 頭の位置と向きだけを基準に保存する。停止中も基準を進めることで、
    -- 過去の軌跡が徐々に後ろへ流れ、胴体が後ろに取り残される
    local realNow = os.clock()
    if snakeLastUpdate then
        local dt = math.clamp(realNow - snakeLastUpdate, 0, 0.05)
        snakePathTime = snakePathTime + dt
    end
    snakeLastUpdate = realNow
    local now = snakePathTime
    local headWorld = fixedBodyCFrame:PointToWorldSpace(headOffset)

    -- 胴体の向きは固定したまま、頭に応じた移動方向へ向ける
    local forward = isMoving and Vector3.new(flightVelocity.X, 0, flightVelocity.Z) or fixedBodyCFrame.LookVector
    forward = Vector3.new(forward.X, 0, forward.Z)
    if forward.Magnitude < 0.001 then
        forward = Vector3.new(0, 0, -1)
    else
        forward = forward.Unit
    end

    snakePathHistory[#snakePathHistory + 1] = {
        time = now,
        position = headWorld,
        forward = forward,
    }
    if #snakePathHistory > 360 then
        table.remove(snakePathHistory, 1)
    end

    -- 指定遅延の頭サンプルを取得する
    local function delayedHeadSample(delay)
        local wanted = now - delay
        for historyIndex = #snakePathHistory, 1, -1 do
            local sample = snakePathHistory[historyIndex]
            if sample.time <= wanted then
                local newer = snakePathHistory[historyIndex + 1]
                if newer and newer.time > sample.time then
                    local alpha = math.clamp(
                        (wanted - sample.time) / (newer.time - sample.time),
                        0,
                        1
                    )
                    local sampleForward = sample.forward:Lerp(newer.forward, alpha)
                    if sampleForward.Magnitude < 0.001 then
                        sampleForward = sample.forward
                    else
                        sampleForward = sampleForward.Unit
                    end
                    return {
                        position = sample.position:Lerp(newer.position, alpha),
                        forward = sampleForward,
                    }
                end
                return sample
            end
        end
        return snakePathHistory[1]
    end

    local historySpeed = SNAKE_HISTORY_SPEED
    local headZ = headOffset.Z
    local previousTarget

    for index, segment in ipairs(snakePose) do
        local part = segment.part
        if part and part.Parent then
            -- 実際の胴体間距離を履歴時間へ変換する。これで頭→足→腕の
            -- 間の分がパーツ長さに依存して安定する
            local distanceBehindHead = math.max(segment.offset.Z - headZ, 0)
            local delay = distanceBehindHead / historySpeed
            local delayed = delayedHeadSample(delay)
            local delayedLocal = fixedBodyCFrame:PointToObjectSpace(delayed.position)

            -- 停止時専用の目標位置は使わず、各パーツが頭の過去軌跡を
            -- そのまま追う。これで直線に同じ経路へ吸われず、自然に収束する
            local targetLocal = Vector3.new(
                delayedLocal.X,
                segment.offset.Y + SNAKE_VERTICAL_OFFSET,
                delayedLocal.Z
            )

            if not isMoving and index > 1 then
                -- 停止時も同じ軸を使い、終点が僅かに頭の後ろへずらす
                -- 頭へ重ならず、急に一直線へ吸われることもない
                local restForward = fixedBodyCFrame:VectorToObjectSpace(delayed.forward)
                restForward = Vector3.new(restForward.X, 0, restForward.Z)
                if restForward.Magnitude > 0.001 then
                    targetLocal = targetLocal - restForward.Unit * SNAKE_REST_TRAIL
                end
            end

            local targetAngle = 0
            if previousTarget then
                local tangent = targetLocal - previousTarget
                if tangent.Magnitude > 0.001 then
                    targetAngle = math.atan2(tangent.X, tangent.Z)
                end
            else
                local delayedForward = fixedBodyCFrame:VectorToObjectSpace(delayed.forward)
                targetAngle = math.atan2(-delayedForward.X, -delayedForward.Z)
            end
            if not isMoving and index == 1 then
                targetAngle = snakeRestHeadAngle
            end

            local currentAngle = snakeJointAngles[index] or targetAngle
            local angleDelta = math.atan2(
                math.sin(targetAngle - currentAngle),
                math.cos(targetAngle - currentAngle)
            )
            local angleBlend = index == 1 and 0.24 or 0.12
            currentAngle = currentAngle + angleDelta * angleBlend
            snakeJointAngles[index] = currentAngle

            local currentPosition = snakeRopePositions[index] or targetLocal
            local positionBlend = index == 1 and 0.30 or 0.14
            local localPosition = currentPosition:Lerp(targetLocal, positionBlend)
            snakeRopePositions[index] = localPosition

            local target = fixedBodyCFrame * CFrame.new(localPosition) * CFrame.Angles(0, currentAngle, 0) * segment.rotation
            part.CFrame = target
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero

            previousTarget = targetLocal
        end
    end

    local rootPart = Character and Character:FindFirstChild("HumanoidRootPart")
    if rootPart and rootPart.Parent then
        rootPart.CFrame = detachedBodyCFrame
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
    end
end

-- 蛇モード開始
local function startSnake()
    if snakeEnabled then return end
    snakeEnabled = true
    start()
    if not enabled then
        snakeEnabled = false
        snakePose = {}
        return
    end

    rebuildSnakePose()
    snakePathHistory = {}
    snakeRopePositions = {}
    snakeJointAngles = {}
    snakePathTime = 0
    snakeLastUpdate = nil
    snakeWasMoving = false
    snakeRestHeadAngle = 0

    -- 初期履歴を頭の前方に配置する
    local initialOffset = snakePose[1] and snakePose[1].offset or Vector3.zero
    local initialPosition = fixedBodyCFrame:PointToWorldSpace(initialOffset)
    local initialForward = fixedBodyCFrame.LookVector
    initialForward = Vector3.new(initialForward.X, 0, initialForward.Z)
    if initialForward.Magnitude < 0.001 then
        initialForward = Vector3.new(0, 0, -1)
    else
        initialForward = initialForward.Unit
    end

    for sampleIndex = 120, 0, -1 do
        snakePathHistory[#snakePathHistory + 1] = {
            time = -sampleIndex / 60,
            position = initialPosition - initialForward * (sampleIndex * 8 / 60),
            forward = initialForward,
        }
    end

    if statusLabel then
        statusLabel:SetText("Status: ON / 蛇: 頭 → 足 → 腕")
    end
end

-- 蛇モード停止
stopSnake = function()
    snakeEnabled = false
    snakePose = {}
    stop()
end

-- UIウィンドウ作成
local Window = Library:CreateWindow({
    Title = "ゆずまいR",
    Footer = "JSON-Style Detached Arm Controller",
    Icon = 120050296012939,
    NotifySide = "Right",
    ShowCustomCursor = false,
    EnableCompacting = true,
    SidebarCompacted = true,
    CornerRadius = 15
})

-- 通常タブ
local MainTab = Window:AddTab("通常", "target")
local MainGroup = MainTab:AddLeftGroupbox("ゆずまいR")
local InfoGroup = MainTab:AddRightGroupbox("Info")
statusLabel = InfoGroup:AddLabel("Status: OFF")

-- 自動ラグドールトグル
MainGroup:AddToggle("AutoRagdoll", {
    Text = "VRゆりまそぅ",
    Default = true,
    Callback = function(value)
        if value then
            if snakeEnabled then stopSnake() end
            start()
        else
            stop()
        end
    end
})

-- タッチスティック表示ボタン
MainGroup:AddButton({
    Text = "Show Touch Sticks",
    Func = function()
        if enabled then createTouchGui() end
    end,
    DoubleClick = false
})

-- 停止ボタン
MainGroup:AddButton({
    Text = "停止 / ゆずまいR解除",
    Func = stop,
    DoubleClick = false
})

-- 蛇タブ
local SnakeTab = Window:AddTab("蛇", "activity")
local SnakeGroup = SnakeTab:AddLeftGroupbox("蛇")
SnakeGroup:AddLabel("頭 → 足 → 腕")

-- 蛇モードトグル
SnakeGroup:AddToggle("SnakeMode", {
    Text = "蛇モード ON",
    Default = false,
    Callback = function(value)
        if value then
            startSnake()
        else
            stopSnake()
        end
    end
})

-- 蛇モード停止ボタン
SnakeGroup:AddButton({
    Text = "蛇モード停止",
    Func = stopSnake,
    DoubleClick = false
})

-- UI設定タブ
local UISettingsTab = Window:AddTab("UI Settings", "settings")
local MenuGroup = UISettingsTab:AddLeftGroupbox("Menu")

-- アンロードボタン
MenuGroup:AddButton({
    Text = "Unload",
    Func = function()
        stop()
        Library:Unload()
    end,
    DoubleClick = false
})

-- メニューキーバインド
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
    Default = "RightShift",
    NoUI = true,
    Text = "Menu keybind"
})
Library.ToggleKeybind = Options.MenuKeybind

-- テーマ・保存管理の設定
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind"})
ThemeManager:SetFolder("YuzamaiVR")
SaveManager:SetFolder("YuzamaiVR")
SaveManager:SetSubFolder("config")
ThemeManager:ApplyToTab(UISettingsTab)
SaveManager:BuildConfigSection(UISettingsTab)
SaveManager:LoadAutoloadConfig()

-- キャラクター安全バインド
local function bindCharacterSafety(character)
    if deathConnection then
        deathConnection:Disconnect()
        deathConnection = nil
    end
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        deathConnection = humanoid.Died:Connect(function()
            if enabled then
                stop()
            else
                restoreCamera()
            end
        end)
    end
end

-- キャラクター削除時の処理
characterRemovingConnection = Player.CharacterRemoving:Connect(function()
    if enabled then
        stop()
    else
        restoreCamera()
    end
end)

-- キャラクター追加時の処理
characterConnection = Player.CharacterAdded:Connect(function(character)
    bindCharacterSafety(character)
    restoreCamera()
    task.defer(function()
        if enabled then return end
        local camera = Workspace.CurrentCamera
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if camera and humanoid and humanoid.Parent then
            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = humanoid
        end
    end)
end)

bindCharacterSafety(Player.Character)
task.defer(start)
notify("ゆずまいR", "Load - ゆずまいR start")

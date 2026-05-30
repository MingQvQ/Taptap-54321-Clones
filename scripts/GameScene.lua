-- ============================================================================
-- GameScene.lua - 游戏主场景逻辑
-- 管理物理世界、关卡加载、碰撞检测、NanoVG渲染、胜负判定
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local Player = require("Player")
local CloneSystem = require("CloneSystem")
local LevelData = require("LevelData")
local SceneManager = require("SceneManager")
local ParallaxBackground = require("ParallaxBackground")

local GameScene = {}

-- 内部状态
local scene_ = nil
local cameraNode_ = nil
local physicsWorld_ = nil
local nvg_ = nil

local mainPlayer_ = nil
local cloneSystem_ = nil
local currentLevel_ = 1

-- 关卡数据
local platforms_ = {}
local spikes_ = {}
local goalArea_ = nil
local spawnPos_ = { x = 0, y = 0 }  -- 出生点坐标

-- 瓦片纹理渲染数据（编辑器测试模式）
local tileCells_ = {}         -- { x, y, size, image, color }[]
local tileImages_ = {}        -- 已加载的纹理缓存 { [imagePath] = nvgImageHandle }
local hasTileTextures_ = false  -- 是否使用纹理渲染（编辑器模式）

-- 地图尺寸（物理单位，用于自适应相机）
local mapGridW_ = 0   -- 网格列数（如 16）
local mapGridH_ = 0   -- 网格行数（如 9）

-- 游戏状态
local STATE_PLAYING = "playing"
local STATE_PAUSED = "paused"
local STATE_WIN = "win"
local STATE_LOSE = "lose"
local gameState_ = STATE_PLAYING
local stateTimer_ = 0  -- 胜负后的延迟
local pauseUI_ = nil   -- 暂停菜单 UI 根引用
local hudUI_ = nil     -- 游戏 HUD（含暂停按钮）

-- 渲染缓存
local screenW_ = 0
local screenH_ = 0

-- 调试模式
local debugMode_ = false
-- 测试模式（可调重力）
local testMode_ = false
-- 视差背景
local parallaxBg_ = nil

-- ============================================================================
-- 精灵帧动画系统
-- ============================================================================
local spriteFrames_ = {
    idle = {},    -- nvgImage 句柄数组
    run = {},
    jump = {},
    showoff = {},
}
local spriteAnimTimer_ = 0      -- 全局动画计时器
local SPRITE_FPS = 8            -- 动画帧率（帧/秒）
local SPRITE_DRAW_SIZE = 48     -- 精灵绘制大小（像素）

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 获取当前每物理单位对应的屏幕像素数（动态适配相机 orthoSize）
local function GetPixelsPerUnit()
    local camera = cameraNode_:GetComponent("Camera")
    return screenH_ / camera.orthoSize
end

--- 物理坐标转屏幕坐标（考虑相机偏移）
local function PhysicsToScreen(px, py)
    local camPos = cameraNode_.position2D
    local ppu = GetPixelsPerUnit()
    local sx = screenW_ / 2 + (px - camPos.x) * ppu
    local sy = screenH_ / 2 - (py - camPos.y) * ppu
    return sx, sy
end

-- ============================================================================
-- 精灵帧加载与动画
-- ============================================================================

function GameScene.LoadSpriteFrames()
    -- idle: 4帧
    for i = 1, 4 do
        local path = "image/character/idle/berie_idle_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.idle, img)
    end
    -- jump: 4帧
    for i = 1, 4 do
        local path = "image/character/jump/berie_jump_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.jump, img)
    end
    -- run: 6帧
    for i = 1, 6 do
        local path = "image/character/run/berie_run_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.run, img)
    end
    -- showoff: 7帧
    for i = 1, 7 do
        local path = "image/character/showoff/berie_showoff_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.showoff, img)
    end
    print("[GameScene] Loaded sprite frames: idle=" .. #spriteFrames_.idle
        .. " jump=" .. #spriteFrames_.jump
        .. " run=" .. #spriteFrames_.run
        .. " showoff=" .. #spriteFrames_.showoff)
end

--- 根据角色物理状态获取当前动画名和帧索引
---@param player table
---@return string animName, number frameIndex
function GameScene.GetAnimFrame(player)
    local vel = player.body and player.body.linearVelocity or Vector2(0, 0)

    -- 到达终点 → showoff
    if player.reachedGoal then
        local totalFrames = #spriteFrames_.showoff
        local idx = math.floor(spriteAnimTimer_ * SPRITE_FPS) % totalFrames + 1
        return "showoff", idx
    end

    -- 空中（不在地面）→ jump
    if not player.onGround then
        -- 上升用前两帧，下降用后两帧
        local jumpFrames = #spriteFrames_.jump
        if jumpFrames > 0 then
            local idx
            if vel.y > 0.5 then
                -- 上升
                idx = math.floor(spriteAnimTimer_ * SPRITE_FPS) % 2 + 1
            else
                -- 下降
                idx = math.floor(spriteAnimTimer_ * SPRITE_FPS) % 2 + 3
                if idx > jumpFrames then idx = jumpFrames end
            end
            return "jump", idx
        end
    end

    -- 地面上有水平速度 → run
    if math.abs(vel.x) > 0.5 then
        local totalFrames = #spriteFrames_.run
        local idx = math.floor(spriteAnimTimer_ * (SPRITE_FPS + 2)) % totalFrames + 1
        return "run", idx
    end

    -- 静止 → idle
    local totalFrames = #spriteFrames_.idle
    local idx = math.floor(spriteAnimTimer_ * SPRITE_FPS) % totalFrames + 1
    return "idle", idx
end

-- ============================================================================
-- 场景生命周期
-- ============================================================================

--- 进入参数：
--- params.level = number → 从 LevelData 加载关卡
--- params.levelData = table → 直接使用传入的关卡数据（编辑器测试模式）
--- params.fromEditor = true → 标记来自编辑器，胜负后返回编辑器
local fromEditor_ = false
local directLevelData_ = nil

function GameScene.Enter(params)
    currentLevel_ = (params and params.level) or 1
    fromEditor_ = (params and params.fromEditor) or false
    directLevelData_ = (params and params.levelData) or nil
    gameState_ = STATE_PLAYING
    stateTimer_ = 0

    -- 清除 UI（游戏场景使用独立 NanoVG 渲染）
    UI.SetRoot(nil)

    -- 创建 NanoVG 上下文
    nvg_ = nvgCreate(1)
    nvgCreateFont(nvg_, "sans", "Fonts/MiSans-Regular.ttf")

    -- 创建背景（缩放倍数 = 屏幕高度 / 源图高度，确保背景充满屏幕）
    local initH = graphics:GetHeight() / graphics:GetDPR()
    local bgZoom = math.max(2.0, initH / 180)
    parallaxBg_ = ParallaxBackground.Create(nvg_, nil, bgZoom)

    -- 加载角色精灵帧
    GameScene.LoadSpriteFrames()

    -- 创建场景
    GameScene.CreatePhysicsScene()

    -- 加载关卡（支持直接数据或索引）
    if directLevelData_ then
        GameScene.LoadLevelFromData(directLevelData_)
    else
        GameScene.LoadLevel(currentLevel_)
    end

    -- 订阅事件
    SubscribeToEvent("Update", "GameScene_HandleUpdate")
    SubscribeToEvent("PostUpdate", "GameScene_HandlePostUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "GameScene_HandleRender")
    SubscribeToEvent("PhysicsBeginContact2D", "GameScene_HandleContactBegin")
    SubscribeToEvent("PhysicsEndContact2D", "GameScene_HandleContactEnd")

    -- 创建 HUD（暂停按钮）
    hudUI_ = UI.Panel {
        width = "100%", height = "100%",
        children = {
            UI.Panel {
                position = "absolute",
                top = 8, right = 8,
                children = {
                    UI.Button {
                        text = "⏸",
                        width = 40, height = 40,
                        fontSize = 18,
                        borderRadius = 20,
                        onClick = function(self)
                            if gameState_ == STATE_PLAYING then
                                GameScene.Pause()
                            end
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(hudUI_)

    if fromEditor_ then
        print("[GameScene] Entered EDITOR TEST mode")
    else
        print("[GameScene] Entered level " .. currentLevel_)
    end
end

function GameScene.Exit()
    -- 清理暂停菜单和 HUD
    GameScene.HidePauseMenu()
    hudUI_ = nil
    UI.SetRoot(nil)

    -- 清理（CloneSystem.Destroy 会一并清理主玩家）
    if cloneSystem_ then
        cloneSystem_:Destroy()
        cloneSystem_ = nil
    end
    mainPlayer_ = nil

    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("PostUpdate")
    UnsubscribeFromEvent("PhysicsBeginContact2D")
    UnsubscribeFromEvent("PhysicsEndContact2D")

    -- 清理视差背景
    if parallaxBg_ then
        parallaxBg_:Destroy()
        parallaxBg_ = nil
    end

    if nvg_ then
        -- 释放精灵帧图片
        for _, frames in pairs(spriteFrames_) do
            for _, img in ipairs(frames) do
                if img and img ~= 0 then
                    nvgDeleteImage(nvg_, img)
                end
            end
        end
        spriteFrames_ = { idle = {}, run = {}, jump = {}, showoff = {} }
        spriteAnimTimer_ = 0

        UnsubscribeFromEvent(nvg_, "NanoVGRender")
        nvgDelete(nvg_)
        nvg_ = nil
    end

    if scene_ then
        scene_:Remove()
        scene_ = nil
    end

    platforms_ = {}
    spikes_ = {}
    goalArea_ = nil
    mapGridW_ = 0
    mapGridH_ = 0
    tileCells_ = {}
    tileImages_ = {}
    hasTileTextures_ = false
end

-- ============================================================================
-- 场景创建
-- ============================================================================

function GameScene.CreatePhysicsScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    physicsWorld_ = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld_.gravity = Vector2(0, -Config.Gravity)

    -- 相机（固定，不跟随玩家）
    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true
    -- orthoSize = 可视高度（物理单位），设为 9 以覆盖整个关卡
    camera.orthoSize = 9
    cameraNode_.position = Vector3(0, 3, -10)

    renderer:SetViewport(0, Viewport:new(scene_, camera))
end

-- ============================================================================
-- 关卡加载
-- ============================================================================

--- 从直接数据加载关卡（编辑器测试模式）
---@param levelData table { spawn, goal, platforms, spikes, camera, playerCount }
function GameScene.LoadLevelFromData(levelData)
    -- 临时覆盖克隆数量（编辑器中可配置）
    if levelData.playerCount then
        Config.CloneCount = levelData.playerCount
    end
    GameScene.ApplyLevelData(levelData)
end

function GameScene.LoadLevel(levelIndex)
    local levelData = LevelData.GetLevel(levelIndex)
    if not levelData then
        print("[GameScene] ERROR: Level " .. levelIndex .. " not found!")
        return
    end
    GameScene.ApplyLevelData(levelData)
end

--- 实际加载关卡数据到物理世界
---@param levelData table
function GameScene.ApplyLevelData(levelData)
    platforms_ = {}
    spikes_ = {}
    tileCells_ = {}
    tileImages_ = {}
    hasTileTextures_ = false

    -- 加载逐格瓦片纹理数据（编辑器测试模式）
    if levelData.tiles and #levelData.tiles > 0 then
        hasTileTextures_ = true
        tileCells_ = levelData.tiles
        -- 预加载所有用到的纹理（去重）
        for _, cell in ipairs(tileCells_) do
            if cell.image and not tileImages_[cell.image] then
                local img = nvgCreateImage(nvg_, cell.image, 0)
                if img > 0 then
                    tileImages_[cell.image] = img
                end
            end
        end
        print("[GameScene] Loaded tile textures: " .. #tileCells_ .. " cells")
    end

    -- 保存地图尺寸并动态调整相机（Cover 策略：地图完全覆盖屏幕）
    if levelData.gridHeight and levelData.gridWidth then
        mapGridW_ = levelData.gridWidth
        mapGridH_ = levelData.gridHeight
        -- 初始设置（后续每帧在 Render 中根据实际屏幕比例动态调整）
        local camera = cameraNode_:GetComponent("Camera")
        camera.orthoSize = mapGridH_
    end

    -- 创建平台
    for i, pData in ipairs(levelData.platforms) do
        local node = scene_:CreateChild("Platform")
        node:SetPosition2D(pData.x, pData.y)

        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC

        local shape = node:CreateComponent("CollisionBox2D")
        shape:SetSize(pData.width, pData.height)
        shape.friction = 0.3
        shape.restitution = 0.0
        shape.categoryBits = 1

        table.insert(platforms_, {
            x = pData.x, y = pData.y,
            width = pData.width, height = pData.height,
            node = node,
        })
    end

    -- 创建尖刺（用传感器检测）
    for i, sData in ipairs(levelData.spikes) do
        local node = scene_:CreateChild("Spike")
        node:SetPosition2D(sData.x, sData.y)

        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC

        local shape = node:CreateComponent("CollisionBox2D")
        shape:SetSize(sData.width, 0.4)
        shape.trigger = true
        shape.categoryBits = 8
        shape.maskBits = 2  -- 只与玩家碰撞

        table.insert(spikes_, {
            x = sData.x, y = sData.y,
            width = sData.width,
            node = node,
        })
    end

    -- 终点区域（传感器）
    goalArea_ = levelData.goal
    local goalNode = scene_:CreateChild("Goal")
    goalNode:SetPosition2D(goalArea_.x, goalArea_.y)

    local goalBody = goalNode:CreateComponent("RigidBody2D")
    goalBody.bodyType = BT_STATIC

    local goalShape = goalNode:CreateComponent("CollisionBox2D")
    goalShape:SetSize(goalArea_.width, goalArea_.height)
    goalShape.trigger = true
    goalShape.categoryBits = 16
    goalShape.maskBits = 2

    -- 设置相机位置到关卡中心
    if levelData.camera then
        cameraNode_:SetPosition(Vector3(levelData.camera.x, levelData.camera.y, -10))
    end

    -- 保存出生点坐标
    spawnPos_.x = levelData.spawn.x
    spawnPos_.y = levelData.spawn.y

    -- 开局不创建玩家，由 CloneSystem 的第一次倒计时生成
    mainPlayer_ = nil

    -- 创建克隆系统（负责生成玩家和克隆体）
    cloneSystem_ = CloneSystem.Create(scene_, levelData.spawn.x, levelData.spawn.y)
end

-- ============================================================================
-- 更新逻辑
-- ============================================================================

function GameScene_HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- L 切换调试模式
    if input:GetKeyPress(KEY_L) then
        debugMode_ = not debugMode_
        print("[GameScene] Debug mode: " .. tostring(debugMode_))
    end

    -- T 切换测试模式（可调重力）
    if input:GetKeyPress(KEY_T) then
        testMode_ = not testMode_
        print("[GameScene] Test mode: " .. tostring(testMode_))
    end

    -- 测试模式：数字键调节重力系数
    if testMode_ then
        -- 1/2 调节上升重力
        if input:GetKeyPress(KEY_1) then
            Config.GravityScaleRising = math.max(0.1, Config.GravityScaleRising - 0.1)
            print("[Test] GravityScaleRising = " .. string.format("%.1f", Config.GravityScaleRising))
        end
        if input:GetKeyPress(KEY_2) then
            Config.GravityScaleRising = Config.GravityScaleRising + 0.1
            print("[Test] GravityScaleRising = " .. string.format("%.1f", Config.GravityScaleRising))
        end
        -- 3/4 调节下降重力
        if input:GetKeyPress(KEY_3) then
            Config.GravityScaleFalling = math.max(0.1, Config.GravityScaleFalling - 0.1)
            print("[Test] GravityScaleFalling = " .. string.format("%.1f", Config.GravityScaleFalling))
        end
        if input:GetKeyPress(KEY_4) then
            Config.GravityScaleFalling = Config.GravityScaleFalling + 0.1
            print("[Test] GravityScaleFalling = " .. string.format("%.1f", Config.GravityScaleFalling))
        end
    end

    -- 暂停键检测（在任何非结算状态都可以触发）
    if input:GetKeyPress(KEY_ESCAPE) then
        if gameState_ == STATE_PLAYING then
            GameScene.Pause()
            return
        elseif gameState_ == STATE_PAUSED then
            GameScene.Resume()
            return
        end
    end

    if gameState_ == STATE_PLAYING then
        GameScene.UpdatePlaying(dt)
    elseif gameState_ == STATE_PAUSED then
        -- 暂停时不更新游戏逻辑
        return
    else
        -- 胜负延迟
        stateTimer_ = stateTimer_ + dt
        if stateTimer_ > 2.5 then
            if fromEditor_ then
                -- 编辑器测试模式：胜负后都返回编辑器
                SceneManager.SwitchTo(SceneManager.SCENE_EDITOR, { fromTest = true })
            elseif gameState_ == STATE_WIN then
                SceneManager.SwitchTo(SceneManager.SCENE_LEVEL_SELECT)
            else
                -- 重试当前关卡
                GameScene.Exit()
                GameScene.Enter({ level = currentLevel_ })
            end
        end
    end
end

function GameScene.UpdatePlaying(dt)
    -- 更新背景（云朵滚动）
    if parallaxBg_ then
        parallaxBg_:Update(dt)
    end

    -- 更新精灵动画计时器
    spriteAnimTimer_ = spriteAnimTimer_ + dt

    -- 更新克隆系统（计时器 + 角色生成）
    if cloneSystem_ then
        cloneSystem_:Update(dt)

        -- 同步主玩家引用（第一次生成后获取）
        if not mainPlayer_ then
            mainPlayer_ = cloneSystem_:GetMainPlayer()
        end

        cloneSystem_:UpdateClones(dt)
    end

    -- 读取输入（玩家已生成后才响应）
    if mainPlayer_ and mainPlayer_.isAlive then
        local leftHeld = input:GetKeyDown(KEY_LEFT) or input:GetKeyDown(KEY_A)
        local rightHeld = input:GetKeyDown(KEY_RIGHT) or input:GetKeyDown(KEY_D)
        local jumpPressed = input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_UP) or input:GetKeyPress(KEY_W)
        mainPlayer_:UpdateInput(dt, leftHeld, rightHeld, jumpPressed)
    end

    -- 检测掉落死亡
    GameScene.CheckFallDeath()

    -- 检测胜负（玩家还没生成时不检测）
    if mainPlayer_ and cloneSystem_:AnyDead() then
        gameState_ = STATE_LOSE
        stateTimer_ = 0
        print("[GameScene] GAME OVER - A character died!")
    elseif mainPlayer_ and cloneSystem_:AllReachedGoal() then
        gameState_ = STATE_WIN
        stateTimer_ = 0
        print("[GameScene] LEVEL CLEAR!")
    end
end

function GameScene.CheckFallDeath()
    -- 动态计算掉落死亡线：相机可视范围底部再往下 2 个单位（完全离开屏幕）
    local camera = cameraNode_:GetComponent("Camera")
    local camY = cameraNode_.position.y
    local fallDeathY = camY - camera.orthoSize / 2 - 2.0

    -- 检查主玩家（可能尚未生成）
    if mainPlayer_ and mainPlayer_.isAlive then
        local pos = mainPlayer_:GetPosition()
        if pos.y < fallDeathY then
            mainPlayer_:Kill()
        end
    end
    -- 检查克隆体
    if cloneSystem_ then
        for _, clone in ipairs(cloneSystem_:GetClones()) do
            if clone.isAlive then
                local pos = clone:GetPosition()
                if pos.y < fallDeathY then
                    clone:Kill()
                end
            end
        end
    end
end

-- ============================================================================
-- 碰撞处理
-- ============================================================================

function GameScene_HandleContactBegin(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")

    -- 检测尖刺碰撞
    if nodeA.name == "Spike" or nodeB.name == "Spike" then
        local charNode = (nodeA.name == "Spike") and nodeB or nodeA
        GameScene.HandleSpikeHit(charNode)
        return
    end

    -- 检测终点碰撞
    if nodeA.name == "Goal" or nodeB.name == "Goal" then
        local charNode = (nodeA.name == "Goal") and nodeB or nodeA
        GameScene.HandleGoalReach(charNode)
        return
    end

    -- 地面碰撞检测
    GameScene.HandleGroundContact(nodeA, nodeB, true)
end

function GameScene_HandleContactEnd(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")

    GameScene.HandleGroundContact(nodeA, nodeB, false)
end

function GameScene.HandleGroundContact(nodeA, nodeB, isBegin)
    -- 查找哪个是角色（玩家和克隆体都需要地面检测）
    local charNode = nil
    local otherNode = nil

    if nodeA.name == "Player" or string.find(nodeA.name, "Clone_", 1, true) then
        charNode = nodeA
        otherNode = nodeB
    elseif nodeB.name == "Player" or string.find(nodeB.name, "Clone_", 1, true) then
        charNode = nodeB
        otherNode = nodeA
    end

    if not charNode then return end
    if otherNode.name ~= "Platform" and otherNode.name ~= "Ground" then return end

    -- 找到对应的 Player 实例（玩家或克隆体）
    local player = GameScene.FindPlayerByNode(charNode)
    if player then
        if isBegin then
            player:OnContactBegin(otherNode)
        else
            player:OnContactEnd(otherNode)
        end
    end
end

function GameScene.HandleSpikeHit(charNode)
    local player = GameScene.FindPlayerByNode(charNode)
    if player and player.isAlive then
        player:Kill()
        print("[GameScene] Character hit spike: " .. charNode.name)
    end
end

function GameScene.HandleGoalReach(charNode)
    local player = GameScene.FindPlayerByNode(charNode)
    if player and player.isAlive and not player.reachedGoal then
        player:SetReachedGoal()
        print("[GameScene] Character reached goal: " .. charNode.name)
    end
end

function GameScene.FindPlayerByNode(node)
    if mainPlayer_ and mainPlayer_.node == node then
        return mainPlayer_
    end
    if cloneSystem_ then
        for _, clone in ipairs(cloneSystem_:GetClones()) do
            if clone.node == node then
                return clone
            end
        end
    end
    return nil
end

-- ============================================================================
-- 相机（固定，无需跟随）
-- ============================================================================

function GameScene_HandlePostUpdate(eventType, eventData)
    -- 相机固定在关卡中心，无需跟随
    -- 录制已内置在 UpdateInput 中，无需额外调用
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

function GameScene_HandleRender(eventType, eventData)
    if not nvg_ then return end

    local dpr = graphics:GetDPR()
    screenW_ = graphics:GetWidth() / dpr
    screenH_ = graphics:GetHeight() / dpr

    -- 动态调整相机 orthoSize（Cover 策略：地图完全覆盖屏幕，不露出地图外部）
    if mapGridW_ > 0 and mapGridH_ > 0 then
        local screenAspect = screenW_ / screenH_
        local mapAspect = mapGridW_ / mapGridH_
        local camera = cameraNode_:GetComponent("Camera")
        if screenAspect > mapAspect then
            -- 屏幕比地图更宽 → 用宽度适配（减小 orthoSize 以放大）
            camera.orthoSize = mapGridW_ / screenAspect
        else
            -- 屏幕比地图更高或相等 → 用高度适配
            camera.orthoSize = mapGridH_
        end
    end

    nvgBeginFrame(nvg_, screenW_, screenH_, dpr)

    GameScene.DrawBackground()
    GameScene.DrawPlatforms()
    GameScene.DrawSpikes()
    GameScene.DrawGoal()
    GameScene.DrawCharacters()
    GameScene.DrawTimerUI()
    GameScene.DrawGameState()
    if debugMode_ then
        GameScene.DrawDebugOverlay()
    end

    nvgEndFrame(nvg_)
end

function GameScene.DrawBackground()
    -- 使用视差背景系统
    if parallaxBg_ then
        parallaxBg_:Draw(screenW_, screenH_)
    else
        -- 回退到纯色渐变
        local c1 = Config.Colors.Background1
        local c2 = Config.Colors.Background2
        nvgBeginPath(nvg_)
        nvgRect(nvg_, 0, 0, screenW_, screenH_)
        local bg = nvgLinearGradient(nvg_, 0, 0, 0, screenH_,
            nvgRGBA(c1[1], c1[2], c1[3], c1[4]),
            nvgRGBA(c2[1], c2[2], c2[3], c2[4]))
        nvgFillPaint(nvg_, bg)
        nvgFill(nvg_)
    end
end

function GameScene.DrawPlatforms()
    local ppu = GetPixelsPerUnit()

    -- 如果有逐格瓦片纹理数据（编辑器测试模式），用纹理渲染
    if hasTileTextures_ then
        local pad = 0.5  -- 每边扩展0.5像素，消除浮点精度导致的缝隙
        for _, cell in ipairs(tileCells_) do
            local sx, sy = PhysicsToScreen(cell.x, cell.y)
            local cellPx = cell.size * ppu

            if cell.image and tileImages_[cell.image] then
                -- 用纹理图案填充（稍微扩大消除缝隙）
                local imgHandle = tileImages_[cell.image]
                local paint = nvgImagePattern(nvg_,
                    sx - cellPx / 2 - pad, sy - cellPx / 2 - pad,
                    cellPx + pad * 2, cellPx + pad * 2, 0, imgHandle, 1.0)
                nvgBeginPath(nvg_)
                nvgRect(nvg_, sx - cellPx / 2 - pad, sy - cellPx / 2 - pad, cellPx + pad * 2, cellPx + pad * 2)
                nvgFillPaint(nvg_, paint)
                nvgFill(nvg_)
            else
                -- 无纹理，用后备颜色填充
                local clr = cell.color or { 80, 180, 80, 255 }
                nvgBeginPath(nvg_)
                nvgRect(nvg_, sx - cellPx / 2 - pad, sy - cellPx / 2 - pad, cellPx + pad * 2, cellPx + pad * 2)
                nvgFillColor(nvg_, nvgRGBA(clr[1], clr[2], clr[3], clr[4] or 255))
                nvgFill(nvg_)
            end
        end
        return
    end

    -- 非编辑器模式：使用合并矩形 + 渐变色渲染
    local c = Config.Colors.Platform
    for _, p in ipairs(platforms_) do
        local sx, sy = PhysicsToScreen(p.x, p.y)
        local sw = p.width * ppu
        local sh = p.height * ppu

        -- 平台主体
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, sx - sw/2, sy - sh/2, sw, sh, 4)
        local grad = nvgLinearGradient(nvg_, sx, sy - sh/2, sx, sy + sh/2,
            nvgRGBA(c[1] + 30, c[2] + 30, c[3] + 30, 255),
            nvgRGBA(c[1] - 20, c[2] - 20, c[3] - 20, 255))
        nvgFillPaint(nvg_, grad)
        nvgFill(nvg_)

        -- 边框
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, sx - sw/2, sy - sh/2, sw, sh, 4)
        nvgStrokeWidth(nvg_, 1.5)
        nvgStrokeColor(nvg_, nvgRGBA(c[1] - 40, c[2] - 40, c[3] - 40, 200))
        nvgStroke(nvg_)
    end
end

function GameScene.DrawSpikes()
    local c = Config.Colors.Spike
    local ppu = GetPixelsPerUnit()
    for _, s in ipairs(spikes_) do
        local sx, sy = PhysicsToScreen(s.x, s.y)
        local sw = s.width * ppu
        local spikeH = 0.4 * ppu

        -- 画三角形尖刺
        local numSpikes = math.floor(sw / 12)
        if numSpikes < 1 then numSpikes = 1 end
        local spikeWidth = sw / numSpikes

        for i = 0, numSpikes - 1 do
            local bx = sx - sw/2 + i * spikeWidth
            nvgBeginPath(nvg_)
            nvgMoveTo(nvg_, bx, sy + spikeH/2)
            nvgLineTo(nvg_, bx + spikeWidth/2, sy - spikeH/2)
            nvgLineTo(nvg_, bx + spikeWidth, sy + spikeH/2)
            nvgClosePath(nvg_)
            nvgFillColor(nvg_, nvgRGBA(c[1], c[2], c[3], c[4]))
            nvgFill(nvg_)
        end
    end
end

function GameScene.DrawGoal()
    if not goalArea_ then return end
    local c = Config.Colors.Goal
    local ppu = GetPixelsPerUnit()
    local sx, sy = PhysicsToScreen(goalArea_.x, goalArea_.y)
    local sw = goalArea_.width * ppu
    local sh = goalArea_.height * ppu

    -- 闪烁效果
    local pulse = math.sin(os.clock() * 3) * 0.3 + 0.7
    local alpha = math.floor(pulse * 180)

    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, sx - sw/2, sy - sh/2, sw, sh, 6)
    nvgFillColor(nvg_, nvgRGBA(c[1], c[2], c[3], alpha))
    nvgFill(nvg_)

    -- 旗帜标记
    nvgBeginPath(nvg_)
    nvgMoveTo(nvg_, sx, sy - sh/2 + 5)
    nvgLineTo(nvg_, sx, sy + sh/2 - 5)
    nvgStrokeWidth(nvg_, 3)
    nvgStrokeColor(nvg_, nvgRGBA(c[1], c[2], c[3], 255))
    nvgStroke(nvg_)

    -- 星形标记
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 24)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg_, nvgRGBA(c[1], c[2], c[3], 255))
    nvgText(nvg_, sx, sy, "★")
end

function GameScene.DrawCharacters()
    -- 画主玩家
    if mainPlayer_ and mainPlayer_.isAlive and mainPlayer_.visible then
        GameScene.DrawSingleCharacter(mainPlayer_)
    end
    -- 画克隆体
    if cloneSystem_ then
        for _, clone in ipairs(cloneSystem_:GetClones()) do
            if clone.isAlive and clone.visible then
                GameScene.DrawSingleCharacter(clone)
            end
        end
    end
end

function GameScene.DrawSingleCharacter(player)
    local pos = player:GetPosition()
    local sx, sy = PhysicsToScreen(pos.x, pos.y)
    local vel = player.body and player.body.linearVelocity or Vector2(0, 0)

    -- 获取当前动画帧
    local animName, frameIdx = GameScene.GetAnimFrame(player)
    local frames = spriteFrames_[animName]
    if not frames or #frames == 0 then return end

    local imgHandle = frames[frameIdx]
    if not imgHandle or imgHandle == 0 then return end

    -- 计算绘制区域（以角色物理中心为基准，精灵稍大于碰撞体）
    local ppu = GetPixelsPerUnit()
    local drawSize = SPRITE_DRAW_SIZE * (ppu / 50)  -- 根据缩放比调整
    local halfSize = drawSize / 2

    -- 判断朝向（根据水平速度翻转）
    local flipX = false
    if vel.x < -0.1 then
        flipX = true
    end

    -- 使用 nvgImagePattern 绘制精灵
    nvgSave(nvg_)

    if flipX then
        -- 水平翻转：平移到精灵中心，水平缩放 -1，再移回
        nvgTranslate(nvg_, sx, sy)
        nvgScale(nvg_, -1, 1)
        nvgTranslate(nvg_, -sx, -sy)
    end

    local imgPat = nvgImagePattern(nvg_, sx - halfSize, sy - halfSize, drawSize, drawSize, 0, imgHandle, 1.0)
    nvgBeginPath(nvg_)
    nvgRect(nvg_, sx - halfSize, sy - halfSize, drawSize, drawSize)
    nvgFillPaint(nvg_, imgPat)
    nvgFill(nvg_)

    nvgRestore(nvg_)
end

-- ============================================================================
-- 出生点传送圈（与计时器合为一体）
-- ============================================================================

function GameScene.DrawTimerUI()
    if not cloneSystem_ then return end

    -- 计算出生点的屏幕坐标（计时器画在玩家下方）
    local sx, sy = PhysicsToScreen(spawnPos_.x, spawnPos_.y)
    local cx = sx
    local cy = sy + 48  -- 玩家脚下
    local outerR = 26
    local innerR = 16

    -- 呼吸闪烁
    local pulse = math.sin(os.clock() * 3) * 0.3 + 0.7
    local ringC = Config.Colors.TimerRing

    -- 外圈（呼吸闪烁的传送圈）
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, cx, cy, outerR + 6)
    nvgStrokeWidth(nvg_, 2)
    nvgStrokeColor(nvg_, nvgRGBA(ringC[1], ringC[2], ringC[3], math.floor(pulse * 140)))
    nvgStroke(nvg_)

    -- 内圈（呼吸闪烁）
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, cx, cy, outerR + 2)
    nvgStrokeWidth(nvg_, 1.5)
    nvgStrokeColor(nvg_, nvgRGBA(ringC[1], ringC[2], ringC[3], math.floor(pulse * 80)))
    nvgStroke(nvg_)

    -- 背景填充圆
    local bgC = Config.Colors.TimerBg
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, cx, cy, outerR)
    nvgFillColor(nvg_, nvgRGBA(bgC[1], bgC[2], bgC[3], bgC[4]))
    nvgFill(nvg_)

    -- 进度弧
    if cloneSystem_:IsActive() then
        local progress = cloneSystem_:GetTimerProgress()
        local startAngle = -math.pi / 2
        local endAngle = startAngle + progress * 2 * math.pi

        nvgBeginPath(nvg_)
        nvgArc(nvg_, cx, cy, outerR - 2, startAngle, endAngle, NVG_CW)
        nvgArc(nvg_, cx, cy, innerR, endAngle, startAngle, NVG_CCW)
        nvgClosePath(nvg_)
        nvgFillColor(nvg_, nvgRGBA(ringC[1], ringC[2], ringC[3], 200))
        nvgFill(nvg_)
    end

    -- 中心数字（倒计时）
    local num = cloneSystem_:GetCurrentNumber()
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 20)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg_, cx, cy, tostring(num))
end

-- ============================================================================
-- 游戏状态显示（胜利/失败）
-- ============================================================================

function GameScene.DrawGameState()
    if gameState_ == STATE_PLAYING then return end

    -- 半透明遮罩
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, screenW_, screenH_)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 150))
    nvgFill(nvg_)

    nvgFontFace(nvg_, "sans")
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if gameState_ == STATE_WIN then
        nvgFontSize(nvg_, 48)
        nvgFillColor(nvg_, nvgRGBA(255, 215, 0, 255))
        nvgText(nvg_, screenW_ / 2, screenH_ / 2 - 20, "通关成功!")

        nvgFontSize(nvg_, 18)
        nvgFillColor(nvg_, nvgRGBA(200, 200, 200, 200))
        nvgText(nvg_, screenW_ / 2, screenH_ / 2 + 30, "即将返回关卡选择...")
    else
        nvgFontSize(nvg_, 48)
        nvgFillColor(nvg_, nvgRGBA(220, 60, 60, 255))
        nvgText(nvg_, screenW_ / 2, screenH_ / 2 - 20, "挑战失败")

        nvgFontSize(nvg_, 18)
        nvgFillColor(nvg_, nvgRGBA(200, 200, 200, 200))
        nvgText(nvg_, screenW_ / 2, screenH_ / 2 + 30, "即将重新开始...")
    end
end

-- ============================================================================
-- 暂停系统
-- ============================================================================

--- 暂停游戏
function GameScene.Pause()
    gameState_ = STATE_PAUSED

    -- 冻结物理
    if physicsWorld_ then
        physicsWorld_.gravity = Vector2(0, 0)
    end
    -- 冻结所有角色（均为 dynamic body）
    if mainPlayer_ and mainPlayer_.body and mainPlayer_.isAlive then
        mainPlayer_.body.linearVelocity = Vector2(0, 0)
        mainPlayer_.body.gravityScale = 0
    end
    if cloneSystem_ then
        for _, clone in ipairs(cloneSystem_:GetClones()) do
            if clone.body and clone.isAlive then
                clone.body.linearVelocity = Vector2(0, 0)
                clone.body.gravityScale = 0
            end
        end
    end

    -- 显示暂停菜单 UI
    GameScene.ShowPauseMenu()
    print("[GameScene] Paused")
end

--- 恢复游戏
function GameScene.Resume()
    -- 隐藏暂停菜单
    GameScene.HidePauseMenu()

    -- 恢复物理
    if physicsWorld_ then
        physicsWorld_.gravity = Vector2(0, -Config.Gravity)
    end
    -- 恢复所有角色重力（让 UpdateGravityScale 下一帧自动设定正确值，先设 falling）
    if mainPlayer_ and mainPlayer_.body and mainPlayer_.isAlive then
        mainPlayer_.body.gravityScale = Config.GravityScaleFalling
    end
    if cloneSystem_ then
        for _, clone in ipairs(cloneSystem_:GetClones()) do
            if clone.body and clone.isAlive then
                clone.body.gravityScale = Config.GravityScaleFalling
            end
        end
    end

    gameState_ = STATE_PLAYING
    print("[GameScene] Resumed")
end

--- 显示暂停菜单
function GameScene.ShowPauseMenu()
    -- 构建按钮列表
    local buttons = {}
    buttons[#buttons + 1] = UI.Button {
        text = "返回游戏",
        variant = "primary",
        width = "80%", maxWidth = 200,
        height = 36,
        onClick = function(self)
            GameScene.Resume()
        end,
    }
    buttons[#buttons + 1] = UI.Button {
        text = "重置关卡",
        variant = "outline",
        width = "80%", maxWidth = 200,
        height = 34,
        onClick = function(self)
            GameScene.HidePauseMenu()
            GameScene.Exit()
            GameScene.Enter({ level = currentLevel_ })
        end,
    }
    if fromEditor_ then
        buttons[#buttons + 1] = UI.Button {
            text = "返回编辑器",
            variant = "primary",
            width = "80%", maxWidth = 200,
            height = 34,
            onClick = function(self)
                GameScene.HidePauseMenu()
                SceneManager.SwitchTo(SceneManager.SCENE_EDITOR, { fromTest = true })
            end,
        }
    end
    buttons[#buttons + 1] = UI.Button {
        text = "返回主菜单",
        variant = "outline",
        width = "80%", maxWidth = 200,
        height = 34,
        onClick = function(self)
            GameScene.HidePauseMenu()
            SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
        end,
    }

    -- 音量区域
    local volumePanel = UI.Panel {
        width = "100%",
        gap = 6,
        padding = 10,
        backgroundColor = { 25, 28, 40, 200 },
        borderRadius = 8,
        children = {
            UI.Label {
                text = "音效设置",
                fontSize = 12,
                fontColor = { 180, 190, 210, 220 },
                marginBottom = 2,
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label { text = "音乐", fontSize = 11, fontColor = { 160, 170, 190, 200 }, width = 32 },
                    UI.Slider {
                        value = Config.Settings.MusicVolume * 100,
                        min = 0, max = 100,
                        flexGrow = 1,
                        onChange = function(self, val) Config.Settings.MusicVolume = val / 100 end,
                    },
                }
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label { text = "音效", fontSize = 11, fontColor = { 160, 170, 190, 200 }, width = 32 },
                    UI.Slider {
                        value = Config.Settings.SFXVolume * 100,
                        min = 0, max = 100,
                        flexGrow = 1,
                        onChange = function(self, val) Config.Settings.SFXVolume = val / 100 end,
                    },
                }
            },
        }
    }

    -- 合并 children: 标题 + 按钮[1] + 音量 + 按钮[2..n]
    local panelChildren = {}
    panelChildren[#panelChildren + 1] = UI.Label {
        text = "暂停",
        fontSize = 22,
        fontColor = { 255, 255, 255, 255 },
        marginBottom = 2,
    }
    panelChildren[#panelChildren + 1] = buttons[1]  -- 返回游戏
    panelChildren[#panelChildren + 1] = volumePanel
    for i = 2, #buttons do
        panelChildren[#panelChildren + 1] = buttons[i]
    end

    pauseUI_ = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 150 },
        children = {
            UI.Panel {
                width = "85%",
                maxWidth = 320,
                padding = 16,
                gap = 8,
                alignItems = "center",
                backgroundColor = { 35, 40, 58, 245 },
                borderRadius = 14,
                borderWidth = 2,
                borderColor = { 80, 140, 255, 100 },
                children = panelChildren,
            }
        }
    }
    UI.SetRoot(pauseUI_)
end

--- 隐藏暂停菜单
function GameScene.HidePauseMenu()
    UI.SetRoot(hudUI_)
    pauseUI_ = nil
end

-- ============================================================================
-- 调试覆盖层（F1 开关）
-- ============================================================================

function GameScene.DrawDebugOverlay()
    nvgFontFace(nvg_, "sans")
    nvgTextAlign(nvg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    local x = 10
    local y = 10
    local lineH = 16
    local lines = {}

    -- 标题
    table.insert(lines, { text = "[DEBUG] L关闭 T测试模式", color = { 255, 255, 0, 255 } })
    table.insert(lines, { text = "状态: " .. gameState_, color = { 200, 200, 200, 255 } })

    -- 重力系数显示
    table.insert(lines, { text = string.format("重力 上升:%.1f 下降:%.1f", Config.GravityScaleRising, Config.GravityScaleFalling),
        color = testMode_ and { 255, 200, 100, 255 } or { 150, 150, 150, 255 } })
    if testMode_ then
        table.insert(lines, { text = "[测试] 1/2调上升 3/4调下降", color = { 255, 180, 80, 255 } })
    end

    -- 主玩家信息
    if mainPlayer_ then
        local pos = mainPlayer_:GetPosition()
        local vel = mainPlayer_.body and mainPlayer_.body.linearVelocity or Vector2(0, 0)
        table.insert(lines, { text = "", color = { 0, 0, 0, 0 } })
        table.insert(lines, { text = "== 玩家 ==", color = { 100, 200, 255, 255 } })
        table.insert(lines, { text = string.format("位置: (%.1f, %.1f)", pos.x, pos.y), color = { 200, 200, 200, 255 } })
        table.insert(lines, { text = string.format("速度: (%.1f, %.1f)", vel.x, vel.y), color = { 200, 200, 200, 255 } })
        table.insert(lines, { text = "着地: " .. tostring(mainPlayer_.onGround), color = { 200, 200, 200, 255 } })
        table.insert(lines, { text = "存活: " .. tostring(mainPlayer_.isAlive), color = mainPlayer_.isAlive and { 100, 255, 100, 255 } or { 255, 80, 80, 255 } })
        table.insert(lines, { text = "到达终点: " .. tostring(mainPlayer_.reachedGoal), color = { 200, 200, 200, 255 } })
        -- 录制状态
        local recStatus = mainPlayer_.recordingDone and "完成" or string.format("录制中 %.1fs/%ds", mainPlayer_.recordTime, Config.RecordDuration)
        table.insert(lines, { text = "录制: " .. recStatus .. " 事件:" .. #mainPlayer_.events, color = { 180, 180, 255, 255 } })
        table.insert(lines, { text = string.format("Coyote: %.2f  Buffer: %.2f", mainPlayer_.coyoteTimer, mainPlayer_.jumpBufferTimer), color = { 180, 255, 180, 255 } })
        table.insert(lines, { text = string.format("GravScale: %.1f", mainPlayer_.body and mainPlayer_.body.gravityScale or 0), color = { 200, 255, 200, 255 } })
    end

    -- 克隆体信息
    if cloneSystem_ then
        local clones = cloneSystem_:GetClones()
        table.insert(lines, { text = "", color = { 0, 0, 0, 0 } })
        table.insert(lines, { text = string.format("== 克隆体 (%d) ==", #clones), color = { 255, 180, 80, 255 } })

        for i, clone in ipairs(clones) do
            local pos = clone:GetPosition()
            local state = "循环中"
            if not clone.isAlive then
                state = "死亡"
            elseif clone.reachedGoal then
                state = "到达终点"
            elseif not clone.playbackEvents then
                state = "等待数据"
            end
            local progress = ""
            if clone.playbackEvents then
                progress = string.format(" [%.1fs]", clone.playbackTime)
            end
            local c = Config.CloneColors[clone.colorIndex] or { 200, 200, 200, 255 }
            table.insert(lines, { text = string.format("#%d %s%s (%.1f,%.1f)", i, state, progress, pos.x, pos.y), color = c })
        end

        -- 计时器信息
        table.insert(lines, { text = "", color = { 0, 0, 0, 0 } })
        table.insert(lines, { text = string.format("计时器: %d  进度: %.0f%%", cloneSystem_:GetCurrentNumber(), cloneSystem_:GetTimerProgress() * 100), color = { 100, 220, 255, 255 } })
        table.insert(lines, { text = "计时器激活: " .. tostring(cloneSystem_:IsActive()), color = { 200, 200, 200, 255 } })
    end

    -- 绘制背景面板
    local panelH = #lines * lineH + 16
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, x - 4, y - 4, 260, panelH, 6)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 180))
    nvgFill(nvg_)

    -- 绘制文本
    nvgFontSize(nvg_, 13)
    for i, line in ipairs(lines) do
        local c = line.color
        nvgFillColor(nvg_, nvgRGBA(c[1], c[2], c[3], c[4]))
        nvgText(nvg_, x + 4, y + (i - 1) * lineH + 4, line.text)
    end
end

-- ============================================================================
-- 注册到场景管理器
-- ============================================================================
SceneManager.Register(SceneManager.SCENE_GAME, GameScene)

return GameScene

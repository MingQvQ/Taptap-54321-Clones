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
local BGM = require("BGM")
local UIScenes = require("UIScenes")
require "urhox-libs.UI.VirtualControls"

local GameScene = {}

-- 木板按钮公共样式
local WOODEN_BTN = {
    image = "image/wooden_btn.png",
    slice = {12, 10, 12, 10},        -- top, right, bottom, left (像素) - 透明背景版
    fit = "sliced",
    textColor = {55, 28, 5, 255},
    fontWeight = "bold",
    bgColor = {0, 0, 0, 0},          -- 按钮本身透明
    shadow = {},                       -- 无阴影
}

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
local goals_ = {}           -- 多终点数组 { x, y, width, height, acceptCount, node }
local goalTarget_ = 0       -- 关卡目标（所有终点 acceptCount 之和）
local goalArea_ = nil       -- 兼容旧单终点数据（LevelData 模块）
local spawnPos_ = { x = 0, y = 0 }  -- 出生点坐标

-- 瓦片纹理渲染数据（编辑器测试模式）
local tileCells_ = {}         -- { x, y, size, image, color }[]
local tileImages_ = {}        -- 已加载的纹理缓存 { [imagePath] = nvgImageHandle }
local hasTileTextures_ = false  -- 是否使用纹理渲染（编辑器模式）

-- 地图尺寸（物理单位，用于自适应相机）
local mapGridW_ = 0   -- 内容宽度
local mapGridH_ = 0   -- 内容高度
local contentMinY_ = 0  -- 内容底边 Y（用于相机垂直定位）
local contentCenterX_ = 0  -- 内容水平中心

-- 游戏状态
local STATE_PLAYING = "playing"
local STATE_PAUSED = "paused"
local STATE_WIN = "win"
local STATE_LOSE = "lose"
local gameState_ = STATE_PLAYING
local stateTimer_ = 0  -- 胜负后的延迟
local pauseUI_ = nil   -- 暂停菜单 UI 根引用
local hudUI_ = nil     -- 游戏 HUD（含暂停按钮）

-- 金币系统
local coins_ = {}           -- { x, y, node, collected, vfxTimer }[]
local coinCount_ = 0        -- 当前关卡已收集金币数
local totalCoins_ = 0       -- 总金币数（持久化）
local COIN_CLOUD_KEY = "player_total_coins"

-- 装饰预制体（纯视觉，无碰撞）
local decorations_ = {}     -- { x, y, image }[]
local decorImages_ = {}     -- 已加载纹理缓存 { [imagePath] = nvgImageHandle }

-- 海鸥飞行敌人
local seagulls_ = {}        -- { x, y, minX, maxX, speed, dir, node, body }[]

-- 渲染缓存
local screenW_ = 0
local screenH_ = 0
local renderFrameCount_ = 0  -- 渲染帧计数器（跳过首帧避免NanoVG图片未就绪）

-- 教程弹窗
local TUTORIAL_CLOUD_KEY = "tutorial_seen"
local tutorialSeen_ = false  -- 是否已看过教程（从 clientCloud 加载）
local tutorialUI_ = nil      -- 教程弹窗 UI 引用

-- 虚拟触控按钮（移动端）
local vcBtnLeft_ = nil
local vcBtnRight_ = nil
local vcBtnJump_ = nil
local vcJumpTriggered_ = false

-- 调试模式
local debugMode_ = false
-- 测试模式（可调重力）
local testMode_ = false
-- 视差背景
local parallaxBg_ = nil

-- 音效系统
local sfxNode_ = nil         -- 音效节点
local sfxSource_ = nil       -- SoundSource 组件
local sfxCoin_ = nil         -- Sound: 金币收集
local sfxGoal_ = nil         -- Sound: 到达终点
local sfxWin_ = nil          -- Sound: 通关
local sfxDeath_ = nil        -- Sound: 失败/死亡

-- ============================================================================
-- 精灵帧动画系统
-- ============================================================================
local spriteFrames_ = {
    idle = {},    -- nvgImage 句柄数组
    run = {},
    jump = {},
    fall = {},        -- 下落帧动画（2帧）
    hit = {},         -- 受击白闪（1帧）
    death = {},       -- 死亡帧动画（4帧）
    showoff = {},
    spike = {},       -- 尖刺帧动画（4帧）
    coin = {},        -- 金币帧动画（4帧）
    coin_vfx = {},    -- 金币收集VFX（4帧）
    seagull = {},     -- 海鸥飞行帧动画（8帧）
    portal = {},      -- 传送门旋转动画（8帧）
}
local spriteAnimTimer_ = 0      -- 全局动画计时器
local SPRITE_FPS = 8            -- 动画帧率（帧/秒）
local SPRITE_DRAW_SIZE = 72     -- 精灵绘制大小（像素）
local PROP_FPS = 6              -- 道具帧动画帧率
local VFX_FPS = 12              -- VFX 帧率（快速播放）
local VFX_DURATION = 4 / VFX_FPS  -- VFX 总时长（4帧）
local DEATH_HIT_DURATION = 0.15  -- hit 白闪持续时间（秒）
local DEATH_FPS = 8              -- 死亡帧动画帧率

-- ============================================================================
-- 工具函数
-- ============================================================================

--- NanoVG 描边文字：先绘制黑色描边（8方向偏移），再绘制白色主体
--- @param vg userdata NanoVG context
--- @param x number 文字 x 坐标
--- @param y number 文字 y 坐标
--- @param text string 文字内容
--- @param fillColor table|nil 主体颜色 {r,g,b,a}，默认白色
--- @param strokeWidth number|nil 描边偏移像素，默认 1.5
local function nvgTextOutlined(vg, x, y, text, fillColor, strokeWidth)
    local sw = strokeWidth or 1.5
    local fc = fillColor or {255, 255, 255, 255}
    -- 黑色描边（8方向偏移）
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 220))
    for _, off in ipairs({{-sw,0},{sw,0},{0,-sw},{0,sw},{-sw,-sw},{sw,-sw},{-sw,sw},{sw,sw}}) do
        nvgText(vg, x + off[1], y + off[2], text)
    end
    -- 白色主体
    nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], fc[4]))
    nvgText(vg, x, y, text)
end

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
    -- fall: 2帧
    for i = 1, 2 do
        local path = "image/character/fall/character_berie_fall_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.fall, img)
    end
    -- hit: 1帧（受击白闪）
    do
        local img = nvgCreateImage(nvg_, "image/character/death/character_berie_hit_1.png", 0)
        table.insert(spriteFrames_.hit, img)
    end
    -- death: 4帧
    for i = 1, 4 do
        local path = "image/character/death/character_berie_death_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.death, img)
    end
    -- showoff: 7帧
    for i = 1, 7 do
        local path = "image/character/showoff/berie_showoff_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.showoff, img)
    end

    -- 尖刺: 4帧
    for i = 1, 4 do
        local path = "image/Prop/trap_spike_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.spike, img)
    end
    -- 金币: 4帧
    for i = 1, 4 do
        local path = "image/Prop/collectibles_coin_gold_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.coin, img)
    end
    -- 金币VFX: 4帧
    for i = 1, 4 do
        local path = "image/Prop/vfx_effect_coin_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.coin_vfx, img)
    end
    -- 海鸥: 8帧
    for i = 1, 8 do
        local path = "image/enemy/seagull/seagull_fly_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.seagull, img)
    end
    -- 传送门: 6帧
    for i = 1, 6 do
        local path = "image/goal/portal/portal_" .. i .. ".png"
        local img = nvgCreateImage(nvg_, path, 0)
        table.insert(spriteFrames_.portal, img)
    end

    print("[GameScene] Loaded sprite frames: idle=" .. #spriteFrames_.idle
        .. " jump=" .. #spriteFrames_.jump
        .. " fall=" .. #spriteFrames_.fall
        .. " hit=" .. #spriteFrames_.hit
        .. " death=" .. #spriteFrames_.death
        .. " run=" .. #spriteFrames_.run
        .. " showoff=" .. #spriteFrames_.showoff
        .. " spike=" .. #spriteFrames_.spike
        .. " coin=" .. #spriteFrames_.coin
        .. " coin_vfx=" .. #spriteFrames_.coin_vfx
        .. " seagull=" .. #spriteFrames_.seagull)
end

--- 根据角色物理状态获取当前动画名和帧索引
---@param player table
---@return string animName, number frameIndex
function GameScene.GetAnimFrame(player)
    local vel = player.body and player.body.linearVelocity or Vector2(0, 0)

    -- 死亡动画（hit白闪 → death帧序列）
    if not player.isAlive and player.deathTime then
        if player.deathTime < DEATH_HIT_DURATION then
            -- hit 白闪阶段
            return "hit", 1
        else
            -- death 帧序列（非循环，停在最后一帧）
            local deathElapsed = player.deathTime - DEATH_HIT_DURATION
            local frameIdx = math.floor(deathElapsed * DEATH_FPS) + 1
            local totalFrames = #spriteFrames_.death
            if frameIdx > totalFrames then frameIdx = totalFrames end
            return "death", frameIdx
        end
    end

    -- 到达终点 → showoff
    if player.reachedGoal then
        local totalFrames = #spriteFrames_.showoff
        local idx = math.floor(spriteAnimTimer_ * SPRITE_FPS) % totalFrames + 1
        return "showoff", idx
    end

    -- 空中（不在地面）
    if not player.onGround then
        if vel.y > 0.5 then
            -- 上升 → jump（前两帧循环）
            local jumpFrames = #spriteFrames_.jump
            if jumpFrames > 0 then
                local idx = math.floor(spriteAnimTimer_ * SPRITE_FPS) % 2 + 1
                return "jump", idx
            end
        else
            -- 下落 → fall（2帧循环）
            local fallFrames = #spriteFrames_.fall
            if fallFrames > 0 then
                local idx = math.floor(spriteAnimTimer_ * SPRITE_FPS) % fallFrames + 1
                return "fall", idx
            end
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
    renderFrameCount_ = 0  -- 重置帧计数器

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

    -- 从 clientCloud 加载总金币数
    clientCloud:Get(COIN_CLOUD_KEY, {
        onComplete = function(success, key, value)
            if success and value then
                totalCoins_ = tonumber(value) or 0
                print("[GameScene] Loaded total coins: " .. totalCoins_)
            end
        end,
    })

    -- 创建 HUD（暂停按钮）
    hudUI_ = UI.Panel {
        width = "100%", height = "100%",
        children = {
            UI.Panel {
                position = "absolute",
                top = 8, left = 8,
                children = {
                    UI.Button {
                        text = "⏸",
                        width = 40, height = 40,
                        fontSize = 18,
                        borderRadius = 20,
                        onClick = function(self)
                            UIScenes.PlayUIClick()
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

    -- 创建虚拟触控按钮（移动端自动显示，桌面端有键盘绑定时自动隐藏）
    -- 根据屏幕短边自适应按钮尺寸（基准: 短边720px时半径55/62）
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local shortEdge = math.min(screenW, screenH)
    local scaleFactor = shortEdge / 720
    local btnRadius = math.floor(55 * scaleFactor)
    local jumpRadius = math.floor(62 * scaleFactor)
    local btnOffset = math.floor(100 * scaleFactor)
    local btnGap = math.floor(130 * scaleFactor)
    local bottomMargin = math.floor(100 * scaleFactor)

    vcJumpTriggered_ = false
    vcBtnLeft_ = VirtualControls.CreateButton({
        label = "◀",
        position = Vector2(btnOffset, -bottomMargin),
        alignment = {HA_LEFT, VA_BOTTOM},
        radius = btnRadius,
        keyBinding = KEY_LEFT,
        opacity = 0.45,
        activeOpacity = 0.8,
        color = {255, 255, 255},
        pressedColor = {180, 220, 255},
    })
    vcBtnRight_ = VirtualControls.CreateButton({
        label = "▶",
        position = Vector2(btnOffset + btnGap, -bottomMargin),
        alignment = {HA_LEFT, VA_BOTTOM},
        radius = btnRadius,
        keyBinding = KEY_RIGHT,
        opacity = 0.45,
        activeOpacity = 0.8,
        color = {255, 255, 255},
        pressedColor = {180, 220, 255},
    })
    vcBtnJump_ = VirtualControls.CreateButton({
        label = "跳",
        position = Vector2(-btnOffset, -bottomMargin),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = jumpRadius,
        keyBinding = KEY_SPACE,
        opacity = 0.45,
        activeOpacity = 0.8,
        color = {255, 230, 150},
        pressedColor = {255, 200, 100},
        on_press = function()
            vcJumpTriggered_ = true
        end,
    })

    -- 第一次进入第1关时检查是否需要显示教程
    if currentLevel_ == 1 and not fromEditor_ then
        clientCloud:Get(TUTORIAL_CLOUD_KEY, {
            onComplete = function(success, key, value)
                if success and value == "1" then
                    tutorialSeen_ = true
                    print("[GameScene] Tutorial already seen")
                else
                    tutorialSeen_ = false
                    -- 首次进入，显示教程弹窗并暂停
                    GameScene.ShowTutorial()
                    print("[GameScene] Showing tutorial for first time")
                end
            end,
        })
    end

    if fromEditor_ then
        print("[GameScene] Entered EDITOR TEST mode")
    else
        print("[GameScene] Entered level " .. currentLevel_)
    end
end

function GameScene.Exit()
    -- 清理虚拟触控按钮
    VirtualControls.Shutdown()
    vcBtnLeft_ = nil
    vcBtnRight_ = nil
    vcBtnJump_ = nil
    vcJumpTriggered_ = false

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
        spriteFrames_ = { idle = {}, run = {}, jump = {}, fall = {}, hit = {}, death = {}, showoff = {}, spike = {}, coin = {}, coin_vfx = {}, seagull = {}, portal = {} }
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
    seagulls_ = {}
    goals_ = {}
    goalTarget_ = 0
    coins_ = {}
    coinCount_ = 0
    decorations_ = {}
    decorImages_ = {}
    goalArea_ = nil
    mapGridW_ = 0
    mapGridH_ = 0
    contentMinY_ = 0
    contentCenterX_ = 0
    tileCells_ = {}
    tileImages_ = {}
    hasTileTextures_ = false

    -- 清理音效
    sfxNode_ = nil
    sfxSource_ = nil
    sfxCoin_ = nil
    sfxGoal_ = nil
    sfxWin_ = nil
    sfxDeath_ = nil
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

    -- 初始化音效系统
    sfxNode_ = scene_:CreateChild("SFX")
    sfxSource_ = sfxNode_:CreateComponent("SoundSource")
    sfxSource_:SetSoundType("Effect")

    sfxCoin_ = cache:GetResource("Sound", "audio/sfx/coin_collect.ogg")
    sfxGoal_ = cache:GetResource("Sound", "audio/sfx/reach_endpoint.ogg")
    sfxWin_ = cache:GetResource("Sound", "audio/sfx/level_complete.ogg")
    sfxDeath_ = cache:GetResource("Sound", "audio/sfx/player_death.ogg")
end

--- 播放音效（最终音量 = 个体系数 × 全局音效音量）
---@param sound userdata Sound 资源
---@param gain number|nil 个体音量系数（默认0.35）
local function PlaySFX(sound, gain)
    if not sound or not sfxSource_ then return end
    local individualGain = gain or 0.35
    local masterSfx = Config.Settings.SFXVolume or 0.4
    sfxSource_:Play(sound, sound.frequency, individualGain * masterSfx)
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
    seagulls_ = {}
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

    -- 保存地图网格尺寸（用于渲染参考）
    if levelData.gridHeight and levelData.gridWidth then
        mapGridW_ = levelData.gridWidth
        mapGridH_ = levelData.gridHeight
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

        local rot = sData.rotation or 0
        local shape = node:CreateComponent("CollisionBox2D")
        -- 90°/270° 时尖刺变为竖向，交换碰撞盒宽高
        if rot == 90 or rot == 270 then
            shape:SetSize(0.4, sData.width)
        else
            shape:SetSize(sData.width, 0.4)
        end
        shape.trigger = true
        shape.categoryBits = 8
        shape.maskBits = 2  -- 只与玩家碰撞

        table.insert(spikes_, {
            x = sData.x, y = sData.y,
            width = sData.width,
            rotation = rot,
            node = node,
        })
    end

    -- 创建海鸥飞行敌人（水平巡逻）
    if levelData.seagulls then
        for i, gData in ipairs(levelData.seagulls) do
            local node = scene_:CreateChild("Seagull")
            node:SetPosition2D(gData.x, gData.y)

            local body = node:CreateComponent("RigidBody2D")
            body.bodyType = BT_KINEMATIC
            body.gravityScale = 0

            local shape = node:CreateComponent("CollisionBox2D")
            shape:SetSize(0.45, 0.3)
            shape.trigger = true
            shape.categoryBits = 64
            shape.maskBits = 2  -- 只与玩家碰撞

            local speed = (gData.speed or 2.0) * 0.6
            local range = gData.range or 3.0
            table.insert(seagulls_, {
                x = gData.x, y = gData.y,
                minX = gData.x - range,
                maxX = gData.x + range,
                speed = speed,
                dir = 1,  -- 1=右, -1=左
                node = node,
                body = body,
            })
        end
    end

    -- 创建金币（用传感器检测）
    coins_ = {}
    coinCount_ = 0
    if levelData.coins then
        for i, cData in ipairs(levelData.coins) do
            local node = scene_:CreateChild("Coin")
            node:SetPosition2D(cData.x, cData.y)

            local body = node:CreateComponent("RigidBody2D")
            body.bodyType = BT_STATIC

            local shape = node:CreateComponent("CollisionCircle2D")
            shape.radius = 0.35
            shape.trigger = true
            shape.categoryBits = 32
            shape.maskBits = 2  -- 只与玩家碰撞

            table.insert(coins_, {
                x = cData.x, y = cData.y,
                node = node,
                collected = false,
                vfxTimer = -1,  -- -1 = 未触发VFX
            })
        end
    end

    -- 加载装饰预制体（纯视觉，不创建物理体）
    decorations_ = {}
    decorImages_ = {}
    if levelData.decorations then
        for _, dData in ipairs(levelData.decorations) do
            table.insert(decorations_, { x = dData.x, y = dData.y, image = dData.image })
            -- 预加载纹理
            if dData.image and not decorImages_[dData.image] then
                local img = nvgCreateImage(nvg_, dData.image, 0)
                if img and img > 0 then
                    decorImages_[dData.image] = img
                end
            end
        end
        if #decorations_ > 0 then
            print("[GameScene] Loaded decorations: " .. #decorations_)
        end
    end

    -- 终点区域（传感器）— 支持多终点
    goals_ = {}
    goalTarget_ = 0

    if levelData.goals and #levelData.goals > 0 then
        -- 新格式：多终点数组（硬编码3只小猪通关）
        goalTarget_ = 3
        for i, gData in ipairs(levelData.goals) do
            local goalNode = scene_:CreateChild("Goal")
            goalNode:SetPosition2D(gData.x, gData.y)

            local goalBody = goalNode:CreateComponent("RigidBody2D")
            goalBody.bodyType = BT_STATIC

            local goalShape = goalNode:CreateComponent("CollisionBox2D")
            goalShape:SetSize(gData.width, gData.height)
            goalShape.trigger = true
            goalShape.categoryBits = 16
            goalShape.maskBits = 2

            table.insert(goals_, {
                x = gData.x, y = gData.y,
                width = gData.width, height = gData.height,
                acceptCount = gData.acceptCount or 1,
                node = goalNode,
            })
        end
        -- 兼容旧渲染：goalArea_ 指向第一个终点
        goalArea_ = goals_[1]
    elseif levelData.goal then
        -- 旧格式：单终点（硬编码3只小猪通关）
        goalArea_ = levelData.goal
        goalTarget_ = 3

        local goalNode = scene_:CreateChild("Goal")
        goalNode:SetPosition2D(goalArea_.x, goalArea_.y)

        local goalBody = goalNode:CreateComponent("RigidBody2D")
        goalBody.bodyType = BT_STATIC

        local goalShape = goalNode:CreateComponent("CollisionBox2D")
        goalShape:SetSize(goalArea_.width, goalArea_.height)
        goalShape.trigger = true
        goalShape.categoryBits = 16
        goalShape.maskBits = 2

        table.insert(goals_, {
            x = goalArea_.x, y = goalArea_.y,
            width = goalArea_.width, height = goalArea_.height,
            acceptCount = goalTarget_,
            node = goalNode,
        })
    end

    -- 计算实际内容包围盒（基于所有游戏元素的位置）
    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge

    local function expandBounds(x, y, hw, hh)
        hw = hw or 0
        hh = hh or 0
        if x - hw < minX then minX = x - hw end
        if x + hw > maxX then maxX = x + hw end
        if y - hh < minY then minY = y - hh end
        if y + hh > maxY then maxY = y + hh end
    end

    -- 出生点
    expandBounds(levelData.spawn.x, levelData.spawn.y, 0.5, 0.5)

    -- 平台
    for _, p in ipairs(platforms_) do
        expandBounds(p.x, p.y, p.width / 2, p.height / 2)
    end

    -- 终点
    for _, g in ipairs(goals_) do
        expandBounds(g.x, g.y, g.width / 2, g.height / 2)
    end

    -- 金币
    for _, c in ipairs(coins_) do
        expandBounds(c.x, c.y, 0.3, 0.3)
    end

    -- 刺
    for _, s in ipairs(spikes_) do
        expandBounds(s.x, s.y, s.width / 2, 0.3)
    end
    -- 海鸥巡逻范围
    for _, sg in ipairs(seagulls_) do
        expandBounds(sg.x, sg.y, (sg.maxX - sg.minX) / 2, 0.5)
    end

    -- 计算内容尺寸（负边距让边缘被裁掉，不露馅）
    local padding = -4.0
    local contentW = (maxX - minX) + padding * 2
    local contentH = (maxY - minY) + padding * 2
    local contentCX = (minX + maxX) / 2

    -- 保存用于动态适配
    mapGridW_ = contentW
    mapGridH_ = contentH
    contentMinY_ = minY - padding
    contentCenterX_ = contentCX

    -- Fit All：根据屏幕宽高比决定 orthoSize
    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr
    local aspect = sw / sh
    local neededH = contentH
    local neededW = contentW / aspect
    local camera = cameraNode_:GetComponent("Camera")
    camera.orthoSize = math.max(neededH, neededW)

    -- 设置相机位置：水平居中于内容，垂直让内容底边对齐视野底边
    local camY = minY - padding + camera.orthoSize / 2
    cameraNode_:SetPosition(Vector3(contentCX, camY, -10))

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

    -- BGM 监控（不受暂停影响，始终保持音乐循环）
    BGM.Tick()

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

    -- M 切换移动端虚拟按钮显示（桌面调试用）
    if input:GetKeyPress(KEY_M) then
        local isMobile = VirtualControls.IsMobileMode()
        VirtualControls.SetMobileMode(not isMobile)
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

    -- 更新金币 VFX 计时器
    for _, coin in ipairs(coins_) do
        if coin.collected and coin.vfxTimer >= 0 then
            coin.vfxTimer = coin.vfxTimer + dt
        end
    end

    -- 更新海鸥巡逻
    for _, sg in ipairs(seagulls_) do
        local pos = sg.node:GetPosition2D()
        local newX = pos.x + sg.speed * sg.dir * dt
        -- 到达边界反转方向
        if newX >= sg.maxX then
            newX = sg.maxX
            sg.dir = -1
        elseif newX <= sg.minX then
            newX = sg.minX
            sg.dir = 1
        end
        sg.body.linearVelocity = Vector2(sg.speed * sg.dir, 0)
    end

    -- 更新死亡动画计时器（所有角色）
    if mainPlayer_ and not mainPlayer_.isAlive and mainPlayer_.deathTime then
        mainPlayer_.deathTime = mainPlayer_.deathTime + dt
    end
    if cloneSystem_ then
        for _, clone in ipairs(cloneSystem_:GetClones()) do
            if not clone.isAlive and clone.deathTime then
                clone.deathTime = clone.deathTime + dt
            end
        end
    end

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
            or (vcBtnLeft_ and vcBtnLeft_.isPressed)
        local rightHeld = input:GetKeyDown(KEY_RIGHT) or input:GetKeyDown(KEY_D)
            or (vcBtnRight_ and vcBtnRight_.isPressed)
        local jumpPressed = input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_UP) or input:GetKeyPress(KEY_W)
            or vcJumpTriggered_
        vcJumpTriggered_ = false
        mainPlayer_:UpdateInput(dt, leftHeld, rightHeld, jumpPressed)
    end

    -- 检测掉落死亡
    GameScene.CheckFallDeath()

    -- 检测胜负（玩家还没生成时不检测）
    -- 失败条件：剩余可能到达终点的小猪数 < 目标数
    if mainPlayer_ and cloneSystem_:CountPotentialSuccess() < goalTarget_ then
        gameState_ = STATE_LOSE
        stateTimer_ = 0
        PlaySFX(sfxDeath_, 0.35)
        print("[GameScene] GAME OVER - Not enough pigs to reach goal!")
    elseif mainPlayer_ and cloneSystem_:CountReachedGoal() >= goalTarget_ and not cloneSystem_:IsActive() then
        gameState_ = STATE_WIN
        stateTimer_ = 0
        PlaySFX(sfxWin_, 0.4)
        -- 保存关卡进度，解锁下一关
        local Progress = require("Progress")
        Progress.CompleteLevel(currentLevel_)
        print("[GameScene] LEVEL CLEAR! (" .. cloneSystem_:CountReachedGoal() .. "/" .. goalTarget_ .. ")")
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
            PlaySFX(sfxDeath_, 0.3)
        end
    end
    -- 检查克隆体
    if cloneSystem_ then
        for _, clone in ipairs(cloneSystem_:GetClones()) do
            if clone.isAlive then
                local pos = clone:GetPosition()
                if pos.y < fallDeathY then
                    clone:Kill()
                    PlaySFX(sfxDeath_, 0.3)
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

    -- 检测海鸥碰撞
    if nodeA.name == "Seagull" or nodeB.name == "Seagull" then
        local charNode = (nodeA.name == "Seagull") and nodeB or nodeA
        GameScene.HandleSpikeHit(charNode)  -- 复用尖刺击杀逻辑
        return
    end

    -- 检测金币碰撞
    if nodeA.name == "Coin" or nodeB.name == "Coin" then
        local coinNode = (nodeA.name == "Coin") and nodeA or nodeB
        local charNode = (nodeA.name == "Coin") and nodeB or nodeA
        GameScene.HandleCoinCollect(charNode, coinNode)
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

    -- 允许平台、地面、以及其他角色（猪踩猪）作为有效地面
    local otherName = otherNode.name
    local isValidGround = (otherName == "Platform" or otherName == "Ground"
        or otherName == "Player" or string.find(otherName, "Clone_", 1, true) ~= nil)
    if not isValidGround then return end

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
        PlaySFX(sfxDeath_, 0.3)
        print("[GameScene] Character hit spike: " .. charNode.name)
    end
end

function GameScene.HandleGoalReach(charNode)
    local player = GameScene.FindPlayerByNode(charNode)
    if player and player.isAlive and not player.reachedGoal then
        player:SetReachedGoal()
        PlaySFX(sfxGoal_, 0.15)
        print("[GameScene] Character reached goal: " .. charNode.name)
    end
end

function GameScene.HandleCoinCollect(charNode, coinNode)
    local player = GameScene.FindPlayerByNode(charNode)
    if not player or not player.isAlive then return end

    -- 找到对应的 coin 数据
    for _, coin in ipairs(coins_) do
        if coin.node == coinNode and not coin.collected then
            coin.collected = true
            coin.vfxTimer = 0  -- 开始播放 VFX
            coinCount_ = coinCount_ + 1
            totalCoins_ = totalCoins_ + 1
            PlaySFX(sfxCoin_, 0.8)
            -- 持久化总金币数到云端
            clientCloud:Set(COIN_CLOUD_KEY, tostring(totalCoins_), {
                onComplete = function(success)
                    if not success then
                        print("[GameScene] Warning: failed to save coin count")
                    end
                end,
            })
            -- 禁用碰撞（不再触发）
            local body = coinNode:GetComponent("RigidBody2D")
            if body then body.enabled = false end
            print("[GameScene] Coin collected! Level: " .. coinCount_ .. " Total: " .. totalCoins_)
            break
        end
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

    -- 首帧执行空渲染帧：NanoVG 图片(nvgCreateImage)需要至少一次 beginFrame/endFrame
    -- 周期来完成纹理上传到 GPU，否则 imagePattern 绘制异常
    renderFrameCount_ = renderFrameCount_ + 1
    if renderFrameCount_ <= 1 then
        nvgBeginFrame(nvg_, screenW_, screenH_, dpr)
        nvgEndFrame(nvg_)
        return
    end

    -- 动态调整相机 orthoSize（Fit All 策略：确保内容在任何宽高比下都完全可见）
    if mapGridH_ > 0 and mapGridW_ > 0 then
        local camera = cameraNode_:GetComponent("Camera")
        local aspect = screenW_ / screenH_
        local neededH = mapGridH_
        local neededW = mapGridW_ / aspect
        local baseOrtho = math.max(neededH, neededW)
        -- 应用用户缩放设置（CameraZoom: 1.0=默认, <1=放大近, >1=缩小远）
        camera.orthoSize = baseOrtho * (Config.Settings.CameraZoom or 1.0)
        -- 相机位置：内容底边对齐视野底边，水平居中 + 用户偏移
        local camX = contentCenterX_ + (Config.Settings.CameraOffsetX or 0)
        local camY = contentMinY_ + camera.orthoSize / 2 + (Config.Settings.CameraOffsetY or 0)
        cameraNode_:SetPosition(Vector3(camX, camY, -10))
    end

    nvgBeginFrame(nvg_, screenW_, screenH_, dpr)

    GameScene.DrawBackground()
    GameScene.DrawDecorations()
    GameScene.DrawPlatforms()
    GameScene.DrawSpikes()
    GameScene.DrawCoins()
    GameScene.DrawSeagulls()
    GameScene.DrawGoal()
    GameScene.DrawTimerUI()       -- tilemap后、角色前
    GameScene.DrawCharacters()
    GameScene.DrawHUD()           -- 左上角 HUD（金币+小猪+计时）
    GameScene.DrawGameState()
    if debugMode_ then
        GameScene.DrawDebugOverlay()
    end

    nvgEndFrame(nvg_)
end

function GameScene.DrawBackground()
    -- 使用视差背景系统
    if parallaxBg_ then
        -- 计算地面在屏幕中的垂直比例（地面Y=内容底边对齐视野底边时约在底部）
        local groundRatio = nil
        if mapGridH_ > 0 and cameraNode_ then
            local camera = cameraNode_:GetComponent("Camera")
            local camY = cameraNode_.position.y
            local orthoH = camera.orthoSize
            local viewBottom = camY - orthoH / 2
            -- 地面 Y 大约在 contentMinY_ + 几个单位处（取内容底部偏上一点作为海岸线位置）
            local groundY = contentMinY_ + 2.0  -- 地面 Y（平台底部区域）
            -- 转为屏幕比例：0=顶部, 1=底部
            groundRatio = 1.0 - (groundY - viewBottom) / orthoH
            groundRatio = math.max(0.5, math.min(1.0, groundRatio))
        end
        parallaxBg_:Draw(screenW_, screenH_, groundRatio)
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
    local ppu = GetPixelsPerUnit()
    local frames = spriteFrames_.spike
    if #frames == 0 then return end

    -- 计算当前帧
    local frameIdx = math.floor(spriteAnimTimer_ * PROP_FPS) % #frames + 1
    local imgHandle = frames[frameIdx]
    if not imgHandle or imgHandle == 0 then return end

    for _, s in ipairs(spikes_) do
        local sx, sy = PhysicsToScreen(s.x, s.y)
        -- 尖刺绘制尺寸：1格
        local drawSize = 1.0 * ppu
        local rot = s.rotation or 0

        if rot ~= 0 then
            -- 带旋转的尖刺：先平移到中心，再旋转绘制
            nvgSave(nvg_)
            nvgTranslate(nvg_, sx, sy)
            nvgRotate(nvg_, math.rad(rot))
            local imgPat = nvgImagePattern(nvg_, -drawSize/2, -drawSize/2, drawSize, drawSize, 0, imgHandle, 1.0)
            nvgBeginPath(nvg_)
            nvgRect(nvg_, -drawSize/2, -drawSize/2, drawSize, drawSize)
            nvgFillPaint(nvg_, imgPat)
            nvgFill(nvg_)
            nvgRestore(nvg_)
        else
            local imgPat = nvgImagePattern(nvg_, sx - drawSize/2, sy - drawSize/2, drawSize, drawSize, 0, imgHandle, 1.0)
            nvgBeginPath(nvg_)
            nvgRect(nvg_, sx - drawSize/2, sy - drawSize/2, drawSize, drawSize)
            nvgFillPaint(nvg_, imgPat)
            nvgFill(nvg_)
        end
    end
end

function GameScene.DrawSeagulls()
    local ppu = GetPixelsPerUnit()
    local frames = spriteFrames_.seagull
    if #frames == 0 then return end

    local frameIdx = math.floor(spriteAnimTimer_ * PROP_FPS) % #frames + 1
    local imgHandle = frames[frameIdx]
    if not imgHandle or imgHandle == 0 then return end

    for _, sg in ipairs(seagulls_) do
        local pos = sg.node:GetPosition2D()
        local sx, sy = PhysicsToScreen(pos.x, pos.y)
        local drawSize = 1.0 * ppu  -- 1格大小

        -- 根据方向翻转
        nvgSave(nvg_)
        nvgTranslate(nvg_, sx, sy)
        if sg.dir < 0 then
            nvgScale(nvg_, -1, 1)
        end
        local imgPat = nvgImagePattern(nvg_, -drawSize/2, -drawSize/2, drawSize, drawSize, 0, imgHandle, 1.0)
        nvgBeginPath(nvg_)
        nvgRect(nvg_, -drawSize/2, -drawSize/2, drawSize, drawSize)
        nvgFillPaint(nvg_, imgPat)
        nvgFill(nvg_)
        nvgRestore(nvg_)
    end
end

function GameScene.DrawCoins()
    local ppu = GetPixelsPerUnit()
    local coinFrames = spriteFrames_.coin
    local vfxFrames = spriteFrames_.coin_vfx

    -- 金币帧动画（循环）
    local coinFrameIdx = 1
    if #coinFrames > 0 then
        coinFrameIdx = math.floor(spriteAnimTimer_ * PROP_FPS) % #coinFrames + 1
    end

    for _, coin in ipairs(coins_) do
        local sx, sy = PhysicsToScreen(coin.x, coin.y)
        local drawSize = 0.8 * ppu  -- 金币略小于1格

        if not coin.collected then
            -- 未收集：渲染金币帧动画
            if #coinFrames > 0 then
                local imgHandle = coinFrames[coinFrameIdx]
                if imgHandle and imgHandle ~= 0 then
                    local imgPat = nvgImagePattern(nvg_, sx - drawSize/2, sy - drawSize/2, drawSize, drawSize, 0, imgHandle, 1.0)
                    nvgBeginPath(nvg_)
                    nvgRect(nvg_, sx - drawSize/2, sy - drawSize/2, drawSize, drawSize)
                    nvgFillPaint(nvg_, imgPat)
                    nvgFill(nvg_)
                end
            end
        else
            -- 已收集：播放 VFX 动画
            if coin.vfxTimer >= 0 and coin.vfxTimer < VFX_DURATION and #vfxFrames > 0 then
                local vfxIdx = math.floor(coin.vfxTimer * VFX_FPS) % #vfxFrames + 1
                local imgHandle = vfxFrames[vfxIdx]
                if imgHandle and imgHandle ~= 0 then
                    -- VFX 稍大一些
                    local vfxSize = 1.2 * ppu
                    local imgPat = nvgImagePattern(nvg_, sx - vfxSize/2, sy - vfxSize/2, vfxSize, vfxSize, 0, imgHandle, 1.0)
                    nvgBeginPath(nvg_)
                    nvgRect(nvg_, sx - vfxSize/2, sy - vfxSize/2, vfxSize, vfxSize)
                    nvgFillPaint(nvg_, imgPat)
                    nvgFill(nvg_)
                end
            end
        end
    end
end

function GameScene.DrawDecorations()
    if #decorations_ == 0 then return end
    local ppu = GetPixelsPerUnit()
    local TREE_HEIGHT_UNITS = 3.0  -- 树高度（物理单位），约为玩家的 2.5~3 倍

    for _, d in ipairs(decorations_) do
        local imgHandle = decorImages_[d.image]
        if imgHandle and imgHandle > 0 then
            local sx, sy = PhysicsToScreen(d.x, d.y)

            -- 获取图片原始尺寸，按高度缩放保持宽高比
            local imgW, imgH = nvgImageSize(nvg_, imgHandle)
            local drawH = TREE_HEIGHT_UNITS * ppu
            local drawW = drawH * (imgW / imgH)

            -- 底部对齐到格子底边（sy 是格子中心，往下半格即底边）
            local bottomY = sy + 0.5 * ppu
            local drawX = sx - drawW / 2
            local drawY = bottomY - drawH

            local imgPat = nvgImagePattern(nvg_, drawX, drawY, drawW, drawH, 0, imgHandle, 1.0)
            nvgBeginPath(nvg_)
            nvgRect(nvg_, drawX, drawY, drawW, drawH)
            nvgFillPaint(nvg_, imgPat)
            nvgFill(nvg_)
        end
    end
end

function GameScene.DrawHUD()
    -- 右上角像素风 HUD 面板
    local margin = 10
    local panelW = 140
    local px = screenW_ - panelW - margin
    local py = margin
    local rowH = 24       -- 每行高度
    local iconSz = 20     -- 图标大小
    local panelH = rowH * 3 + 12  -- 3行内容 + padding

    -- 面板背景
    nvgBeginPath(nvg_)
    nvgRect(nvg_, px, py, panelW, panelH)
    nvgFillColor(nvg_, nvgRGBA(15, 15, 35, 200))
    nvgFill(nvg_)

    -- 2px 像素边框
    nvgBeginPath(nvg_)
    nvgRect(nvg_, px, py, panelW, panelH)
    nvgStrokeWidth(nvg_, 2)
    nvgStrokeColor(nvg_, nvgRGBA(58, 58, 106, 255))
    nvgStroke(nvg_)

    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 14)
    nvgTextAlign(nvg_, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local contentX = px + 8
    local contentY = py + 6 + rowH / 2

    -- 第1行：小猪数量（剩余/需要）
    local reached = 0
    local totalPigs = 0
    if cloneSystem_ then
        reached = cloneSystem_:CountReachedGoal()
        -- 总小猪 = 已生成的（含已到终点和存活的）
        totalPigs = cloneSystem_:GetCurrentNumber() -- 还没生的
        if cloneSystem_:GetMainPlayer() then
            totalPigs = totalPigs + 1 + #cloneSystem_:GetClones()
        end
    end
    nvgTextOutlined(nvg_, contentX, contentY, "🐷", {255, 180, 200, 255})
    nvgTextOutlined(nvg_, contentX + iconSz + 4, contentY, reached .. "/" .. goalTarget_ .. " 目标", {255, 255, 255, 255})

    -- 第2行：计时器倒计时
    contentY = contentY + rowH
    local timerNum = 0
    if cloneSystem_ and cloneSystem_:IsActive() then
        timerNum = cloneSystem_:GetCurrentNumber()
    end
    nvgTextOutlined(nvg_, contentX, contentY, "⏳", {80, 200, 240, 255})
    if timerNum > 0 then
        nvgTextOutlined(nvg_, contentX + iconSz + 4, contentY, "×" .. timerNum .. " 待出发", {255, 255, 255, 255})
    else
        nvgTextOutlined(nvg_, contentX + iconSz + 4, contentY, "全部出发", {255, 255, 255, 255})
    end

    -- 第3行：金币
    contentY = contentY + rowH
    -- 金币图标
    local coinFrames = spriteFrames_.coin
    if #coinFrames > 0 and coinFrames[1] and coinFrames[1] ~= 0 then
        local imgPat = nvgImagePattern(nvg_, contentX, contentY - iconSz/2, iconSz, iconSz, 0, coinFrames[1], 1.0)
        nvgBeginPath(nvg_)
        nvgRect(nvg_, contentX, contentY - iconSz/2, iconSz, iconSz)
        nvgFillPaint(nvg_, imgPat)
        nvgFill(nvg_)
    else
        nvgTextOutlined(nvg_, contentX, contentY, "🪙", {255, 215, 0, 255})
    end
    nvgTextOutlined(nvg_, contentX + iconSz + 4, contentY, "×" .. totalCoins_, {255, 215, 0, 240})
end

function GameScene.DrawGoal()
    if #goals_ == 0 and not goalArea_ then return end
    local ppu = GetPixelsPerUnit()
    local frames = spriteFrames_.portal
    local hasFrames = #frames > 0

    -- 帧动画索引（6fps旋转速度）
    local frameIdx = math.floor(spriteAnimTimer_ * 6) % math.max(1, #frames) + 1

    -- 渲染所有终点
    for _, goal in ipairs(goals_) do
        local sx, sy = PhysicsToScreen(goal.x, goal.y)
        sy = sy - ppu * 0.4  -- 向上偏移
        local drawH = goal.height * ppu * 1.8  -- 放大
        local drawW = drawH  -- 1:1 正方形帧

        if hasFrames then
            local imgHandle = frames[frameIdx]
            if imgHandle and imgHandle ~= 0 then
                nvgSave(nvg_)
                local imgPat = nvgImagePattern(nvg_, sx - drawW/2, sy - drawH/2, drawW, drawH, 0, imgHandle, 1.0)
                nvgBeginPath(nvg_)
                nvgRect(nvg_, sx - drawW/2, sy - drawH/2, drawW, drawH)
                nvgFillPaint(nvg_, imgPat)
                nvgFill(nvg_)
                nvgRestore(nvg_)
            end
        else
            -- fallback: 简单矩形
            local pulse = math.sin(os.clock() * 3) * 0.3 + 0.7
            local alpha = math.floor(pulse * 180)
            nvgBeginPath(nvg_)
            nvgRoundedRect(nvg_, sx - drawW/2, sy - drawH/2, drawW, drawH, 4)
            nvgFillColor(nvg_, nvgRGBA(120, 80, 220, alpha))
            nvgFill(nvg_)
        end

        -- 如果 acceptCount > 1，显示数字
        if goal.acceptCount and goal.acceptCount > 1 then
            nvgFontFace(nvg_, "sans")
            nvgFontSize(nvg_, 12)
            nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgTextOutlined(nvg_, sx, sy + drawH/2 + 10, "×" .. goal.acceptCount, {255, 255, 255, 230})
        end
    end
end

function GameScene.DrawCharacters()
    -- 画主玩家（存活或死亡动画播放中都渲染）
    if mainPlayer_ and mainPlayer_.visible then
        if mainPlayer_.isAlive or mainPlayer_.deathTime then
            GameScene.DrawSingleCharacter(mainPlayer_)
        end
    end
    -- 画克隆体
    if cloneSystem_ then
        for _, clone in ipairs(cloneSystem_:GetClones()) do
            if clone.visible then
                if clone.isAlive or clone.deathTime then
                    GameScene.DrawSingleCharacter(clone)
                end
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
    if not cloneSystem_:IsActive() then return end

    -- 出生点屏幕坐标
    local sx, sy = PhysicsToScreen(spawnPos_.x, spawnPos_.y)
    local ppu = GetPixelsPerUnit()
    -- 方形尺寸 = 约1个瓦片大小
    local tileSize = ppu * 0.8
    local halfSize = tileSize / 2
    -- 位置：出生点同高度（略偏左）
    local cx = sx - tileSize * 0.8
    local cy = sy

    local progress = cloneSystem_:GetTimerProgress()
    local num = cloneSystem_:GetCurrentNumber()

    -- 像素风方形背景（深色）
    nvgBeginPath(nvg_)
    nvgRect(nvg_, cx - halfSize, cy - halfSize, tileSize, tileSize)
    nvgFillColor(nvg_, nvgRGBA(20, 20, 40, 210))
    nvgFill(nvg_)

    -- 2px 像素边框
    nvgBeginPath(nvg_)
    nvgRect(nvg_, cx - halfSize, cy - halfSize, tileSize, tileSize)
    nvgStrokeWidth(nvg_, 2)
    nvgStrokeColor(nvg_, nvgRGBA(80, 180, 220, 255))
    nvgStroke(nvg_)

    -- 进度条（从底部向上填充）
    local fillH = tileSize * progress
    nvgBeginPath(nvg_)
    nvgRect(nvg_, cx - halfSize + 2, cy + halfSize - fillH - 2, tileSize - 4, fillH)
    nvgFillColor(nvg_, nvgRGBA(80, 200, 240, 140))
    nvgFill(nvg_)

    -- 中心数字
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, tileSize * 0.55)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgTextOutlined(nvg_, cx, cy, tostring(num), {255, 255, 255, 255}, 2)
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
        nvgTextOutlined(nvg_, screenW_ / 2, screenH_ / 2 - 20, "通关成功!", {255, 215, 0, 255}, 2.5)

        nvgFontSize(nvg_, 18)
        nvgTextOutlined(nvg_, screenW_ / 2, screenH_ / 2 + 30, "即将返回关卡选择...", {255, 255, 255, 200})
    else
        nvgFontSize(nvg_, 48)
        nvgTextOutlined(nvg_, screenW_ / 2, screenH_ / 2 - 20, "挑战失败", {255, 80, 80, 255}, 2.5)

        nvgFontSize(nvg_, 18)
        nvgTextOutlined(nvg_, screenW_ / 2, screenH_ / 2 + 30, "即将重新开始...", {255, 255, 255, 200})
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
-- ============================================================================
-- 教程/帮助弹窗
-- ============================================================================

function GameScene.ShowTutorial(fromPause)
    gameState_ = STATE_PAUSED
    tutorialUI_ = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = "90%",
                maxWidth = 340,
                padding = 18,
                gap = 12,
                alignItems = "center",
                backgroundColor = { 35, 40, 58, 250 },
                borderRadius = 14,
                borderWidth = 2,
                borderColor = { 80, 140, 255, 100 },
                children = {
                    UI.Label {
                        text = "克隆小猪的故事",
                        fontSize = 16,
                        fontWeight = "bold",
                        fontColor = { 255, 220, 80, 255 },
                        marginBottom = 4,
                    },
                    UI.Label {
                        text = "早就听说海滩尽头风景格外漂亮，小猪心里满是向往，独自出发前往。一路上障碍不少，单靠自己走起来格外吃力。\n\n好在它意外学会了神奇的克隆术，只要倒数五四三二一，就能唤来一群一模一样的伙伴。这些克隆小猪会跟着它同步行动，一路结伴同行。\n\n现在就由你来指挥这支队伍，穿过沙滩，一起走到旅途的终点吧！",
                        fontSize = 10,
                        fontColor = { 220, 225, 240, 255 },
                        textAlign = "left",
                        width = "100%",
                    },
                    UI.Button {
                        text = fromPause and "返回" or "我已经知道了！！！",
                        width = "80%", maxWidth = 180,
                        height = 64,
                        backgroundImage = WOODEN_BTN.image,
                        backgroundFit = WOODEN_BTN.fit,
                        backgroundSlice = WOODEN_BTN.slice,
                        backgroundColor = WOODEN_BTN.bgColor,
                        boxShadow = WOODEN_BTN.shadow,
                        fontColor = WOODEN_BTN.textColor,
                        fontWeight = WOODEN_BTN.fontWeight,
                        fontSize = 11,
                        borderWidth = 0,
                        marginTop = 4,
                        onClick = function(self)
                            UIScenes.PlayUIClick()
                            if fromPause then
                                GameScene.ShowPauseMenu()
                            else
                                GameScene.HideTutorial()
                            end
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(tutorialUI_)

    -- 标记已看过教程
    if not tutorialSeen_ then
        tutorialSeen_ = true
        clientCloud:Set(TUTORIAL_CLOUD_KEY, "1", {
            onComplete = function(success)
                print("[GameScene] Tutorial seen flag saved: " .. tostring(success))
            end,
        })
    end
end

function GameScene.HideTutorial()
    tutorialUI_ = nil
    gameState_ = STATE_PLAYING
    UI.SetRoot(hudUI_)
end

function GameScene.ShowPauseMenu()
    -- 构建按钮列表
    local buttons = {}
    buttons[#buttons + 1] = UI.Button {
        text = "返回游戏",
        width = "80%", maxWidth = 150,
        height = 72,
        backgroundImage = WOODEN_BTN.image,
        backgroundFit = WOODEN_BTN.fit,
        backgroundSlice = WOODEN_BTN.slice,
        backgroundColor = WOODEN_BTN.bgColor,
        boxShadow = WOODEN_BTN.shadow,
        fontColor = WOODEN_BTN.textColor,
        fontWeight = WOODEN_BTN.fontWeight,
        fontSize = 11,
        borderWidth = 0,
        onClick = function(self)
            UIScenes.PlayUIClick()
            GameScene.Resume()
        end,
    }
    buttons[#buttons + 1] = UI.Button {
        text = "帮助",
        width = "80%", maxWidth = 150,
        height = 72,
        backgroundImage = WOODEN_BTN.image,
        backgroundFit = WOODEN_BTN.fit,
        backgroundSlice = WOODEN_BTN.slice,
        backgroundColor = WOODEN_BTN.bgColor,
        boxShadow = WOODEN_BTN.shadow,
        fontColor = WOODEN_BTN.textColor,
        fontWeight = WOODEN_BTN.fontWeight,
        fontSize = 11,
        borderWidth = 0,
        onClick = function(self)
            UIScenes.PlayUIClick()
            GameScene.ShowTutorial(true)  -- fromPause=true
        end,
    }
    buttons[#buttons + 1] = UI.Button {
        text = "重置关卡",
        width = "80%", maxWidth = 150,
        height = 72,
        backgroundImage = WOODEN_BTN.image,
        backgroundFit = WOODEN_BTN.fit,
        backgroundSlice = WOODEN_BTN.slice,
        backgroundColor = WOODEN_BTN.bgColor,
        boxShadow = WOODEN_BTN.shadow,
        fontColor = WOODEN_BTN.textColor,
        fontWeight = WOODEN_BTN.fontWeight,
        fontSize = 11,
        borderWidth = 0,
        onClick = function(self)
            UIScenes.PlayUIClick()
            GameScene.HidePauseMenu()
            GameScene.Exit()
            GameScene.Enter({ level = currentLevel_ })
        end,
    }
    if fromEditor_ then
        buttons[#buttons + 1] = UI.Button {
            text = "返回编辑器",
            width = "80%", maxWidth = 150,
            height = 72,
            backgroundImage = WOODEN_BTN.image,
            backgroundFit = WOODEN_BTN.fit,
            backgroundSlice = WOODEN_BTN.slice,
            backgroundColor = WOODEN_BTN.bgColor,
            boxShadow = WOODEN_BTN.shadow,
            fontColor = WOODEN_BTN.textColor,
            fontWeight = WOODEN_BTN.fontWeight,
            fontSize = 11,
            borderWidth = 0,
            onClick = function(self)
                UIScenes.PlayUIClick()
                GameScene.HidePauseMenu()
                SceneManager.SwitchTo(SceneManager.SCENE_EDITOR, { fromTest = true })
            end,
        }
    end
    buttons[#buttons + 1] = UI.Button {
        text = "返回主菜单",
        width = "80%", maxWidth = 150,
        height = 72,
        backgroundImage = WOODEN_BTN.image,
        backgroundFit = WOODEN_BTN.fit,
        backgroundSlice = WOODEN_BTN.slice,
        backgroundColor = WOODEN_BTN.bgColor,
        boxShadow = WOODEN_BTN.shadow,
        fontColor = WOODEN_BTN.textColor,
        fontWeight = WOODEN_BTN.fontWeight,
        fontSize = 11,
        borderWidth = 0,
        onClick = function(self)
            UIScenes.PlayUIClick()
            GameScene.HidePauseMenu()
            SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
        end,
    }

    -- 音效设置按钮
    buttons[#buttons + 1] = UI.Button {
        text = "音效设置",
        width = "80%", maxWidth = 150,
        height = 72,
        backgroundImage = WOODEN_BTN.image,
        backgroundFit = WOODEN_BTN.fit,
        backgroundSlice = WOODEN_BTN.slice,
        backgroundColor = WOODEN_BTN.bgColor,
        boxShadow = WOODEN_BTN.shadow,
        fontColor = WOODEN_BTN.textColor,
        fontWeight = WOODEN_BTN.fontWeight,
        fontSize = 11,
        borderWidth = 0,
        onClick = function(self)
            UIScenes.PlayUIClick()
            GameScene.ShowAudioSettingsPanel()
        end,
    }
    -- 镜头设置按钮
    buttons[#buttons + 1] = UI.Button {
        text = "镜头设置",
        width = "80%", maxWidth = 150,
        height = 72,
        backgroundImage = WOODEN_BTN.image,
        backgroundFit = WOODEN_BTN.fit,
        backgroundSlice = WOODEN_BTN.slice,
        backgroundColor = WOODEN_BTN.bgColor,
        boxShadow = WOODEN_BTN.shadow,
        fontColor = WOODEN_BTN.textColor,
        fontWeight = WOODEN_BTN.fontWeight,
        fontSize = 11,
        borderWidth = 0,
        onClick = function(self)
            UIScenes.PlayUIClick()
            GameScene.ShowCameraSettingsPanel()
        end,
    }

    -- 合并 children: 标题 + 所有按钮
    local panelChildren = {}
    panelChildren[#panelChildren + 1] = UI.Label {
        text = "暂停",
        fontSize = 22,
        fontColor = { 255, 255, 255, 255 },
        marginBottom = 2,
    }
    for i = 1, #buttons do
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
                maxHeight = "90%",
                padding = 16,
                gap = 8,
                alignItems = "center",
                backgroundColor = { 35, 40, 58, 245 },
                borderRadius = 14,
                borderWidth = 2,
                borderColor = { 80, 140, 255, 100 },
                overflow = "scroll",
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

--- 音效设置子面板
function GameScene.ShowAudioSettingsPanel()
    local audioUI = UI.Panel {
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
                gap = 10,
                alignItems = "center",
                backgroundColor = { 35, 40, 58, 245 },
                borderRadius = 14,
                borderWidth = 2,
                borderColor = { 80, 140, 255, 100 },
                children = {
                    UI.Label {
                        text = "音效设置",
                        fontSize = 18,
                        fontColor = { 255, 255, 255, 255 },
                        marginBottom = 4,
                    },
                    UI.Panel {
                        width = "100%",
                        gap = 8,
                        padding = 10,
                        backgroundColor = { 25, 28, 40, 200 },
                        borderRadius = 8,
                        children = {
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
                                        onChange = function(self, val) BGM.SetVolume(val / 100) end,
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
                    },
                    UI.Button {
                        text = "返回",
                        width = "80%", maxWidth = 150,
                        height = 72,
                        backgroundImage = WOODEN_BTN.image,
                        backgroundFit = WOODEN_BTN.fit,
                        backgroundSlice = WOODEN_BTN.slice,
                        backgroundColor = WOODEN_BTN.bgColor,
                        boxShadow = WOODEN_BTN.shadow,
                        fontColor = WOODEN_BTN.textColor,
                        fontWeight = WOODEN_BTN.fontWeight,
                        fontSize = 11,
                        borderWidth = 0,
                        onClick = function(self)
                            UIScenes.PlayUIClick()
                            GameScene.ShowPauseMenu()
                        end,
                    },
                }
            }
        }
    }
    UI.SetRoot(audioUI)
end

--- 镜头设置子面板
function GameScene.ShowCameraSettingsPanel()
    local zoomValLabel = UI.Label {
        text = string.format("%.0f%%", Config.Settings.CameraZoom * 100),
        fontSize = 10, fontColor = { 100, 220, 200, 255 }, width = 36, textAlign = "right",
    }
    local offsetXValLabel = UI.Label {
        text = string.format("%.1f", Config.Settings.CameraOffsetX),
        fontSize = 10, fontColor = { 100, 220, 200, 255 }, width = 36, textAlign = "right",
    }
    local offsetYValLabel = UI.Label {
        text = string.format("%.1f", Config.Settings.CameraOffsetY),
        fontSize = 10, fontColor = { 100, 220, 200, 255 }, width = 36, textAlign = "right",
    }

    local cameraUI = UI.Panel {
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
                gap = 10,
                alignItems = "center",
                backgroundColor = { 35, 40, 58, 245 },
                borderRadius = 14,
                borderWidth = 2,
                borderColor = { 80, 140, 255, 100 },
                children = {
                    UI.Label {
                        text = "镜头设置",
                        fontSize = 18,
                        fontColor = { 255, 255, 255, 255 },
                        marginBottom = 4,
                    },
                    UI.Panel {
                        width = "100%",
                        gap = 8,
                        padding = 10,
                        backgroundColor = { 25, 28, 40, 200 },
                        borderRadius = 8,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 6,
                                children = {
                                    UI.Label { text = "大小", fontSize = 11, fontColor = { 160, 170, 190, 200 }, width = 32 },
                                    UI.Slider {
                                        value = Config.Settings.CameraZoom * 100,
                                        min = 50, max = 200,
                                        flexGrow = 1,
                                        onChange = function(self, val)
                                            Config.Settings.CameraZoom = val / 100
                                            zoomValLabel:SetText(string.format("%.0f%%", val))
                                        end,
                                    },
                                    zoomValLabel,
                                }
                            },
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 6,
                                children = {
                                    UI.Label { text = "水平", fontSize = 11, fontColor = { 160, 170, 190, 200 }, width = 32 },
                                    UI.Slider {
                                        value = (Config.Settings.CameraOffsetX + 5) * 10,
                                        min = 0, max = 100,
                                        flexGrow = 1,
                                        onChange = function(self, val)
                                            Config.Settings.CameraOffsetX = val / 10 - 5
                                            offsetXValLabel:SetText(string.format("%.1f", val / 10 - 5))
                                        end,
                                    },
                                    offsetXValLabel,
                                }
                            },
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 6,
                                children = {
                                    UI.Label { text = "垂直", fontSize = 11, fontColor = { 160, 170, 190, 200 }, width = 32 },
                                    UI.Slider {
                                        value = (Config.Settings.CameraOffsetY + 5) * 10,
                                        min = 0, max = 100,
                                        flexGrow = 1,
                                        onChange = function(self, val)
                                            Config.Settings.CameraOffsetY = val / 10 - 5
                                            offsetYValLabel:SetText(string.format("%.1f", val / 10 - 5))
                                        end,
                                    },
                                    offsetYValLabel,
                                }
                            },
                        }
                    },
                    UI.Button {
                        text = "返回",
                        width = "80%", maxWidth = 150,
                        height = 72,
                        backgroundImage = WOODEN_BTN.image,
                        backgroundFit = WOODEN_BTN.fit,
                        backgroundSlice = WOODEN_BTN.slice,
                        backgroundColor = WOODEN_BTN.bgColor,
                        boxShadow = WOODEN_BTN.shadow,
                        fontColor = WOODEN_BTN.textColor,
                        fontWeight = WOODEN_BTN.fontWeight,
                        fontSize = 11,
                        borderWidth = 0,
                        onClick = function(self)
                            UIScenes.PlayUIClick()
                            GameScene.ShowPauseMenu()
                        end,
                    },
                }
            }
        }
    }
    UI.SetRoot(cameraUI)
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

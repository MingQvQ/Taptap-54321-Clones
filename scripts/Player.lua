-- ============================================================================
-- Player.lua - 玩家/克隆体控制器
-- ============================================================================
-- 录制模式（仅玩家）：
--   开局立即启动固定 5 秒录制，只录制 3 种输入事件（无坐标）：
--     1) left_start / left_end  — A 键按下/抬起时间
--     2) right_start / right_end — D 键按下/抬起时间
--     3) jump — 空格按下的瞬间时间点
--   5 秒到立即停止录制，后续操作不再记录。
--
-- 回放模式（仅克隆体）：
--   拿到玩家录制完成的事件序列，循环播放（每 5 秒为一个周期）。
--   根据事件重建输入状态 → 用相同物理逻辑驱动。
--
-- 可变重力：
--   上升时 gravityScale = Config.GravityScaleRising（轻盈）
--   下降时 gravityScale = Config.GravityScaleFalling（快速落地）
-- ============================================================================

local Config = require("Config")

-- Coyote Time 配置
local COYOTE_GRACE_TIME = 0.1

local Player = {}
Player.__index = Player

--- 创建玩家/克隆体
---@param scene userdata
---@param spawnX number
---@param spawnY number
---@param colorIndex number
---@param isPlayer boolean
---@return table
function Player.Create(scene, spawnX, spawnY, colorIndex, isPlayer)
    local self = setmetatable({}, Player)

    self.colorIndex = colorIndex or 1
    self.isPlayer = isPlayer or false
    self.isAlive = true
    self.reachedGoal = false
    self.visible = true
    self.spawnX = spawnX
    self.spawnY = spawnY

    -- 创建节点
    self.node = scene:CreateChild(isPlayer and "Player" or ("Clone_" .. colorIndex))
    self.node:SetPosition2D(spawnX, spawnY)

    -- 刚体 - 所有角色都是动态物理体
    self.body = self.node:CreateComponent("RigidBody2D")
    self.body.bodyType = BT_DYNAMIC
    self.body.fixedRotation = true
    self.body.linearDamping = 0.0
    self.body.angularDamping = 0.0
    self.body.gravityScale = Config.GravityScaleFalling  -- 初始下落状态

    -- 主碰撞体（矩形，防止蹭边缘卡上去）
    local bodyShape = self.node:CreateComponent("CollisionBox2D")
    bodyShape:SetSize(Config.PlayerRadius * 1.6, Config.PlayerRadius * 2.0)
    bodyShape:SetCenter(0, 0)
    bodyShape.density = 1.0
    bodyShape.friction = 0.0
    bodyShape.restitution = 0.0
    bodyShape.categoryBits = 2
    bodyShape.maskBits = 0xFFFF

    -- 脚底传感器（检测平台 category=1 和其他角色 category=2）
    local footSensor = self.node:CreateComponent("CollisionCircle2D")
    footSensor.radius = Config.PlayerRadius * 0.6
    footSensor.center = Vector2(0, -Config.PlayerRadius * 0.9)
    footSensor.trigger = true
    footSensor.categoryBits = 4
    footSensor.maskBits = 3  -- 1(平台) | 2(角色) = 3

    -- 地面检测
    self.onGround = false
    self.groundContactCount = 0

    -- Coyote Time + Jump Buffer
    self.coyoteTimer = 0
    self.jumpBufferTimer = 0
    self.hasJumped = false

    -- ========== 事件录制系统（仅玩家） ==========
    self.isRecording = isPlayer        -- 玩家开局即录制
    self.recordTime = 0                -- 当前录制时间（0 → RecordDuration）
    self.recordingDone = false         -- 录制是否结束
    self.events = {}                   -- 事件列表 { {time=, type=}, ... }
    -- 当前输入状态跟踪（用于检测按下/抬起边沿）
    self.prevLeft = false
    self.prevRight = false

    -- ========== 事件回放系统（仅克隆体） ==========
    self.playbackEvents = nil          -- 录制完成后的事件序列（引用）
    self.playbackTime = 0              -- 当前回放周期内时间
    self.playbackEventIdx = 1          -- 下一个待触发的事件索引
    -- 回放重建的输入状态
    self.pb_leftHeld = false
    self.pb_rightHeld = false
    self.pb_jumpThisFrame = false

    return self
end

-- ============================================================================
-- 地面碰撞
-- ============================================================================

function Player:OnContactBegin(otherNode)
    if not self.isAlive then return end
    local name = otherNode.name
    -- 平台、地面、其他角色（猪踩猪）都算有效地面
    if name == "Platform" or name == "Ground"
        or name == "Player" or string.find(name, "Clone_", 1, true) then
        self.groundContactCount = self.groundContactCount + 1
        self.onGround = true
    end
end

function Player:OnContactEnd(otherNode)
    if not self.isAlive then return end
    local name = otherNode.name
    if name == "Platform" or name == "Ground"
        or name == "Player" or string.find(name, "Clone_", 1, true) then
        self.groundContactCount = self.groundContactCount - 1
        if self.groundContactCount <= 0 then
            self.groundContactCount = 0
            self.onGround = false
        end
    end
end

-- ============================================================================
-- 可变重力（每帧更新）
-- ============================================================================

function Player:UpdateGravityScale()
    if not self.body or not self.isAlive or self.reachedGoal then return end
    local vy = self.body.linearVelocity.y
    if vy > 0.1 then
        -- 上升
        self.body.gravityScale = Config.GravityScaleRising
    else
        -- 下降或静止
        self.body.gravityScale = Config.GravityScaleFalling
    end
end

-- ============================================================================
-- 核心移动+跳跃逻辑（Coyote Time + Jump Buffer）
-- ============================================================================

function Player:ApplyInput(dt, moveX, jumpPressed)
    if not self.isAlive or self.reachedGoal then return end

    -- 1. 土狼时间
    if self.onGround then
        self.coyoteTimer = COYOTE_GRACE_TIME
        self.hasJumped = false
    else
        if self.coyoteTimer > 0 then
            self.coyoteTimer = self.coyoteTimer - dt
        end
    end

    -- 2. 输入缓冲
    if jumpPressed then
        self.jumpBufferTimer = COYOTE_GRACE_TIME
    else
        if self.jumpBufferTimer > 0 then
            self.jumpBufferTimer = self.jumpBufferTimer - dt
        end
    end

    -- 3. 跳跃判定
    local canJump = self.onGround or (self.coyoteTimer > 0 and not self.hasJumped)
    local wantJump = jumpPressed or self.jumpBufferTimer > 0

    local currentVel = self.body.linearVelocity
    local desiredVelX = moveX * Config.PlayerSpeed

    if canJump and wantJump then
        self.body.linearVelocity = Vector2(desiredVelX, Config.PlayerJumpSpeed)
        self.body.awake = true
        self.coyoteTimer = 0
        self.jumpBufferTimer = 0
        self.hasJumped = true
    else
        self.body.linearVelocity = Vector2(desiredVelX, currentVel.y)
    end

    -- 4. 可变重力
    self:UpdateGravityScale()
end

-- ============================================================================
-- 玩家更新：录制事件 + 驱动物理
-- ============================================================================

--- 玩家每帧调用
---@param dt number
---@param leftHeld boolean  A键是否按住
---@param rightHeld boolean D键是否按住
---@param jumpPressed boolean  空格是否刚按下（GetKeyPress）
function Player:UpdateInput(dt, leftHeld, rightHeld, jumpPressed)
    if not self.isAlive or self.reachedGoal then return end

    -- === 录制逻辑 ===
    if self.isRecording and not self.recordingDone then
        self.recordTime = self.recordTime + dt

        -- 检测按键边沿 → 生成事件
        -- Left
        if leftHeld and not self.prevLeft then
            table.insert(self.events, { time = self.recordTime, type = "left_start" })
        elseif not leftHeld and self.prevLeft then
            table.insert(self.events, { time = self.recordTime, type = "left_end" })
        end
        -- Right
        if rightHeld and not self.prevRight then
            table.insert(self.events, { time = self.recordTime, type = "right_start" })
        elseif not rightHeld and self.prevRight then
            table.insert(self.events, { time = self.recordTime, type = "right_end" })
        end
        -- Jump（瞬间触发）
        if jumpPressed then
            table.insert(self.events, { time = self.recordTime, type = "jump" })
        end

        self.prevLeft = leftHeld
        self.prevRight = rightHeld

        -- 5 秒到，终止录制
        if self.recordTime >= Config.RecordDuration then
            self.recordingDone = true
            self.isRecording = false
            -- 如果录制结束时有按键仍按住，补一个 end 事件在终止点
            if self.prevLeft then
                table.insert(self.events, { time = Config.RecordDuration, type = "left_end" })
            end
            if self.prevRight then
                table.insert(self.events, { time = Config.RecordDuration, type = "right_end" })
            end
            print("[Player] Recording done. Events: " .. #self.events .. " Duration: " .. Config.RecordDuration .. "s")
        end
    end

    -- === 驱动物理（玩家始终响应操控） ===
    local moveX = 0
    if leftHeld then moveX = moveX - 1 end
    if rightHeld then moveX = moveX + 1 end

    self:ApplyInput(dt, moveX, jumpPressed)
end

-- ============================================================================
-- 克隆体更新：从事件序列循环回放
-- ============================================================================

--- 克隆体每帧调用
---@param dt number
function Player:UpdatePlayback(dt)
    if not self.isAlive or self.reachedGoal then return end
    if not self.playbackEvents then return end

    local duration = Config.RecordDuration
    local events = self.playbackEvents
    local numEvents = #events

    -- 推进时间
    self.playbackTime = self.playbackTime + dt

    -- 循环：超出录制时长则重置
    if self.playbackTime >= duration then
        self.playbackTime = self.playbackTime - duration
        -- 重置输入状态和事件索引
        self.playbackEventIdx = 1
        self.pb_leftHeld = false
        self.pb_rightHeld = false
    end

    -- 触发当前时间之前的所有事件
    self.pb_jumpThisFrame = false
    while self.playbackEventIdx <= numEvents do
        local ev = events[self.playbackEventIdx]
        if ev.time <= self.playbackTime then
            -- 处理事件
            if ev.type == "left_start" then
                self.pb_leftHeld = true
            elseif ev.type == "left_end" then
                self.pb_leftHeld = false
            elseif ev.type == "right_start" then
                self.pb_rightHeld = true
            elseif ev.type == "right_end" then
                self.pb_rightHeld = false
            elseif ev.type == "jump" then
                self.pb_jumpThisFrame = true
            end
            self.playbackEventIdx = self.playbackEventIdx + 1
        else
            break
        end
    end

    -- 从重建的输入状态驱动物理
    local moveX = 0
    if self.pb_leftHeld then moveX = moveX - 1 end
    if self.pb_rightHeld then moveX = moveX + 1 end

    self:ApplyInput(dt, moveX, self.pb_jumpThisFrame)
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 设置回放数据（录制完成后的事件序列引用）
function Player:SetPlaybackData(data)
    self.playbackEvents = data
    self.playbackTime = 0
    self.playbackEventIdx = 1
    self.pb_leftHeld = false
    self.pb_rightHeld = false
    self.pb_jumpThisFrame = false
end

--- 获取录制的事件序列
function Player:GetRecordedEvents()
    return self.events
end

--- 录制是否完成
function Player:IsRecordingDone()
    return self.recordingDone
end

--- 获取当前录制进度（0~1）
function Player:GetRecordProgress()
    if self.recordingDone then return 1.0 end
    return math.min(self.recordTime / Config.RecordDuration, 1.0)
end

--- 获取位置
function Player:GetPosition()
    if self.node then return self.node.position2D end
    return Vector2(0, 0)
end

--- 杀死角色（死亡后失去控制、禁用碰撞）
function Player:Kill()
    if not self.isAlive then return end
    self.isAlive = false
    self.deathTime = 0  -- 死亡动画计时器
    if self.body then
        self.body.linearVelocity = Vector2(0, 0)
        self.body.gravityScale = 0
        self.body.enabled = false  -- 禁用物理碰撞
    end
end

--- 到达终点
function Player:SetReachedGoal()
    self.reachedGoal = true
    if self.body then
        self.body.linearVelocity = Vector2(0, 0)
        self.body.gravityScale = 0
        self.body.enabled = false
    end
    self.visible = false
end

--- 销毁
function Player:Destroy()
    if self.node then
        self.node:Remove()
        self.node = nil
    end
    self.body = nil
end

return Player

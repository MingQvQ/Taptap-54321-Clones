-- ============================================================================
-- CloneSystem.lua - 角色生成系统
-- 管理环形计时器、54321数字递减、玩家和克隆体生成
-- 第一次倒计时（快）生成玩家，后续倒计时（慢）生成克隆体
-- ============================================================================

local Config = require("Config")
local Player = require("Player")

local CloneSystem = {}
CloneSystem.__index = CloneSystem

--- 创建克隆系统实例
---@param scene userdata
---@param spawnX number
---@param spawnY number
---@return table
function CloneSystem.Create(scene, spawnX, spawnY)
    local self = setmetatable({}, CloneSystem)

    self.scene = scene
    self.spawnX = spawnX
    self.spawnY = spawnY

    -- 计时器状态
    self.timerProgress = 0        -- 0~1 环形进度
    self.currentNumber = Config.CloneCount  -- 当前显示数字（N->...->1->0）
    self.spawnCount = 0           -- 已生成角色数量（0=还没生成玩家）
    self.isActive = true          -- 计时器是否激活

    -- 主玩家引用（第一次生成时创建）
    self.mainPlayer = nil

    -- 克隆体列表
    self.clones = {}              -- Player 实例数组

    return self
end

--- 获取当前倒计时间隔（第一次快，后续慢）
function CloneSystem:GetCurrentInterval()
    if self.spawnCount == 0 then
        return Config.FirstSpawnInterval
    else
        return Config.CloneInterval
    end
end

--- 更新计时器和角色生成
---@param dt number
function CloneSystem:Update(dt)
    if not self.isActive then return end
    if self.currentNumber <= 0 then
        self.isActive = false
        return
    end

    -- 更新环形进度（根据当前间隔）
    local interval = self:GetCurrentInterval()
    self.timerProgress = self.timerProgress + dt / interval

    if self.timerProgress >= 1.0 then
        self.timerProgress = 0
        -- 生成角色
        self:SpawnNext()
        -- 数字递减
        self.currentNumber = self.currentNumber - 1
        if self.currentNumber <= 0 then
            self.isActive = false
        end
    end
end

--- 生成下一个角色（第一个是玩家，后续是克隆体）
function CloneSystem:SpawnNext()
    self.spawnCount = self.spawnCount + 1

    if self.spawnCount == 1 then
        -- 第一个：生成玩家
        self.mainPlayer = Player.Create(
            self.scene,
            self.spawnX,
            self.spawnY,
            1,    -- 颜色索引（玩家蓝色）
            true  -- 是玩家
        )
        print("[CloneSystem] Spawned PLAYER (first character)")
    else
        -- 后续：生成克隆体
        if not self.mainPlayer then return end

        local colorIndex = self.spawnCount  -- 2,3,4,5
        local clone = Player.Create(
            self.scene,
            self.spawnX,
            self.spawnY,
            colorIndex,
            false
        )

        -- 引用主玩家的录制事件序列（录制完成后为完整5秒数据，循环播放）
        clone:SetPlaybackData(self.mainPlayer:GetRecordedEvents())

        table.insert(self.clones, clone)
        print("[CloneSystem] Spawned clone #" .. (#self.clones) .. " (color " .. colorIndex .. ")")
    end
end

--- 更新所有克隆体
---@param dt number
function CloneSystem:UpdateClones(dt)
    for _, clone in ipairs(self.clones) do
        if clone.isAlive and not clone.reachedGoal then
            clone:UpdatePlayback(dt)
        end
    end
end

--- 获取主玩家
function CloneSystem:GetMainPlayer()
    return self.mainPlayer
end

--- 获取所有克隆体
function CloneSystem:GetClones()
    return self.clones
end

--- 获取当前计时器显示数字
function CloneSystem:GetCurrentNumber()
    return self.currentNumber
end

--- 获取计时器进度（0~1）
function CloneSystem:GetTimerProgress()
    return self.timerProgress
end

--- 检查计时器是否激活
function CloneSystem:IsActive()
    return self.isActive
end

--- 检查玩家是否已生成
function CloneSystem:IsPlayerSpawned()
    return self.mainPlayer ~= nil
end

--- 获取所有存活角色（含主玩家）
function CloneSystem:GetAllAliveCharacters()
    local result = {}
    if self.mainPlayer and self.mainPlayer.isAlive then
        table.insert(result, self.mainPlayer)
    end
    for _, clone in ipairs(self.clones) do
        if clone.isAlive then
            table.insert(result, clone)
        end
    end
    return result
end

--- 统计已到达终点的角色数量
---@return number
function CloneSystem:CountReachedGoal()
    local count = 0
    if self.mainPlayer and self.mainPlayer.reachedGoal then
        count = count + 1
    end
    for _, clone in ipairs(self.clones) do
        if clone.reachedGoal then
            count = count + 1
        end
    end
    return count
end

--- 检查是否全部到达终点（旧接口，兼容保留）
function CloneSystem:AllReachedGoal()
    -- 玩家还没生成，不算通关
    if not self.mainPlayer then return false end
    if not self.mainPlayer.reachedGoal then
        return false
    end
    -- 如果计时器还在运行，还没生成完所有角色
    if self.isActive then
        return false
    end
    for _, clone in ipairs(self.clones) do
        if not clone.reachedGoal then
            return false
        end
    end
    return true
end

--- 检查是否有角色死亡
function CloneSystem:AnyDead()
    if self.mainPlayer and not self.mainPlayer.isAlive then
        return true
    end
    for _, clone in ipairs(self.clones) do
        if not clone.isAlive then
            return true
        end
    end
    return false
end

--- 获取仍可能到达终点的角色数（已到达 + 存活 + 未生成）
function CloneSystem:CountPotentialSuccess()
    local count = 0
    -- 已到达终点的
    count = count + self:CountReachedGoal()
    -- 存活但还没到终点的
    if self.mainPlayer and self.mainPlayer.isAlive and not self.mainPlayer.reachedGoal then
        count = count + 1
    end
    for _, clone in ipairs(self.clones) do
        if clone.isAlive and not clone.reachedGoal then
            count = count + 1
        end
    end
    -- 还没生成的
    count = count + self.currentNumber
    return count
end

--- 销毁所有角色
function CloneSystem:Destroy()
    for _, clone in ipairs(self.clones) do
        clone:Destroy()
    end
    self.clones = {}
    if self.mainPlayer then
        self.mainPlayer:Destroy()
        self.mainPlayer = nil
    end
end

return CloneSystem

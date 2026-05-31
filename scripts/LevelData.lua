-- ============================================================================
-- LevelData.lua - 关卡数据加载器
-- 支持从编辑器云存储(clientCloud)加载关卡，以及从静态 JSON 文件加载
-- 编辑器关卡(level01/02/03)优先映射到前3个关卡槽位
-- ============================================================================

local TilemapData = require("LevelEditor.TilemapData")
local EditorTestBridge = require("LevelEditor.EditorTestBridge")

local LevelData = {}

-- 关卡列表（运行时加载）
LevelData.Levels = {}

-- 云端关卡是否已加载完成
LevelData.cloudReady = false

-- ============================================================================
-- 编辑器云端关卡映射配置
-- key: clientCloud 存储键名
-- index: 对应的游戏关卡槽位（1开始）
-- name: 显示名称
-- ============================================================================

local CLOUD_LEVEL_MAP = {
    { key = "lvled_level01", index = 1, name = "Level 01" },
    { key = "lvled_level02", index = 2, name = "Level 02" },
    { key = "lvled_level03", index = 3, name = "Level 03" },
    { key = "lvled_level04", index = 4, name = "Level 04" },
    { key = "lvled_level05", index = 5, name = "Level 05" },
}

local EDITOR_SAVE_DIR = "LevelEditor"

-- ============================================================================
-- 内部工具函数
-- ============================================================================

--- 将编辑器瓦片地图数据转换为游戏关卡格式
---@param tilemapRawData table TilemapData.Serialize() 产出的原始数据
---@param levelName string 关卡显示名称
---@return table|nil levelData 兼容 GameScene.ApplyLevelData 的格式
local function ConvertTilemapToLevel(tilemapRawData, levelName)
    -- Deserialize 到 TilemapData 单例（临时覆盖）
    TilemapData.Deserialize(tilemapRawData)
    -- 验证地图合法性（需要出生点+终点）
    local valid, errMsg = EditorTestBridge.Validate()
    if not valid then
        print("[LevelData] Tilemap validation failed: " .. tostring(errMsg))
        return nil
    end
    -- 转换为游戏格式
    local levelData = EditorTestBridge.ConvertToLevelData()
    levelData.name = levelName or levelData.name
    return levelData
end

--- 从静态 JSON 文件加载单个关卡
---@param index number 关卡索引（1开始）
---@return table|nil
local function LoadLevelFromJSON(index)
    local path = "Levels/level_" .. index .. ".json"
    if not cache:Exists(path) then
        return nil
    end
    local file = cache:GetFile(path)
    if file == nil then
        return nil
    end
    local content = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        log:Write(LOG_ERROR, "[LevelData] Failed to parse " .. path .. ": " .. tostring(data))
        return nil
    end
    return data
end

--- 尝试从本地文件缓存加载编辑器关卡（同步，即时可用）
---@param filename string 文件名（不含扩展名），如 "level01"
---@return table|nil 原始瓦片地图数据
local function LoadEditorLevelFromLocal(filename)
    local path = EDITOR_SAVE_DIR .. "/" .. filename .. ".json"
    if not fileSystem:FileExists(path) then
        return nil
    end
    local file = File(path, FILE_READ)
    if not file:IsOpen() then
        return nil
    end
    local content = file:ReadString()
    file:Close()
    if content == "" then return nil end
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        print("[LevelData] Local parse error for " .. filename .. ": " .. tostring(data))
        return nil
    end
    return data
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 初始化：加载所有关卡
--- 优先级：编辑器关卡(本地缓存) > 静态 JSON > 云端异步更新
function LevelData.Init()
    LevelData.Levels = {}
    LevelData.cloudReady = false

    -- 第一步：从本地文件缓存同步加载编辑器关卡（填充前3关）
    local localLoaded = 0
    for _, mapping in ipairs(CLOUD_LEVEL_MAP) do
        local filename = mapping.key:gsub("^lvled_", "")
        local tilemapData = LoadEditorLevelFromLocal(filename)
        if tilemapData then
            local levelData = ConvertTilemapToLevel(tilemapData, mapping.name)
            if levelData then
                LevelData.Levels[mapping.index] = levelData
                localLoaded = localLoaded + 1
                print("[LevelData] Slot " .. mapping.index .. " loaded from local: " .. filename)
            end
        end
    end

    -- 第二步：对于没有编辑器数据的槽位，用静态 JSON 填充
    local index = 1
    while true do
        if LevelData.Levels[index] == nil then
            local data = LoadLevelFromJSON(index)
            if data == nil then
                -- 如果之前的槽位有数据但当前没有，继续查找后面的
                if index <= #CLOUD_LEVEL_MAP then
                    index = index + 1
                    goto continue
                end
                break
            end
            LevelData.Levels[index] = data
        end
        index = index + 1
        ::continue::
    end

    -- 确保 Levels 是连续的序列（去除中间空洞）
    local compacted = {}
    for i = 1, #LevelData.Levels + 3 do
        if LevelData.Levels[i] then
            table.insert(compacted, LevelData.Levels[i])
        end
    end
    LevelData.Levels = compacted

    print("[LevelData] Initial load: " .. #LevelData.Levels .. " levels (" .. localLoaded .. " from editor cache)")

    -- 第三步：异步从云端加载最新编辑器关卡（覆盖本地缓存版本）
    LevelData.LoadCloudLevels()
end

--- 从 clientCloud 异步加载编辑器关卡，更新到对应槽位
function LevelData.LoadCloudLevels()
    -- 使用 BatchGet 一次性获取所有编辑器关卡
    local batch = clientCloud:BatchGet()
    for _, mapping in ipairs(CLOUD_LEVEL_MAP) do
        batch:Key(mapping.key)
    end
    batch:Fetch({
        ok = function(values, iscores)
            local updated = 0
            for _, mapping in ipairs(CLOUD_LEVEL_MAP) do
                local tilemapData = values[mapping.key]
                if tilemapData then
                    local levelData = ConvertTilemapToLevel(tilemapData, mapping.name)
                    if levelData then
                        LevelData.Levels[mapping.index] = levelData
                        updated = updated + 1
                    end
                end
            end
            LevelData.cloudReady = true

            -- 确保至少有云端关卡数量的槽位
            if updated > 0 then
                -- 重新压缩确保序列连续
                local maxIdx = 0
                for i = 1, 100 do
                    if LevelData.Levels[i] then maxIdx = i end
                end
                -- 填补空洞（如果有的话）
                for i = 1, maxIdx do
                    if LevelData.Levels[i] == nil then
                        local fallback = LoadLevelFromJSON(i)
                        if fallback then
                            LevelData.Levels[i] = fallback
                        end
                    end
                end
            end

            print("[LevelData] Cloud update: " .. updated .. " levels refreshed, total: " .. #LevelData.Levels)
        end,
        error = function(code, reason)
            LevelData.cloudReady = true
            print("[LevelData] Cloud load error: " .. tostring(reason))
        end,
    })
end

--- 获取关卡数量
function LevelData.GetLevelCount()
    return #LevelData.Levels
end

--- 获取指定关卡数据
---@param index number 关卡索引（1开始）
---@return table|nil
function LevelData.GetLevel(index)
    return LevelData.Levels[index]
end

return LevelData

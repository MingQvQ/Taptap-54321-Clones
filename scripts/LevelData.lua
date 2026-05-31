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

--- 安全读取文件全部文本内容（兼容无 \0 终止符的纯文本文件）
--- ReadString() 读取到 \0 终止符为止，对于外部创建的 JSON 文件（无终止符）
--- 在部分平台上可能返回空字符串。改用 ReadLine() 逐行拼接保证兼容性。
---@param file any Deserializer (File / MemoryBuffer returned by cache:GetFile)
---@return string
local function ReadFileText(file)
    local lines = {}
    while not file:IsEof() do
        lines[#lines + 1] = file:ReadLine()
    end
    return table.concat(lines, "\n")
end

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

--- 硬编码关卡文件路径映射（确保打包进安装包）
local LEVEL_JSON_FILES = {
    [1] = "Levels/level01.json",
    [2] = "Levels/level02.json",
    [3] = "Levels/level03.json",
    [4] = "Levels/level04.json",
    [5] = "Levels/level05.json",
}

--- 从静态 JSON 文件加载单个关卡
---@param index number 关卡索引（1开始）
---@return table|nil
local function LoadLevelFromJSON(index)
    local path = LEVEL_JSON_FILES[index]
    if not path then
        return nil
    end
    if not cache:Exists(path) then
        print("[LevelData] File not found: " .. path)
        return nil
    end
    local file = cache:GetFile(path)
    if file == nil then
        return nil
    end
    local content = ReadFileText(file)
    file:Close()
    if content == "" then
        print("[LevelData] Empty content from: " .. path)
        return nil
    end
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
--- 直接从素材库 JSON 文件加载，不再被云端/编辑器缓存覆盖
function LevelData.Init()
    LevelData.Levels = {}
    LevelData.cloudReady = true  -- 不再依赖云端加载

    -- 从素材库 JSON 文件加载所有关卡（level01~05.json）
    for index, path in pairs(LEVEL_JSON_FILES) do
        local data = LoadLevelFromJSON(index)
        if data then
            LevelData.Levels[index] = data
            print("[LevelData] Slot " .. index .. " loaded from JSON: " .. path)
        else
            print("[LevelData] WARNING: Failed to load " .. path)
        end
    end

    print("[LevelData] Loaded " .. #LevelData.Levels .. " levels from assets")
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

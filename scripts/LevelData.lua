-- ============================================================================
-- LevelData.lua - 关卡数据加载器
-- 从 JSON 文件加载关卡数据
-- 关卡文件位于 assets/Levels/level_N.json
-- ============================================================================

local LevelData = {}

-- 关卡列表（运行时加载）
LevelData.Levels = {}

--- 从 JSON 文件加载单个关卡
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
        log:Write(LOG_ERROR, "LevelData: Failed to parse " .. path .. ": " .. tostring(data))
        return nil
    end
    return data
end

--- 初始化：加载所有关卡
function LevelData.Init()
    LevelData.Levels = {}
    local index = 1
    while true do
        local data = LoadLevelFromJSON(index)
        if data == nil then
            break
        end
        LevelData.Levels[index] = data
        index = index + 1
    end
    log:Write(LOG_INFO, "LevelData: Loaded " .. #LevelData.Levels .. " levels")
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

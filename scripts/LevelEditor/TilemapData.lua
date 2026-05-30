-- ============================================================================
-- TilemapData.lua - 瓦片地图数据模块（v2）
-- 双层架构：瓦片层（静态地图贴图） + 预制体层（带标签的游戏对象）
-- 支持自定义瓦片贴图、可调地图大小
-- ============================================================================

local TilemapData = {}

-- ============================================================================
-- 瓦片注册表（静态地图贴图）
-- 用户导入的瓦片图片，用于绘制地形
-- ============================================================================

--- 瓦片定义格式: { id, name, image, color }
--- image: 贴图路径（相对 assets/），如 "Tiles/grass.png"
--- color: 备用颜色（无贴图时的 fallback）
TilemapData.tileRegistry = {
    [0] = { id = 0, name = "空", image = nil, color = { 0, 0, 0, 0 } },
    [1] = { id = 1, name = "草地", image = nil, color = { 80, 180, 80, 255 } },
    [2] = { id = 2, name = "泥土", image = nil, color = { 140, 90, 50, 255 } },
    [3] = { id = 3, name = "石头", image = nil, color = { 120, 125, 135, 255 } },
    [4] = { id = 4, name = "木板", image = nil, color = { 160, 120, 60, 255 } },
}

--- 下一个可用瓦片 ID
TilemapData.nextTileId = 5

-- ============================================================================
-- 预制体注册表（带标签的游戏对象）
-- 运行时读取标签来放置对应预制体
-- ============================================================================

--- 预制体定义格式: { id, name, tag, icon, color }
--- tag: 游戏运行时识别标签（如 "player_spawn", "spike"）
--- icon: 编辑器中显示的图标（emoji）
TilemapData.prefabRegistry = {
    [0] = { id = 0, name = "空", tag = "", icon = "", color = { 0, 0, 0, 0 } },
    [1] = { id = 1, name = "玩家出生点", tag = "player_spawn", icon = "🧍", color = { 80, 160, 255, 200 } },
    [2] = { id = 2, name = "终点", tag = "goal", icon = "🚩", color = { 255, 215, 0, 200 } },
    [3] = { id = 3, name = "尖刺", tag = "spike", icon = "🔺", color = { 220, 50, 50, 200 } },
    [4] = { id = 4, name = "金币", tag = "coin", icon = "🟡", color = { 255, 200, 0, 200 } },
    [5] = { id = 5, name = "移动平台", tag = "moving_platform", icon = "↔️", color = { 100, 180, 220, 200 } },
}

--- 下一个可用预制体 ID
TilemapData.nextPrefabId = 6

-- ============================================================================
-- 地图实例数据
-- ============================================================================

--- 网格大小（可调）
TilemapData.gridWidth = 16
TilemapData.gridHeight = 12

--- 单格像素大小（渲染用，不影响物理）
TilemapData.cellSize = 1.0

--- 瓦片层: [row][col] = tileId（0=空）
TilemapData.tileLayer = {}

--- 预制体层: [row][col] = prefabId（0=空）
TilemapData.prefabLayer = {}

-- ============================================================================
-- 瓦片注册 API
-- ============================================================================

--- 注册一个新的自定义瓦片
---@param name string 瓦片名称
---@param imagePath string|nil 贴图路径（如 "Tiles/grass.png"）
---@param color table|nil 备用颜色 {r,g,b,a}
---@return number 新瓦片 ID
function TilemapData.RegisterTile(name, imagePath, color)
    local id = TilemapData.nextTileId
    TilemapData.tileRegistry[id] = {
        id = id,
        name = name,
        image = imagePath,
        color = color or { 200, 200, 200, 255 },
    }
    TilemapData.nextTileId = id + 1
    return id
end

--- 更新已有瓦片的贴图
---@param tileId number
---@param imagePath string
function TilemapData.SetTileImage(tileId, imagePath)
    if TilemapData.tileRegistry[tileId] then
        TilemapData.tileRegistry[tileId].image = imagePath
    end
end

--- 获取瓦片信息
---@param tileId number
---@return table
function TilemapData.GetTileInfo(tileId)
    return TilemapData.tileRegistry[tileId] or TilemapData.tileRegistry[0]
end

--- 注册一个新的预制体类型
---@param name string
---@param tag string 游戏运行时标签
---@param icon string emoji 图标
---@param color table|nil
---@return number 新预制体 ID
function TilemapData.RegisterPrefab(name, tag, icon, color)
    local id = TilemapData.nextPrefabId
    TilemapData.prefabRegistry[id] = {
        id = id,
        name = name,
        tag = tag,
        icon = icon or "❓",
        color = color or { 180, 180, 180, 200 },
    }
    TilemapData.nextPrefabId = id + 1
    return id
end

--- 获取预制体信息
---@param prefabId number
---@return table
function TilemapData.GetPrefabInfo(prefabId)
    return TilemapData.prefabRegistry[prefabId] or TilemapData.prefabRegistry[0]
end

-- ============================================================================
-- 地图操作 API
-- ============================================================================

--- 初始化/重置地图（指定新大小）
---@param width? number 网格宽度（默认16）
---@param height? number 网格高度（默认12）
function TilemapData.New(width, height)
    TilemapData.gridWidth = width or 16
    TilemapData.gridHeight = height or 12
    TilemapData.tileLayer = {}
    TilemapData.prefabLayer = {}
    for row = 1, TilemapData.gridHeight do
        TilemapData.tileLayer[row] = {}
        TilemapData.prefabLayer[row] = {}
        for col = 1, TilemapData.gridWidth do
            TilemapData.tileLayer[row][col] = 0
            TilemapData.prefabLayer[row][col] = 0
        end
    end
end

--- 调整地图大小（保留已有数据）
---@param newWidth number
---@param newHeight number
function TilemapData.Resize(newWidth, newHeight)
    local oldW = TilemapData.gridWidth
    local oldH = TilemapData.gridHeight
    local oldTiles = TilemapData.tileLayer
    local oldPrefabs = TilemapData.prefabLayer

    TilemapData.gridWidth = newWidth
    TilemapData.gridHeight = newHeight
    TilemapData.tileLayer = {}
    TilemapData.prefabLayer = {}

    for row = 1, newHeight do
        TilemapData.tileLayer[row] = {}
        TilemapData.prefabLayer[row] = {}
        for col = 1, newWidth do
            if row <= oldH and col <= oldW then
                TilemapData.tileLayer[row][col] = oldTiles[row][col] or 0
                TilemapData.prefabLayer[row][col] = oldPrefabs[row][col] or 0
            else
                TilemapData.tileLayer[row][col] = 0
                TilemapData.prefabLayer[row][col] = 0
            end
        end
    end
end

--- 获取瓦片层数据
---@param row number
---@param col number
---@return number tileId
function TilemapData.GetTile(row, col)
    if row < 1 or row > TilemapData.gridHeight then return 0 end
    if col < 1 or col > TilemapData.gridWidth then return 0 end
    return TilemapData.tileLayer[row][col] or 0
end

--- 设置瓦片层数据
---@param row number
---@param col number
---@param tileId number
function TilemapData.SetTile(row, col, tileId)
    if row < 1 or row > TilemapData.gridHeight then return end
    if col < 1 or col > TilemapData.gridWidth then return end
    TilemapData.tileLayer[row][col] = tileId or 0
end

--- 获取预制体层数据
---@param row number
---@param col number
---@return number prefabId
function TilemapData.GetPrefab(row, col)
    if row < 1 or row > TilemapData.gridHeight then return 0 end
    if col < 1 or col > TilemapData.gridWidth then return 0 end
    return TilemapData.prefabLayer[row][col] or 0
end

--- 设置预制体层数据
---@param row number
---@param col number
---@param prefabId number
function TilemapData.SetPrefab(row, col, prefabId)
    if row < 1 or row > TilemapData.gridHeight then return end
    if col < 1 or col > TilemapData.gridWidth then return end
    TilemapData.prefabLayer[row][col] = prefabId or 0
end

--- 清空整张地图（保持当前大小）
function TilemapData.Clear()
    TilemapData.New(TilemapData.gridWidth, TilemapData.gridHeight)
end

-- ============================================================================
-- 序列化 / 反序列化（JSON 存储）
-- ============================================================================

--- 序列化为 JSON 可存储的 table
---@return table
function TilemapData.Serialize()
    local data = {
        version = 2,
        gridWidth = TilemapData.gridWidth,
        gridHeight = TilemapData.gridHeight,
        -- 瓦片注册表（只存自定义的，id>=1）
        tileRegistry = {},
        -- 预制体注册表
        prefabRegistry = {},
        -- 瓦片层（稀疏存储，只存非0）
        tiles = {},
        -- 预制体层（稀疏存储，只存非0）
        prefabs = {},
    }

    -- 保存瓦片注册表
    for id, info in pairs(TilemapData.tileRegistry) do
        if id >= 1 then
            data.tileRegistry[tostring(id)] = {
                name = info.name,
                image = info.image,
                color = info.color,
            }
        end
    end

    -- 保存预制体注册表
    for id, info in pairs(TilemapData.prefabRegistry) do
        if id >= 1 then
            data.prefabRegistry[tostring(id)] = {
                name = info.name,
                tag = info.tag,
                icon = info.icon,
                color = info.color,
            }
        end
    end

    -- 保存瓦片层（稀疏）
    for row = 1, TilemapData.gridHeight do
        for col = 1, TilemapData.gridWidth do
            local t = TilemapData.tileLayer[row][col]
            if t ~= 0 then
                table.insert(data.tiles, { row, col, t })
            end
        end
    end

    -- 保存预制体层（稀疏）
    for row = 1, TilemapData.gridHeight do
        for col = 1, TilemapData.gridWidth do
            local p = TilemapData.prefabLayer[row][col]
            if p ~= 0 then
                table.insert(data.prefabs, { row, col, p })
            end
        end
    end

    return data
end

--- 从 table 反序列化
---@param data table
function TilemapData.Deserialize(data)
    -- 地图大小
    TilemapData.gridWidth = data.gridWidth or 16
    TilemapData.gridHeight = data.gridHeight or 12

    -- 初始化空白网格
    TilemapData.tileLayer = {}
    TilemapData.prefabLayer = {}
    for row = 1, TilemapData.gridHeight do
        TilemapData.tileLayer[row] = {}
        TilemapData.prefabLayer[row] = {}
        for col = 1, TilemapData.gridWidth do
            TilemapData.tileLayer[row][col] = 0
            TilemapData.prefabLayer[row][col] = 0
        end
    end

    -- 恢复瓦片注册表
    if data.tileRegistry then
        for idStr, info in pairs(data.tileRegistry) do
            local id = tonumber(idStr)
            if id then
                TilemapData.tileRegistry[id] = {
                    id = id,
                    name = info.name,
                    image = info.image,
                    color = info.color or { 200, 200, 200, 255 },
                }
                if id >= TilemapData.nextTileId then
                    TilemapData.nextTileId = id + 1
                end
            end
        end
    end

    -- 恢复预制体注册表
    if data.prefabRegistry then
        for idStr, info in pairs(data.prefabRegistry) do
            local id = tonumber(idStr)
            if id then
                TilemapData.prefabRegistry[id] = {
                    id = id,
                    name = info.name,
                    tag = info.tag,
                    icon = info.icon or "❓",
                    color = info.color or { 180, 180, 180, 200 },
                }
                if id >= TilemapData.nextPrefabId then
                    TilemapData.nextPrefabId = id + 1
                end
            end
        end
    end

    -- 恢复瓦片层
    if data.tiles then
        for _, entry in ipairs(data.tiles) do
            local row, col, tileId = entry[1], entry[2], entry[3]
            if row >= 1 and row <= TilemapData.gridHeight and col >= 1 and col <= TilemapData.gridWidth then
                TilemapData.tileLayer[row][col] = tileId
            end
        end
    end

    -- 恢复预制体层
    if data.prefabs then
        for _, entry in ipairs(data.prefabs) do
            local row, col, prefabId = entry[1], entry[2], entry[3]
            if row >= 1 and row <= TilemapData.gridHeight and col >= 1 and col <= TilemapData.gridWidth then
                TilemapData.prefabLayer[row][col] = prefabId
            end
        end
    end
end

return TilemapData

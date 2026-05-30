-- ============================================================================
-- TilemapData.lua - 瓦片地图纯数据模块
-- 存储网格大小、瓦片类型定义、每格的 tileId + layer
-- 不包含任何渲染逻辑
-- ============================================================================

local TilemapData = {}

-- ============================================================================
-- 瓦片类型定义
-- ============================================================================

--- 瓦片类型枚举
TilemapData.TILE_EMPTY    = 0   -- 空
TilemapData.TILE_GROUND   = 1   -- 地面
TilemapData.TILE_PLATFORM = 2   -- 平台
TilemapData.TILE_SPIKE    = 3   -- 尖刺
TilemapData.TILE_COIN     = 4   -- 金币

--- 瓦片类型信息表（名称、颜色、图标）
TilemapData.TileTypes = {
    [0] = { id = 0, name = "空",   icon = "⬜", color = { 0, 0, 0, 0 } },
    [1] = { id = 1, name = "地面", icon = "🟫", color = { 80, 180, 80, 255 } },
    [2] = { id = 2, name = "平台", icon = "🟦", color = { 100, 160, 220, 255 } },
    [3] = { id = 3, name = "尖刺", icon = "🔺", color = { 220, 50, 50, 255 } },
    [4] = { id = 4, name = "金币", icon = "🟡", color = { 255, 215, 0, 255 } },
}

-- ============================================================================
-- 地图实例数据
-- ============================================================================

--- 当前地图的网格大小
TilemapData.gridWidth = 16
TilemapData.gridHeight = 12

--- 网格数据：二维数组 [row][col] = { tileId, layer }
--- row: 1~gridHeight（从上到下）
--- col: 1~gridWidth（从左到右）
TilemapData.cells = {}

-- ============================================================================
-- API
-- ============================================================================

--- 初始化空白地图
---@param width? number 网格宽度（默认16）
---@param height? number 网格高度（默认12）
function TilemapData.New(width, height)
    TilemapData.gridWidth = width or 16
    TilemapData.gridHeight = height or 12
    TilemapData.cells = {}
    for row = 1, TilemapData.gridHeight do
        TilemapData.cells[row] = {}
        for col = 1, TilemapData.gridWidth do
            TilemapData.cells[row][col] = { tileId = TilemapData.TILE_EMPTY, layer = 0 }
        end
    end
end

--- 获取某格的瓦片数据
---@param row number 行号（1开始，从上到下）
---@param col number 列号（1开始，从左到右）
---@return table|nil { tileId, layer }
function TilemapData.GetCell(row, col)
    if row < 1 or row > TilemapData.gridHeight then return nil end
    if col < 1 or col > TilemapData.gridWidth then return nil end
    return TilemapData.cells[row][col]
end

--- 设置某格的瓦片
---@param row number
---@param col number
---@param tileId number
---@param layer? number 图层（默认0）
function TilemapData.SetCell(row, col, tileId, layer)
    if row < 1 or row > TilemapData.gridHeight then return end
    if col < 1 or col > TilemapData.gridWidth then return end
    TilemapData.cells[row][col] = {
        tileId = tileId or TilemapData.TILE_EMPTY,
        layer = layer or 0,
    }
end

--- 清空整张地图
function TilemapData.Clear()
    TilemapData.New(TilemapData.gridWidth, TilemapData.gridHeight)
end

--- 序列化为可存储的 table（用于 JSON 导出）
---@return table
function TilemapData.Serialize()
    local data = {
        gridWidth = TilemapData.gridWidth,
        gridHeight = TilemapData.gridHeight,
        cells = {},
    }
    for row = 1, TilemapData.gridHeight do
        data.cells[row] = {}
        for col = 1, TilemapData.gridWidth do
            local cell = TilemapData.cells[row][col]
            -- 只存非空格子以节省空间
            if cell.tileId ~= TilemapData.TILE_EMPTY then
                data.cells[row][col] = { cell.tileId, cell.layer }
            end
        end
    end
    return data
end

--- 从 table 反序列化（JSON 加载后调用）
---@param data table
function TilemapData.Deserialize(data)
    TilemapData.gridWidth = data.gridWidth or 16
    TilemapData.gridHeight = data.gridHeight or 12
    TilemapData.cells = {}
    for row = 1, TilemapData.gridHeight do
        TilemapData.cells[row] = {}
        for col = 1, TilemapData.gridWidth do
            local saved = data.cells and data.cells[row] and data.cells[row][col]
            if saved then
                -- saved 格式: { tileId, layer } 或 [1]=tileId, [2]=layer
                TilemapData.cells[row][col] = {
                    tileId = saved[1] or TilemapData.TILE_EMPTY,
                    layer = saved[2] or 0,
                }
            else
                TilemapData.cells[row][col] = { tileId = TilemapData.TILE_EMPTY, layer = 0 }
            end
        end
    end
end

--- 获取瓦片类型信息
---@param tileId number
---@return table
function TilemapData.GetTileInfo(tileId)
    return TilemapData.TileTypes[tileId] or TilemapData.TileTypes[0]
end

return TilemapData

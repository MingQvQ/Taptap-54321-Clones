-- ============================================================================
-- TilemapData.lua - 瓦片地图数据模块（v3）
-- 多图层架构（最多5层），每层有独立 zOrder 渲染层级
-- 支持自定义瓦片贴图、预制体标签、可调地图大小、撤销系统
-- ============================================================================

local TilemapData = {}

-- ============================================================================
-- 瓦片注册表（静态地图贴图）
-- ============================================================================

TilemapData.tileRegistry = {
    [0] = { id = 0, name = "空", image = nil, color = { 0, 0, 0, 0 } },
    [1] = { id = 1, name = "草地", image = nil, color = { 80, 180, 80, 255 } },
    [2] = { id = 2, name = "泥土", image = nil, color = { 140, 90, 50, 255 } },
    [3] = { id = 3, name = "石头", image = nil, color = { 120, 125, 135, 255 } },
    [4] = { id = 4, name = "木板", image = nil, color = { 160, 120, 60, 255 } },
}

-- 预注册瓦片素材（softy_sand + tilemap_tiles）
local preloadTiles = {
    -- softy_sand 沙地瓦片 (46张)
    { name = "softy_sand_01", image = "image/tilemap/softy_sand/softy_sand_01.png", group = "softy_sand" },
    { name = "softy_sand_02", image = "image/tilemap/softy_sand/softy_sand_02.png", group = "softy_sand" },
    { name = "softy_sand_03", image = "image/tilemap/softy_sand/softy_sand_03.png", group = "softy_sand" },
    { name = "softy_sand_04", image = "image/tilemap/softy_sand/softy_sand_04.png", group = "softy_sand" },
    { name = "softy_sand_05", image = "image/tilemap/softy_sand/softy_sand_05.png", group = "softy_sand" },
    { name = "softy_sand_06", image = "image/tilemap/softy_sand/softy_sand_06.png", group = "softy_sand" },
    { name = "softy_sand_07", image = "image/tilemap/softy_sand/softy_sand_07.png", group = "softy_sand" },
    { name = "softy_sand_08", image = "image/tilemap/softy_sand/softy_sand_08.png", group = "softy_sand" },
    { name = "softy_sand_09", image = "image/tilemap/softy_sand/softy_sand_09.png", group = "softy_sand" },
    { name = "softy_sand_10", image = "image/tilemap/softy_sand/softy_sand_10.png", group = "softy_sand" },
    { name = "softy_sand_12", image = "image/tilemap/softy_sand/softy_sand_12.png", group = "softy_sand" },
    { name = "softy_sand_13", image = "image/tilemap/softy_sand/softy_sand_13.png", group = "softy_sand" },
    { name = "softy_sand_14", image = "image/tilemap/softy_sand/softy_sand_14.png", group = "softy_sand" },
    { name = "softy_sand_15", image = "image/tilemap/softy_sand/softy_sand_15.png", group = "softy_sand" },
    { name = "softy_sand_16", image = "image/tilemap/softy_sand/softy_sand_16.png", group = "softy_sand" },
    { name = "softy_sand_17", image = "image/tilemap/softy_sand/softy_sand_17.png", group = "softy_sand" },
    { name = "softy_sand_18", image = "image/tilemap/softy_sand/softy_sand_18.png", group = "softy_sand" },
    { name = "softy_sand_19", image = "image/tilemap/softy_sand/softy_sand_19.png", group = "softy_sand" },
    { name = "softy_sand_20", image = "image/tilemap/softy_sand/softy_sand_20.png", group = "softy_sand" },
    { name = "softy_sand_21", image = "image/tilemap/softy_sand/softy_sand_21.png", group = "softy_sand" },
    { name = "softy_sand_23", image = "image/tilemap/softy_sand/softy_sand_23.png", group = "softy_sand" },
    { name = "softy_sand_24", image = "image/tilemap/softy_sand/softy_sand_24.png", group = "softy_sand" },
    { name = "softy_sand_25", image = "image/tilemap/softy_sand/softy_sand_25.png", group = "softy_sand" },
    { name = "softy_sand_26", image = "image/tilemap/softy_sand/softy_sand_26.png", group = "softy_sand" },
    { name = "softy_sand_27", image = "image/tilemap/softy_sand/softy_sand_27.png", group = "softy_sand" },
    { name = "softy_sand_28", image = "image/tilemap/softy_sand/softy_sand_28.png", group = "softy_sand" },
    { name = "softy_sand_29", image = "image/tilemap/softy_sand/softy_sand_29.png", group = "softy_sand" },
    { name = "softy_sand_30", image = "image/tilemap/softy_sand/softy_sand_30.png", group = "softy_sand" },
    { name = "softy_sand_31", image = "image/tilemap/softy_sand/softy_sand_31.png", group = "softy_sand" },
    { name = "softy_sand_32", image = "image/tilemap/softy_sand/softy_sand_32.png", group = "softy_sand" },
    { name = "softy_sand_33", image = "image/tilemap/softy_sand/softy_sand_33.png", group = "softy_sand" },
    { name = "softy_sand_34", image = "image/tilemap/softy_sand/softy_sand_34.png", group = "softy_sand" },
    { name = "softy_sand_35", image = "image/tilemap/softy_sand/softy_sand_35.png", group = "softy_sand" },
    { name = "softy_sand_36", image = "image/tilemap/softy_sand/softy_sand_36.png", group = "softy_sand" },
    { name = "softy_sand_37", image = "image/tilemap/softy_sand/softy_sand_37.png", group = "softy_sand" },
    { name = "softy_sand_38", image = "image/tilemap/softy_sand/softy_sand_38.png", group = "softy_sand" },
    { name = "softy_sand_39", image = "image/tilemap/softy_sand/softy_sand_39.png", group = "softy_sand" },
    { name = "softy_sand_40", image = "image/tilemap/softy_sand/softy_sand_40.png", group = "softy_sand" },
    { name = "softy_sand_41", image = "image/tilemap/softy_sand/softy_sand_41.png", group = "softy_sand" },
    { name = "softy_sand_42", image = "image/tilemap/softy_sand/softy_sand_42.png", group = "softy_sand" },
    { name = "softy_sand_43", image = "image/tilemap/softy_sand/softy_sand_43.png", group = "softy_sand" },
    { name = "softy_sand_44", image = "image/tilemap/softy_sand/softy_sand_44.png", group = "softy_sand" },
    { name = "softy_sand_49", image = "image/tilemap/softy_sand/softy_sand_49.png", group = "softy_sand" },
    { name = "softy_sand_50", image = "image/tilemap/softy_sand/softy_sand_50.png", group = "softy_sand" },
    { name = "softy_sand_51", image = "image/tilemap/softy_sand/softy_sand_51.png", group = "softy_sand" },
    { name = "softy_sand_52", image = "image/tilemap/softy_sand/softy_sand_52.png", group = "softy_sand" },
    { name = "softy_sand_53", image = "image/tilemap/softy_sand/softy_sand_53.png", group = "softy_sand" },
    -- tilemap_tiles 通用瓦片 (47张)
    { name = "tilemap_01", image = "image/tilemap/tilemap_tiles/tilemap_01.png", group = "tilemap_tiles" },
    { name = "tilemap_02", image = "image/tilemap/tilemap_tiles/tilemap_02.png", group = "tilemap_tiles" },
    { name = "tilemap_03", image = "image/tilemap/tilemap_tiles/tilemap_03.png", group = "tilemap_tiles" },
    { name = "tilemap_05", image = "image/tilemap/tilemap_tiles/tilemap_05.png", group = "tilemap_tiles" },
    { name = "tilemap_07", image = "image/tilemap/tilemap_tiles/tilemap_07.png", group = "tilemap_tiles" },
    { name = "tilemap_08", image = "image/tilemap/tilemap_tiles/tilemap_08.png", group = "tilemap_tiles" },
    { name = "tilemap_10", image = "image/tilemap/tilemap_tiles/tilemap_10.png", group = "tilemap_tiles" },
    { name = "tilemap_11", image = "image/tilemap/tilemap_tiles/tilemap_11.png", group = "tilemap_tiles" },
    { name = "tilemap_13", image = "image/tilemap/tilemap_tiles/tilemap_13.png", group = "tilemap_tiles" },
    { name = "tilemap_14", image = "image/tilemap/tilemap_tiles/tilemap_14.png", group = "tilemap_tiles" },
    { name = "tilemap_16", image = "image/tilemap/tilemap_tiles/tilemap_16.png", group = "tilemap_tiles" },
    { name = "tilemap_18", image = "image/tilemap/tilemap_tiles/tilemap_18.png", group = "tilemap_tiles" },
    { name = "tilemap_19", image = "image/tilemap/tilemap_tiles/tilemap_19.png", group = "tilemap_tiles" },
    { name = "tilemap_20", image = "image/tilemap/tilemap_tiles/tilemap_20.png", group = "tilemap_tiles" },
    { name = "tilemap_22", image = "image/tilemap/tilemap_tiles/tilemap_22.png", group = "tilemap_tiles" },
    { name = "tilemap_24", image = "image/tilemap/tilemap_tiles/tilemap_24.png", group = "tilemap_tiles" },
    { name = "tilemap_25", image = "image/tilemap/tilemap_tiles/tilemap_25.png", group = "tilemap_tiles" },
    { name = "tilemap_27", image = "image/tilemap/tilemap_tiles/tilemap_27.png", group = "tilemap_tiles" },
    { name = "tilemap_28", image = "image/tilemap/tilemap_tiles/tilemap_28.png", group = "tilemap_tiles" },
    { name = "tilemap_30", image = "image/tilemap/tilemap_tiles/tilemap_30.png", group = "tilemap_tiles" },
    { name = "tilemap_31", image = "image/tilemap/tilemap_tiles/tilemap_31.png", group = "tilemap_tiles" },
    { name = "tilemap_33", image = "image/tilemap/tilemap_tiles/tilemap_33.png", group = "tilemap_tiles" },
    { name = "tilemap_34", image = "image/tilemap/tilemap_tiles/tilemap_34.png", group = "tilemap_tiles" },
    { name = "tilemap_35", image = "image/tilemap/tilemap_tiles/tilemap_35.png", group = "tilemap_tiles" },
    { name = "tilemap_36", image = "image/tilemap/tilemap_tiles/tilemap_36.png", group = "tilemap_tiles" },
    { name = "tilemap_37", image = "image/tilemap/tilemap_tiles/tilemap_37.png", group = "tilemap_tiles" },
    { name = "tilemap_39", image = "image/tilemap/tilemap_tiles/tilemap_39.png", group = "tilemap_tiles" },
    { name = "tilemap_58", image = "image/tilemap/tilemap_tiles/tilemap_58.png", group = "tilemap_tiles" },
    { name = "tilemap_59", image = "image/tilemap/tilemap_tiles/tilemap_59.png", group = "tilemap_tiles" },
    { name = "tilemap_61", image = "image/tilemap/tilemap_tiles/tilemap_61.png", group = "tilemap_tiles" },
    { name = "tilemap_62", image = "image/tilemap/tilemap_tiles/tilemap_62.png", group = "tilemap_tiles" },
    { name = "tilemap_64", image = "image/tilemap/tilemap_tiles/tilemap_64.png", group = "tilemap_tiles" },
    { name = "tilemap_65", image = "image/tilemap/tilemap_tiles/tilemap_65.png", group = "tilemap_tiles" },
    { name = "tilemap_67", image = "image/tilemap/tilemap_tiles/tilemap_67.png", group = "tilemap_tiles" },
    { name = "tilemap_68", image = "image/tilemap/tilemap_tiles/tilemap_68.png", group = "tilemap_tiles" },
    { name = "tilemap_69", image = "image/tilemap/tilemap_tiles/tilemap_69.png", group = "tilemap_tiles" },
    { name = "tilemap_70", image = "image/tilemap/tilemap_tiles/tilemap_70.png", group = "tilemap_tiles" },
    { name = "tilemap_71", image = "image/tilemap/tilemap_tiles/tilemap_71.png", group = "tilemap_tiles" },
    { name = "tilemap_73", image = "image/tilemap/tilemap_tiles/tilemap_73.png", group = "tilemap_tiles" },
    { name = "tilemap_75", image = "image/tilemap/tilemap_tiles/tilemap_75.png", group = "tilemap_tiles" },
    { name = "tilemap_76", image = "image/tilemap/tilemap_tiles/tilemap_76.png", group = "tilemap_tiles" },
    { name = "tilemap_78", image = "image/tilemap/tilemap_tiles/tilemap_78.png", group = "tilemap_tiles" },
    { name = "tilemap_79", image = "image/tilemap/tilemap_tiles/tilemap_79.png", group = "tilemap_tiles" },
    { name = "tilemap_81", image = "image/tilemap/tilemap_tiles/tilemap_81.png", group = "tilemap_tiles" },
    { name = "tilemap_82", image = "image/tilemap/tilemap_tiles/tilemap_82.png", group = "tilemap_tiles" },
    { name = "tilemap_84", image = "image/tilemap/tilemap_tiles/tilemap_84.png", group = "tilemap_tiles" },
    { name = "tilemap_85", image = "image/tilemap/tilemap_tiles/tilemap_85.png", group = "tilemap_tiles" },
}

-- 自动注册预加载瓦片
local nextId = 5
for _, tile in ipairs(preloadTiles) do
    TilemapData.tileRegistry[nextId] = {
        id = nextId,
        name = tile.name,
        image = tile.image,
        color = { 200, 200, 200, 255 },
        group = tile.group,
    }
    nextId = nextId + 1
end
TilemapData.nextTileId = nextId

-- ============================================================================
-- 预制体注册表（带标签的游戏对象）
-- ============================================================================

TilemapData.prefabRegistry = {
    [0] = { id = 0, name = "空", tag = "", icon = "", color = { 0, 0, 0, 0 } },
    [1] = { id = 1, name = "玩家出生点", tag = "player_spawn", icon = "", color = { 80, 160, 255, 200 }, playerCount = 5 },
    [2] = { id = 2, name = "终点", tag = "goal", icon = "🚪", color = { 255, 215, 0, 200 } },
    [3] = { id = 3, name = "尖刺", tag = "spike", icon = "🔺", color = { 220, 50, 50, 200 } },
    [4] = { id = 4, name = "金币", tag = "coin", icon = "🟡", color = { 255, 200, 0, 200 } },
    [5] = { id = 5, name = "移动平台", tag = "moving_platform", icon = "↔️", color = { 100, 180, 220, 200 } },
}
TilemapData.nextPrefabId = 6

-- ============================================================================
-- 多图层系统
-- ============================================================================

--- 最大图层数
TilemapData.MAX_LAYERS = 5

--- 网格大小
TilemapData.gridWidth = 16
TilemapData.gridHeight = 12

--- 图层列表: { { id, name, type, zOrder, visible, data } }
--- type: "tile" 或 "prefab"
--- zOrder: 渲染层级，数字越大渲染越靠后（覆盖前面的）
--- data: [row][col] = id
TilemapData.layers = {}

--- 下一个图层唯一ID（递增，不复用）
local nextLayerUid_ = 1

--- 当前活跃图层索引（在 layers 数组中的位置）
TilemapData.activeLayerIndex = 1

-- ============================================================================
-- 撤销系统
-- ============================================================================

local undoStack_ = {}
local MAX_UNDO = 50

--- 记录一次操作到撤销栈
---@param action table { type, layerIndex, row, col, oldValue, newValue }
local function PushUndo(action)
    table.insert(undoStack_, action)
    if #undoStack_ > MAX_UNDO then
        table.remove(undoStack_, 1)
    end
end

--- 执行撤销
function TilemapData.Undo()
    if #undoStack_ == 0 then return false end
    local action = table.remove(undoStack_)
    if action.type == "paint" then
        local layer = TilemapData.layers[action.layerIndex]
        if layer and layer.data[action.row] then
            layer.data[action.row][action.col] = action.oldValue
        end
    elseif action.type == "batch" then
        -- 批量操作：逆序恢复所有子操作
        for i = #action.ops, 1, -1 do
            local op = action.ops[i]
            local layer = TilemapData.layers[op.layerIndex]
            if layer and layer.data[op.row] then
                layer.data[op.row][op.col] = op.oldValue
            end
        end
    end
    return true
end

--- 清空撤销栈
function TilemapData.ClearUndo()
    undoStack_ = {}
end

--- 获取撤销栈大小
function TilemapData.GetUndoCount()
    return #undoStack_
end

-- ============================================================================
-- 批量操作（拖拽绘制合并为一次撤销）
-- ============================================================================

local batchOps_ = nil  -- nil=非批量模式, table=正在收集

--- 开始一次批量操作（鼠标按下时调用）
function TilemapData.BeginBatch()
    batchOps_ = {}
end

--- 结束批量操作并压入撤销栈（鼠标松开时调用）
function TilemapData.EndBatch()
    if batchOps_ and #batchOps_ > 0 then
        PushUndo({ type = "batch", ops = batchOps_ })
    end
    batchOps_ = nil
end

--- 取消批量操作（不压入撤销栈）
function TilemapData.CancelBatch()
    batchOps_ = nil
end

-- ============================================================================
-- 图层管理 API
-- ============================================================================

--- 创建一个空白图层数据网格
local function CreateEmptyGrid(w, h)
    local grid = {}
    for row = 1, h do
        grid[row] = {}
        for col = 1, w do
            grid[row][col] = 0
        end
    end
    return grid
end

--- 新建图层
---@param name string 图层名称
---@param layerType string "tile" 或 "prefab"
---@param zOrder? number 渲染层级（默认自动递增）
---@return number|nil 新图层在 layers 中的索引，超出上限返回 nil
function TilemapData.AddLayer(name, layerType, zOrder)
    if #TilemapData.layers >= TilemapData.MAX_LAYERS then
        return nil
    end
    local uid = nextLayerUid_
    nextLayerUid_ = nextLayerUid_ + 1

    -- 默认 zOrder: 当前最大值 + 1
    if not zOrder then
        zOrder = 0
        for _, l in ipairs(TilemapData.layers) do
            if l.zOrder >= zOrder then zOrder = l.zOrder + 1 end
        end
    end

    local layer = {
        id = uid,
        name = name or ("图层" .. uid),
        type = layerType or "tile",
        zOrder = zOrder,
        visible = true,
        data = CreateEmptyGrid(TilemapData.gridWidth, TilemapData.gridHeight),
    }
    table.insert(TilemapData.layers, layer)
    return #TilemapData.layers
end

--- 删除图层
---@param index number 图层在 layers 数组中的索引
function TilemapData.RemoveLayer(index)
    if #TilemapData.layers <= 1 then return end  -- 至少保留一个
    table.remove(TilemapData.layers, index)
    -- 修正 activeLayerIndex
    if TilemapData.activeLayerIndex > #TilemapData.layers then
        TilemapData.activeLayerIndex = #TilemapData.layers
    end
end

--- 设置活跃图层
---@param index number
function TilemapData.SetActiveLayer(index)
    if index >= 1 and index <= #TilemapData.layers then
        TilemapData.activeLayerIndex = index
    end
end

--- 获取活跃图层
---@return table|nil
function TilemapData.GetActiveLayer()
    return TilemapData.layers[TilemapData.activeLayerIndex]
end

--- 设置图层 zOrder
---@param index number
---@param zOrder number
function TilemapData.SetLayerZOrder(index, zOrder)
    local layer = TilemapData.layers[index]
    if layer then
        layer.zOrder = zOrder
    end
end

--- 设置图层名称
---@param index number
---@param name string
function TilemapData.SetLayerName(index, name)
    local layer = TilemapData.layers[index]
    if layer then
        layer.name = name
    end
end

--- 设置图层可见性
---@param index number
---@param visible boolean
function TilemapData.SetLayerVisible(index, visible)
    local layer = TilemapData.layers[index]
    if layer then
        layer.visible = visible
    end
end

--- 获取按 zOrder 排序的图层索引列表（升序，先绘制的在前）
---@return table 排序后的索引数组
function TilemapData.GetLayersSortedByZOrder()
    local indices = {}
    for i = 1, #TilemapData.layers do
        table.insert(indices, i)
    end
    table.sort(indices, function(a, b)
        return TilemapData.layers[a].zOrder < TilemapData.layers[b].zOrder
    end)
    return indices
end

-- ============================================================================
-- 注册表 API
-- ============================================================================

function TilemapData.RegisterTile(name, imagePath, color)
    local id = TilemapData.nextTileId
    TilemapData.tileRegistry[id] = {
        id = id, name = name, image = imagePath,
        color = color or { 200, 200, 200, 255 },
    }
    TilemapData.nextTileId = id + 1
    return id
end

function TilemapData.SetTileImage(tileId, imagePath)
    if TilemapData.tileRegistry[tileId] then
        TilemapData.tileRegistry[tileId].image = imagePath
    end
end

function TilemapData.GetTileInfo(tileId)
    return TilemapData.tileRegistry[tileId] or TilemapData.tileRegistry[0]
end

function TilemapData.RegisterPrefab(name, tag, icon, color)
    local id = TilemapData.nextPrefabId
    TilemapData.prefabRegistry[id] = {
        id = id, name = name, tag = tag,
        icon = icon or "❓", color = color or { 180, 180, 180, 200 },
    }
    TilemapData.nextPrefabId = id + 1
    return id
end

function TilemapData.GetPrefabInfo(prefabId)
    return TilemapData.prefabRegistry[prefabId] or TilemapData.prefabRegistry[0]
end

-- ============================================================================
-- 地图操作 API
-- ============================================================================

--- 初始化新地图（重置所有图层）
---@param width? number
---@param height? number
function TilemapData.New(width, height)
    TilemapData.gridWidth = width or 16
    TilemapData.gridHeight = height or 12
    TilemapData.layers = {}
    TilemapData.activeLayerIndex = 1
    nextLayerUid_ = 1
    TilemapData.ClearUndo()

    -- 默认创建一个瓦片层和一个预制体层
    TilemapData.AddLayer("地形", "tile", 0)
    TilemapData.AddLayer("预制体", "prefab", 1)
    TilemapData.activeLayerIndex = 1
end

--- 调整地图大小（保留已有数据）
---@param newWidth number
---@param newHeight number
function TilemapData.Resize(newWidth, newHeight)
    local oldW = TilemapData.gridWidth
    local oldH = TilemapData.gridHeight

    TilemapData.gridWidth = newWidth
    TilemapData.gridHeight = newHeight

    for _, layer in ipairs(TilemapData.layers) do
        local oldData = layer.data
        layer.data = {}
        for row = 1, newHeight do
            layer.data[row] = {}
            for col = 1, newWidth do
                if row <= oldH and col <= oldW and oldData[row] then
                    layer.data[row][col] = oldData[row][col] or 0
                else
                    layer.data[row][col] = 0
                end
            end
        end
    end
    TilemapData.ClearUndo()
end

--- 在活跃图层上设置格子（带撤销记录）
---@param row number
---@param col number
---@param value number tileId 或 prefabId
function TilemapData.Paint(row, col, value)
    if row < 1 or row > TilemapData.gridHeight then return end
    if col < 1 or col > TilemapData.gridWidth then return end
    local layer = TilemapData.layers[TilemapData.activeLayerIndex]
    if not layer then return end

    local oldValue = layer.data[row][col]
    if oldValue == value then return end  -- 无变化不记录

    layer.data[row][col] = value

    local op = {
        type = "paint",
        layerIndex = TilemapData.activeLayerIndex,
        row = row, col = col,
        oldValue = oldValue, newValue = value,
    }

    if batchOps_ then
        table.insert(batchOps_, op)
    else
        PushUndo(op)
    end
end

--- 擦除活跃图层上的格子（等价于 Paint(row, col, 0)）
---@param row number
---@param col number
function TilemapData.Erase(row, col)
    TilemapData.Paint(row, col, 0)
end

--- 获取指定图层格子值
---@param layerIndex number
---@param row number
---@param col number
---@return number
function TilemapData.GetCell(layerIndex, row, col)
    if row < 1 or row > TilemapData.gridHeight then return 0 end
    if col < 1 or col > TilemapData.gridWidth then return 0 end
    local layer = TilemapData.layers[layerIndex]
    if not layer then return 0 end
    return layer.data[row][col] or 0
end

--- 清空所有图层数据
function TilemapData.Clear()
    for _, layer in ipairs(TilemapData.layers) do
        layer.data = CreateEmptyGrid(TilemapData.gridWidth, TilemapData.gridHeight)
    end
    TilemapData.ClearUndo()
end

-- ============================================================================
-- 序列化 / 反序列化
-- ============================================================================

function TilemapData.Serialize()
    local data = {
        version = 3,
        gridWidth = TilemapData.gridWidth,
        gridHeight = TilemapData.gridHeight,
        tileRegistry = {},
        prefabRegistry = {},
        layers = {},
    }

    -- 瓦片注册表
    for id, info in pairs(TilemapData.tileRegistry) do
        if id >= 1 then
            data.tileRegistry[tostring(id)] = {
                name = info.name, image = info.image, color = info.color,
            }
        end
    end

    -- 预制体注册表
    for id, info in pairs(TilemapData.prefabRegistry) do
        if id >= 1 then
            data.prefabRegistry[tostring(id)] = {
                name = info.name, tag = info.tag,
                icon = info.icon, color = info.color,
            }
        end
    end

    -- 图层（稀疏存储）
    for _, layer in ipairs(TilemapData.layers) do
        local layerData = {
            id = layer.id,
            name = layer.name,
            type = layer.type,
            zOrder = layer.zOrder,
            visible = layer.visible,
            cells = {},
        }
        for row = 1, TilemapData.gridHeight do
            for col = 1, TilemapData.gridWidth do
                local v = layer.data[row][col]
                if v ~= 0 then
                    table.insert(layerData.cells, { row, col, v })
                end
            end
        end
        table.insert(data.layers, layerData)
    end

    return data
end

function TilemapData.Deserialize(data)
    TilemapData.gridWidth = data.gridWidth or 16
    TilemapData.gridHeight = data.gridHeight or 12
    TilemapData.layers = {}
    TilemapData.activeLayerIndex = 1
    TilemapData.ClearUndo()

    -- 恢复瓦片注册表
    if data.tileRegistry then
        for idStr, info in pairs(data.tileRegistry) do
            local id = tonumber(idStr)
            if id then
                TilemapData.tileRegistry[id] = {
                    id = id, name = info.name, image = info.image,
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
                    id = id, name = info.name, tag = info.tag,
                    icon = info.icon or "❓", color = info.color or { 180, 180, 180, 200 },
                }
                if id >= TilemapData.nextPrefabId then
                    TilemapData.nextPrefabId = id + 1
                end
            end
        end
    end

    -- 恢复图层
    if data.layers then
        local maxUid = 0
        for _, layerData in ipairs(data.layers) do
            local grid = CreateEmptyGrid(TilemapData.gridWidth, TilemapData.gridHeight)
            if layerData.cells then
                for _, entry in ipairs(layerData.cells) do
                    local row, col, v = entry[1], entry[2], entry[3]
                    if row >= 1 and row <= TilemapData.gridHeight
                        and col >= 1 and col <= TilemapData.gridWidth then
                        grid[row][col] = v
                    end
                end
            end
            table.insert(TilemapData.layers, {
                id = layerData.id or 0,
                name = layerData.name or "图层",
                type = layerData.type or "tile",
                zOrder = layerData.zOrder or 0,
                visible = layerData.visible ~= false,
                data = grid,
            })
            if (layerData.id or 0) > maxUid then
                maxUid = layerData.id
            end
        end
        nextLayerUid_ = maxUid + 1
    end

    -- 确保至少有一个图层
    if #TilemapData.layers == 0 then
        TilemapData.AddLayer("地形", "tile", 0)
    end
end

return TilemapData

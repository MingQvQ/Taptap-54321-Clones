-- ============================================================================
-- EditorTestBridge.lua - 编辑器地图数据 → 游戏关卡格式转换
-- 将瓦片网格数据转换为 GameScene 可用的物理关卡数据
-- ============================================================================

local TilemapData = require("LevelEditor.TilemapData")
local Config = require("Config")

local EditorTestBridge = {}

-- ============================================================================
-- 坐标转换常量
-- 编辑器网格: row=1~gridHeight, col=1~gridWidth（左上角为 1,1）
-- 物理世界: Y-up 左手坐标系，中心约在屏幕中央
-- ============================================================================

--- 单个格子在物理世界中的尺寸（米）
local CELL_SIZE = 1.0

--- 将网格坐标 (row, col) 转换为物理世界中心坐标 (x, y)
--- row=1 是最上面一行 → y 最大, row=gridHeight 是最下面 → y 最小
---@param row number
---@param col number
---@return number x, number y
local function GridToPhysics(row, col)
    local gridW = TilemapData.gridWidth
    local gridH = TilemapData.gridHeight

    -- X: 以网格中心为原点 → col=1 在左侧, col=gridW 在右侧
    local x = (col - 0.5 - gridW / 2) * CELL_SIZE

    -- Y: row=1 在顶部(y大), row=gridH 在底部(y小)
    -- 以网格中心为原点
    local y = (gridH / 2 - row + 0.5) * CELL_SIZE

    return x, y
end

-- ============================================================================
-- 验证函数
-- ============================================================================

--- 验证地图是否满足测试条件（至少1个出生点 + 1个终点）
---@return boolean valid, string|nil errorMsg
function EditorTestBridge.Validate()
    local spawnCount = 0
    local goalCount = 0

    for i, layer in ipairs(TilemapData.layers) do
        if layer.type == "prefab" then
            for row = 1, TilemapData.gridHeight do
                for col = 1, TilemapData.gridWidth do
                    local v = layer.data[row][col]
                    if v ~= 0 then
                        local info = TilemapData.GetPrefabInfo(v)
                        if info.tag == "player_spawn" then
                            spawnCount = spawnCount + 1
                        elseif info.tag == "goal" then
                            goalCount = goalCount + 1
                        end
                    end
                end
            end
        end
    end

    if spawnCount == 0 and goalCount == 0 then
        return false, "请放置至少一个玩家出生点和一个终点"
    elseif spawnCount == 0 then
        return false, "请放置至少一个玩家出生点"
    elseif goalCount == 0 then
        return false, "请放置至少一个终点"
    end

    return true, nil
end

-- ============================================================================
-- 平台合并算法
-- 将相邻的同行实心瓦片合并为矩形平台
-- ============================================================================

--- 在指定瓦片图层中提取所有平台矩形
---@param layer table 瓦片图层
---@return table[] platforms 平台数组 { x, y, width, height }
local function ExtractPlatformsFromLayer(layer)
    local gridW = TilemapData.gridWidth
    local gridH = TilemapData.gridHeight
    local platforms = {}

    -- 标记已处理的格子
    local visited = {}
    for row = 1, gridH do
        visited[row] = {}
    end

    -- 逐行扫描，合并水平连续瓦片
    for row = 1, gridH do
        local col = 1
        while col <= gridW do
            local v = layer.data[row][col]
            if v ~= 0 and not visited[row][col] then
                -- 找到一个实心格子，向右扩展
                local startCol = col
                while col <= gridW and layer.data[row][col] ~= 0 and not visited[row][col] do
                    visited[row][col] = true
                    col = col + 1
                end
                local endCol = col - 1
                local width = (endCol - startCol + 1) * CELL_SIZE
                local height = CELL_SIZE

                -- 尝试向下合并相同宽度的行
                local mergeRow = row + 1
                while mergeRow <= gridH do
                    local canMerge = true
                    for c = startCol, endCol do
                        if layer.data[mergeRow][c] == 0 or visited[mergeRow][c] then
                            canMerge = false
                            break
                        end
                    end
                    -- 确保下一行不超出合并范围
                    if canMerge then
                        -- 检查合并行左右不超出范围（确保是同宽度块）
                        if startCol > 1 and layer.data[mergeRow][startCol - 1] ~= 0 and not visited[mergeRow][startCol - 1] then
                            canMerge = false
                        end
                        if endCol < gridW and layer.data[mergeRow][endCol + 1] ~= 0 and not visited[mergeRow][endCol + 1] then
                            canMerge = false
                        end
                    end
                    if canMerge then
                        for c = startCol, endCol do
                            visited[mergeRow][c] = true
                        end
                        height = height + CELL_SIZE
                        mergeRow = mergeRow + 1
                    else
                        break
                    end
                end

                -- 计算中心坐标
                local centerCol = (startCol + endCol) / 2
                local centerRow = row + (height / CELL_SIZE - 1) / 2
                local cx, cy = GridToPhysics(centerRow, centerCol)

                table.insert(platforms, {
                    x = cx,
                    y = cy,
                    width = width,
                    height = height,
                })
            else
                col = col + 1
            end
        end
    end

    return platforms
end

-- ============================================================================
-- 主转换函数
-- ============================================================================

--- 将当前编辑器地图数据转换为 GameScene 关卡格式
---@return table levelData 兼容 GameScene.LoadLevel 的数据格式
function EditorTestBridge.ConvertToLevelData()
    local gridW = TilemapData.gridWidth
    local gridH = TilemapData.gridHeight

    local levelData = {
        name = "编辑器测试",
        camera = { x = 0, y = 0 },
        spawn = { x = 0, y = 0 },
        goals = {},           -- 多终点数组 { x, y, width, height, acceptCount }
        goalTarget = 0,       -- 关卡目标 = 所有终点 acceptCount 之和
        platforms = {},
        spikes = {},
        coins = {},           -- 金币数组 { x, y }
        seagulls = {},        -- 海鸥飞行敌人 { x, y, range, speed }
        decorations = {},     -- 装饰预制体 { x, y, image }
        playerCount = Config.CloneCount,
    }

    -- 逐格瓦片数据（用于纹理渲染）
    local tilesCells = {}

    -- 遍历所有图层
    for i, layer in ipairs(TilemapData.layers) do
        if layer.type == "tile" then
            -- 地形层 → 提取平台（合并矩形用于物理碰撞）
            -- 环境层 → 仅渲染，不生成碰撞体
            local isEnvironment = (layer.layerKind == TilemapData.LAYER_KIND_ENVIRONMENT)

            if not isEnvironment then
                local layerPlatforms = ExtractPlatformsFromLayer(layer)
                for _, p in ipairs(layerPlatforms) do
                    table.insert(levelData.platforms, p)
                end
            end

            -- 所有瓦片层都提取逐格数据（用于纹理渲染）
            for row = 1, gridH do
                for col = 1, gridW do
                    local v = layer.data[row][col]
                    if v ~= 0 then
                        local tileInfo = TilemapData.GetTileInfo(v)
                        local px, py = GridToPhysics(row, col)
                        table.insert(tilesCells, {
                            x = px,
                            y = py,
                            size = CELL_SIZE,
                            image = tileInfo.image,  -- 纹理路径（可能为 nil）
                            color = tileInfo.color,  -- 后备颜色
                            zOrder = layer.zOrder,   -- 渲染层级
                        })
                    end
                end
            end

        elseif layer.type == "prefab" then
            -- 预制体层 → 提取出生点、终点、尖刺等
            for row = 1, gridH do
                for col = 1, gridW do
                    local v = layer.data[row][col]
                    if v ~= 0 then
                        local info = TilemapData.GetPrefabInfo(v)
                        local px, py = GridToPhysics(row, col)

                        if info.tag == "player_spawn" then
                            levelData.spawn = { x = px, y = py }
                            -- 使用出生点配置的玩家数量
                            levelData.playerCount = info.playerCount or Config.CloneCount

                        elseif info.tag == "goal" then
                            local acceptCount = info.acceptCount or 1
                            table.insert(levelData.goals, {
                                x = px, y = py,
                                width = CELL_SIZE * 0.8,
                                height = CELL_SIZE * 1.2,
                                acceptCount = acceptCount,
                            })
                            levelData.goalTarget = levelData.goalTarget + acceptCount

                        elseif info.tag == "spike" then
                            local rot = TilemapData.GetRotation(i, row, col)
                            table.insert(levelData.spikes, {
                                x = px, y = py,
                                width = CELL_SIZE * 0.8,
                                rotation = rot,  -- 0/90/180/270 度
                            })

                        elseif info.tag == "coin" then
                            table.insert(levelData.coins, {
                                x = px, y = py,
                            })

                        elseif info.tag == "seagull" then
                            table.insert(levelData.seagulls, {
                                x = px, y = py,
                                range = info.range or 3.0,
                                speed = info.speed or 2.0,
                            })

                        elseif info.tag == "decoration" then
                            table.insert(levelData.decorations, {
                                x = px, y = py,
                                image = info.image,
                            })
                        end
                    end
                end
            end
        end
    end

    -- 相机位置设为地图中心
    levelData.camera = { x = 0, y = 0 }

    -- 传递网格尺寸信息，供 GameScene 动态调整相机
    levelData.gridWidth = gridW
    levelData.gridHeight = gridH

    -- 传递逐格瓦片数据（纹理渲染用）
    levelData.tiles = tilesCells

    return levelData
end

return EditorTestBridge

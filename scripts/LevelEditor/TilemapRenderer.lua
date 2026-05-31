-- ============================================================================
-- TilemapRenderer.lua - 瓦片地图 NanoVG 渲染器（v3）
-- 按 zOrder 升序渲染多个图层（数字越大越后绘制=覆盖前面的）
-- 支持自定义贴图 + 预制体图标标记
-- ============================================================================

local TilemapData = require("LevelEditor.TilemapData")

local TilemapRenderer = {}

-- ============================================================================
-- 渲染配置
-- ============================================================================

TilemapRenderer.gridLineColor = { 60, 70, 90, 150 }
TilemapRenderer.backgroundColor = { 30, 34, 48, 255 }
TilemapRenderer.hoverColor = { 255, 255, 255, 40 }
TilemapRenderer.hoverBorderColor = { 255, 255, 255, 120 }

--- 当前悬停的格子
TilemapRenderer.hoverRow = -1
TilemapRenderer.hoverCol = -1

--- NanoVG 图片缓存
local imageCache_ = {}

-- ============================================================================
-- 图片管理
-- ============================================================================

local function GetOrLoadImage(vg, imagePath)
    if not imagePath or imagePath == "" then return nil end
    if imageCache_[imagePath] then
        return imageCache_[imagePath]
    end
    local handle = nvgCreateImage(vg, imagePath, 0)
    if handle and handle > 0 then
        imageCache_[imagePath] = handle
        return handle
    end
    return nil
end

function TilemapRenderer.ClearImageCache()
    imageCache_ = {}
end

-- ============================================================================
-- 布局计算
-- ============================================================================

function TilemapRenderer.CalcLayout(screenW, screenH, margins)
    local m = margins or { top = 48, bottom = 52, left = 80, right = 12 }
    local availW = screenW - m.left - m.right
    local availH = screenH - m.top - m.bottom

    local cellW = availW / TilemapData.gridWidth
    local cellH = availH / TilemapData.gridHeight
    local cellSize = math.floor(math.min(cellW, cellH))
    if cellSize < 8 then cellSize = 8 end

    local totalW = cellSize * TilemapData.gridWidth
    local totalH = cellSize * TilemapData.gridHeight

    local offsetX = m.left + math.floor((availW - totalW) / 2)
    local offsetY = m.top + math.floor((availH - totalH) / 2)

    return {
        offsetX = offsetX,
        offsetY = offsetY,
        cellSize = cellSize,
        totalW = totalW,
        totalH = totalH,
    }
end

function TilemapRenderer.ScreenToGrid(sx, sy, layout)
    local col = math.floor((sx - layout.offsetX) / layout.cellSize) + 1
    local row = math.floor((sy - layout.offsetY) / layout.cellSize) + 1
    return row, col
end

-- ============================================================================
-- 渲染
-- ============================================================================

--- 渲染单个瓦片类型图层
local function DrawTileLayer(vg, layer, layout)
    local cellSize = layout.cellSize
    local ox = layout.offsetX
    local oy = layout.offsetY

    for row = 1, TilemapData.gridHeight do
        for col = 1, TilemapData.gridWidth do
            local tileId = layer.data[row][col]
            if tileId ~= 0 then
                local info = TilemapData.GetTileInfo(tileId)
                local cx = ox + (col - 1) * cellSize
                local cy = oy + (row - 1) * cellSize

                local imgHandle = GetOrLoadImage(vg, info.image)
                if imgHandle then
                    local paint = nvgImagePattern(vg, cx, cy, cellSize, cellSize, 0, imgHandle, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, cx, cy, cellSize, cellSize)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                else
                    local c = info.color
                    nvgBeginPath(vg)
                    nvgRect(vg, cx + 1, cy + 1, cellSize - 2, cellSize - 2)
                    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], c[4]))
                    nvgFill(vg)
                end
            end
        end
    end
end

--- 渲染玩家出生点（圆圈 + 数字）
local function DrawSpawnPoint(vg, cx, cy, cellSize, info)
    local centerX = cx + cellSize * 0.5
    local centerY = cy + cellSize * 0.5
    local radius = (cellSize - 6) * 0.45
    local c = info.color
    local playerCount = info.playerCount or 5

    -- 外圆填充
    nvgBeginPath(vg)
    nvgCircle(vg, centerX, centerY, radius)
    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(c[4] * 0.5)))
    nvgFill(vg)

    -- 外圆边框
    nvgBeginPath(vg)
    nvgCircle(vg, centerX, centerY, radius)
    nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], 240))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)

    -- 中心数字（玩家数量）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, cellSize * 0.45)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, centerX, centerY, tostring(playerCount))
end

--- 渲染单个预制体类型图层
---@param vg userdata
---@param layer table
---@param layout table
---@param layerIdx number 图层索引（用于读取旋转数据）
local function DrawPrefabLayer(vg, layer, layout, layerIdx)
    local cellSize = layout.cellSize
    local ox = layout.offsetX
    local oy = layout.offsetY

    nvgFontFace(vg, "sans")
    for row = 1, TilemapData.gridHeight do
        for col = 1, TilemapData.gridWidth do
            local prefabId = layer.data[row][col]
            if prefabId ~= 0 then
                local info = TilemapData.GetPrefabInfo(prefabId)
                local cx = ox + (col - 1) * cellSize
                local cy = oy + (row - 1) * cellSize

                -- 获取旋转角度
                local rotation = TilemapData.GetRotation(layerIdx, row, col)

                -- 玩家出生点：特殊绘制（圆圈+数字）
                if info.tag == "player_spawn" then
                    DrawSpawnPoint(vg, cx, cy, cellSize, info)
                elseif info.image then
                    -- 有图片的预制体（装饰类）：绘制图片
                    local imgHandle = GetOrLoadImage(vg, info.image)
                    if imgHandle then
                        -- 应用旋转渲染
                        if rotation ~= 0 then
                            nvgSave(vg)
                            nvgTranslate(vg, cx + cellSize * 0.5, cy + cellSize * 0.5)
                            nvgRotate(vg, math.rad(rotation))
                            local paint = nvgImagePattern(vg, -cellSize * 0.5, -cellSize * 0.5, cellSize, cellSize, 0, imgHandle, 1.0)
                            nvgBeginPath(vg)
                            nvgRect(vg, -cellSize * 0.5, -cellSize * 0.5, cellSize, cellSize)
                            nvgFillPaint(vg, paint)
                            nvgFill(vg)
                            nvgRestore(vg)
                        else
                            local paint = nvgImagePattern(vg, cx, cy, cellSize, cellSize, 0, imgHandle, 1.0)
                            nvgBeginPath(vg)
                            nvgRect(vg, cx, cy, cellSize, cellSize)
                            nvgFillPaint(vg, paint)
                            nvgFill(vg)
                        end
                    else
                        -- 图片加载失败，fallback 色块
                        local c = info.color
                        nvgBeginPath(vg)
                        nvgRect(vg, cx + 2, cy + 2, cellSize - 4, cellSize - 4)
                        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(c[4] * 0.6)))
                        nvgFill(vg)
                    end
                else
                    -- 带旋转的图标渲染（尖刺等）
                    if rotation ~= 0 then
                        nvgSave(vg)
                        nvgTranslate(vg, cx + cellSize * 0.5, cy + cellSize * 0.5)
                        nvgRotate(vg, math.rad(rotation))

                        -- 半透明背景
                        local c = info.color
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, -cellSize * 0.5 + 2, -cellSize * 0.5 + 2, cellSize - 4, cellSize - 4, 4)
                        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(c[4] * 0.6)))
                        nvgFill(vg)

                        -- 边框
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, -cellSize * 0.5 + 2, -cellSize * 0.5 + 2, cellSize - 4, cellSize - 4, 4)
                        nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], 220))
                        nvgStrokeWidth(vg, 1.5)
                        nvgStroke(vg)

                        -- 图标
                        if info.icon and info.icon ~= "" then
                            nvgFontSize(vg, cellSize * 0.55)
                            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                            nvgText(vg, 0, 0, info.icon)
                        end

                        nvgRestore(vg)
                    else
                        -- 半透明背景
                        local c = info.color
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, cx + 2, cy + 2, cellSize - 4, cellSize - 4, 4)
                        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(c[4] * 0.6)))
                        nvgFill(vg)

                        -- 边框
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, cx + 2, cy + 2, cellSize - 4, cellSize - 4, 4)
                        nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], 220))
                        nvgStrokeWidth(vg, 1.5)
                        nvgStroke(vg)

                        -- 图标
                        if info.icon and info.icon ~= "" then
                            nvgFontSize(vg, cellSize * 0.55)
                            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                            nvgText(vg, cx + cellSize * 0.5, cy + cellSize * 0.5, info.icon)
                        end
                    end
                end
            end
        end
    end
end

--- 绘制整个地图（按 zOrder 升序渲染所有可见图层）
---@param vg userdata NanoVG 上下文
---@param layout table CalcLayout 返回值
function TilemapRenderer.Draw(vg, layout)
    local cellSize = layout.cellSize
    local ox = layout.offsetX
    local oy = layout.offsetY

    -- 1. 背景
    local bg = TilemapRenderer.backgroundColor
    nvgBeginPath(vg)
    nvgRect(vg, ox, oy, layout.totalW, layout.totalH)
    nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
    nvgFill(vg)

    -- 2. 按 zOrder 排序后依次渲染图层
    local sortedIndices = TilemapData.GetLayersSortedByZOrder()
    for _, layerIdx in ipairs(sortedIndices) do
        local layer = TilemapData.layers[layerIdx]
        if layer.visible then
            if layer.type == "tile" then
                DrawTileLayer(vg, layer, layout)
            elseif layer.type == "prefab" then
                DrawPrefabLayer(vg, layer, layout, layerIdx)
            end
        end
    end

    -- 3. 网格线
    local gc = TilemapRenderer.gridLineColor
    nvgBeginPath(vg)
    nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], gc[4]))
    nvgStrokeWidth(vg, 1.0)
    for col = 0, TilemapData.gridWidth do
        local x = ox + col * cellSize
        nvgMoveTo(vg, x, oy)
        nvgLineTo(vg, x, oy + layout.totalH)
    end
    for row = 0, TilemapData.gridHeight do
        local y = oy + row * cellSize
        nvgMoveTo(vg, ox, y)
        nvgLineTo(vg, ox + layout.totalW, y)
    end
    nvgStroke(vg)

    -- 4. 活跃图层高亮边框（让用户知道当前编辑的是哪层）
    -- 在悬停格子旁边显示小标记
    -- (此处仅做悬停高亮)

    -- 5. 悬停高亮
    if TilemapRenderer.hoverRow >= 1 and TilemapRenderer.hoverRow <= TilemapData.gridHeight
        and TilemapRenderer.hoverCol >= 1 and TilemapRenderer.hoverCol <= TilemapData.gridWidth then
        local hx = ox + (TilemapRenderer.hoverCol - 1) * cellSize
        local hy = oy + (TilemapRenderer.hoverRow - 1) * cellSize
        local hc = TilemapRenderer.hoverColor
        nvgBeginPath(vg)
        nvgRect(vg, hx, hy, cellSize, cellSize)
        nvgFillColor(vg, nvgRGBA(hc[1], hc[2], hc[3], hc[4]))
        nvgFill(vg)

        local bc = TilemapRenderer.hoverBorderColor
        nvgBeginPath(vg)
        nvgRect(vg, hx, hy, cellSize, cellSize)
        nvgStrokeColor(vg, nvgRGBA(bc[1], bc[2], bc[3], bc[4]))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)
    end
end

return TilemapRenderer

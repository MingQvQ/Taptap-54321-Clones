-- ============================================================================
-- TilemapRenderer.lua - 瓦片地图 NanoVG 渲染器
-- 从 TilemapData 读取数据，在编辑器中用 NanoVG 绘制网格和瓦片
-- ============================================================================

local TilemapData = require("LevelEditor.TilemapData")

local TilemapRenderer = {}

-- ============================================================================
-- 渲染配置
-- ============================================================================

--- 网格线颜色
TilemapRenderer.gridLineColor = { 60, 70, 90, 180 }

--- 背景色
TilemapRenderer.backgroundColor = { 30, 34, 48, 255 }

--- 高亮色（鼠标悬停格子）
TilemapRenderer.hoverColor = { 255, 255, 255, 40 }

--- 当前悬停的格子（由外部设置）
TilemapRenderer.hoverRow = -1
TilemapRenderer.hoverCol = -1

-- ============================================================================
-- 内部计算
-- ============================================================================

--- 计算渲染区域参数（居中显示，留出 UI 边距）
---@param screenW number 屏幕逻辑宽度
---@param screenH number 屏幕逻辑高度
---@param margins table { top, bottom, left, right }
---@return table { offsetX, offsetY, cellSize, totalW, totalH }
function TilemapRenderer.CalcLayout(screenW, screenH, margins)
    local m = margins or { top = 48, bottom = 52, left = 72, right = 12 }
    local availW = screenW - m.left - m.right
    local availH = screenH - m.top - m.bottom

    -- 根据网格大小计算单元格尺寸（取较小值以完整显示）
    local cellW = availW / TilemapData.gridWidth
    local cellH = availH / TilemapData.gridHeight
    local cellSize = math.floor(math.min(cellW, cellH))
    if cellSize < 8 then cellSize = 8 end

    -- 总绘制区域大小
    local totalW = cellSize * TilemapData.gridWidth
    local totalH = cellSize * TilemapData.gridHeight

    -- 居中偏移（在可用区域内居中）
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

--- 屏幕坐标转换为网格坐标
---@param sx number 屏幕 X
---@param sy number 屏幕 Y
---@param layout table CalcLayout 返回值
---@return number row, number col （可能超出范围，调用方需验证）
function TilemapRenderer.ScreenToGrid(sx, sy, layout)
    local col = math.floor((sx - layout.offsetX) / layout.cellSize) + 1
    local row = math.floor((sy - layout.offsetY) / layout.cellSize) + 1
    return row, col
end

--- 网格坐标转换为屏幕坐标（格子左上角）
---@param row number
---@param col number
---@param layout table
---@return number x, number y
function TilemapRenderer.GridToScreen(row, col, layout)
    local x = layout.offsetX + (col - 1) * layout.cellSize
    local y = layout.offsetY + (row - 1) * layout.cellSize
    return x, y
end

-- ============================================================================
-- 渲染
-- ============================================================================

--- 绘制整个瓦片地图（在 NanoVGRender 事件回调中调用）
---@param vg userdata NanoVG 上下文
---@param layout table CalcLayout 返回值
function TilemapRenderer.Draw(vg, layout)
    local cellSize = layout.cellSize
    local ox = layout.offsetX
    local oy = layout.offsetY

    -- 1. 绘制背景
    local bg = TilemapRenderer.backgroundColor
    nvgBeginPath(vg)
    nvgRect(vg, ox, oy, layout.totalW, layout.totalH)
    nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
    nvgFill(vg)

    -- 2. 绘制所有瓦片
    for row = 1, TilemapData.gridHeight do
        for col = 1, TilemapData.gridWidth do
            local cell = TilemapData.cells[row][col]
            if cell and cell.tileId ~= TilemapData.TILE_EMPTY then
                local info = TilemapData.GetTileInfo(cell.tileId)
                local c = info.color
                local cx = ox + (col - 1) * cellSize
                local cy = oy + (row - 1) * cellSize

                nvgBeginPath(vg)

                if cell.tileId == TilemapData.TILE_SPIKE then
                    -- 尖刺绘制为三角形
                    nvgMoveTo(vg, cx + cellSize * 0.5, cy + 2)
                    nvgLineTo(vg, cx + cellSize - 2, cy + cellSize - 2)
                    nvgLineTo(vg, cx + 2, cy + cellSize - 2)
                    nvgClosePath(vg)
                elseif cell.tileId == TilemapData.TILE_COIN then
                    -- 金币绘制为圆形
                    local radius = cellSize * 0.35
                    nvgCircle(vg, cx + cellSize * 0.5, cy + cellSize * 0.5, radius)
                else
                    -- 地面/平台绘制为矩形（留1px边距）
                    nvgRect(vg, cx + 1, cy + 1, cellSize - 2, cellSize - 2)
                end

                nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], c[4]))
                nvgFill(vg)
            end
        end
    end

    -- 3. 绘制网格线
    local gc = TilemapRenderer.gridLineColor
    nvgBeginPath(vg)
    nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], gc[4]))
    nvgStrokeWidth(vg, 1.0)

    -- 垂直线
    for col = 0, TilemapData.gridWidth do
        local x = ox + col * cellSize
        nvgMoveTo(vg, x, oy)
        nvgLineTo(vg, x, oy + layout.totalH)
    end
    -- 水平线
    for row = 0, TilemapData.gridHeight do
        local y = oy + row * cellSize
        nvgMoveTo(vg, ox, y)
        nvgLineTo(vg, ox + layout.totalW, y)
    end
    nvgStroke(vg)

    -- 4. 绘制悬停高亮
    if TilemapRenderer.hoverRow >= 1 and TilemapRenderer.hoverRow <= TilemapData.gridHeight
        and TilemapRenderer.hoverCol >= 1 and TilemapRenderer.hoverCol <= TilemapData.gridWidth then
        local hx = ox + (TilemapRenderer.hoverCol - 1) * cellSize
        local hy = oy + (TilemapRenderer.hoverRow - 1) * cellSize
        local hc = TilemapRenderer.hoverColor
        nvgBeginPath(vg)
        nvgRect(vg, hx, hy, cellSize, cellSize)
        nvgFillColor(vg, nvgRGBA(hc[1], hc[2], hc[3], hc[4]))
        nvgFill(vg)

        -- 高亮边框
        nvgBeginPath(vg)
        nvgRect(vg, hx, hy, cellSize, cellSize)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 120))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)
    end
end

return TilemapRenderer

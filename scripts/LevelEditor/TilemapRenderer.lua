-- ============================================================================
-- TilemapRenderer.lua - 瓦片地图 NanoVG 渲染器（v2）
-- 支持自定义贴图渲染 + 预制体图标标记
-- 双层渲染：底层瓦片贴图 → 上层预制体标记
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

--- NanoVG 图片缓存: imagePath -> nvgImageHandle
local imageCache_ = {}

-- ============================================================================
-- 图片管理
-- ============================================================================

--- 获取或加载 NanoVG 图片句柄
---@param vg userdata NanoVG 上下文
---@param imagePath string 贴图路径
---@return number|nil NanoVG 图片句柄
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

--- 清除图片缓存（场景退出时调用）
function TilemapRenderer.ClearImageCache()
    imageCache_ = {}
end

-- ============================================================================
-- 布局计算
-- ============================================================================

--- 计算渲染区域参数
---@param screenW number 屏幕逻辑宽度
---@param screenH number 屏幕逻辑高度
---@param margins table { top, bottom, left, right }
---@return table { offsetX, offsetY, cellSize, totalW, totalH }
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

--- 屏幕坐标 → 网格坐标
---@param sx number
---@param sy number
---@param layout table
---@return number row, number col
function TilemapRenderer.ScreenToGrid(sx, sy, layout)
    local col = math.floor((sx - layout.offsetX) / layout.cellSize) + 1
    local row = math.floor((sy - layout.offsetY) / layout.cellSize) + 1
    return row, col
end

-- ============================================================================
-- 渲染
-- ============================================================================

--- 绘制整个地图（NanoVGRender 回调中调用）
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

    -- 2. 瓦片层
    for row = 1, TilemapData.gridHeight do
        for col = 1, TilemapData.gridWidth do
            local tileId = TilemapData.tileLayer[row][col]
            if tileId ~= 0 then
                local info = TilemapData.GetTileInfo(tileId)
                local cx = ox + (col - 1) * cellSize
                local cy = oy + (row - 1) * cellSize

                -- 尝试用贴图渲染
                local imgHandle = GetOrLoadImage(vg, info.image)
                if imgHandle then
                    local paint = nvgImagePattern(vg, cx, cy, cellSize, cellSize, 0, imgHandle, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, cx, cy, cellSize, cellSize)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                else
                    -- fallback: 纯色矩形
                    local c = info.color
                    nvgBeginPath(vg)
                    nvgRect(vg, cx + 1, cy + 1, cellSize - 2, cellSize - 2)
                    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], c[4]))
                    nvgFill(vg)
                end
            end
        end
    end

    -- 3. 预制体层（绘制在瓦片层之上）
    nvgFontFace(vg, "sans")
    for row = 1, TilemapData.gridHeight do
        for col = 1, TilemapData.gridWidth do
            local prefabId = TilemapData.prefabLayer[row][col]
            if prefabId ~= 0 then
                local info = TilemapData.GetPrefabInfo(prefabId)
                local cx = ox + (col - 1) * cellSize
                local cy = oy + (row - 1) * cellSize

                -- 半透明背景标记
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

                -- 图标文字
                if info.icon and info.icon ~= "" then
                    nvgFontSize(vg, cellSize * 0.55)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                    nvgText(vg, cx + cellSize * 0.5, cy + cellSize * 0.5, info.icon)
                end
            end
        end
    end

    -- 4. 网格线
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

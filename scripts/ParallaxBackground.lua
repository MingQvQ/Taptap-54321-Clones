-- ============================================================================
-- ParallaxBackground.lua - 像素风平铺背景 + 云朵自动滚动
-- 图层有透明度，从底到顶自然叠加：天空 → 云朵 → 沙滩 → 海浪
-- ============================================================================

local ParallaxBackground = {}
ParallaxBackground.__index = ParallaxBackground

-- NanoVG 图片标志位：水平重复 + 最近邻采样（像素风）
local IMG_FLAGS = 2 + 32  -- NVG_IMAGE_REPEATX(2) + NVG_IMAGE_NEAREST(32)

-- 层配置（从底到顶绘制）
-- scrollSpeed: 像素/秒（原始像素），0 = 静态
-- yAnchor: 垂直锚点（0.0=图片顶部对齐屏幕顶，1.0=图片底部对齐屏幕底）
local DEFAULT_LAYERS = {
    { name = "sky",          file = "image/tilemap/background/sky.png",          scrollSpeed = 0,  yAnchor = 0.0, fill = true },
    { name = "clouds_small", file = "image/tilemap/background/clouds_small.png", scrollSpeed = 6,  yAnchor = 0.0, yOffset = -18 },
    { name = "clouds_tiny",  file = "image/tilemap/background/clouds_tiny.png",  scrollSpeed = 8,  yAnchor = 0.0, yOffset = -18 },
    { name = "clouds_big",   file = "image/tilemap/background/clouds_big.png",   scrollSpeed = 12, yAnchor = 0.0, yOffset = -18 },
    { name = "desert",       file = "image/tilemap/background/desert.png",       scrollSpeed = 0,  yAnchor = 0.85, scaleMul = 1.10 },
    { name = "beach",        file = "image/tilemap/background/beach.png",        scrollSpeed = 0,  yAnchor = 0.85, scaleMul = 1.10 },
}

--- 创建背景实例
---@param nvgContext userdata NanoVG 上下文
---@param config table|nil 可选层配置
---@param zoom number|nil 统一缩放倍数（默认自动根据屏幕高度取整数倍）
---@return table
function ParallaxBackground.Create(nvgContext, config, zoom)
    local self = setmetatable({}, ParallaxBackground)
    self.nvg = nvgContext
    self.layers = {}
    self.time = 0
    self.zoom = zoom  -- nil = 自动

    local layerConfigs = config or DEFAULT_LAYERS
    for _, cfg in ipairs(layerConfigs) do
        local img = nvgCreateImage(nvgContext, cfg.file, IMG_FLAGS)
        if img and img ~= 0 then
            local w, h = nvgImageSize(nvgContext, img)
            table.insert(self.layers, {
                name = cfg.name,
                image = img,
                imgW = w,
                imgH = h,
                scrollSpeed = cfg.scrollSpeed or 0,
                yAnchor = cfg.yAnchor or 0.0,
                yOffset = cfg.yOffset or 0,
                fill = cfg.fill or false,
                scaleMul = cfg.scaleMul or 1.0,
                offset = 0,
            })
        else
            print("[Background] WARNING: Failed to load " .. cfg.file)
        end
    end

    print("[Background] Loaded " .. #self.layers .. " layers, zoom=" .. tostring(self.zoom or "auto"))
    return self
end

--- 每帧更新（驱动云朵滚动）
---@param dt number
function ParallaxBackground:Update(dt)
    self.time = self.time + dt
    for _, layer in ipairs(self.layers) do
        if layer.scrollSpeed ~= 0 then
            layer.offset = layer.offset + layer.scrollSpeed * dt
        end
    end
end

--- 渲染所有层
---@param screenW number 屏幕宽度（逻辑像素）
---@param screenH number 屏幕高度（逻辑像素）
function ParallaxBackground:Draw(screenW, screenH)
    local nvg = self.nvg

    -- 计算统一缩放
    local scale
    if self.zoom then
        scale = self.zoom
        -- 保底：即使指定了 zoom，也不能让背景高度小于屏幕
        if scale * 180 < screenH then
            scale = screenH / 180
        end
    else
        -- 自动：整数倍填满屏幕高度
        scale = math.max(1, math.floor(screenH / 180))
        if scale * 180 < screenH then
            scale = scale + 1
        end
    end

    for _, layer in ipairs(self.layers) do
        local layerScale
        if layer.fill then
            -- fill 层：确保铺满全屏高度（取能覆盖屏幕的最小倍数）
            layerScale = math.max(scale, math.ceil(screenH / layer.imgH))
        else
            layerScale = scale * layer.scaleMul
        end

        local tileW = layer.imgW * layerScale
        local tileH = layer.imgH * layerScale

        -- 垂直定位：yAnchor=0 顶部对齐，yAnchor=1 底部对齐，yOffset 像素偏移（负=上移）
        local drawY = (screenH - tileH) * layer.yAnchor + layer.yOffset

        -- 水平滚动偏移
        local ox = 0
        if layer.scrollSpeed ~= 0 then
            ox = -((layer.offset * layerScale) % tileW)
        end

        -- 绘制（透明图层自然叠加，无需 scissor）
        local paint = nvgImagePattern(nvg, ox, drawY, tileW, tileH, 0, layer.image, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, drawY, screenW, tileH)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)
    end
end

--- 销毁（释放图片）
function ParallaxBackground:Destroy()
    if self.nvg then
        for _, layer in ipairs(self.layers) do
            if layer.image and layer.image ~= 0 then
                nvgDeleteImage(self.nvg, layer.image)
            end
        end
    end
    self.layers = {}
    self.nvg = nil
end

return ParallaxBackground

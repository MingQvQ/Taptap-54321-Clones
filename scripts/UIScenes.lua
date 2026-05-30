-- ============================================================================
-- UIScenes.lua - UI 界面模块
-- 包含：开始游戏界面（滚动天空背景）、关卡选择界面（JSON配置）、设置界面
-- 使用 urhox-libs/UI 控件库
-- ============================================================================

local UI = require("urhox-libs/UI")
local tween = require("tween")
local Config = require("Config")
local SceneManager = require("SceneManager")
local LevelData = require("LevelData")


local UIScenes = {}

-- ============================================================================
-- 通用 Tween 动画管理（跨场景共享）
-- ============================================================================

local activeTweens_ = {}

--- 给控件添加缩放动画
local function AnimateScale(widget, proxy, targetScale, easing, duration)
    -- 移除该代理上旧的 tween
    local i = 1
    while i <= #activeTweens_ do
        if activeTweens_[i].proxy == proxy then
            table.remove(activeTweens_, i)
        else
            i = i + 1
        end
    end
    -- 新建 tween
    local tw = tween.new(duration or 0.2, proxy, { scale = targetScale }, easing or "outBack")
    table.insert(activeTweens_, { tween = tw, proxy = proxy, widget = widget })
end

--- 每帧驱动所有活跃的 tween
local function UpdateTweens(dt)
    local i = 1
    while i <= #activeTweens_ do
        local entry = activeTweens_[i]
        local finished = entry.tween:update(dt)
        if entry.widget and entry.proxy then
            entry.widget:SetProp("scale", entry.proxy.scale)
        end
        if finished then
            if entry.onComplete then entry.onComplete() end
            table.remove(activeTweens_, i)
        else
            i = i + 1
        end
    end
end

--- 清除所有 tween
local function ClearAllTweens()
    activeTweens_ = {}
end

-- ============================================================================
-- 开始游戏界面 (Title Screen) - 滚动天空背景 + 克隆人标题
-- ============================================================================

local TitleScene = {}

---@type NVGContextWrapper
local titleNvg_ = nil

-- 3D 透视云朵系统
local cloudImages_ = {}       -- NanoVG image handles (数组)
local cloudImgSizes_ = {}     -- { {w,h}, ... } 每张图原始尺寸
local cloudParticles_ = {}    -- 云朵粒子列表
local CLOUD_COUNT = 18        -- 同屏云朵数
local CLOUD_SPEED = 60        -- 基础前进速度（像素/秒）
local CLOUD_Z_MIN = 0.1       -- 最远处 Z（最小缩放）
local CLOUD_Z_MAX = 1.2       -- 最近处 Z（最大缩放）

-- 天空渐变色
local SKY_TOP = { 90, 160, 255 }
local SKY_BOTTOM = { 200, 230, 255 }

--- 生成/重置一个云朵粒子
local function SpawnCloud(p, screenW, screenH, randomZ)
    p.imgIdx = math.random(1, #cloudImages_)
    if randomZ then
        p.z = CLOUD_Z_MIN + math.random() * (CLOUD_Z_MAX - CLOUD_Z_MIN)
    else
        p.z = CLOUD_Z_MIN  -- 新生成的从最远处开始
    end
    -- 随机水平位置（基于屏幕宽度，考虑缩放后可能超出）
    local spread = screenW * 0.8
    p.x = (math.random() - 0.5) * spread
    -- 垂直位置：远处的靠近地平线（中心偏上），近处的分散
    p.y = (math.random() - 0.5) * screenH * 0.4 - screenH * 0.1
    return p
end

function TitleScene.Enter(params)
    -- 创建 NanoVG 上下文
    titleNvg_ = nvgCreate(1)

    -- 加载云朵精灵图（最近邻采样保持像素风格）
    local IMG_FLAGS = 32  -- NVG_IMAGE_NEAREST
    local cloudFiles = {
        "image/cloud_sprite_1_20260530131000.png",
        "image/cloud_sprite_2_20260530131006.png",
        "image/cloud_sprite_3_20260530131019.png",
    }
    cloudImages_ = {}
    cloudImgSizes_ = {}
    for i, f in ipairs(cloudFiles) do
        local img = nvgCreateImage(titleNvg_, f, IMG_FLAGS)
        if img and img ~= 0 then
            local w, h = nvgImageSize(titleNvg_, img)
            table.insert(cloudImages_, img)
            table.insert(cloudImgSizes_, { w = w, h = h })
        end
    end

    -- 初始化云朵粒子（随机分布在不同深度）
    local screenW = graphics:GetWidth() / graphics:GetDPR()
    local screenH = graphics:GetHeight() / graphics:GetDPR()
    cloudParticles_ = {}
    math.randomseed(os.time())
    for i = 1, CLOUD_COUNT do
        local p = {}
        SpawnCloud(p, screenW, screenH, true)  -- true = 随机Z深度
        table.insert(cloudParticles_, p)
    end

    -- 注册事件
    SubscribeToEvent("Update", "TitleScene_HandleUpdate")
    SubscribeToEvent(titleNvg_, "NanoVGRender", "TitleScene_HandleRender")

    -- UI 层 - 标题 + 按钮
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "90%",
                maxWidth = 360,
                padding = 30,
                gap = 16,
                alignItems = "center",
                backgroundColor = { 0, 0, 0, 120 },
                borderRadius = 20,
                children = {
                    -- 克隆人角色图标
                    UI.Panel {
                        width = 100,
                        height = 100,
                        backgroundImage = "image/clone_character_20260530074154.png",
                        backgroundFit = "contain",
                    },
                    -- 游戏标题
                    UI.Label {
                        text = "影子伙伴",
                        fontSize = 42,
                        fontWeight = "bold",
                        fontColor = { 255, 255, 255, 255 },
                    },
                    UI.Label {
                        text = "SHADOW PARTNER",
                        fontSize = 14,
                        fontColor = { 200, 220, 255, 180 },
                    },
                    -- 间隔
                    UI.Panel { height = 16 },
                    -- 开始按钮（带 tween 动画）
                    (function()
                        local proxy = { scale = 1.0 }
                        return UI.Button {
                            text = "开始游戏",
                            variant = "primary",
                            width = 200,
                            height = 48,
                            scale = 1.0,
                            onPointerEnter = function(ev, self)
                                AnimateScale(self, proxy, 1.1, "outBack", 0.2)
                            end,
                            onPointerLeave = function(ev, self)
                                AnimateScale(self, proxy, 1.0, "outQuad", 0.2)
                            end,
                            onPointerDown = function(ev, self)
                                AnimateScale(self, proxy, 0.95, "outQuart", 0.1)
                            end,
                            onPointerUp = function(ev, self)
                                AnimateScale(self, proxy, 1.1, "outBack", 0.15)
                            end,
                            onClick = function(self)
                                SceneManager.SwitchTo(SceneManager.SCENE_LEVEL_SELECT)
                            end,
                        }
                    end)(),
                    -- 设置按钮（带 tween 动画）
                    (function()
                        local proxy = { scale = 1.0 }
                        return UI.Button {
                            text = "设置",
                            variant = "outline",
                            width = 200,
                            height = 44,
                            scale = 1.0,
                            onPointerEnter = function(ev, self)
                                AnimateScale(self, proxy, 1.1, "outBack", 0.2)
                            end,
                            onPointerLeave = function(ev, self)
                                AnimateScale(self, proxy, 1.0, "outQuad", 0.2)
                            end,
                            onPointerDown = function(ev, self)
                                AnimateScale(self, proxy, 0.95, "outQuart", 0.1)
                            end,
                            onPointerUp = function(ev, self)
                                AnimateScale(self, proxy, 1.1, "outBack", 0.15)
                            end,
                            onClick = function(self)
                                SceneManager.SwitchTo(SceneManager.SCENE_SETTINGS)
                            end,
                        }
                    end)(),
                    -- 关卡编辑器按钮（带 tween 动画）
                    (function()
                        local proxy = { scale = 1.0 }
                        return UI.Button {
                            text = "关卡编辑器",
                            variant = "outline",
                            width = 200,
                            height = 44,
                            scale = 1.0,
                            onPointerEnter = function(ev, self)
                                AnimateScale(self, proxy, 1.1, "outBack", 0.2)
                            end,
                            onPointerLeave = function(ev, self)
                                AnimateScale(self, proxy, 1.0, "outQuad", 0.2)
                            end,
                            onPointerDown = function(ev, self)
                                AnimateScale(self, proxy, 0.95, "outQuart", 0.1)
                            end,
                            onPointerUp = function(ev, self)
                                AnimateScale(self, proxy, 1.1, "outBack", 0.15)
                            end,
                            onClick = function(self)
                                SceneManager.SwitchTo(SceneManager.SCENE_EDITOR)
                            end,
                        }
                    end)(),
                    -- 版本号
                    UI.Panel { height = 6 },
                    UI.Label {
                        text = "v" .. Config.Version,
                        fontSize = 12,
                        fontColor = { 200, 210, 230, 150 },
                    },
                }
            }
        }
    }
    UI.SetRoot(root)
end

function TitleScene.Exit()
    -- 清除事件
    UnsubscribeFromEvent("Update")
    if titleNvg_ then
        UnsubscribeFromEvent(titleNvg_, "NanoVGRender")
        for _, img in ipairs(cloudImages_) do
            nvgDeleteImage(titleNvg_, img)
        end
    end
    cloudImages_ = {}
    cloudImgSizes_ = {}
    cloudParticles_ = {}
    ClearAllTweens()
    UI.SetRoot(nil)
    titleNvg_ = nil
end

SceneManager.Register(SceneManager.SCENE_TITLE, TitleScene)

-- Title 全局事件回调
function TitleScene_HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    local screenW = graphics:GetWidth() / graphics:GetDPR()
    local screenH = graphics:GetHeight() / graphics:GetDPR()

    -- 更新云朵粒子：Z 递增（从远到近）
    for _, p in ipairs(cloudParticles_) do
        -- Z 越大 = 越近，速度也越快（透视加速）
        local speedMul = 0.3 + p.z * 0.7
        p.z = p.z + CLOUD_SPEED * speedMul * dt * 0.01

        -- 超过最大 Z（飞出屏幕）→ 重置到远处
        if p.z > CLOUD_Z_MAX then
            SpawnCloud(p, screenW, screenH, false)
        end
    end

    -- 驱动按钮 tween 动画
    UpdateTweens(dt)
end

function TitleScene_HandleRender(eventType, eventData)
    if not titleNvg_ then return end
    if #cloudImages_ == 0 then return end

    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr

    nvgBeginFrame(titleNvg_, logW, logH, dpr)

    -- 绘制天空渐变背景
    local skyPaint = nvgLinearGradient(titleNvg_, 0, 0, 0, logH,
        nvgRGBA(SKY_TOP[1], SKY_TOP[2], SKY_TOP[3], 255),
        nvgRGBA(SKY_BOTTOM[1], SKY_BOTTOM[2], SKY_BOTTOM[3], 255))
    nvgBeginPath(titleNvg_)
    nvgRect(titleNvg_, 0, 0, logW, logH)
    nvgFillPaint(titleNvg_, skyPaint)
    nvgFill(titleNvg_)

    -- 按 Z 排序（远的先画，近的后画）
    local sorted = {}
    for i, p in ipairs(cloudParticles_) do
        sorted[i] = p
    end
    table.sort(sorted, function(a, b) return a.z < b.z end)

    -- 绘制每朵云
    local cx = logW * 0.5  -- 屏幕中心（消失点）
    local cy = logH * 0.45 -- 消失点略偏上

    for _, p in ipairs(sorted) do
        local imgIdx = p.imgIdx
        if imgIdx and cloudImages_[imgIdx] then
            local imgW = cloudImgSizes_[imgIdx].w
            local imgH = cloudImgSizes_[imgIdx].h

            -- 透视缩放：Z 越大（越近）显示越大
            local scale = p.z * 1.5

            -- 透视位移：从消失点向外扩散
            local drawX = cx + p.x * p.z
            local drawY = cy + p.y * p.z

            -- 计算绘制尺寸
            local dw = imgW * scale
            local dh = imgH * scale

            -- 透明度：远处淡，近处清晰
            local alpha = math.min(1.0, p.z / CLOUD_Z_MAX * 1.2)
            -- 超近处也渐隐（飞出屏幕效果）
            if p.z > CLOUD_Z_MAX * 0.85 then
                local fadeOut = (CLOUD_Z_MAX - p.z) / (CLOUD_Z_MAX * 0.15)
                alpha = alpha * math.max(0, fadeOut)
            end

            -- 绘制云朵
            nvgSave(titleNvg_)
            nvgGlobalAlpha(titleNvg_, alpha)
            local paint = nvgImagePattern(titleNvg_,
                drawX - dw * 0.5, drawY - dh * 0.5,
                dw, dh, 0, cloudImages_[imgIdx], 1.0)
            nvgBeginPath(titleNvg_)
            nvgRect(titleNvg_, drawX - dw * 0.5, drawY - dh * 0.5, dw, dh)
            nvgFillPaint(titleNvg_, paint)
            nvgFill(titleNvg_)
            nvgRestore(titleNvg_)
        end
    end

    nvgEndFrame(titleNvg_)
end

-- ============================================================================
-- 关卡选择界面 (Level Select)
-- 从 JSON 配置加载布局
-- ============================================================================

local LevelSelectScene = {}

--- 从 JSON 加载关卡选择布局配置
local function LoadLevelSelectConfig()
    local path = "Levels/level_select.json"
    if not cache:Exists(path) then
        -- 使用默认配置
        return nil
    end
    local file = cache:GetFile(path)
    if not file then return nil end
    local content = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        log:Write(LOG_ERROR, "UIScenes: Failed to parse level_select.json: " .. tostring(data))
        return nil
    end
    return data
end

-- 默认路径配置（锯齿蛇形：右→下→右→右→上→右→右→下→右）
local DEFAULT_LEVEL_POSITIONS = {
    { row = 1, col = 1 },  -- 关卡1: 起点
    { row = 1, col = 2 },  -- 关卡2: 右
    { row = 2, col = 2 },  -- 关卡3: 下
    { row = 2, col = 3 },  -- 关卡4: 右
    { row = 2, col = 4 },  -- 关卡5: 右
    { row = 1, col = 4 },  -- 关卡6: 上
    { row = 1, col = 5 },  -- 关卡7: 右
    { row = 1, col = 6 },  -- 关卡8: 右
    { row = 2, col = 6 },  -- 关卡9: 下
    { row = 2, col = 7 },  -- 关卡10: 右(终点)
}

-- 默认样式
local DEFAULT_STYLE = {
    unlocked = { backgroundColor = { 180, 40, 50, 255 }, borderColor = { 0, 0, 0, 255 }, textColor = { 255, 255, 255, 255 } },
    locked = { backgroundColor = { 0, 0, 0, 0 }, borderColor = { 255, 255, 255, 150 }, icon = "🔒" },
    connection = { color = { 255, 255, 255, 150 }, thickness = 3 },
}

--- 创建关卡节点
local function CreateLevelNode(index, unlocked, nodeSize, style)
    local s = style or DEFAULT_STYLE
    if unlocked then
        local bgColor = s.unlocked and s.unlocked.backgroundColor or DEFAULT_STYLE.unlocked.backgroundColor
        local bdColor = s.unlocked and s.unlocked.borderColor or DEFAULT_STYLE.unlocked.borderColor
        local txtColor = s.unlocked and s.unlocked.textColor or DEFAULT_STYLE.unlocked.textColor

        -- 动画代理对象
        local proxy = { scale = 1.0 }

        local node = UI.Panel {
            width = nodeSize, height = nodeSize,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = bgColor,
            borderRadius = 6,
            borderWidth = 2,
            borderColor = bdColor,
            scale = 1.0,
            onPointerEnter = function(ev, self)
                AnimateScale(self, proxy, 1.1, "outBack", 0.2)
            end,
            onPointerLeave = function(ev, self)
                AnimateScale(self, proxy, 1.0, "outQuad", 0.2)
                -- 恢复颜色
                self:SetProp("backgroundColor", bgColor)
            end,
            onPointerDown = function(ev, self)
                AnimateScale(self, proxy, 0.95, "outQuart", 0.1)
                self:SetProp("backgroundColor", { 120, 120, 120, 255 })
            end,
            onPointerUp = function(ev, self)
                AnimateScale(self, proxy, 1.1, "outBack", 0.15)
                self:SetProp("backgroundColor", bgColor)
            end,
            onClick = function(self)
                SceneManager.SwitchTo(SceneManager.SCENE_GAME, { level = index })
            end,
            children = {
                UI.Label {
                    text = tostring(index),
                    fontSize = 22,
                    fontWeight = "bold",
                    fontColor = txtColor,
                },
            }
        }
        return node
    else
        local bgColor = s.locked and s.locked.backgroundColor or DEFAULT_STYLE.locked.backgroundColor
        local bdColor = s.locked and s.locked.borderColor or DEFAULT_STYLE.locked.borderColor
        local icon = s.locked and s.locked.icon or DEFAULT_STYLE.locked.icon
        return UI.Panel {
            width = nodeSize, height = nodeSize,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = bgColor,
            borderRadius = 6,
            borderWidth = 2,
            borderColor = bdColor,
            children = {
                UI.Label {
                    text = icon,
                    fontSize = 20,
                },
            }
        }
    end
end

--- 创建水平连接线
local function CreateHLine(gapWidth, style)
    local s = style or DEFAULT_STYLE
    local color = s.connection and s.connection.color or DEFAULT_STYLE.connection.color
    local thickness = s.connection and s.connection.thickness or DEFAULT_STYLE.connection.thickness
    return UI.Panel {
        width = gapWidth, height = thickness,
        backgroundColor = color,
        borderRadius = 1,
        alignSelf = "center",
    }
end

--- 创建垂直连接线（包裹在nodeSize宽容器中居中）
local function CreateVLine(nodeSize, gapHeight, style)
    local s = style or DEFAULT_STYLE
    local color = s.connection and s.connection.color or DEFAULT_STYLE.connection.color
    local thickness = s.connection and s.connection.thickness or DEFAULT_STYLE.connection.thickness
    return UI.Panel {
        width = nodeSize, height = gapHeight,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = thickness, height = gapHeight,
                backgroundColor = color,
                borderRadius = 1,
            },
        }
    }
end

--- 预计算连接关系（支持对角线路径：自动拆分为垂直+水平两段）
local function ComputeConnections(levelPositions, gridRows)
    local hConn = {}
    local vConn = {}
    for r = 1, gridRows do
        hConn[r] = {}
        vConn[r] = {}
    end
    for i = 1, #levelPositions - 1 do
        local a = levelPositions[i]
        local b = levelPositions[i + 1]
        if a.row == b.row then
            -- 同行：水平连接
            local minCol = math.min(a.col, b.col)
            local maxCol = math.max(a.col, b.col)
            for c = minCol, maxCol - 1 do
                hConn[a.row][c] = true
            end
        elseif a.col == b.col then
            -- 同列：垂直连接
            local minRow = math.min(a.row, b.row)
            local maxRow = math.max(a.row, b.row)
            for r = minRow, maxRow - 1 do
                vConn[r][a.col] = true
            end
        else
            -- 对角线：拆分为先垂直(在起点列)再水平(在终点行)
            local minRow = math.min(a.row, b.row)
            local maxRow = math.max(a.row, b.row)
            for r = minRow, maxRow - 1 do
                vConn[r][a.col] = true
            end
            local minCol = math.min(a.col, b.col)
            local maxCol = math.max(a.col, b.col)
            for c = minCol, maxCol - 1 do
                hConn[b.row][c] = true
            end
        end
    end
    return hConn, vConn
end

function LevelSelectScene.Enter(params)
    local levelCount = LevelData.GetLevelCount()
    local unlockedCount = levelCount  -- 目前全部解锁

    -- 加载 JSON 配置
    local config = LoadLevelSelectConfig()
    local gridRows = 2
    local gridCols = 7
    local nodeSize = 52
    local gapSize = 20
    local levelPositions = DEFAULT_LEVEL_POSITIONS

    local style = DEFAULT_STYLE

    if config then
        gridRows = config.grid and config.grid.rows or gridRows
        gridCols = config.grid and config.grid.cols or gridCols
        nodeSize = config.grid and config.grid.nodeSize or nodeSize
        gapSize = config.grid and config.grid.gap or gapSize
        if config.path and #config.path > 0 then
            levelPositions = config.path
        end
        if config.style then
            style = config.style
        end
    end

    -- 获取第一关名字作为标题
    local firstLevel = LevelData.GetLevel(1)
    local levelName = firstLevel and firstLevel.name or "未知"

    -- 预计算连接
    local hConn, vConn = ComputeConnections(levelPositions, gridRows)

    -- === 顶部黑色条 ===
    local topBar = UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 20,
        paddingRight = 20,
        backgroundColor = { 0, 0, 0, 255 },
        children = {
            UI.Label {
                text = "LEVEL 1",
                fontSize = 16,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 255 },
            },
            UI.Label {
                text = string.upper(levelName),
                fontSize = 16,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 255 },
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Label {
                        text = "⭐",
                        fontSize = 14,
                    },
                    UI.Label {
                        text = "0/" .. tostring(levelCount * 3),
                        fontSize = 16,
                        fontColor = { 255, 255, 255, 255 },
                    },
                }
            },
        }
    }

    -- === 底部黑色条 ===
    local bottomBar = UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 255 },
        children = {
            UI.Button {
                text = "← 返回",
                variant = "ghost",
                height = 32,
                onClick = function(self)
                    SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
                end,
                fontColor = { 255, 255, 255, 255 },
            },
        }
    }

    -- === 中间关卡网格 ===
    local gridRowWidgets = {}

    for row = 1, gridRows do
        local rowChildren = {}
        for col = 1, gridCols do
            -- 查找该位置是否有关卡
            local levelIndex = nil
            for i, pos in ipairs(levelPositions) do
                if pos.row == row and pos.col == col then
                    levelIndex = i
                    break
                end
            end

            if levelIndex then
                local unlocked = (levelIndex <= unlockedCount)
                table.insert(rowChildren, CreateLevelNode(levelIndex, unlocked, nodeSize, style))
            else
                table.insert(rowChildren, UI.Panel { width = nodeSize, height = nodeSize })
            end

            -- 水平连接线
            if col < gridCols then
                if hConn[row][col] then
                    table.insert(rowChildren, CreateHLine(gapSize, style))
                else
                    table.insert(rowChildren, UI.Panel { width = gapSize, height = 3 })
                end
            end
        end

        table.insert(gridRowWidgets, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            children = rowChildren,
        })

        -- 行间垂直连接线
        if row < gridRows then
            local vLineChildren = {}
            for col = 1, gridCols do
                if vConn[row][col] then
                    table.insert(vLineChildren, CreateVLine(nodeSize, gapSize, style))
                else
                    table.insert(vLineChildren, UI.Panel { width = nodeSize, height = gapSize })
                end
                if col < gridCols then
                    table.insert(vLineChildren, UI.Panel { width = gapSize, height = gapSize })
                end
            end
            table.insert(gridRowWidgets, UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                children = vLineChildren,
            })
        end
    end

    local gridArea = UI.Panel {
        flex = 1,
        width = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 30, 35, 50, 255 },
        gap = 0,
        children = gridRowWidgets,
    }

    -- === 整体布局 ===
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 255 },
        children = {
            topBar,
            gridArea,
            bottomBar,
        }
    }

    UI.SetRoot(root)

    -- 注册 Update 事件驱动 tween 动画
    SubscribeToEvent("Update", "LevelSelectScene_HandleUpdate")
end

function LevelSelectScene_HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    UpdateTweens(dt)
end

function LevelSelectScene.Exit()
    UnsubscribeFromEvent("Update")
    ClearAllTweens()
    UI.SetRoot(nil)
end

SceneManager.Register(SceneManager.SCENE_LEVEL_SELECT, LevelSelectScene)

-- ============================================================================
-- 设置界面 (Settings)
-- ============================================================================

local SettingsScene = {}

function SettingsScene.Enter(params)
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 25, 28, 42, 255 },
        children = {
            UI.Panel {
                width = "90%",
                maxWidth = 400,
                padding = 32,
                gap = 16,
                alignItems = "center",
                backgroundColor = { 35, 40, 58, 240 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 80, 140, 255, 80 },
                children = {
                    UI.Label {
                        text = "设置",
                        fontSize = 28,
                        fontColor = { 255, 255, 255, 255 },
                        marginBottom = 8,
                    },
                    -- 音乐音量
                    UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = "音乐音量",
                                fontSize = 14,
                                fontColor = { 180, 190, 210, 220 },
                            },
                            UI.Slider {
                                value = Config.Settings.MusicVolume * 100,
                                min = 0,
                                max = 100,
                                width = "100%",
                                onChange = function(self, val)
                                    Config.Settings.MusicVolume = val / 100
                                end,
                            },
                        }
                    },
                    -- 音效音量
                    UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = "音效音量",
                                fontSize = 14,
                                fontColor = { 180, 190, 210, 220 },
                            },
                            UI.Slider {
                                value = Config.Settings.SFXVolume * 100,
                                min = 0,
                                max = 100,
                                width = "100%",
                                onChange = function(self, val)
                                    Config.Settings.SFXVolume = val / 100
                                end,
                            },
                        }
                    },
                    -- 游戏说明
                    UI.Panel { height = 8 },
                    UI.Panel {
                        width = "100%",
                        padding = 12,
                        backgroundColor = { 20, 24, 36, 200 },
                        borderRadius = 8,
                        children = {
                            UI.Label {
                                text = "玩法说明:\n" ..
                                    "· 方向键/WASD 移动，空格跳跃\n" ..
                                    "· 出生点计时器每圈生成一个克隆体\n" ..
                                    "· 克隆体会复刻你的全部操作\n" ..
                                    "· 所有角色到达终点即通关\n" ..
                                    "· 任何角色掉落或碰尖刺即失败",
                                fontSize = 12,
                                fontColor = { 160, 170, 190, 200 },
                            },
                        }
                    },
                    -- 返回按钮
                    UI.Panel { height = 12 },
                    UI.Button {
                        text = "返回",
                        variant = "primary",
                        width = 150,
                        height = 44,
                        onClick = function(self)
                            SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
                        end,
                    },
                }
            }
        }
    }
    UI.SetRoot(root)
end

function SettingsScene.Exit()
    UI.SetRoot(nil)
end

SceneManager.Register(SceneManager.SCENE_SETTINGS, SettingsScene)

return UIScenes

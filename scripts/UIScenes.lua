-- ============================================================================
-- UIScenes.lua - UI 界面模块
-- 包含：开始游戏界面（滚动天空背景）、关卡选择界面（JSON配置）、设置界面
-- 使用 urhox-libs/UI 控件库 - PixelForge 像素风格
-- ============================================================================

local UI = require("urhox-libs/UI")
local tween = require("tween")
local Config = require("Config")
local SceneManager = require("SceneManager")
local LevelData = require("LevelData")
local BGM = require("BGM")


local UIScenes = {}

-- ============================================================================
-- UI 点击音效（全局共享）
-- ============================================================================
local uiClickNode_ = nil
local uiClickSource_ = nil
local uiClickSound_ = nil

local function InitUIClickSound()
    if uiClickNode_ then return end
    uiClickNode_ = scene_ and scene_:CreateChild("UIClickSFX") or nil
    if not uiClickNode_ then
        -- 创建一个临时 scene 用于 UI 音效
        local tmpScene = Scene()
        uiClickNode_ = tmpScene:CreateChild("UIClickSFX")
    end
    uiClickSource_ = uiClickNode_:CreateComponent("SoundSource")
    uiClickSource_:SetSoundType("Effect")
    uiClickSound_ = cache:GetResource("Sound", "audio/sfx/ui_click.ogg")
end

local function PlayUIClick()
    if not uiClickSource_ then InitUIClickSound() end
    if uiClickSound_ and uiClickSource_ then
        local masterSfx = Config.Settings.SFXVolume or 0.4
        uiClickSource_:Play(uiClickSound_, uiClickSound_.frequency, 0.8 * masterSfx)
    end
end

-- 导出供其他模块使用
UIScenes.PlayUIClick = PlayUIClick

-- ============================================================================
-- PixelForge 像素风格主题色
-- ============================================================================
local PF = {
    bg       = { 15, 15, 35, 255 },        -- 深色背景
    surface  = { 27, 27, 58, 255 },        -- 面板背景
    surfaceH = { 37, 37, 80, 255 },        -- 面板悬浮
    primary  = { 33, 189, 174, 255 },      -- 主色 Teal
    primaryP = { 25, 168, 153, 255 },      -- 主色按下
    secondary = { 108, 92, 231, 255 },     -- 副色 紫
    text     = { 240, 240, 240, 255 },     -- 主文字
    textSec  = { 160, 160, 192, 255 },     -- 副文字
    border   = { 58, 58, 106, 255 },       -- 边框
    danger   = { 255, 71, 87, 255 },       -- 红
    gold     = { 255, 217, 61, 255 },      -- 金
    shadow   = { 10, 10, 26, 204 },        -- 阴影
}

-- ============================================================================
-- 木板告示牌按钮公共样式（九宫格拉伸）
-- ============================================================================
local WOODEN_BTN = {
    image = "image/wooden_btn.png",
    slice = {12, 10, 12, 10},        -- top, right, bottom, left (像素) - 透明背景版
    fit = "sliced",
    textColor = {55, 28, 5, 255},    -- 深棕色文字，木板上清晰
    fontWeight = "bold",
    bgColor = {0, 0, 0, 0},          -- 按钮本身透明
    shadow = {},                       -- 无阴影
}

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
-- 开始游戏界面 (Title Screen) - 像素风封面
-- ============================================================================

local TitleScene = {}

function TitleScene.Enter(params)
    -- 注册事件
    SubscribeToEvent("Update", "TitleScene_HandleUpdate")

    -- 重置编辑器按钮状态
    TitleScene._editorContainer = nil
    TitleScene._editorVisible = false

    -- UI 层 - 像素风标题 + 按钮（封面背景图）
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundImage = "image/edited_game_cover_beach_v3_20260530211652.png",
        backgroundFit = "cover",
        children = {
            -- 主内容区（无背景框）
            UI.Panel {
                gap = 12,
                alignItems = "center",
                children = {
                    -- 游戏 Logo
                    UI.Panel {
                        width = 300,
                        height = 300,
                        backgroundImage = "image/clone_piggy_logo_v3_20260531004006.png",
                        backgroundFit = "contain",
                    },
                    -- 开始按钮（像素风）
                    (function()
                        local proxy = { scale = 1.0 }
                        return UI.Button {
                            text = "开始游戏",
                            size = "xl",
                            width = 150,
                            height = 100,
                            backgroundImage = WOODEN_BTN.image,
                            backgroundFit = WOODEN_BTN.fit,
                            backgroundSlice = WOODEN_BTN.slice,
                            backgroundColor = WOODEN_BTN.bgColor,
                            boxShadow = WOODEN_BTN.shadow,
                            fontColor = WOODEN_BTN.textColor,
                            fontWeight = WOODEN_BTN.fontWeight,
                            fontSize = 12,
                            borderWidth = 0,
                            scale = 1.0,
                            onPointerEnter = function(ev, self)
                                AnimateScale(self, proxy, 1.08, "outBack", 0.2)
                            end,
                            onPointerLeave = function(ev, self)
                                AnimateScale(self, proxy, 1.0, "outQuad", 0.2)
                            end,
                            onPointerDown = function(ev, self)
                                AnimateScale(self, proxy, 0.95, "outQuart", 0.1)
                            end,
                            onPointerUp = function(ev, self)
                                AnimateScale(self, proxy, 1.08, "outBack", 0.15)
                            end,
                            onClick = function(self)
                                PlayUIClick()
                                SceneManager.SwitchTo(SceneManager.SCENE_LEVEL_SELECT)
                            end,
                        }
                    end)(),
                    -- 设置按钮（像素风）
                    (function()
                        local proxy = { scale = 1.0 }
                        return UI.Button {
                            text = "设置",
                            size = "xl",
                            width = 150,
                            height = 100,
                            backgroundImage = WOODEN_BTN.image,
                            backgroundFit = WOODEN_BTN.fit,
                            backgroundSlice = WOODEN_BTN.slice,
                            backgroundColor = WOODEN_BTN.bgColor,
                            boxShadow = WOODEN_BTN.shadow,
                            fontColor = WOODEN_BTN.textColor,
                            fontWeight = WOODEN_BTN.fontWeight,
                            fontSize = 12,
                            borderWidth = 0,
                            scale = 1.0,
                            onPointerEnter = function(ev, self)
                                AnimateScale(self, proxy, 1.08, "outBack", 0.2)
                            end,
                            onPointerLeave = function(ev, self)
                                AnimateScale(self, proxy, 1.0, "outQuad", 0.2)
                            end,
                            onPointerDown = function(ev, self)
                                AnimateScale(self, proxy, 0.95, "outQuart", 0.1)
                            end,
                            onPointerUp = function(ev, self)
                                AnimateScale(self, proxy, 1.08, "outBack", 0.15)
                            end,
                            onClick = function(self)
                                PlayUIClick()
                                SceneManager.SwitchTo(SceneManager.SCENE_SETTINGS)
                            end,
                        }
                    end)(),
                    -- 关卡编辑器按钮容器（默认隐藏，按L键显示）
                    (function()
                        local proxy = { scale = 1.0 }
                        local container = UI.Panel {
                            width = 150,
                            height = 0,
                            overflow = "hidden",
                            alignItems = "center",
                            children = {
                                UI.Button {
                                    text = "关卡编辑器",
                                    size = "xl",
                                    width = 150,
                                    height = 100,
                                    backgroundImage = WOODEN_BTN.image,
                                    backgroundFit = WOODEN_BTN.fit,
                                    backgroundSlice = WOODEN_BTN.slice,
                                    backgroundColor = WOODEN_BTN.bgColor,
                                    boxShadow = WOODEN_BTN.shadow,
                                    fontColor = WOODEN_BTN.textColor,
                                    fontWeight = WOODEN_BTN.fontWeight,
                                    fontSize = 12,
                                    borderWidth = 0,
                                    scale = 1.0,
                                    onPointerEnter = function(ev, self)
                                        AnimateScale(self, proxy, 1.08, "outBack", 0.2)
                                    end,
                                    onPointerLeave = function(ev, self)
                                        AnimateScale(self, proxy, 1.0, "outQuad", 0.2)
                                    end,
                                    onPointerDown = function(ev, self)
                                        AnimateScale(self, proxy, 0.95, "outQuart", 0.1)
                                    end,
                                    onPointerUp = function(ev, self)
                                        AnimateScale(self, proxy, 1.08, "outBack", 0.15)
                                    end,
                                    onClick = function(self)
                                        PlayUIClick()
                                        SceneManager.SwitchTo(SceneManager.SCENE_EDITOR)
                                    end,
                                },
                            }
                        }
                        TitleScene._editorContainer = container
                        return container
                    end)(),
                }
            },
            -- 右下角版本号和作者
            UI.Panel {
                position = "absolute",
                bottom = 12,
                right = 12,
                alignItems = "flex-end",
                gap = 2,
                children = {
                    UI.Label {
                        text = "By DimSum",
                        fontSize = 10,
                        fontColor = { 240, 240, 240, 200 },
                    },
                    UI.Label {
                        text = "v" .. Config.Version,
                        fontSize = 10,
                        fontColor = { 240, 240, 240, 160 },
                    },
                }
            },
        }
    }
    UI.SetRoot(root)

    -- 编辑器按钮容器初始高度=0，已隐藏
end

function TitleScene.Exit()
    UnsubscribeFromEvent("Update")
    ClearAllTweens()
    UI.SetRoot(nil)
end

SceneManager.Register(SceneManager.SCENE_TITLE, TitleScene)

-- Title 全局事件回调
function TitleScene_HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    UpdateTweens(dt)
    BGM.Tick()

    -- 按 L 键切换显示关卡编辑器按钮
    if input:GetKeyPress(KEY_L) then
        local container = TitleScene._editorContainer
        if container then
            if TitleScene._editorVisible then
                container:SetStyle({ height = 0 })
                TitleScene._editorVisible = false
            else
                container:SetStyle({ height = 100 })
                TitleScene._editorVisible = true
            end
        end
    end
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

-- 默认样式（像素风）
local DEFAULT_STYLE = {
    unlocked = { backgroundColor = PF.primary, borderColor = PF.primaryP, textColor = PF.text },
    locked = { backgroundColor = { 0, 0, 0, 0 }, borderColor = PF.border, icon = "🔒" },
    connection = { color = PF.textSec, thickness = 3 },
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
            borderRadius = 0,
            borderWidth = 2,
            borderColor = bdColor,
            scale = 1.0,
            onPointerEnter = function(ev, self)
                AnimateScale(self, proxy, 1.1, "outBack", 0.2)
            end,
            onPointerLeave = function(ev, self)
                AnimateScale(self, proxy, 1.0, "outQuad", 0.2)
                self:SetProp("backgroundColor", bgColor)
            end,
            onPointerDown = function(ev, self)
                AnimateScale(self, proxy, 0.95, "outQuart", 0.1)
                self:SetProp("backgroundColor", PF.surfaceH)
            end,
            onPointerUp = function(ev, self)
                AnimateScale(self, proxy, 1.1, "outBack", 0.15)
                self:SetProp("backgroundColor", bgColor)
            end,
            onClick = function(self)
                PlayUIClick()
                SceneManager.SwitchTo(SceneManager.SCENE_GAME, { level = index })
            end,
            children = {
                UI.Label {
                    text = tostring(index),
                    fontSize = math.floor(nodeSize * 0.42),
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
            borderRadius = 0,
            borderWidth = 2,
            borderColor = bdColor,
            children = {
                UI.Label {
                    text = icon,
                    fontSize = math.floor(nodeSize * 0.38),
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
        borderRadius = 0,
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
                borderRadius = 0,
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
    local Progress = require("Progress")
    local unlockedCount = math.min(Progress.GetUnlockedLevel(), levelCount)

    -- 暂时只显示前5关（后续关卡隐藏，不是删除）
    local MAX_VISIBLE_LEVELS = 5
    levelCount = math.min(levelCount, MAX_VISIBLE_LEVELS)
    unlockedCount = math.min(unlockedCount, MAX_VISIBLE_LEVELS)

    -- 加载 JSON 配置
    local config = LoadLevelSelectConfig()
    local gridRows = 2
    local gridCols = 7
    local baseNodeSize = 52
    local baseGapSize = 20
    local levelPositions = DEFAULT_LEVEL_POSITIONS

    -- 1.5倍缩放，根据屏幕宽度自适应
    local screenW = graphics:GetWidth() / graphics:GetDPR()
    local scaleFactor = 1.5
    -- 确保放大后不会超出屏幕（预留左右边距40px）
    local maxGridWidth = screenW - 40
    local nodeSize = math.floor(baseNodeSize * scaleFactor)
    local gapSize = math.floor(baseGapSize * scaleFactor)

    local style = DEFAULT_STYLE

    if config then
        gridRows = config.grid and config.grid.rows or gridRows
        gridCols = config.grid and config.grid.cols or gridCols
        if config.grid and config.grid.nodeSize then
            nodeSize = math.floor(config.grid.nodeSize * scaleFactor)
        end
        if config.grid and config.grid.gap then
            gapSize = math.floor(config.grid.gap * scaleFactor)
        end
        if config.path and #config.path > 0 then
            levelPositions = config.path
        end
        if config.style then
            style = config.style
        end
    end

    -- 裁剪路径只保留可见关卡数量
    if #levelPositions > MAX_VISIBLE_LEVELS then
        local trimmed = {}
        for i = 1, MAX_VISIBLE_LEVELS do
            trimmed[i] = levelPositions[i]
        end
        levelPositions = trimmed
        -- 自动缩减网格列数
        local maxCol = 1
        for _, pos in ipairs(levelPositions) do
            if pos.col > maxCol then maxCol = pos.col end
        end
        gridCols = maxCol
    end

    -- 根据实际列数检查是否超出屏幕，若超出则缩小
    local totalGridWidth = gridCols * nodeSize + (gridCols - 1) * gapSize
    if totalGridWidth > maxGridWidth and maxGridWidth > 0 then
        local shrink = maxGridWidth / totalGridWidth
        nodeSize = math.floor(nodeSize * shrink)
        gapSize = math.floor(gapSize * shrink)
    end

    -- 获取第一关信息
    local firstLevel = LevelData.GetLevel(1)

    -- 预计算连接
    local hConn, vConn = ComputeConnections(levelPositions, gridRows)

    -- === 顶部条（像素风） ===
    local topBar = UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 20,
        paddingRight = 20,
        backgroundColor = PF.surface,
        borderBottomWidth = 2,
        borderColor = PF.border,
        children = {
            UI.Label {
                text = "LEVEL 1",
                fontSize = 16,
                fontWeight = "bold",
                fontColor = PF.primary,
            },
            -- 中间：金币数
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = "🪙",
                        fontSize = 16,
                    },
                    UI.Label {
                        text = "0",
                        fontSize = 16,
                        fontWeight = "bold",
                        fontColor = PF.gold,
                    },
                }
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
                        fontColor = PF.gold,
                    },
                }
            },
        }
    }

    -- === 底部条（像素风） ===
    local bottomBar = UI.Panel {
        width = "100%",
        paddingTop = 8,
        paddingBottom = 12,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = PF.surface,
        borderTopWidth = 2,
        borderColor = PF.border,
        children = {
            (function()
                local proxy = { scale = 1.0 }
                return UI.Button {
                    text = "< 返回",
                    size = "xl",
                    width = 150,
                    height = 100,
                    backgroundImage = WOODEN_BTN.image,
                    backgroundFit = WOODEN_BTN.fit,
                    backgroundSlice = WOODEN_BTN.slice,
                    backgroundColor = WOODEN_BTN.bgColor,
                    boxShadow = WOODEN_BTN.shadow,
                    fontColor = WOODEN_BTN.textColor,
                    fontWeight = WOODEN_BTN.fontWeight,
                    fontSize = 12,
                    borderWidth = 0,
                    scale = 1.0,
                    onPointerEnter = function(ev, self)
                        AnimateScale(self, proxy, 1.08, "outBack", 0.2)
                    end,
                    onPointerLeave = function(ev, self)
                        AnimateScale(self, proxy, 1.0, "outQuad", 0.2)
                    end,
                    onPointerDown = function(ev, self)
                        AnimateScale(self, proxy, 0.95, "outQuart", 0.1)
                    end,
                    onPointerUp = function(ev, self)
                        AnimateScale(self, proxy, 1.08, "outBack", 0.15)
                    end,
                    onClick = function(self)
                        PlayUIClick()
                        SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
                    end,
                }
            end)(),
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
        backgroundColor = PF.bg,
        gap = 0,
        children = gridRowWidgets,
    }

    -- === 整体布局 ===
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = PF.bg,
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
    BGM.Tick()
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
        backgroundColor = PF.bg,
        children = {
            UI.Panel {
                width = "90%",
                maxWidth = 400,
                padding = 24,
                gap = 14,
                alignItems = "center",
                backgroundColor = PF.surface,
                borderRadius = 0,
                borderWidth = 3,
                borderColor = PF.border,
                children = {
                    UI.Label {
                        text = "设置",
                        fontSize = 24,
                        fontWeight = "bold",
                        fontColor = PF.primary,
                        marginBottom = 6,
                    },
                    -- 音乐音量
                    UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = "音乐音量",
                                fontSize = 12,
                                fontColor = PF.textSec,
                            },
                            UI.Slider {
                                value = Config.Settings.MusicVolume * 100,
                                min = 0,
                                max = 100,
                                width = "100%",
                                onChange = function(self, val)
                                    BGM.SetVolume(val / 100)
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
                                fontSize = 12,
                                fontColor = PF.textSec,
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
                    UI.Panel { height = 6 },
                    UI.Panel {
                        width = "100%",
                        padding = 12,
                        backgroundColor = PF.bg,
                        borderRadius = 0,
                        borderWidth = 2,
                        borderColor = PF.border,
                        children = {
                            UI.Label {
                                text = "玩法说明:\n" ..
                                    "· 方向键/WASD 移动，空格跳跃\n" ..
                                    "· 出生点计时器每圈生成一个克隆体\n" ..
                                    "· 克隆体会复刻你的全部操作\n" ..
                                    "· 所有角色到达终点即通关\n" ..
                                    "· 任何角色掉落或碰尖刺即失败",
                                fontSize = 10,
                                fontColor = PF.textSec,
                            },
                        }
                    },
                    -- 返回按钮
                    UI.Panel { height = 10 },
                    UI.Button {
                        text = "返回",
                        width = 150,
                        height = 72,
                        backgroundImage = WOODEN_BTN.image,
                        backgroundFit = WOODEN_BTN.fit,
                        backgroundSlice = WOODEN_BTN.slice,
                        backgroundColor = WOODEN_BTN.bgColor,
                        boxShadow = WOODEN_BTN.shadow,
                        fontColor = WOODEN_BTN.textColor,
                        fontWeight = WOODEN_BTN.fontWeight,
                        fontSize = 12,
                        borderWidth = 0,
                        onClick = function(self)
                            PlayUIClick()
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

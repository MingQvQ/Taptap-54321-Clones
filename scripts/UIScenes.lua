-- ============================================================================
-- UIScenes.lua - UI 界面模块
-- 包含：开始游戏界面（滚动天空背景）、关卡选择界面（JSON配置）、设置界面
-- 使用 urhox-libs/UI 控件库
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local SceneManager = require("SceneManager")
local LevelData = require("LevelData")

local UIScenes = {}

-- ============================================================================
-- 开始游戏界面 (Title Screen) - 滚动天空背景 + 克隆人标题
-- ============================================================================

local TitleScene = {}

---@type NVGContextWrapper
local titleNvg_ = nil
local titleScrollOffset_ = 0
local titleBgTexture_ = nil
local titleBgW_ = 0
local titleBgH_ = 0

function TitleScene.Enter(params)
    -- 创建 NanoVG 上下文用于滚动背景
    titleNvg_ = nvgCreate(1)
    titleScrollOffset_ = 0

    -- 预加载天空背景纹理
    local bgImg = nvgCreateImage(titleNvg_, "image/sky_bg_20260530074148.png", 0)
    titleBgTexture_ = bgImg
    -- 获取图片尺寸
    titleBgW_, titleBgH_ = nvgImageSize(titleNvg_, bgImg)

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
                    -- 开始按钮
                    UI.Button {
                        text = "开始游戏",
                        variant = "primary",
                        width = 200,
                        height = 48,
                        onClick = function(self)
                            SceneManager.SwitchTo(SceneManager.SCENE_LEVEL_SELECT)
                        end,
                    },
                    -- 设置按钮
                    UI.Button {
                        text = "设置",
                        variant = "outline",
                        width = 200,
                        height = 44,
                        onClick = function(self)
                            SceneManager.SwitchTo(SceneManager.SCENE_SETTINGS)
                        end,
                    },
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
    end
    UI.SetRoot(nil)
    titleNvg_ = nil
    titleBgTexture_ = nil
end

SceneManager.Register(SceneManager.SCENE_TITLE, TitleScene)

-- Title 全局事件回调
function TitleScene_HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    -- 背景从右向左滚动，速度约 30 像素/秒
    titleScrollOffset_ = titleScrollOffset_ + dt * 30
end

function TitleScene_HandleRender(eventType, eventData)
    if not titleNvg_ or not titleBgTexture_ then return end

    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr

    nvgBeginFrame(titleNvg_, logW, logH, dpr)

    -- 计算背景绘制参数：保持纵横比覆盖全屏高度
    local drawH = logH
    local drawW = drawH * (titleBgW_ / titleBgH_)

    -- 滚动偏移（循环）
    local offset = titleScrollOffset_ % drawW

    -- 绘制两份实现无缝循环
    local paint1 = nvgImagePattern(titleNvg_, -offset, 0, drawW, drawH, 0, titleBgTexture_, 1.0)
    nvgBeginPath(titleNvg_)
    nvgRect(titleNvg_, -offset, 0, drawW, drawH)
    nvgFillPaint(titleNvg_, paint1)
    nvgFill(titleNvg_)

    local paint2 = nvgImagePattern(titleNvg_, -offset + drawW, 0, drawW, drawH, 0, titleBgTexture_, 1.0)
    nvgBeginPath(titleNvg_)
    nvgRect(titleNvg_, -offset + drawW, 0, drawW, drawH)
    nvgFillPaint(titleNvg_, paint2)
    nvgFill(titleNvg_)

    -- 如果还有空隙，绘制第三份
    if -offset + drawW * 2 < logW then
        local paint3 = nvgImagePattern(titleNvg_, -offset + drawW * 2, 0, drawW, drawH, 0, titleBgTexture_, 1.0)
        nvgBeginPath(titleNvg_)
        nvgRect(titleNvg_, -offset + drawW * 2, 0, drawW, drawH)
        nvgFillPaint(titleNvg_, paint3)
        nvgFill(titleNvg_)
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

-- 默认路径配置（当 JSON 加载失败时）
local DEFAULT_LEVEL_POSITIONS = {
    { row = 2, col = 1 },
    { row = 2, col = 2 },
    { row = 2, col = 3 },
    { row = 1, col = 3 },
    { row = 1, col = 4 },
    { row = 1, col = 5 },
    { row = 2, col = 5 },
    { row = 3, col = 5 },
    { row = 3, col = 4 },
    { row = 3, col = 3 },
    { row = 3, col = 2 },
    { row = 3, col = 1 },
}

--- 创建关卡节点
local function CreateLevelNode(index, unlocked, nodeSize)
    if unlocked then
        return UI.Panel {
            width = nodeSize, height = nodeSize,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = { 180, 40, 50, 255 },
            borderRadius = 6,
            borderWidth = 2,
            borderColor = { 220, 60, 70, 255 },
            onClick = function(self)
                SceneManager.SwitchTo(SceneManager.SCENE_GAME, { level = index })
            end,
            children = {
                UI.Label {
                    text = tostring(index),
                    fontSize = 22,
                    fontWeight = "bold",
                    fontColor = { 255, 255, 255, 255 },
                },
            }
        }
    else
        return UI.Panel {
            width = nodeSize, height = nodeSize,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = { 60, 60, 60, 120 },
            borderRadius = 6,
            borderWidth = 2,
            borderColor = { 150, 150, 150, 120 },
            children = {
                UI.Label {
                    text = "🔒",
                    fontSize = 20,
                },
            }
        }
    end
end

--- 创建水平连接线
local function CreateHLine(gapWidth)
    return UI.Panel {
        width = gapWidth, height = 3,
        backgroundColor = { 180, 180, 180, 150 },
        borderRadius = 1,
        alignSelf = "center",
    }
end

--- 创建垂直连接线（包裹在nodeSize宽容器中居中）
local function CreateVLine(nodeSize, gapHeight)
    return UI.Panel {
        width = nodeSize, height = gapHeight,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 3, height = gapHeight,
                backgroundColor = { 180, 180, 180, 150 },
                borderRadius = 1,
            },
        }
    }
end

--- 预计算连接关系
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
            local minCol = math.min(a.col, b.col)
            local maxCol = math.max(a.col, b.col)
            for c = minCol, maxCol - 1 do
                hConn[a.row][c] = true
            end
        elseif a.col == b.col then
            local minRow = math.min(a.row, b.row)
            local maxRow = math.max(a.row, b.row)
            for r = minRow, maxRow - 1 do
                vConn[r][a.col] = true
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
    local gridRows = 3
    local gridCols = 5
    local nodeSize = 52
    local gapSize = 20
    local levelPositions = DEFAULT_LEVEL_POSITIONS

    if config then
        gridRows = config.grid and config.grid.rows or gridRows
        gridCols = config.grid and config.grid.cols or gridCols
        nodeSize = config.grid and config.grid.nodeSize or nodeSize
        gapSize = config.grid and config.grid.gap or gapSize
        if config.path and #config.path > 0 then
            levelPositions = config.path
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
                table.insert(rowChildren, CreateLevelNode(levelIndex, unlocked, nodeSize))
            else
                table.insert(rowChildren, UI.Panel { width = nodeSize, height = nodeSize })
            end

            -- 水平连接线
            if col < gridCols then
                if hConn[row][col] then
                    table.insert(rowChildren, CreateHLine(gapSize))
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
                    table.insert(vLineChildren, CreateVLine(nodeSize, gapSize))
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
end

function LevelSelectScene.Exit()
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

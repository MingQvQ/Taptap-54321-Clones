-- ============================================================================
-- LevelEditorUI.lua - 关卡编辑器 UI 与交互逻辑
-- 顶部工具栏（当前选中瓦片）、左侧瓦片库、底部操作按钮
-- 集成 TilemapData + TilemapRenderer，处理鼠标绘制
-- ============================================================================

local UI = require("urhox-libs/UI")
local TilemapData = require("LevelEditor.TilemapData")
local TilemapRenderer = require("LevelEditor.TilemapRenderer")
local SceneManager = require("SceneManager")

local LevelEditorUI = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local nvg_ = nil
local currentTileId_ = TilemapData.TILE_GROUND  -- 默认选中地面
local layout_ = nil   -- 渲染布局缓存
local isDrawing_ = false  -- 鼠标是否按下中

-- UI 引用
local selectedLabel_ = nil
local paletteButtons_ = {}

-- UI 边距（与 TilemapRenderer 对齐）
local UI_MARGINS = { top = 48, bottom = 52, left = 72, right = 12 }

-- ============================================================================
-- 文件操作
-- ============================================================================

--- 保存地图到 JSON 文件
local function SaveToJSON()
    local data = TilemapData.Serialize()
    local json = cjson.encode(data)
    local file = File("LevelEditor/tilemap_save.json", FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(json)
        file:Close()
        log:Write(LOG_INFO, "[LevelEditor] Saved tilemap to LevelEditor/tilemap_save.json")
    else
        log:Write(LOG_ERROR, "[LevelEditor] Failed to open file for writing")
    end
end

--- 从 JSON 文件加载地图
local function LoadFromJSON()
    local path = "LevelEditor/tilemap_save.json"
    if not fileSystem:FileExists(path) then
        log:Write(LOG_WARNING, "[LevelEditor] No save file found: " .. path)
        return false
    end
    local file = File(path, FILE_READ)
    if not file:IsOpen() then
        log:Write(LOG_ERROR, "[LevelEditor] Failed to open file for reading")
        return false
    end
    local content = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        log:Write(LOG_ERROR, "[LevelEditor] JSON parse error: " .. tostring(data))
        return false
    end
    TilemapData.Deserialize(data)
    log:Write(LOG_INFO, "[LevelEditor] Loaded tilemap from " .. path)
    return true
end

-- ============================================================================
-- 瓦片选择
-- ============================================================================

--- 切换当前选中瓦片
local function SelectTile(tileId)
    currentTileId_ = tileId
    -- 更新顶部标签
    if selectedLabel_ then
        local info = TilemapData.GetTileInfo(tileId)
        selectedLabel_:SetText(info.icon .. " " .. info.name)
    end
    -- 更新调色板按钮高亮
    for id, btn in pairs(paletteButtons_) do
        if id == tileId then
            btn:SetProp("borderColor", { 255, 255, 100, 255 })
            btn:SetProp("borderWidth", 3)
        else
            btn:SetProp("borderColor", { 80, 90, 110, 200 })
            btn:SetProp("borderWidth", 1)
        end
    end
end

-- ============================================================================
-- 场景生命周期（注册为 SceneManager 场景）
-- ============================================================================

function LevelEditorUI.Enter(params)
    -- 初始化空白地图
    TilemapData.New(16, 12)

    -- 创建 NanoVG 上下文
    nvg_ = nvgCreate(1)
    nvgCreateFont(nvg_, "sans", "Fonts/MiSans-Regular.ttf")

    -- 构建 UI
    LevelEditorUI.BuildUI()

    -- 注册事件
    SubscribeToEvent("Update", "LevelEditor_HandleUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "LevelEditor_HandleRender")
    SubscribeToEvent("MouseButtonDown", "LevelEditor_HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "LevelEditor_HandleMouseUp")

    -- 默认选中地面
    SelectTile(TilemapData.TILE_GROUND)
end

function LevelEditorUI.Exit()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("MouseButtonDown")
    UnsubscribeFromEvent("MouseButtonUp")
    if nvg_ then
        UnsubscribeFromEvent(nvg_, "NanoVGRender")
    end
    UI.SetRoot(nil)
    nvg_ = nil
    layout_ = nil
    selectedLabel_ = nil
    paletteButtons_ = {}
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function LevelEditorUI.BuildUI()
    -- 瓦片调色板按钮列表（左侧）
    local paletteChildren = {}
    local tileIds = {
        TilemapData.TILE_GROUND,
        TilemapData.TILE_PLATFORM,
        TilemapData.TILE_SPIKE,
        TilemapData.TILE_COIN,
    }
    for _, tileId in ipairs(tileIds) do
        local info = TilemapData.GetTileInfo(tileId)
        local btn = UI.Panel {
            width = 52, height = 52,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = { info.color[1], info.color[2], info.color[3], 180 },
            borderRadius = 8,
            borderWidth = 1,
            borderColor = { 80, 90, 110, 200 },
            onClick = function(self)
                SelectTile(tileId)
            end,
            children = {
                UI.Label {
                    text = info.icon,
                    fontSize = 22,
                },
                UI.Label {
                    text = info.name,
                    fontSize = 10,
                    fontColor = { 255, 255, 255, 200 },
                },
            },
        }
        paletteButtons_[tileId] = btn
        table.insert(paletteChildren, btn)
    end

    -- 橡皮擦按钮
    local eraserBtn = UI.Panel {
        width = 52, height = 52,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 60, 60, 70, 180 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 80, 90, 110, 200 },
        onClick = function(self)
            SelectTile(TilemapData.TILE_EMPTY)
        end,
        children = {
            UI.Label { text = "🧹", fontSize = 22 },
            UI.Label { text = "擦除", fontSize = 10, fontColor = { 255, 255, 255, 200 } },
        },
    }
    paletteButtons_[TilemapData.TILE_EMPTY] = eraserBtn
    table.insert(paletteChildren, eraserBtn)

    -- === 顶部工具栏 ===
    local defaultInfo = TilemapData.GetTileInfo(currentTileId_)
    selectedLabel_ = UI.Label {
        text = defaultInfo.icon .. " " .. defaultInfo.name,
        fontSize = 16,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
    }

    local topBar = UI.Panel {
        width = "100%",
        height = UI_MARGINS.top,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 16,
        paddingRight = 16,
        backgroundColor = { 20, 22, 34, 240 },
        borderColor = { 60, 70, 100, 100 },
        borderWidth = 0,
        children = {
            UI.Label {
                text = "关卡编辑器",
                fontSize = 16,
                fontColor = { 180, 200, 240, 255 },
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label { text = "当前:", fontSize = 13, fontColor = { 150, 160, 180, 200 } },
                    selectedLabel_,
                },
            },
            UI.Label {
                text = TilemapData.gridWidth .. "×" .. TilemapData.gridHeight,
                fontSize = 13,
                fontColor = { 120, 130, 150, 180 },
            },
        },
    }

    -- === 左侧瓦片库 ===
    local leftPanel = UI.Panel {
        width = UI_MARGINS.left,
        height = "100%",
        paddingTop = 8,
        paddingBottom = 8,
        gap = 8,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 20, 22, 34, 200 },
        children = paletteChildren,
    }

    -- === 底部操作栏 ===
    local bottomBar = UI.Panel {
        width = "100%",
        height = UI_MARGINS.bottom,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 16,
        backgroundColor = { 20, 22, 34, 240 },
        children = {
            UI.Button {
                text = "💾 保存",
                variant = "primary",
                height = 36,
                onClick = function(self)
                    SaveToJSON()
                end,
            },
            UI.Button {
                text = "📂 加载",
                variant = "outline",
                height = 36,
                onClick = function(self)
                    LoadFromJSON()
                end,
            },
            UI.Button {
                text = "🧹 清空",
                variant = "danger",
                height = 36,
                onClick = function(self)
                    TilemapData.Clear()
                end,
            },
            UI.Button {
                text = "▶ 测试",
                variant = "success",
                height = 36,
                onClick = function(self)
                    -- TODO: 跳转到游戏场景测试当前编辑的关卡
                    log:Write(LOG_INFO, "[LevelEditor] Test level (TODO)")
                end,
            },
            UI.Button {
                text = "← 返回",
                variant = "ghost",
                height = 36,
                onClick = function(self)
                    SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
                end,
                fontColor = { 200, 210, 230, 220 },
            },
        },
    }

    -- === 整体布局 ===
    -- 使用绝对定位：顶部固定、左侧固定、底部固定
    -- 中间区域留给 NanoVG 绘制（不放 UI 组件）
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        children = {
            -- 顶部
            topBar,
            -- 中间行：左侧面板 + 空白（NanoVG 绘制区）
            UI.Panel {
                flex = 1,
                width = "100%",
                flexDirection = "row",
                children = {
                    leftPanel,
                    -- 右侧空白区域（NanoVG 负责渲染）
                    UI.Panel { flex = 1 },
                },
            },
            -- 底部
            bottomBar,
        },
    }

    UI.SetRoot(root)
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function LevelEditor_HandleUpdate(eventType, eventData)
    -- 更新布局缓存
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr
    layout_ = TilemapRenderer.CalcLayout(logW, logH, UI_MARGINS)

    -- 获取鼠标位置，更新悬停格子
    local mouseX = input.mousePosition.x / dpr
    local mouseY = input.mousePosition.y / dpr
    local row, col = TilemapRenderer.ScreenToGrid(mouseX, mouseY, layout_)
    TilemapRenderer.hoverRow = row
    TilemapRenderer.hoverCol = col

    -- 鼠标按住拖动绘制
    if isDrawing_ then
        TilemapData.SetCell(row, col, currentTileId_)
    end
end

function LevelEditor_HandleRender(eventType, eventData)
    if not nvg_ or not layout_ then return end

    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr

    nvgBeginFrame(nvg_, logW, logH, dpr)
    TilemapRenderer.Draw(nvg_, layout_)
    nvgEndFrame(nvg_)
end

function LevelEditor_HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_LEFT then
        isDrawing_ = true
        -- 立即绘制当前格
        if layout_ then
            local dpr = graphics:GetDPR()
            local mouseX = input.mousePosition.x / dpr
            local mouseY = input.mousePosition.y / dpr
            local row, col = TilemapRenderer.ScreenToGrid(mouseX, mouseY, layout_)
            TilemapData.SetCell(row, col, currentTileId_)
        end
    elseif button == MOUSEB_RIGHT then
        -- 右键擦除
        if layout_ then
            local dpr = graphics:GetDPR()
            local mouseX = input.mousePosition.x / dpr
            local mouseY = input.mousePosition.y / dpr
            local row, col = TilemapRenderer.ScreenToGrid(mouseX, mouseY, layout_)
            TilemapData.SetCell(row, col, TilemapData.TILE_EMPTY)
        end
    end
end

function LevelEditor_HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_LEFT then
        isDrawing_ = false
    end
end

-- 注册为场景（需要在 SceneManager 中添加对应常量）
if SceneManager.SCENE_EDITOR then
    SceneManager.Register(SceneManager.SCENE_EDITOR, LevelEditorUI)
end

return LevelEditorUI

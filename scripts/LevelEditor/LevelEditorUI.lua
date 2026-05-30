-- ============================================================================
-- LevelEditorUI.lua - 关卡编辑器 UI 与交互逻辑（v2）
-- 双分类面板（瓦片 / 预制体）、地图大小调节、文件操作
-- 集成 TilemapData v2 + TilemapRenderer v2
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
local layout_ = nil       -- 渲染布局缓存
local isDrawing_ = false  -- 鼠标是否按下中

--- 编辑模式: "tile" 或 "prefab"
local editMode_ = "tile"

--- 当前选中的瓦片 ID（editMode_ == "tile" 时使用）
local currentTileId_ = 1

--- 当前选中的预制体 ID（editMode_ == "prefab" 时使用）
local currentPrefabId_ = 1

-- UI 引用
local selectedLabel_ = nil
local sizeLabel_ = nil
local tilePalettePanel_ = nil
local prefabPalettePanel_ = nil
local tileModeBtn_ = nil
local prefabModeBtn_ = nil

-- UI 边距（与 TilemapRenderer 对齐）
local UI_MARGINS = { top = 48, bottom = 52, left = 80, right = 12 }

-- ============================================================================
-- UI 更新辅助（需在文件操作前定义，因为 Load 会调用）
-- ============================================================================

--- 更新顶部选中标签
local function UpdateSelectedLabel()
    if not selectedLabel_ then return end
    if editMode_ == "tile" then
        local info = TilemapData.GetTileInfo(currentTileId_)
        selectedLabel_:SetText("🧱 " .. info.name)
    else
        local info = TilemapData.GetPrefabInfo(currentPrefabId_)
        selectedLabel_:SetText(info.icon .. " " .. info.name)
    end
end

--- 更新地图大小标签
local function UpdateSizeLabel()
    if sizeLabel_ then
        sizeLabel_:SetText(TilemapData.gridWidth .. "×" .. TilemapData.gridHeight)
    end
end

-- ============================================================================
-- 文件操作
-- ============================================================================

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
    TilemapRenderer.ClearImageCache()
    -- 更新 UI 显示
    UpdateSizeLabel()
    UpdateSelectedLabel()
    log:Write(LOG_INFO, "[LevelEditor] Loaded tilemap from " .. path)
    return true
end

--- 切换编辑模式
local function SetEditMode(mode)
    editMode_ = mode
    -- 切换面板可见性
    if tilePalettePanel_ and prefabPalettePanel_ then
        if mode == "tile" then
            tilePalettePanel_:SetProp("display", "flex")
            prefabPalettePanel_:SetProp("display", "none")
        else
            tilePalettePanel_:SetProp("display", "none")
            prefabPalettePanel_:SetProp("display", "flex")
        end
    end
    -- 更新 tab 按钮样式
    if tileModeBtn_ and prefabModeBtn_ then
        if mode == "tile" then
            tileModeBtn_:SetProp("backgroundColor", { 70, 130, 220, 255 })
            prefabModeBtn_:SetProp("backgroundColor", { 50, 55, 70, 200 })
        else
            tileModeBtn_:SetProp("backgroundColor", { 50, 55, 70, 200 })
            prefabModeBtn_:SetProp("backgroundColor", { 70, 130, 220, 255 })
        end
    end
    UpdateSelectedLabel()
end

-- ============================================================================
-- 场景生命周期
-- ============================================================================

function LevelEditorUI.Enter(params)
    TilemapData.New(16, 12)

    nvg_ = nvgCreate(1)
    nvgCreateFont(nvg_, "sans", "Fonts/MiSans-Regular.ttf")

    LevelEditorUI.BuildUI()

    SubscribeToEvent("Update", "LevelEditor_HandleUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "LevelEditor_HandleRender")
    SubscribeToEvent("MouseButtonDown", "LevelEditor_HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "LevelEditor_HandleMouseUp")

    -- 默认选中瓦片模式，草地
    SetEditMode("tile")
end

function LevelEditorUI.Exit()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("MouseButtonDown")
    UnsubscribeFromEvent("MouseButtonUp")
    if nvg_ then
        UnsubscribeFromEvent(nvg_, "NanoVGRender")
    end
    UI.SetRoot(nil)
    TilemapRenderer.ClearImageCache()
    nvg_ = nil
    layout_ = nil
    selectedLabel_ = nil
    sizeLabel_ = nil
    tilePalettePanel_ = nil
    prefabPalettePanel_ = nil
    tileModeBtn_ = nil
    prefabModeBtn_ = nil
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function LevelEditorUI.BuildUI()
    -- === 瓦片调色板 ===
    local tileChildren = {}
    -- 橡皮擦
    local eraserTileBtn = UI.Panel {
        width = 52, height = 52,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 60, 60, 70, 180 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 80, 90, 110, 200 },
        onClick = function(self)
            currentTileId_ = 0
            UpdateSelectedLabel()
        end,
        children = {
            UI.Label { text = "🧹", fontSize = 20 },
            UI.Label { text = "擦除", fontSize = 9, fontColor = { 255, 255, 255, 180 } },
        },
    }
    table.insert(tileChildren, eraserTileBtn)

    -- 瓦片类型按钮
    for id = 1, TilemapData.nextTileId - 1 do
        local info = TilemapData.tileRegistry[id]
        if info then
            local tileId = id
            local btn = UI.Panel {
                width = 52, height = 52,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { info.color[1], info.color[2], info.color[3], 180 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 80, 90, 110, 200 },
                onClick = function(self)
                    currentTileId_ = tileId
                    UpdateSelectedLabel()
                end,
                children = {
                    UI.Label { text = "🧱", fontSize = 18 },
                    UI.Label { text = info.name, fontSize = 9, fontColor = { 255, 255, 255, 200 } },
                },
            }
            table.insert(tileChildren, btn)
        end
    end

    tilePalettePanel_ = UI.Panel {
        width = "100%",
        gap = 6,
        alignItems = "center",
        flexWrap = "wrap",
        flexDirection = "row",
        justifyContent = "center",
        paddingLeft = 4,
        paddingRight = 4,
        children = tileChildren,
    }

    -- === 预制体调色板 ===
    local prefabChildren = {}
    -- 橡皮擦
    local eraserPrefabBtn = UI.Panel {
        width = 52, height = 52,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 60, 60, 70, 180 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 80, 90, 110, 200 },
        onClick = function(self)
            currentPrefabId_ = 0
            UpdateSelectedLabel()
        end,
        children = {
            UI.Label { text = "🧹", fontSize = 20 },
            UI.Label { text = "擦除", fontSize = 9, fontColor = { 255, 255, 255, 180 } },
        },
    }
    table.insert(prefabChildren, eraserPrefabBtn)

    for id = 1, TilemapData.nextPrefabId - 1 do
        local info = TilemapData.prefabRegistry[id]
        if info then
            local prefabId = id
            local btn = UI.Panel {
                width = 52, height = 52,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { info.color[1], info.color[2], info.color[3], 140 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 80, 90, 110, 200 },
                onClick = function(self)
                    currentPrefabId_ = prefabId
                    UpdateSelectedLabel()
                end,
                children = {
                    UI.Label { text = info.icon, fontSize = 18 },
                    UI.Label { text = info.name, fontSize = 9, fontColor = { 255, 255, 255, 200 } },
                },
            }
            table.insert(prefabChildren, btn)
        end
    end

    prefabPalettePanel_ = UI.Panel {
        width = "100%",
        gap = 6,
        alignItems = "center",
        flexWrap = "wrap",
        flexDirection = "row",
        justifyContent = "center",
        paddingLeft = 4,
        paddingRight = 4,
        display = "none",  -- 默认隐藏
        children = prefabChildren,
    }

    -- === 模式切换 Tab ===
    tileModeBtn_ = UI.Panel {
        width = 60, height = 28,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 70, 130, 220, 255 },
        borderRadius = 6,
        onClick = function(self)
            SetEditMode("tile")
        end,
        children = {
            UI.Label { text = "瓦片", fontSize = 11, fontColor = { 255, 255, 255, 255 } },
        },
    }
    prefabModeBtn_ = UI.Panel {
        width = 60, height = 28,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 50, 55, 70, 200 },
        borderRadius = 6,
        onClick = function(self)
            SetEditMode("prefab")
        end,
        children = {
            UI.Label { text = "预制体", fontSize = 11, fontColor = { 255, 255, 255, 255 } },
        },
    }

    local modeTabs = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 6,
        paddingTop = 6,
        paddingBottom = 6,
        children = {
            tileModeBtn_,
            prefabModeBtn_,
        },
    }

    -- === 顶部工具栏 ===
    selectedLabel_ = UI.Label {
        text = "🧱 草地",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
    }

    sizeLabel_ = UI.Label {
        text = TilemapData.gridWidth .. "×" .. TilemapData.gridHeight,
        fontSize = 12,
        fontColor = { 120, 130, 150, 200 },
    }

    -- 地图大小调节按钮
    local sizeControls = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        children = {
            UI.Panel {
                width = 22, height = 22,
                justifyContent = "center", alignItems = "center",
                backgroundColor = { 60, 65, 80, 200 },
                borderRadius = 4,
                onClick = function(self)
                    local w = math.max(4, TilemapData.gridWidth - 2)
                    local h = math.max(4, TilemapData.gridHeight - 1)
                    TilemapData.Resize(w, h)
                    UpdateSizeLabel()
                end,
                children = { UI.Label { text = "−", fontSize = 14, fontColor = { 255, 255, 255, 220 } } },
            },
            sizeLabel_,
            UI.Panel {
                width = 22, height = 22,
                justifyContent = "center", alignItems = "center",
                backgroundColor = { 60, 65, 80, 200 },
                borderRadius = 4,
                onClick = function(self)
                    local w = math.min(40, TilemapData.gridWidth + 2)
                    local h = math.min(30, TilemapData.gridHeight + 1)
                    TilemapData.Resize(w, h)
                    UpdateSizeLabel()
                end,
                children = { UI.Label { text = "+", fontSize = 14, fontColor = { 255, 255, 255, 220 } } },
            },
        },
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
        children = {
            UI.Label {
                text = "关卡编辑器",
                fontSize = 15,
                fontColor = { 180, 200, 240, 255 },
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Label { text = "当前:", fontSize = 12, fontColor = { 150, 160, 180, 200 } },
                    selectedLabel_,
                },
            },
            sizeControls,
        },
    }

    -- === 左侧面板 ===
    local leftPanel = UI.Panel {
        width = UI_MARGINS.left,
        height = "100%",
        paddingTop = 4,
        paddingBottom = 4,
        alignItems = "center",
        backgroundColor = { 20, 22, 34, 200 },
        children = {
            modeTabs,
            tilePalettePanel_,
            prefabPalettePanel_,
        },
    }

    -- === 底部操作栏 ===
    local bottomBar = UI.Panel {
        width = "100%",
        height = UI_MARGINS.bottom,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 12,
        backgroundColor = { 20, 22, 34, 240 },
        children = {
            UI.Button {
                text = "💾 保存",
                variant = "primary",
                height = 34,
                onClick = function(self) SaveToJSON() end,
            },
            UI.Button {
                text = "📂 加载",
                variant = "outline",
                height = 34,
                onClick = function(self) LoadFromJSON() end,
            },
            UI.Button {
                text = "🧹 清空",
                variant = "danger",
                height = 34,
                onClick = function(self) TilemapData.Clear() end,
            },
            UI.Button {
                text = "▶ 测试",
                variant = "success",
                height = 34,
                onClick = function(self)
                    log:Write(LOG_INFO, "[LevelEditor] Test level (TODO)")
                end,
            },
            UI.Button {
                text = "← 返回",
                variant = "ghost",
                height = 34,
                onClick = function(self)
                    SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
                end,
            },
        },
    }

    -- === 整体布局 ===
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        children = {
            topBar,
            UI.Panel {
                flex = 1,
                width = "100%",
                flexDirection = "row",
                children = {
                    leftPanel,
                    UI.Panel { flex = 1 },  -- NanoVG 绘制区
                },
            },
            bottomBar,
        },
    }

    UI.SetRoot(root)
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function LevelEditor_HandleUpdate(eventType, eventData)
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr
    layout_ = TilemapRenderer.CalcLayout(logW, logH, UI_MARGINS)

    -- 鼠标悬停
    local mouseX = input.mousePosition.x / dpr
    local mouseY = input.mousePosition.y / dpr
    local row, col = TilemapRenderer.ScreenToGrid(mouseX, mouseY, layout_)
    TilemapRenderer.hoverRow = row
    TilemapRenderer.hoverCol = col

    -- 鼠标按住拖动绘制
    if isDrawing_ then
        if editMode_ == "tile" then
            TilemapData.SetTile(row, col, currentTileId_)
        else
            TilemapData.SetPrefab(row, col, currentPrefabId_)
        end
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
        if layout_ then
            local dpr = graphics:GetDPR()
            local mouseX = input.mousePosition.x / dpr
            local mouseY = input.mousePosition.y / dpr
            local row, col = TilemapRenderer.ScreenToGrid(mouseX, mouseY, layout_)
            if editMode_ == "tile" then
                TilemapData.SetTile(row, col, currentTileId_)
            else
                TilemapData.SetPrefab(row, col, currentPrefabId_)
            end
        end
    elseif button == MOUSEB_RIGHT then
        -- 右键擦除当前层
        if layout_ then
            local dpr = graphics:GetDPR()
            local mouseX = input.mousePosition.x / dpr
            local mouseY = input.mousePosition.y / dpr
            local row, col = TilemapRenderer.ScreenToGrid(mouseX, mouseY, layout_)
            if editMode_ == "tile" then
                TilemapData.SetTile(row, col, 0)
            else
                TilemapData.SetPrefab(row, col, 0)
            end
        end
    end
end

function LevelEditor_HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_LEFT then
        isDrawing_ = false
    end
end

-- 注册为场景
if SceneManager.SCENE_EDITOR then
    SceneManager.Register(SceneManager.SCENE_EDITOR, LevelEditorUI)
end

return LevelEditorUI

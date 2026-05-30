-- ============================================================================
-- LevelEditorUI.lua - 关卡编辑器 UI 与交互逻辑（v4）
-- 左侧：瓦片调色板网格（N×N 格子预览 + 框选多瓦片）
-- 右侧：操作工具（绘制/擦除）+ 图层管理
-- 支持 Ctrl+Z 撤销、拖拽批量、多瓦片同时放置、清空确认弹框
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
local layout_ = nil
local isDrawing_ = false

--- 当前选中的画笔值（单个瓦片，向后兼容）
local currentBrushId_ = 1

--- 当前 Tab: "tile" 或 "prefab"
local currentTab_ = "tile"

--- 当前工具: "paint" 或 "erase"
local currentTool_ = "paint"

-- ==============================
-- 瓦片调色板网格系统
-- ==============================

--- 调色板网格的列数（每行显示多少个瓦片）
local PALETTE_COLS = 9

--- 所有已加载的瓦片 ID 列表（按注册顺序排列）
local paletteTileIds_ = {}

--- 多瓦片选区：{ startRow, startCol, endRow, endCol } 在调色板网格中的位置
--- 选区为 nil 表示未选择；单格选择时 start==end
local paletteSelection_ = nil

--- 多瓦片画笔：存储选区中的瓦片 ID 矩阵
--- brushMatrix_[dr][dc] = tileId（dr/dc 从 1 开始）
local brushMatrix_ = nil
local brushMatrixRows_ = 0
local brushMatrixCols_ = 0

--- 整理模式：用于交换瓦片位置
local arrangeMode_ = false
local arrangeSourceIndex_ = nil  -- paletteTileIds_ 中的索引

-- UI 引用
local selectedLabel_ = nil
local sizeLabel_ = nil
local layerListPanel_ = nil
local palettePanel_ = nil
local tileModeBtn_ = nil
local prefabModeBtn_ = nil
local paintToolBtn_ = nil
local eraseToolBtn_ = nil
local confirmOverlay_ = nil
local saveOverlay_ = nil
local loadOverlay_ = nil
local loadListPanel_ = nil
local saveNameField_ = nil
local assetPickerOverlay_ = nil
local assetListPanel_ = nil
local arrangeModeBtn_ = nil

-- UI 边距（左侧面板加宽以容纳网格）
local UI_MARGINS = { top = 48, bottom = 52, left = 220, right = 140 }

-- 不可删除的预制体 ID（玩家出生点、终点）
local PROTECTED_PREFAB_IDS = { [1] = true, [2] = true }

-- ============================================================================
-- UI 更新辅助
-- ============================================================================

-- ============================================================================
-- 自动扫描并加载所有瓦片图片到注册表
-- ============================================================================

--- 扫描 tilemap_tiles 目录并自动注册所有瓦片
local function AutoLoadTileAssets()
    -- ScanDir 需要文件系统路径（带 assets/ 前缀）
    local fsDir = "assets/image/tilemap/tilemap_tiles/"
    -- 资源路径（不带 assets/ 前缀，用于 cache/UI）
    local resDir = "image/tilemap/tilemap_tiles/"
    local pngFiles = fileSystem:ScanDir(fsDir, "*.png", SCAN_FILES, false)

    -- 按文件名排序（按数字顺序）
    table.sort(pngFiles, function(a, b)
        local numA = tonumber(string.match(a, "(%d+)")) or 0
        local numB = tonumber(string.match(b, "(%d+)")) or 0
        return numA < numB
    end)

    for _, fname in ipairs(pngFiles) do
        -- 跳过 .meta 文件
        if not string.match(fname, "%.meta$") then
            local path = resDir .. fname  -- 使用资源路径
            local name = string.match(fname, "([^/]+)%.[^.]+$") or fname
            -- 检查是否已注册（避免重复）
            local alreadyRegistered = false
            for id, info in pairs(TilemapData.tileRegistry) do
                if info.image == path then
                    alreadyRegistered = true
                    break
                end
            end
            if not alreadyRegistered then
                TilemapData.RegisterTile(name, path, { 200, 200, 200, 255 })
            end
        end
    end
end

--- 刷新调色板瓦片列表（收集所有已注册的瓦片 ID）
local function RefreshPaletteTileIds()
    paletteTileIds_ = {}
    for id = 1, TilemapData.nextTileId - 1 do
        if TilemapData.tileRegistry[id] then
            table.insert(paletteTileIds_, id)
        end
    end
end

--- 根据调色板网格的行列获取对应的 tile ID（超出范围返回 0）
local function GetPaletteTileAt(row, col)
    local index = (row - 1) * PALETTE_COLS + col
    if index >= 1 and index <= #paletteTileIds_ then
        return paletteTileIds_[index]
    end
    return 0
end

--- 获取调色板网格的总行数
local function GetPaletteRows()
    return math.ceil(#paletteTileIds_ / PALETTE_COLS)
end

--- 从当前选区构建画笔矩阵
local function BuildBrushMatrix()
    if not paletteSelection_ then
        brushMatrix_ = nil
        brushMatrixRows_ = 0
        brushMatrixCols_ = 0
        return
    end

    local r1 = math.min(paletteSelection_.startRow, paletteSelection_.endRow)
    local r2 = math.max(paletteSelection_.startRow, paletteSelection_.endRow)
    local c1 = math.min(paletteSelection_.startCol, paletteSelection_.endCol)
    local c2 = math.max(paletteSelection_.startCol, paletteSelection_.endCol)

    brushMatrixRows_ = r2 - r1 + 1
    brushMatrixCols_ = c2 - c1 + 1
    brushMatrix_ = {}

    for dr = 1, brushMatrixRows_ do
        brushMatrix_[dr] = {}
        for dc = 1, brushMatrixCols_ do
            local tileId = GetPaletteTileAt(r1 + dr - 1, c1 + dc - 1)
            brushMatrix_[dr][dc] = tileId
        end
    end

    -- 单格选中时也更新 currentBrushId_
    if brushMatrixRows_ == 1 and brushMatrixCols_ == 1 then
        currentBrushId_ = brushMatrix_[1][1]
    end
end

-- ============================================================================
-- UI 更新辅助
-- ============================================================================

local function UpdateSelectedLabel()
    if not selectedLabel_ then return end
    if currentTool_ == "erase" then
        selectedLabel_:SetText("🧹 擦除模式")
        return
    end
    if currentTab_ == "tile" then
        if brushMatrix_ and (brushMatrixRows_ > 1 or brushMatrixCols_ > 1) then
            selectedLabel_:SetText("🧱 " .. brushMatrixCols_ .. "×" .. brushMatrixRows_ .. " 区域")
        else
            local info = TilemapData.GetTileInfo(currentBrushId_)
            selectedLabel_:SetText("🧱 " .. info.name)
        end
    else
        local info = TilemapData.GetPrefabInfo(currentBrushId_)
        selectedLabel_:SetText(info.icon .. " " .. info.name)
    end
end

local function UpdateSizeLabel()
    if sizeLabel_ then
        sizeLabel_:SetText(TilemapData.gridWidth .. "×" .. TilemapData.gridHeight)
    end
end

-- 前向声明
local RebuildLayerList
local RebuildPalette
local UpdateToolButtons

-- ============================================================================
-- 工具切换
-- ============================================================================

UpdateToolButtons = function()
    if not paintToolBtn_ or not eraseToolBtn_ then return end
    if currentTool_ == "paint" then
        paintToolBtn_:SetProp("backgroundColor", { 50, 130, 90, 255 })
        paintToolBtn_:SetProp("borderWidth", 2)
        paintToolBtn_:SetProp("borderColor", { 120, 255, 160, 255 })
        eraseToolBtn_:SetProp("backgroundColor", { 50, 55, 70, 180 })
        eraseToolBtn_:SetProp("borderWidth", 1)
        eraseToolBtn_:SetProp("borderColor", { 80, 90, 110, 200 })
    else
        paintToolBtn_:SetProp("backgroundColor", { 50, 55, 70, 180 })
        paintToolBtn_:SetProp("borderWidth", 1)
        paintToolBtn_:SetProp("borderColor", { 80, 90, 110, 200 })
        eraseToolBtn_:SetProp("backgroundColor", { 160, 60, 60, 255 })
        eraseToolBtn_:SetProp("borderWidth", 2)
        eraseToolBtn_:SetProp("borderColor", { 255, 140, 140, 255 })
    end
    UpdateSelectedLabel()
end

-- ============================================================================
-- 文件操作
-- ============================================================================

local SAVE_DIR = "LevelEditor"

local function SaveToFile(filename)
    fileSystem:CreateDir(SAVE_DIR)
    local path = SAVE_DIR .. "/" .. filename .. ".json"
    local data = TilemapData.Serialize()
    local json = cjson.encode(data)
    local file = File(path, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(json)
        file:Close()
        log:Write(LOG_INFO, "[LevelEditor] Saved: " .. path)
    else
        log:Write(LOG_ERROR, "[LevelEditor] Failed to save: " .. path)
    end
end

local function LoadFromFile(filename)
    local path = SAVE_DIR .. "/" .. filename
    if not fileSystem:FileExists(path) then
        log:Write(LOG_WARNING, "[LevelEditor] No save file: " .. path)
        return false
    end
    local file = File(path, FILE_READ)
    if not file:IsOpen() then return false end
    local content = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        log:Write(LOG_ERROR, "[LevelEditor] JSON error: " .. tostring(data))
        return false
    end
    TilemapData.Deserialize(data)
    TilemapRenderer.ClearImageCache()
    currentBrushId_ = 1
    UpdateSizeLabel()
    UpdateSelectedLabel()
    RebuildLayerList()
    RebuildPalette()
    log:Write(LOG_INFO, "[LevelEditor] Loaded: " .. path)
    return true
end

-- 弹框：保存
local function ShowSaveDialog()
    if saveOverlay_ then saveOverlay_:SetVisible(true) end
end
local function HideSaveDialog()
    if saveOverlay_ then saveOverlay_:SetVisible(false) end
end

-- 弹框：加载（扫描目录并列举文件）
local RebuildLoadList
local function ShowLoadDialog()
    if loadOverlay_ then
        RebuildLoadList()
        loadOverlay_:SetVisible(true)
    end
end
local function HideLoadDialog()
    if loadOverlay_ then loadOverlay_:SetVisible(false) end
end

RebuildLoadList = function()
    if not loadListPanel_ then return end
    loadListPanel_:ClearChildren()

    fileSystem:CreateDir(SAVE_DIR)
    local files = fileSystem:ScanDir(SAVE_DIR .. "/", "*.json", SCAN_FILES, false)

    if #files == 0 then
        loadListPanel_:AddChild(UI.Label {
            text = "暂无存档文件",
            fontSize = 12, fontColor = { 150, 160, 180, 180 },
        })
        return
    end

    for _, fname in ipairs(files) do
        local filename = fname
        loadListPanel_:AddChild(UI.Panel {
            width = "100%", height = 36,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            backgroundColor = { 40, 44, 60, 180 },
            borderRadius = 6,
            onClick = function(self)
                LoadFromFile(filename)
                HideLoadDialog()
            end,
            children = {
                UI.Label {
                    text = "📄 " .. filename,
                    fontSize = 12, fontColor = { 255, 255, 255, 230 },
                },
            },
        })
    end
end

-- ============================================================================
-- 素材选择器（扫描 assets/ 下的图片）
-- ============================================================================

--- 扫描素材目录
-- ScanDir 需要 "assets/" 前缀的文件系统路径
-- 资源加载使用不带 "assets/" 前缀的资源路径
local ASSET_SCAN_DIRS = {
    { fs = "assets/image/tilemap/", res = "image/tilemap/" },
}

local function ScanImageAssets()
    local results = {}
    for _, dirInfo in ipairs(ASSET_SCAN_DIRS) do
        local pngFiles = fileSystem:ScanDir(dirInfo.fs, "*.png", SCAN_FILES, true)
        for _, f in ipairs(pngFiles) do
            table.insert(results, dirInfo.res .. f)
        end
        local jpgFiles = fileSystem:ScanDir(dirInfo.fs, "*.jpg", SCAN_FILES, true)
        for _, f in ipairs(jpgFiles) do
            table.insert(results, dirInfo.res .. f)
        end
    end
    return results
end

local RebuildAssetList

local function ShowAssetPicker()
    if assetPickerOverlay_ then
        RebuildAssetList()
        assetPickerOverlay_:SetVisible(true)
    end
end

local function HideAssetPicker()
    if assetPickerOverlay_ then
        assetPickerOverlay_:SetVisible(false)
    end
end

RebuildAssetList = function()
    if not assetListPanel_ then return end
    assetListPanel_:ClearChildren()

    local assets = ScanImageAssets()

    if #assets == 0 then
        assetListPanel_:AddChild(UI.Label {
            text = "未找到图片素材",
            fontSize = 12, fontColor = { 150, 160, 180, 180 },
        })
        assetListPanel_:AddChild(UI.Label {
            text = "请将 .png/.jpg 放入 assets/image/tilemap/",
            fontSize = 10, fontColor = { 120, 130, 150, 150 },
        })
        return
    end

    for _, assetPath in ipairs(assets) do
        local displayName = assetPath
        -- 缩短显示名
        if #displayName > 35 then
            displayName = "..." .. string.sub(displayName, -32)
        end

        local path = assetPath
        assetListPanel_:AddChild(UI.Panel {
            width = "100%", height = 38,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 10, paddingRight = 10,
            gap = 8,
            backgroundColor = { 40, 44, 60, 180 },
            borderRadius = 6,
            onClick = function(self)
                -- 用文件名（不含扩展名）作为瓦片名
                local name = string.match(path, "([^/]+)%.[^.]+$") or "瓦片"
                local newId = TilemapData.RegisterTile(name, path, { 200, 200, 200, 255 })
                currentBrushId_ = newId
                currentTool_ = "paint"
                UpdateToolButtons()
                RebuildPalette()
                HideAssetPicker()
            end,
            children = {
                UI.Label { text = "🖼", fontSize = 14 },
                UI.Label {
                    text = displayName,
                    fontSize = 11, fontColor = { 255, 255, 255, 220 },
                    flex = 1,
                },
            },
        })
    end
end

-- ============================================================================
-- 确认弹框
-- ============================================================================

local function ShowConfirmDialog()
    if confirmOverlay_ then
        confirmOverlay_:SetVisible(true)
    end
end

local function HideConfirmDialog()
    if confirmOverlay_ then
        confirmOverlay_:SetVisible(false)
    end
end

-- ============================================================================
-- 场景生命周期
-- ============================================================================

function LevelEditorUI.Enter(params)
    TilemapData.New(16, 12)

    -- 自动加载所有瓦片素材
    AutoLoadTileAssets()
    RefreshPaletteTileIds()

    nvg_ = nvgCreate(1)
    nvgCreateFont(nvg_, "sans", "Fonts/MiSans-Regular.ttf")

    currentBrushId_ = 1
    currentTab_ = "tile"
    currentTool_ = "paint"
    paletteSelection_ = nil
    brushMatrix_ = nil
    brushMatrixRows_ = 0
    brushMatrixCols_ = 0
    arrangeMode_ = false
    arrangeSourceIndex_ = nil

    LevelEditorUI.BuildUI()

    SubscribeToEvent("Update", "LevelEditor_HandleUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "LevelEditor_HandleRender")
    SubscribeToEvent("MouseButtonDown", "LevelEditor_HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "LevelEditor_HandleMouseUp")
    SubscribeToEvent("KeyDown", "LevelEditor_HandleKeyDown")
end

function LevelEditorUI.Exit()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("MouseButtonDown")
    UnsubscribeFromEvent("MouseButtonUp")
    UnsubscribeFromEvent("KeyDown")
    if nvg_ then
        UnsubscribeFromEvent(nvg_, "NanoVGRender")
    end
    UI.SetRoot(nil)
    TilemapRenderer.ClearImageCache()
    nvg_ = nil
    layout_ = nil
    selectedLabel_ = nil
    sizeLabel_ = nil
    layerListPanel_ = nil
    palettePanel_ = nil
    tileModeBtn_ = nil
    prefabModeBtn_ = nil
    paintToolBtn_ = nil
    eraseToolBtn_ = nil
    confirmOverlay_ = nil
    saveOverlay_ = nil
    loadOverlay_ = nil
    loadListPanel_ = nil
    saveNameField_ = nil
    assetPickerOverlay_ = nil
    assetListPanel_ = nil
end

-- ============================================================================
-- 左侧调色板（Tab 切换瓦片/预制体，带增删）
-- ============================================================================

RebuildPalette = function()
    if not palettePanel_ then return end

    local children = {}

    if currentTab_ == "tile" then
        -- 瓦片网格调色板
        RefreshPaletteTileIds()
        local totalRows = GetPaletteRows()
        local CELL_SIZE = 22  -- 每个格子的像素大小

        -- 提示文字
        local hintText = arrangeMode_ and "整理模式：点击两个瓦片交换位置" or "点击选择瓦片"
        table.insert(children, UI.Label {
            text = hintText,
            fontSize = 9,
            fontColor = arrangeMode_ and { 255, 200, 100, 220 } or { 150, 160, 180, 150 },
            marginBottom = 2,
        })

        -- 构建网格行
        for row = 1, totalRows do
            local rowChildren = {}
            for col = 1, PALETTE_COLS do
                local tileId = GetPaletteTileAt(row, col)
                local cellRow = row
                local cellCol = col
                local cellIndex = (row - 1) * PALETTE_COLS + col

                -- 判断是否选中
                local isSelected = false
                if paletteSelection_ then
                    isSelected = (row == paletteSelection_.startRow and col == paletteSelection_.startCol)
                end
                -- 判断是否为整理模式中的源瓦片
                local isArrangeSource = (arrangeMode_ and arrangeSourceIndex_ == cellIndex)

                if tileId > 0 then
                    local info = TilemapData.tileRegistry[tileId]
                    local bgProps = {}
                    if info and info.image then
                        bgProps.backgroundImage = info.image
                        bgProps.backgroundFit = "cover"
                    else
                        bgProps.backgroundColor = info and { info.color[1], info.color[2], info.color[3], 220 } or { 80, 80, 80, 200 }
                    end

                    bgProps.width = CELL_SIZE
                    bgProps.height = CELL_SIZE
                    bgProps.borderRadius = 2

                    -- 高亮逻辑
                    if isArrangeSource then
                        bgProps.borderWidth = 2
                        bgProps.borderColor = { 255, 200, 50, 255 }
                    elseif isSelected and not arrangeMode_ then
                        bgProps.borderWidth = 2
                        bgProps.borderColor = { 100, 200, 255, 255 }
                    else
                        bgProps.borderWidth = 0
                    end

                    bgProps.onClick = function(self)
                        if arrangeMode_ then
                            -- 整理模式：交换瓦片位置
                            if arrangeSourceIndex_ == nil then
                                -- 选中第一个（源）
                                arrangeSourceIndex_ = cellIndex
                                RebuildPalette()
                            else
                                -- 选中第二个（目标），执行交换
                                local srcIdx = arrangeSourceIndex_
                                local dstIdx = cellIndex
                                if srcIdx ~= dstIdx and srcIdx <= #paletteTileIds_ and dstIdx <= #paletteTileIds_ then
                                    paletteTileIds_[srcIdx], paletteTileIds_[dstIdx] = paletteTileIds_[dstIdx], paletteTileIds_[srcIdx]
                                end
                                arrangeSourceIndex_ = nil
                                RebuildPalette()
                            end
                        else
                            -- 普通模式：选择瓦片用于绘制
                            paletteSelection_ = { startRow = cellRow, startCol = cellCol, endRow = cellRow, endCol = cellCol }
                            currentBrushId_ = tileId
                            brushMatrix_ = nil
                            brushMatrixRows_ = 0
                            brushMatrixCols_ = 0
                            currentTool_ = "paint"
                            UpdateToolButtons()
                            UpdateSelectedLabel()
                            RebuildPalette()
                        end
                    end

                    table.insert(rowChildren, UI.Panel(bgProps))
                else
                    -- 空格（也可以作为交换目标）
                    table.insert(rowChildren, UI.Panel {
                        width = CELL_SIZE, height = CELL_SIZE,
                        backgroundColor = { 25, 28, 40, 100 },
                        borderRadius = 2,
                    })
                end
            end

            table.insert(children, UI.Panel {
                flexDirection = "row",
                gap = 1,
                children = rowChildren,
            })
        end

        -- 添加瓦片按钮（打开素材选择器）
        table.insert(children, UI.Panel {
            width = "100%", height = 30,
            justifyContent = "center", alignItems = "center",
            backgroundColor = { 50, 100, 70, 150 },
            borderRadius = 6,
            marginTop = 8,
            onClick = function(self)
                ShowAssetPicker()
            end,
            children = {
                UI.Label { text = "+ 添加更多瓦片", fontSize = 10, fontColor = { 255, 255, 255, 220 } },
            },
        })

    else
        -- 预制体列表（保持原有列表样式）
        for id = 1, TilemapData.nextPrefabId - 1 do
            local info = TilemapData.prefabRegistry[id]
            if info then
                local prefabId = id
                local isSelected = (currentBrushId_ == prefabId and currentTool_ == "paint")
                local canDelete = not PROTECTED_PREFAB_IDS[prefabId]

                local rowChildren = {
                    UI.Panel {
                        flex = 1, height = "100%",
                        flexDirection = "row",
                        alignItems = "center", gap = 6,
                        onClick = function(self)
                            currentBrushId_ = prefabId
                            currentTool_ = "paint"
                            UpdateToolButtons()
                            RebuildPalette()
                        end,
                        children = {
                            UI.Panel {
                                width = 28, height = 28,
                                backgroundColor = { info.color[1], info.color[2], info.color[3], 180 },
                                borderRadius = 4,
                                justifyContent = "center", alignItems = "center",
                                children = {
                                    UI.Label { text = info.icon, fontSize = 14 },
                                },
                            },
                            UI.Label {
                                text = info.name, fontSize = 11,
                                fontColor = { 255, 255, 255, 220 },
                            },
                        },
                    },
                }

                if canDelete then
                    table.insert(rowChildren, UI.Panel {
                        width = 20, height = 20,
                        justifyContent = "center", alignItems = "center",
                        backgroundColor = { 140, 50, 50, 150 },
                        borderRadius = 4,
                        onClick = function(self)
                            TilemapData.prefabRegistry[prefabId] = nil
                            if currentBrushId_ == prefabId then
                                currentBrushId_ = 1
                            end
                            UpdateSelectedLabel()
                            RebuildPalette()
                        end,
                        children = {
                            UI.Label { text = "×", fontSize = 12, fontColor = { 255, 200, 200, 220 } },
                        },
                    })
                end

                table.insert(children, UI.Panel {
                    width = "100%", height = 40,
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 4,
                    paddingLeft = 4, paddingRight = 4,
                    backgroundColor = isSelected and { 50, 90, 160, 200 } or { 40, 44, 58, 120 },
                    borderRadius = 6,
                    borderWidth = isSelected and 2 or 0,
                    borderColor = { 100, 180, 255, 255 },
                    children = rowChildren,
                })
            end
        end

        -- 添加预制体按钮
        table.insert(children, UI.Panel {
            width = "100%", height = 30,
            justifyContent = "center", alignItems = "center",
            backgroundColor = { 50, 100, 70, 150 },
            borderRadius = 6,
            marginTop = 6,
            onClick = function(self)
                local r = math.random(80, 200)
                local g = math.random(80, 200)
                local b = math.random(80, 200)
                local newId = TilemapData.RegisterPrefab("新预制体", "custom_" .. TilemapData.nextPrefabId, "❓", { r, g, b, 200 })
                currentBrushId_ = newId
                currentTool_ = "paint"
                UpdateToolButtons()
                RebuildPalette()
            end,
            children = {
                UI.Label { text = "+ 添加预制体", fontSize = 10, fontColor = { 255, 255, 255, 220 } },
            },
        })
    end

    palettePanel_:ClearChildren()
    for _, child in ipairs(children) do
        palettePanel_:AddChild(child)
    end
end

-- ============================================================================
-- 图层面板
-- ============================================================================

RebuildLayerList = function()
    if not layerListPanel_ then return end
    local children = {}

    for i, layer in ipairs(TilemapData.layers) do
        local idx = i
        local isActive = (i == TilemapData.activeLayerIndex)

        local row = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 3,
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 3, paddingBottom = 3,
            backgroundColor = isActive and { 50, 90, 160, 180 } or { 40, 44, 58, 150 },
            borderRadius = 4,
            onClick = function(self)
                TilemapData.SetActiveLayer(idx)
                -- 切换到对应 tab
                currentTab_ = layer.type
                currentBrushId_ = 1
                UpdateSelectedLabel()
                RebuildLayerList()
                RebuildPalette()
                -- 更新 tab 按钮样式
                if tileModeBtn_ and prefabModeBtn_ then
                    if currentTab_ == "tile" then
                        tileModeBtn_:SetProp("backgroundColor", { 70, 130, 220, 255 })
                        prefabModeBtn_:SetProp("backgroundColor", { 50, 55, 70, 200 })
                    else
                        tileModeBtn_:SetProp("backgroundColor", { 50, 55, 70, 200 })
                        prefabModeBtn_:SetProp("backgroundColor", { 70, 130, 220, 255 })
                    end
                end
            end,
            children = {
                -- 可见性
                UI.Panel {
                    width = 18, height = 18,
                    justifyContent = "center", alignItems = "center",
                    onClick = function(self)
                        TilemapData.SetLayerVisible(idx, not layer.visible)
                        RebuildLayerList()
                    end,
                    children = {
                        UI.Label {
                            text = layer.visible and "👁" or "—",
                            fontSize = 10,
                            fontColor = layer.visible and { 255, 255, 255, 220 } or { 100, 100, 100, 150 },
                        },
                    },
                },
                -- 名称（可编辑）+ 信息
                UI.Panel {
                    flex = 1,
                    children = {
                        UI.TextField {
                            value = layer.name,
                            fontSize = 10,
                            height = 20,
                            paddingHorizontal = 4,
                            backgroundColor = { 30, 34, 48, isActive and 200 or 100 },
                            borderWidth = 0,
                            borderRadius = 3,
                            onSubmit = function(self, val)
                                if val and #val > 0 then
                                    TilemapData.layers[idx].name = val
                                end
                            end,
                            onBlur = function(self)
                                local val = self.props.value
                                if val and #val > 0 then
                                    TilemapData.layers[idx].name = val
                                end
                            end,
                        },
                        UI.Label {
                            text = (layer.type == "tile" and "瓦片" or "预制体") .. " z:" .. layer.zOrder,
                            fontSize = 8,
                            fontColor = { 150, 160, 180, 150 },
                        },
                    },
                },
                -- zOrder 调整
                UI.Panel {
                    width = 16, height = 16,
                    justifyContent = "center", alignItems = "center",
                    backgroundColor = { 70, 75, 90, 150 },
                    borderRadius = 3,
                    onClick = function(self)
                        TilemapData.SetLayerZOrder(idx, layer.zOrder + 1)
                        RebuildLayerList()
                    end,
                    children = { UI.Label { text = "↑", fontSize = 9, fontColor = { 255, 255, 255, 200 } } },
                },
                UI.Panel {
                    width = 16, height = 16,
                    justifyContent = "center", alignItems = "center",
                    backgroundColor = { 70, 75, 90, 150 },
                    borderRadius = 3,
                    onClick = function(self)
                        TilemapData.SetLayerZOrder(idx, layer.zOrder - 1)
                        RebuildLayerList()
                    end,
                    children = { UI.Label { text = "↓", fontSize = 9, fontColor = { 255, 255, 255, 200 } } },
                },
            },
        }
        table.insert(children, row)
    end

    -- 添加/删除图层
    if #TilemapData.layers < TilemapData.MAX_LAYERS then
        table.insert(children, UI.Panel {
            width = "100%", height = 22,
            justifyContent = "center", alignItems = "center",
            backgroundColor = { 50, 120, 80, 150 },
            borderRadius = 4, marginTop = 4,
            onClick = function(self)
                local lastType = TilemapData.layers[#TilemapData.layers].type
                local newType = (lastType == "tile") and "prefab" or "tile"
                TilemapData.AddLayer(nil, newType)
                RebuildLayerList()
            end,
            children = { UI.Label { text = "+ 图层", fontSize = 10, fontColor = { 255, 255, 255, 220 } } },
        })
    end
    if #TilemapData.layers > 1 then
        table.insert(children, UI.Panel {
            width = "100%", height = 22,
            justifyContent = "center", alignItems = "center",
            backgroundColor = { 140, 50, 50, 150 },
            borderRadius = 4, marginTop = 2,
            onClick = function(self)
                TilemapData.RemoveLayer(TilemapData.activeLayerIndex)
                currentBrushId_ = 1
                UpdateSelectedLabel()
                RebuildLayerList()
                RebuildPalette()
            end,
            children = { UI.Label { text = "- 删除层", fontSize = 10, fontColor = { 255, 255, 255, 200 } } },
        })
    end

    layerListPanel_:ClearChildren()
    for _, child in ipairs(children) do
        layerListPanel_:AddChild(child)
    end
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function LevelEditorUI.BuildUI()
    -- === 顶部工具栏 ===
    selectedLabel_ = UI.Label {
        text = "🧱 草地",
        fontSize = 14, fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
    }
    sizeLabel_ = UI.Label {
        text = TilemapData.gridWidth .. "×" .. TilemapData.gridHeight,
        fontSize = 12, fontColor = { 120, 130, 150, 200 },
    }

    local sizeControls = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 4,
        children = {
            UI.Panel {
                width = 22, height = 22,
                justifyContent = "center", alignItems = "center",
                backgroundColor = { 60, 65, 80, 200 }, borderRadius = 4,
                onClick = function(self)
                    TilemapData.Resize(math.max(4, TilemapData.gridWidth - 2), math.max(4, TilemapData.gridHeight - 1))
                    UpdateSizeLabel()
                end,
                children = { UI.Label { text = "−", fontSize = 14, fontColor = { 255, 255, 255, 220 } } },
            },
            sizeLabel_,
            UI.Panel {
                width = 22, height = 22,
                justifyContent = "center", alignItems = "center",
                backgroundColor = { 60, 65, 80, 200 }, borderRadius = 4,
                onClick = function(self)
                    TilemapData.Resize(math.min(40, TilemapData.gridWidth + 2), math.min(30, TilemapData.gridHeight + 1))
                    UpdateSizeLabel()
                end,
                children = { UI.Label { text = "+", fontSize = 14, fontColor = { 255, 255, 255, 220 } } },
            },
        },
    }

    local topBar = UI.Panel {
        width = "100%", height = UI_MARGINS.top,
        flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        paddingLeft = 16, paddingRight = 16,
        backgroundColor = { 20, 22, 34, 240 },
        children = {
            UI.Label { text = "关卡编辑器", fontSize = 15, fontColor = { 180, 200, 240, 255 } },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Label { text = "当前:", fontSize = 12, fontColor = { 150, 160, 180, 200 } },
                    selectedLabel_,
                },
            },
            sizeControls,
            UI.Label { text = "Ctrl+Z 撤销", fontSize = 10, fontColor = { 100, 110, 130, 150 } },
        },
    }

    -- === 左侧面板: Tab + 调色板 ===
    tileModeBtn_ = UI.Panel {
        width = 36, height = 26,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 70, 130, 220, 255 },
        borderRadius = 5,
        onClick = function(self)
            currentTab_ = "tile"
            currentBrushId_ = 1
            tileModeBtn_:SetProp("backgroundColor", { 70, 130, 220, 255 })
            prefabModeBtn_:SetProp("backgroundColor", { 50, 55, 70, 200 })
            UpdateSelectedLabel()
            RebuildPalette()
        end,
        children = { UI.Label { text = "瓦片", fontSize = 10, fontColor = { 255, 255, 255, 255 } } },
    }
    prefabModeBtn_ = UI.Panel {
        width = 42, height = 26,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 50, 55, 70, 200 },
        borderRadius = 5,
        onClick = function(self)
            currentTab_ = "prefab"
            currentBrushId_ = 1
            tileModeBtn_:SetProp("backgroundColor", { 50, 55, 70, 200 })
            prefabModeBtn_:SetProp("backgroundColor", { 70, 130, 220, 255 })
            UpdateSelectedLabel()
            RebuildPalette()
        end,
        children = { UI.Label { text = "预制体", fontSize = 10, fontColor = { 255, 255, 255, 255 } } },
    }

    palettePanel_ = UI.Panel {
        width = "100%",
        flex = 1,
        gap = 4,
        paddingLeft = 4, paddingRight = 4,
        overflow = "scroll",
        children = {},
    }

    arrangeModeBtn_ = UI.Panel {
        width = 42, height = 22,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 50, 55, 70, 200 },
        borderRadius = 4,
        borderWidth = 0,
        onClick = function(self)
            arrangeMode_ = not arrangeMode_
            arrangeSourceIndex_ = nil
            if arrangeMode_ then
                arrangeModeBtn_:SetProp("backgroundColor", { 180, 130, 30, 255 })
                arrangeModeBtn_:SetProp("borderWidth", 1)
                arrangeModeBtn_:SetProp("borderColor", { 255, 220, 100, 255 })
            else
                arrangeModeBtn_:SetProp("backgroundColor", { 50, 55, 70, 200 })
                arrangeModeBtn_:SetProp("borderWidth", 0)
            end
            RebuildPalette()
        end,
        children = { UI.Label { text = "整理", fontSize = 9, fontColor = { 255, 255, 255, 200 } } },
    }

    local leftPanel = UI.Panel {
        width = UI_MARGINS.left,
        height = "100%",
        paddingTop = 6, paddingBottom = 6,
        gap = 6,
        alignItems = "center",
        backgroundColor = { 20, 22, 34, 200 },
        children = {
            -- Tab 行 + 整理按钮
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center", gap = 4,
                children = { tileModeBtn_, prefabModeBtn_, arrangeModeBtn_ },
            },
            -- 调色板（滚动）
            palettePanel_,
        },
    }

    -- === 右侧面板: 操作工具 + 图层 ===
    paintToolBtn_ = UI.Panel {
        width = "100%", height = 32,
        flexDirection = "row",
        justifyContent = "center", alignItems = "center", gap = 6,
        backgroundColor = { 50, 130, 90, 255 },
        borderRadius = 6,
        borderWidth = 2,
        borderColor = { 120, 255, 160, 255 },
        onClick = function(self)
            currentTool_ = "paint"
            UpdateToolButtons()
            RebuildPalette()
        end,
        children = {
            UI.Label { text = "✏️", fontSize = 12 },
            UI.Label { text = "绘制", fontSize = 11, fontColor = { 255, 255, 255, 240 } },
        },
    }
    eraseToolBtn_ = UI.Panel {
        width = "100%", height = 32,
        flexDirection = "row",
        justifyContent = "center", alignItems = "center", gap = 6,
        backgroundColor = { 50, 55, 70, 180 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = { 80, 90, 110, 200 },
        onClick = function(self)
            currentTool_ = "erase"
            UpdateToolButtons()
            RebuildPalette()
        end,
        children = {
            UI.Label { text = "🧹", fontSize = 12 },
            UI.Label { text = "擦除", fontSize = 11, fontColor = { 255, 255, 255, 240 } },
        },
    }

    layerListPanel_ = UI.Panel {
        width = "100%",
        gap = 4,
        children = {},
    }

    local rightPanel = UI.Panel {
        width = UI_MARGINS.right,
        height = "100%",
        paddingTop = 6, paddingBottom = 6,
        paddingLeft = 6, paddingRight = 6,
        gap = 8,
        backgroundColor = { 20, 22, 34, 200 },
        children = {
            -- 操作工具
            UI.Label { text = "操作", fontSize = 11, fontColor = { 150, 160, 180, 180 } },
            paintToolBtn_,
            eraseToolBtn_,
            -- 分割线
            UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 70, 90, 100 }, marginTop = 4, marginBottom = 4 },
            -- 图层
            UI.Label { text = "图层", fontSize = 11, fontColor = { 150, 160, 180, 180 } },
            layerListPanel_,
        },
    }

    -- === 底部操作栏 ===
    local bottomBar = UI.Panel {
        width = "100%", height = UI_MARGINS.bottom,
        flexDirection = "row",
        justifyContent = "center", alignItems = "center", gap = 12,
        backgroundColor = { 20, 22, 34, 240 },
        children = {
            UI.Button {
                text = "💾 保存", variant = "primary", height = 34,
                onClick = function(self) ShowSaveDialog() end,
            },
            UI.Button {
                text = "📂 加载", variant = "outline", height = 34,
                onClick = function(self) ShowLoadDialog() end,
            },
            UI.Button {
                text = "🧹 清空", variant = "danger", height = 34,
                onClick = function(self) ShowConfirmDialog() end,
            },
            UI.Button {
                text = "↩ 撤销", variant = "outline", height = 34,
                onClick = function(self) TilemapData.Undo() end,
            },
            UI.Button {
                text = "← 返回", variant = "ghost", height = 34,
                onClick = function(self) SceneManager.SwitchTo(SceneManager.SCENE_TITLE) end,
            },
        },
    }

    -- === 清空确认弹框（默认隐藏）===
    confirmOverlay_ = UI.Panel {
        position = "absolute",
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        visible = false,
        onClick = function(self)
            HideConfirmDialog()
        end,
        children = {
            UI.Panel {
                width = 280, height = 150,
                justifyContent = "center", alignItems = "center",
                gap = 20,
                backgroundColor = { 35, 38, 55, 250 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 80, 90, 120, 200 },
                onClick = function(self)
                    -- 阻止点击穿透到 overlay
                end,
                children = {
                    UI.Label {
                        text = "确定要清空所有图层数据吗？",
                        fontSize = 14, fontColor = { 255, 255, 255, 240 },
                    },
                    UI.Label {
                        text = "此操作不可撤销",
                        fontSize = 11, fontColor = { 255, 150, 150, 200 },
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 16,
                        children = {
                            UI.Button {
                                text = "确认清空", variant = "danger", height = 34,
                                onClick = function(self)
                                    TilemapData.Clear()
                                    HideConfirmDialog()
                                end,
                            },
                            UI.Button {
                                text = "取消", variant = "outline", height = 34,
                                onClick = function(self)
                                    HideConfirmDialog()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    -- === 保存弹框 ===
    saveNameField_ = UI.TextField {
        value = "my_level",
        fontSize = 13,
        height = 36,
        width = 220,
        placeholder = "输入文件名...",
        borderRadius = 6,
        onSubmit = function(self, val)
            if val and #val > 0 then
                SaveToFile(val)
                HideSaveDialog()
            end
        end,
    }

    saveOverlay_ = UI.Panel {
        position = "absolute",
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        visible = false,
        onClick = function(self)
            HideSaveDialog()
        end,
        children = {
            UI.Panel {
                width = 320, height = 180,
                justifyContent = "center", alignItems = "center",
                gap = 16,
                backgroundColor = { 35, 38, 55, 250 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 80, 90, 120, 200 },
                onClick = function(self) end,  -- 阻止穿透
                children = {
                    UI.Label {
                        text = "保存关卡",
                        fontSize = 15, fontWeight = "bold",
                        fontColor = { 255, 255, 255, 240 },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            saveNameField_,
                            UI.Label { text = ".json", fontSize = 12, fontColor = { 150, 160, 180, 180 } },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 16,
                        children = {
                            UI.Button {
                                text = "确认保存", variant = "primary", height = 34,
                                onClick = function(self)
                                    local val = saveNameField_.props.value
                                    if val and #val > 0 then
                                        SaveToFile(val)
                                        HideSaveDialog()
                                    end
                                end,
                            },
                            UI.Button {
                                text = "取消", variant = "outline", height = 34,
                                onClick = function(self) HideSaveDialog() end,
                            },
                        },
                    },
                },
            },
        },
    }

    -- === 加载弹框 ===
    loadListPanel_ = UI.Panel {
        width = "100%",
        gap = 6,
        paddingLeft = 8, paddingRight = 8,
        overflow = "scroll",
        maxHeight = 240,
        children = {},
    }

    loadOverlay_ = UI.Panel {
        position = "absolute",
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        visible = false,
        onClick = function(self)
            HideLoadDialog()
        end,
        children = {
            UI.Panel {
                width = 340,
                minHeight = 160, maxHeight = 360,
                justifyContent = "flex-start", alignItems = "center",
                gap = 12,
                paddingTop = 16, paddingBottom = 16,
                backgroundColor = { 35, 38, 55, 250 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 80, 90, 120, 200 },
                onClick = function(self) end,  -- 阻止穿透
                children = {
                    UI.Label {
                        text = "加载关卡",
                        fontSize = 15, fontWeight = "bold",
                        fontColor = { 255, 255, 255, 240 },
                    },
                    UI.Label {
                        text = "点击选择要加载的文件",
                        fontSize = 11, fontColor = { 150, 160, 180, 150 },
                    },
                    loadListPanel_,
                    UI.Button {
                        text = "取消", variant = "outline", height = 32,
                        onClick = function(self) HideLoadDialog() end,
                    },
                },
            },
        },
    }

    -- === 素材选择器弹框 ===
    assetListPanel_ = UI.Panel {
        width = "100%",
        gap = 6,
        paddingLeft = 8, paddingRight = 8,
        overflow = "scroll",
        maxHeight = 300,
        children = {},
    }

    assetPickerOverlay_ = UI.Panel {
        position = "absolute",
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        visible = false,
        onClick = function(self)
            HideAssetPicker()
        end,
        children = {
            UI.Panel {
                width = 380,
                minHeight = 200, maxHeight = 440,
                justifyContent = "flex-start", alignItems = "center",
                gap = 12,
                paddingTop = 16, paddingBottom = 16,
                backgroundColor = { 35, 38, 55, 250 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 80, 90, 120, 200 },
                onClick = function(self) end,  -- 阻止穿透
                children = {
                    UI.Label {
                        text = "选择素材图片",
                        fontSize = 15, fontWeight = "bold",
                        fontColor = { 255, 255, 255, 240 },
                    },
                    UI.Label {
                        text = "点击图片将其添加为瓦片",
                        fontSize = 11, fontColor = { 150, 160, 180, 150 },
                    },
                    assetListPanel_,
                    UI.Button {
                        text = "取消", variant = "outline", height = 32,
                        onClick = function(self) HideAssetPicker() end,
                    },
                },
            },
        },
    }

    -- === 整体布局 ===
    local root = UI.Panel {
        width = "100%", height = "100%",
        children = {
            topBar,
            UI.Panel {
                flex = 1, width = "100%",
                flexDirection = "row",
                children = {
                    leftPanel,
                    UI.Panel { flex = 1 },  -- NanoVG 绘制区
                    rightPanel,
                },
            },
            bottomBar,
            confirmOverlay_,
            saveOverlay_,
            loadOverlay_,
            assetPickerOverlay_,
        },
    }

    UI.SetRoot(root)
    RebuildPalette()
    RebuildLayerList()
end

-- ============================================================================
-- 事件处理
-- ============================================================================

--- 使用多瓦片画笔绘制一个区域
local function PaintWithBrush(anchorRow, anchorCol)
    if brushMatrix_ and (brushMatrixRows_ > 1 or brushMatrixCols_ > 1) then
        -- 多瓦片画笔：以 anchor 为左上角放置整个矩阵
        for dr = 1, brushMatrixRows_ do
            for dc = 1, brushMatrixCols_ do
                local tileId = brushMatrix_[dr][dc]
                if tileId and tileId > 0 then
                    TilemapData.Paint(anchorRow + dr - 1, anchorCol + dc - 1, tileId)
                end
            end
        end
    else
        -- 单瓦片画笔
        TilemapData.Paint(anchorRow, anchorCol, currentBrushId_)
    end
end

function LevelEditor_HandleUpdate(eventType, eventData)
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr
    layout_ = TilemapRenderer.CalcLayout(logW, logH, UI_MARGINS)

    local mouseX = input.mousePosition.x / dpr
    local mouseY = input.mousePosition.y / dpr
    local row, col = TilemapRenderer.ScreenToGrid(mouseX, mouseY, layout_)
    TilemapRenderer.hoverRow = row
    TilemapRenderer.hoverCol = col

    -- 拖拽绘制/擦除（仅在地图区域内有效）
    if isDrawing_ and row >= 1 and row <= TilemapData.gridHeight
        and col >= 1 and col <= TilemapData.gridWidth then
        if currentTool_ == "erase" then
            TilemapData.Paint(row, col, 0)
        else
            PaintWithBrush(row, col)
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

    -- 多瓦片画笔悬停预览
    if brushMatrix_ and (brushMatrixRows_ > 1 or brushMatrixCols_ > 1) and currentTool_ == "paint" then
        local hr = TilemapRenderer.hoverRow
        local hc = TilemapRenderer.hoverCol
        if hr >= 1 and hr <= TilemapData.gridHeight and hc >= 1 and hc <= TilemapData.gridWidth then
            local cellSize = layout_.cellSize
            local ox = layout_.offsetX
            local oy = layout_.offsetY
            -- 绘制每个画笔格的半透明预览
            for dr = 1, brushMatrixRows_ do
                for dc = 1, brushMatrixCols_ do
                    local tileId = brushMatrix_[dr][dc]
                    if tileId and tileId > 0 then
                        local drawRow = hr + dr - 1
                        local drawCol = hc + dc - 1
                        if drawRow >= 1 and drawRow <= TilemapData.gridHeight
                            and drawCol >= 1 and drawCol <= TilemapData.gridWidth then
                            local cx = ox + (drawCol - 1) * cellSize
                            local cy = oy + (drawRow - 1) * cellSize
                            -- 半透明蓝色覆盖
                            nvgBeginPath(nvg_)
                            nvgRect(nvg_, cx, cy, cellSize, cellSize)
                            nvgFillColor(nvg_, nvgRGBA(80, 160, 255, 60))
                            nvgFill(nvg_)
                        end
                    end
                end
            end
            -- 外框
            local x1 = ox + (hc - 1) * cellSize
            local y1 = oy + (hr - 1) * cellSize
            local w = brushMatrixCols_ * cellSize
            local h = brushMatrixRows_ * cellSize
            nvgBeginPath(nvg_)
            nvgRect(nvg_, x1, y1, w, h)
            nvgStrokeColor(nvg_, nvgRGBA(80, 200, 255, 180))
            nvgStrokeWidth(nvg_, 2.0)
            nvgStroke(nvg_)
        end
    end

    nvgEndFrame(nvg_)
end

function LevelEditor_HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local dpr = graphics:GetDPR()
    local mouseX = input.mousePosition.x / dpr
    local mouseY = input.mousePosition.y / dpr

    -- 如果鼠标在 UI 面板区域（左侧/右侧/顶栏/底栏），不启动地图绘制
    local inMapArea = (mouseX >= UI_MARGINS.left and mouseX <= (graphics:GetWidth() / dpr - UI_MARGINS.right)
        and mouseY >= UI_MARGINS.top and mouseY <= (graphics:GetHeight() / dpr - UI_MARGINS.bottom))

    if button == MOUSEB_LEFT then
        if inMapArea and layout_ then
            isDrawing_ = true
            TilemapData.BeginBatch()
            local row, col = TilemapRenderer.ScreenToGrid(mouseX, mouseY, layout_)
            if currentTool_ == "erase" then
                TilemapData.Paint(row, col, 0)
            else
                PaintWithBrush(row, col)
            end
        end
    elseif button == MOUSEB_RIGHT then
        -- 右键始终擦除（仅在地图区域）
        if inMapArea and layout_ then
            isDrawing_ = true
            TilemapData.BeginBatch()
            local row, col = TilemapRenderer.ScreenToGrid(mouseX, mouseY, layout_)
            TilemapData.Paint(row, col, 0)
        end
    end
end

function LevelEditor_HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_LEFT then
        -- 结束地图绘制
        if isDrawing_ then
            isDrawing_ = false
            TilemapData.EndBatch()
        end
    elseif button == MOUSEB_RIGHT then
        if isDrawing_ then
            isDrawing_ = false
            TilemapData.EndBatch()
        end
    end
end

function LevelEditor_HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_Z and input:GetQualifierDown(QUAL_CTRL) then
        TilemapData.Undo()
    end
end

-- 注册为场景
if SceneManager.SCENE_EDITOR then
    SceneManager.Register(SceneManager.SCENE_EDITOR, LevelEditorUI)
end

return LevelEditorUI

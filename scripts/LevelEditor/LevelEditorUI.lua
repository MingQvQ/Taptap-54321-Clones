-- ============================================================================
-- LevelEditorUI.lua - 关卡编辑器 UI 与交互逻辑（v4）
-- 左侧：瓦片调色板网格（N×N 格子预览 + 框选多瓦片）
-- 右侧：操作工具（绘制/擦除）+ 图层管理
-- 支持 Ctrl+Z 撤销、拖拽批量、多瓦片同时放置、清空确认弹框
-- ============================================================================

local UI = require("urhox-libs/UI")
local TilemapData = require("LevelEditor.TilemapData")
local TilemapRenderer = require("LevelEditor.TilemapRenderer")
local EditorTestBridge = require("LevelEditor.EditorTestBridge")
local SceneManager = require("SceneManager")

local LevelEditorUI = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local nvg_ = nil
local layout_ = nil
local isDrawing_ = false

--- 弹窗关闭后的冷却计时器（防止点击弹窗按钮后误放瓦片）
local uiCooldownTimer_ = 0
local UI_COOLDOWN_DURATION = 0.4  -- 冷却时间（秒）

--- 脏标记：追踪是否有未保存的改动
local dirty_ = false

--- 退出确认弹窗
local exitConfirmOverlay_ = nil

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

--- 瓦片集列表：{ { name, folder, tileIds = {}, collapsed = false }, ... }
local paletteTileSets_ = {}

--- 所有已加载的瓦片 ID 列表（按注册顺序排列，兼容旧逻辑）
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
local arrangeSourceIndex_ = nil  -- { setIdx, localIdx } 或 nil

--- 当前预制体放置旋转角度（0/90/180/270）
local currentRotation_ = 0

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
local deleteOverlay_ = nil
local deleteListPanel_ = nil
local arrangeModeBtn_ = nil

--- 判断是否有任何弹窗/遮罩处于可见状态（用于阻断底层射线/点击）
local function IsAnyOverlayVisible()
    if confirmOverlay_ and confirmOverlay_:IsVisible() then return true end
    if saveOverlay_ and saveOverlay_:IsVisible() then return true end
    if loadOverlay_ and loadOverlay_:IsVisible() then return true end
    if assetPickerOverlay_ and assetPickerOverlay_:IsVisible() then return true end
    if deleteOverlay_ and deleteOverlay_:IsVisible() then return true end
    if exitConfirmOverlay_ and exitConfirmOverlay_:IsVisible() then return true end
    return false
end

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

--- 瓦片集显示名映射（group 名 → 友好中文名）
local TILESET_DISPLAY_NAMES = {
    tilemap_tiles = "通用瓦片",
    softy_sand = "沙地",
    basic = "基础色块",
}

--- 每组瓦片在面板中显示的列数（默认 PALETTE_COLS）
local TILESET_COLS = {
    tilemap_tiles = 4,
    softy_sand = 4,
    basic = 4,
}

--- 瓦片集排列顺序（basic 放最后）
local TILESET_ORDER = { "softy_sand", "tilemap_tiles", "basic" }

--- 从 tileRegistry 的 group 字段构建瓦片集分组
local function AutoLoadTileAssets()
    paletteTileSets_ = {}

    -- 按 group 分组收集已注册瓦片
    local groupMap = {}   -- group -> { tileIds }
    local groupOrder = {} -- 保持发现顺序

    for id = 1, TilemapData.nextTileId - 1 do
        local info = TilemapData.tileRegistry[id]
        if info and info.group then
            local g = info.group
            if not groupMap[g] then
                groupMap[g] = {}
                table.insert(groupOrder, g)
            end
            table.insert(groupMap[g], id)
        end
    end

    -- 按 TILESET_ORDER 排列（basic 放最后），未在 ORDER 里的组追加到末尾
    local orderedGroups = {}
    local ordered = {}
    for _, g in ipairs(TILESET_ORDER) do
        if groupMap[g] then
            table.insert(orderedGroups, g)
            ordered[g] = true
        end
    end
    for _, g in ipairs(groupOrder) do
        if not ordered[g] then
            table.insert(orderedGroups, g)
        end
    end

    -- 构建瓦片集列表
    for _, folder in ipairs(orderedGroups) do
        local displayName = TILESET_DISPLAY_NAMES[folder] or folder
        table.insert(paletteTileSets_, {
            name = displayName,
            folder = folder,
            tileIds = groupMap[folder],
            collapsed = false,
        })
    end
end

--- 刷新调色板瓦片列表（从瓦片集构建扁平列表，兼容旧逻辑）
local function RefreshPaletteTileIds()
    paletteTileIds_ = {}
    for _, tileSet in ipairs(paletteTileSets_) do
        for _, id in ipairs(tileSet.tileIds) do
            table.insert(paletteTileIds_, id)
        end
    end
    -- 补充不在任何分组中的瓦片（手动添加的）
    local inSet = {}
    for _, id in ipairs(paletteTileIds_) do inSet[id] = true end
    for id = 1, TilemapData.nextTileId - 1 do
        if TilemapData.tileRegistry[id] and not inSet[id] then
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
-- 文件操作（使用 clientCloud 持久化 + File 作为会话缓存）
-- ============================================================================

local SAVE_DIR = "LevelEditor"
local CLOUD_PREFIX = "lvled_"
local CLOUD_INDEX_KEY = "lvled_index"

--- 云端保存索引（文件名列表），编辑器初始化时从 cloud 加载
local saveIndex_ = {}
local cloudIndexLoaded_ = false

--- 从云端加载保存索引（编辑器初始化时调用）
local function LoadCloudIndex()
    clientCloud:Get(CLOUD_INDEX_KEY, {
        ok = function(values, iscores)
            if values[CLOUD_INDEX_KEY] then
                saveIndex_ = values[CLOUD_INDEX_KEY]
            end
            cloudIndexLoaded_ = true
            print("[LevelEditor] Cloud index loaded, " .. #saveIndex_ .. " saves")
        end,
        error = function(code, reason)
            cloudIndexLoaded_ = true
            print("[LevelEditor] Cloud index load error: " .. tostring(reason))
        end
    })
end

local function SaveToFile(filename)
    -- 1. 本地 File 缓存（同一会话内即时可用）
    fileSystem:CreateDir(SAVE_DIR)
    local path = SAVE_DIR .. "/" .. filename .. ".json"
    local data = TilemapData.Serialize()
    local json = cjson.encode(data)
    local file = File(path, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(json)
        file:Close()
    end

    -- 2. 持久化到云端（跨刷新保留）
    local cloudKey = CLOUD_PREFIX .. filename
    clientCloud:Set(cloudKey, data, {
        ok = function()
            print("[LevelEditor] Cloud saved: " .. cloudKey)
        end,
        error = function(code, reason)
            print("[LevelEditor] Cloud save error: " .. tostring(reason))
        end
    })

    -- 3. 更新索引（去重后写入云端）
    local found = false
    for _, name in ipairs(saveIndex_) do
        if name == filename then found = true; break end
    end
    if not found then
        table.insert(saveIndex_, filename)
        clientCloud:Set(CLOUD_INDEX_KEY, saveIndex_, {
            ok = function() end,
            error = function() end
        })
    end

    dirty_ = false
    print("[LevelEditor] Saved: " .. filename)
end

local function LoadFromFile(filename)
    -- 优先尝试本地 File 缓存（速度快，同一会话内）
    local localName = filename
    if not string.find(localName, "%.json$") then
        localName = localName .. ".json"
    end
    local path = SAVE_DIR .. "/" .. localName
    if fileSystem:FileExists(path) then
        local file = File(path, FILE_READ)
        if file:IsOpen() then
            local content = file:ReadString()
            file:Close()
            local ok, data = pcall(cjson.decode, content)
            if ok then
                TilemapData.Deserialize(data)
                TilemapRenderer.ClearImageCache()
                currentBrushId_ = 1
                dirty_ = false
                UpdateSizeLabel()
                UpdateSelectedLabel()
                RebuildLayerList()
                RebuildPalette()
                print("[LevelEditor] Loaded from local: " .. filename)
                return true
            end
        end
    end

    -- 本地没有，从云端加载
    local cloudKey = CLOUD_PREFIX .. filename:gsub("%.json$", "")
    clientCloud:Get(cloudKey, {
        ok = function(values, iscores)
            local data = values[cloudKey]
            if data then
                TilemapData.Deserialize(data)
                TilemapRenderer.ClearImageCache()
                currentBrushId_ = 1
                dirty_ = false
                UpdateSizeLabel()
                UpdateSelectedLabel()
                RebuildLayerList()
                RebuildPalette()
                print("[LevelEditor] Loaded from cloud: " .. cloudKey)

                -- 缓存到本地 File（后续同会话内快速加载）
                fileSystem:CreateDir(SAVE_DIR)
                local cacheFile = File(path, FILE_WRITE)
                if cacheFile:IsOpen() then
                    cacheFile:WriteString(cjson.encode(data))
                    cacheFile:Close()
                end
            else
                print("[LevelEditor] Cloud key not found: " .. cloudKey)
            end
        end,
        error = function(code, reason)
            print("[LevelEditor] Cloud load error: " .. tostring(reason))
        end
    })
    return true  -- 异步加载中
end

-- 弹框：保存
local function ShowSaveDialog()
    if saveOverlay_ then saveOverlay_:SetVisible(true) end
end
local function HideSaveDialog()
    if saveOverlay_ then saveOverlay_:SetVisible(false) end
    uiCooldownTimer_ = UI_COOLDOWN_DURATION
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
    uiCooldownTimer_ = UI_COOLDOWN_DURATION
end

-- 弹框：删除关卡文件
local RebuildDeleteList
local function ShowDeleteDialog()
    if deleteOverlay_ then
        RebuildDeleteList()
        deleteOverlay_:SetVisible(true)
    end
end
local function HideDeleteDialog()
    if deleteOverlay_ then deleteOverlay_:SetVisible(false) end
    uiCooldownTimer_ = UI_COOLDOWN_DURATION
end

--- 获取文件大小（不存在或无法打开返回 0）
local function GetLocalFileSize(path)
    if not fileSystem:FileExists(path) then return 0 end
    local f = File(path, FILE_READ)
    if not f:IsOpen() then return 0 end
    local sz = f:GetSize()
    f:Close()
    return sz
end

--- 删除指定关卡文件（本地 + 云端 + 索引）
local function DeleteLevelFile(filename)
    -- 1. 删除本地文件
    local path = SAVE_DIR .. "/" .. filename .. ".json"
    if fileSystem:FileExists(path) then
        -- 尝试直接删除，沙箱可能不支持则写空文件标记
        local ok = pcall(function() fileSystem:Delete(path) end)
        if not ok then
            local f = File(path, FILE_WRITE)
            if f:IsOpen() then
                f:WriteString("")
                f:Close()
            end
        end
        print("[LevelEditor] Deleted local: " .. path)
    end

    -- 2. 删除云端数据（设为 nil 清除）
    local cloudKey = CLOUD_PREFIX .. filename
    clientCloud:Set(cloudKey, nil, {
        ok = function()
            print("[LevelEditor] Deleted cloud: " .. cloudKey)
        end,
        error = function(code, reason)
            print("[LevelEditor] Cloud delete error: " .. tostring(reason))
        end
    })

    -- 3. 从索引中移除并更新云端索引
    for i = #saveIndex_, 1, -1 do
        if saveIndex_[i] == filename then
            table.remove(saveIndex_, i)
            break
        end
    end
    clientCloud:Set(CLOUD_INDEX_KEY, saveIndex_, {
        ok = function() end,
        error = function() end
    })

    -- 刷新列表
    RebuildDeleteList()
end

RebuildDeleteList = function()
    if not deleteListPanel_ then return end
    deleteListPanel_:ClearChildren()

    -- 合并云端索引和本地文件列表（去重）
    local allNames = {}
    local nameSet = {}

    for _, name in ipairs(saveIndex_) do
        if not nameSet[name] then
            nameSet[name] = true
            table.insert(allNames, name)
        end
    end

    fileSystem:CreateDir(SAVE_DIR)
    local files = fileSystem:ScanDir(SAVE_DIR .. "/", "*.json", SCAN_FILES, false)
    for _, fname in ipairs(files) do
        local baseName = fname:gsub("%.json$", "")
        -- 跳过被清空标记的文件（0字节）
        local fpath = SAVE_DIR .. "/" .. fname
        if not nameSet[baseName] and GetLocalFileSize(fpath) > 0 then
            nameSet[baseName] = true
            table.insert(allNames, baseName)
        end
    end

    if #allNames == 0 then
        deleteListPanel_:AddChild(UI.Label {
            text = "暂无存档文件",
            fontSize = 12, fontColor = { 150, 160, 180, 180 },
        })
        return
    end

    for _, name in ipairs(allNames) do
        local filename = name
        deleteListPanel_:AddChild(UI.Panel {
            width = "100%", height = 36,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            paddingLeft = 12, paddingRight = 8,
            backgroundColor = { 40, 44, 60, 180 },
            borderRadius = 6,
            onClick = function(self) end,  -- 阻止穿透
            children = {
                UI.Label {
                    text = "📄 " .. filename .. ".json",
                    fontSize = 12, fontColor = { 255, 255, 255, 230 },
                    flexShrink = 1,
                },
                UI.Button {
                    text = "🗑", variant = "danger", width = 32, height = 28,
                    onClick = function(self)
                        DeleteLevelFile(filename)
                    end,
                },
            },
        })
    end
end

RebuildLoadList = function()
    if not loadListPanel_ then return end
    loadListPanel_:ClearChildren()

    -- 合并云端索引和本地文件列表（去重）
    local allNames = {}
    local nameSet = {}

    -- 优先显示云端索引（持久化数据）
    for _, name in ipairs(saveIndex_) do
        if not nameSet[name] then
            nameSet[name] = true
            table.insert(allNames, name)
        end
    end

    -- 补充本地文件（同会话保存但云端还没同步的）
    fileSystem:CreateDir(SAVE_DIR)
    local files = fileSystem:ScanDir(SAVE_DIR .. "/", "*.json", SCAN_FILES, false)
    for _, fname in ipairs(files) do
        local baseName = fname:gsub("%.json$", "")
        -- 跳过被清空标记的文件（0字节）
        local fpath = SAVE_DIR .. "/" .. fname
        if not nameSet[baseName] and GetLocalFileSize(fpath) > 0 then
            nameSet[baseName] = true
            table.insert(allNames, baseName)
        end
    end

    if #allNames == 0 then
        loadListPanel_:AddChild(UI.Label {
            text = "暂无存档文件",
            fontSize = 12, fontColor = { 150, 160, 180, 180 },
        })
        return
    end

    for _, name in ipairs(allNames) do
        local filename = name
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
                    text = "📄 " .. filename .. ".json",
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
    uiCooldownTimer_ = UI_COOLDOWN_DURATION
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
    uiCooldownTimer_ = UI_COOLDOWN_DURATION
end

-- ============================================================================
-- 场景生命周期
-- ============================================================================

-- 预设网格尺寸配置（对应相机 orthoSize 自适应）
local GRID_PRESETS = {
    { label = "30×13", w = 30, h = 13, desc = "宽屏扩展(推荐)" },
    { label = "24×13", w = 24, h = 13, desc = "标准16:9" },
    { label = "20×11", w = 20, h = 11, desc = "紧凑" },
    { label = "16×9",  w = 16, h = 9,  desc = "迷你" },
}
local currentPresetIndex_ = 1  -- 默认 30×13

function LevelEditorUI.Enter(params)
    local fromTest = params and params.fromTest

    -- 初始化云端保存索引（仅首次加载）
    if not cloudIndexLoaded_ then
        LoadCloudIndex()
    end

    if not fromTest then
        -- 全新进入编辑器：重置地图数据
        TilemapData.New(GRID_PRESETS[1].w, GRID_PRESETS[1].h)
        dirty_ = false
    end
    -- 从测试模式返回：保留 TilemapData 现有数据，不重置

    -- 从注册表构建瓦片集分组
    AutoLoadTileAssets()
    RefreshPaletteTileIds()

    nvg_ = nvgCreate(1)
    nvgCreateFont(nvg_, "sans", "Fonts/MiSans-Regular.ttf")

    if not fromTest then
        currentBrushId_ = 1
        currentTab_ = "tile"
        currentTool_ = "paint"
        paletteSelection_ = nil
        brushMatrix_ = nil
        brushMatrixRows_ = 0
        brushMatrixCols_ = 0
        arrangeMode_ = false
        arrangeSourceIndex_ = nil
    end

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
    deleteOverlay_ = nil
    deleteListPanel_ = nil
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
        -- 瓦片网格调色板（按瓦片集分组）
        RefreshPaletteTileIds()
        local CELL_SIZE_DEFAULT = 22  -- 默认格子像素大小（>4列时）
        local CELL_SIZE_LARGE = 46   -- 4列及以下布局时使用更大格子

        -- 提示文字
        local hintText = arrangeMode_ and "整理模式：点击两个瓦片交换位置" or "点击选择瓦片"
        table.insert(children, UI.Label {
            text = hintText,
            fontSize = 9,
            fontColor = arrangeMode_ and { 255, 200, 100, 220 } or { 150, 160, 180, 150 },
            marginBottom = 2,
        })

        -- 按瓦片集分组显示
        for setIdx, tileSet in ipairs(paletteTileSets_) do
            local setFolder = tileSet.folder
            local isCollapsed = tileSet.collapsed

            -- 分组标题栏（可折叠）
            local capturedSetIdx = setIdx
            table.insert(children, UI.Panel {
                width = "100%", height = 20,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 4, paddingRight = 4,
                backgroundColor = { 40, 45, 60, 200 },
                borderRadius = 3,
                marginTop = (setIdx > 1) and 4 or 0,
                onClick = function(self)
                    paletteTileSets_[capturedSetIdx].collapsed = not paletteTileSets_[capturedSetIdx].collapsed
                    RebuildPalette()
                end,
                children = {
                    UI.Label {
                        text = isCollapsed and "▶" or "▼",
                        fontSize = 8,
                        fontColor = { 180, 190, 210, 200 },
                    },
                    UI.Label {
                        text = " " .. tileSet.name .. " (" .. #tileSet.tileIds .. ")",
                        fontSize = 9,
                        fontColor = { 200, 210, 230, 220 },
                    },
                },
            })

            -- 如果未折叠，显示该组的瓦片网格
            if not isCollapsed then
                local setTileIds = tileSet.tileIds
                local groupCols = TILESET_COLS[setFolder] or PALETTE_COLS
                local cellSize = (groupCols <= 4) and CELL_SIZE_LARGE or CELL_SIZE_DEFAULT
                local setRows = math.ceil(#setTileIds / groupCols)

                for row = 1, setRows do
                    local rowChildren = {}
                    for col = 1, groupCols do
                        local localIndex = (row - 1) * groupCols + col
                        local tileId = setTileIds[localIndex] or 0

                        if tileId > 0 then
                            local info = TilemapData.tileRegistry[tileId]
                            local bgProps = {}
                            if info and info.image then
                                bgProps.backgroundImage = info.image
                                bgProps.backgroundFit = "cover"
                            else
                                bgProps.backgroundColor = info and { info.color[1], info.color[2], info.color[3], 220 } or { 80, 80, 80, 200 }
                            end

                            bgProps.width = cellSize
                            bgProps.height = cellSize
                            bgProps.borderRadius = 2

                            -- 高亮逻辑：当前选中
                            local isSelected = (currentBrushId_ == tileId and currentTool_ == "paint" and not arrangeMode_)
                            -- 整理模式中的源瓦片
                            local isArrangeSource = (arrangeMode_ and arrangeSourceIndex_ ~= nil
                                and arrangeSourceIndex_.setIdx == setIdx and arrangeSourceIndex_.localIdx == localIndex)

                            if isArrangeSource then
                                bgProps.borderWidth = 2
                                bgProps.borderColor = { 255, 200, 50, 255 }
                            elseif isSelected then
                                bgProps.borderWidth = 2
                                bgProps.borderColor = { 100, 200, 255, 255 }
                            else
                                bgProps.borderWidth = 0
                            end

                            -- 捕获闭包变量
                            local capturedTileId = tileId
                            local capturedLocalIndex = localIndex
                            bgProps.onClick = function(self)
                                if arrangeMode_ then
                                    if arrangeSourceIndex_ == nil then
                                        arrangeSourceIndex_ = { setIdx = capturedSetIdx, localIdx = capturedLocalIndex }
                                        RebuildPalette()
                                    else
                                        -- 交换：仅在同一组内交换
                                        local src = arrangeSourceIndex_
                                        if src.setIdx == capturedSetIdx then
                                            local srcLocalIdx = src.localIdx
                                            local dstLocalIdx = capturedLocalIndex
                                            if srcLocalIdx ~= dstLocalIdx
                                                and srcLocalIdx <= #paletteTileSets_[capturedSetIdx].tileIds
                                                and dstLocalIdx <= #paletteTileSets_[capturedSetIdx].tileIds then
                                                local ids = paletteTileSets_[capturedSetIdx].tileIds
                                                ids[srcLocalIdx], ids[dstLocalIdx] = ids[dstLocalIdx], ids[srcLocalIdx]
                                            end
                                        end
                                        arrangeSourceIndex_ = nil
                                        RebuildPalette()
                                    end
                                else
                                    -- 普通模式：选择瓦片
                                    currentBrushId_ = capturedTileId
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
                            -- 空格占位（不可选）
                            table.insert(rowChildren, UI.Panel {
                                width = cellSize, height = cellSize,
                                backgroundColor = { 25, 28, 40, 100 },
                                borderRadius = 2,
                            })
                        end
                    end

                    table.insert(children, UI.Panel {
                        flexDirection = "row",
                        gap = 2,
                        children = rowChildren,
                    })
                end
            end
        end

        -- 手动添加的瓦片（不属于任何分组）
        local ungroupedIds = {}
        local inSet = {}
        for _, ts in ipairs(paletteTileSets_) do
            for _, id in ipairs(ts.tileIds) do inSet[id] = true end
        end
        for id = 1, TilemapData.nextTileId - 1 do
            if TilemapData.tileRegistry[id] and not inSet[id] then
                table.insert(ungroupedIds, id)
            end
        end

        if #ungroupedIds > 0 then
            table.insert(children, UI.Panel {
                width = "100%", height = 20,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 4,
                backgroundColor = { 40, 45, 60, 200 },
                borderRadius = 3,
                marginTop = 4,
                children = {
                    UI.Label {
                        text = "▼ 自定义 (" .. #ungroupedIds .. ")",
                        fontSize = 9,
                        fontColor = { 200, 210, 230, 220 },
                    },
                },
            })
            local ungroupedRows = math.ceil(#ungroupedIds / PALETTE_COLS)
            for row = 1, ungroupedRows do
                local rowChildren = {}
                for col = 1, PALETTE_COLS do
                    local localIndex = (row - 1) * PALETTE_COLS + col
                    local tileId = ungroupedIds[localIndex] or 0
                    if tileId > 0 then
                        local info = TilemapData.tileRegistry[tileId]
                        local bgProps = {}
                        if info and info.image then
                            bgProps.backgroundImage = info.image
                            bgProps.backgroundFit = "cover"
                        else
                            bgProps.backgroundColor = info and { info.color[1], info.color[2], info.color[3], 220 } or { 80, 80, 80, 200 }
                        end
                        bgProps.width = CELL_SIZE_DEFAULT
                        bgProps.height = CELL_SIZE_DEFAULT
                        bgProps.borderRadius = 2
                        local isSelected = (currentBrushId_ == tileId and currentTool_ == "paint" and not arrangeMode_)
                        if isSelected then
                            bgProps.borderWidth = 2
                            bgProps.borderColor = { 100, 200, 255, 255 }
                        else
                            bgProps.borderWidth = 0
                        end
                        local capturedTileId = tileId
                        bgProps.onClick = function(self)
                            currentBrushId_ = capturedTileId
                            brushMatrix_ = nil
                            brushMatrixRows_ = 0
                            brushMatrixCols_ = 0
                            currentTool_ = "paint"
                            UpdateToolButtons()
                            UpdateSelectedLabel()
                            RebuildPalette()
                        end
                        table.insert(rowChildren, UI.Panel(bgProps))
                    else
                        table.insert(rowChildren, UI.Panel {
                            width = CELL_SIZE_DEFAULT, height = CELL_SIZE_DEFAULT,
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
        end



    else
        -- 预制体列表（保持原有列表样式）
        for id = 1, TilemapData.nextPrefabId - 1 do
            local info = TilemapData.prefabRegistry[id]
            if info then
                local prefabId = id
                local isSelected = (currentBrushId_ == prefabId and currentTool_ == "paint")
                local canDelete = not PROTECTED_PREFAB_IDS[prefabId]

                -- 构建名称标签（含属性值）
                local displayName = info.name
                if info.tag == "player_spawn" then
                    displayName = info.name .. " ×" .. (info.playerCount or 5)
                elseif info.tag == "goal" then
                    displayName = info.name .. " ×" .. (info.acceptCount or 1)
                end

                -- 构建图标面板（有图片时显示图片缩略图，否则显示色块+emoji）
                local iconPanel
                if info.image then
                    iconPanel = UI.Panel {
                        width = 28, height = 28,
                        borderRadius = 4,
                        backgroundImage = info.image,
                        backgroundFit = "cover",
                    }
                else
                    iconPanel = UI.Panel {
                        width = 28, height = 28,
                        backgroundColor = { info.color[1], info.color[2], info.color[3], 180 },
                        borderRadius = 4,
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label { text = info.icon, fontSize = 14 },
                        },
                    }
                end

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
                            iconPanel,
                            UI.Label {
                                text = displayName, fontSize = 11,
                                fontColor = { 255, 255, 255, 220 },
                            },
                        },
                    },
                }

                -- 出生点/终点：增减属性按钮
                if info.tag == "player_spawn" or info.tag == "goal" then
                    table.insert(rowChildren, UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 2,
                        children = {
                            UI.Panel {
                                width = 20, height = 20,
                                justifyContent = "center", alignItems = "center",
                                backgroundColor = { 60, 70, 100, 200 },
                                borderRadius = 4,
                                onClick = function(self)
                                    if info.tag == "player_spawn" then
                                        info.playerCount = math.max(1, (info.playerCount or 5) - 1)
                                    else
                                        info.acceptCount = math.max(1, (info.acceptCount or 1) - 1)
                                    end
                                    dirty_ = true
                                    RebuildPalette()
                                end,
                                children = { UI.Label { text = "−", fontSize = 12, fontColor = { 200, 200, 255, 255 } } },
                            },
                            UI.Panel {
                                width = 20, height = 20,
                                justifyContent = "center", alignItems = "center",
                                backgroundColor = { 60, 70, 100, 200 },
                                borderRadius = 4,
                                onClick = function(self)
                                    if info.tag == "player_spawn" then
                                        info.playerCount = (info.playerCount or 5) + 1
                                    else
                                        info.acceptCount = (info.acceptCount or 1) + 1
                                    end
                                    dirty_ = true
                                    RebuildPalette()
                                end,
                                children = { UI.Label { text = "+", fontSize = 12, fontColor = { 200, 200, 255, 255 } } },
                            },
                        },
                    })
                end

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
                            text = (layer.layerKind == "terrain" and "地形层" or layer.layerKind == "environment" and "环境层" or "预制体层") .. " z:" .. layer.zOrder,
                            fontSize = 8,
                            fontColor = layer.layerKind == "environment" and { 120, 200, 120, 180 } or { 150, 160, 180, 150 },
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

    -- 添加图层按钮组（环境层/地形层/预制体层）
    if #TilemapData.layers < TilemapData.MAX_LAYERS then
        table.insert(children, UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 3, marginTop = 4,
            children = {
                UI.Panel {
                    flex = 1, height = 20,
                    justifyContent = "center", alignItems = "center",
                    backgroundColor = { 50, 140, 80, 180 },
                    borderRadius = 3,
                    onClick = function(self)
                        TilemapData.AddLayer("环境", "tile", nil, TilemapData.LAYER_KIND_ENVIRONMENT)
                        RebuildLayerList()
                    end,
                    children = { UI.Label { text = "+环境", fontSize = 9, fontColor = { 255, 255, 255, 220 } } },
                },
                UI.Panel {
                    flex = 1, height = 20,
                    justifyContent = "center", alignItems = "center",
                    backgroundColor = { 50, 100, 160, 180 },
                    borderRadius = 3,
                    onClick = function(self)
                        TilemapData.AddLayer("地形", "tile", nil, TilemapData.LAYER_KIND_TERRAIN)
                        RebuildLayerList()
                    end,
                    children = { UI.Label { text = "+地形", fontSize = 9, fontColor = { 255, 255, 255, 220 } } },
                },
                UI.Panel {
                    flex = 1, height = 20,
                    justifyContent = "center", alignItems = "center",
                    backgroundColor = { 140, 100, 50, 180 },
                    borderRadius = 3,
                    onClick = function(self)
                        TilemapData.AddLayer("预制体", "prefab", nil, TilemapData.LAYER_KIND_PREFAB)
                        RebuildLayerList()
                    end,
                    children = { UI.Label { text = "+预制体", fontSize = 9, fontColor = { 255, 255, 255, 220 } } },
                },
            },
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
                    currentPresetIndex_ = currentPresetIndex_ - 1
                    if currentPresetIndex_ < 1 then currentPresetIndex_ = #GRID_PRESETS end
                    local preset = GRID_PRESETS[currentPresetIndex_]
                    TilemapData.Resize(preset.w, preset.h)
                    dirty_ = true
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
                    currentPresetIndex_ = currentPresetIndex_ + 1
                    if currentPresetIndex_ > #GRID_PRESETS then currentPresetIndex_ = 1 end
                    local preset = GRID_PRESETS[currentPresetIndex_]
                    TilemapData.Resize(preset.w, preset.h)
                    dirty_ = true
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
            -- 自动切换到第一个瓦片类型的图层
            for i, layer in ipairs(TilemapData.layers) do
                if layer.type == "tile" then
                    TilemapData.SetActiveLayer(i)
                    break
                end
            end
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
            -- 自动切换到第一个预制体类型的图层
            for i, layer in ipairs(TilemapData.layers) do
                if layer.type == "prefab" then
                    TilemapData.SetActiveLayer(i)
                    break
                end
            end
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
                text = "🗑 删除", variant = "outline", height = 34,
                onClick = function(self) ShowDeleteDialog() end,
            },
            UI.Button {
                text = "🧹 清空", variant = "danger", height = 34,
                onClick = function(self) ShowConfirmDialog() end,
            },
            UI.Button {
                text = "↩ 撤销", variant = "outline", height = 34,
                onClick = function(self) TilemapData.Undo(); dirty_ = true end,
            },
            UI.Button {
                text = "▶ 测试", variant = "primary", height = 34,
                onClick = function(self) LevelEditorUI.LaunchTest() end,
            },
            UI.Button {
                text = "← 返回", variant = "ghost", height = 34,
                onClick = function(self)
                    if dirty_ then
                        -- 有未保存改动，弹窗确认
                        if exitConfirmOverlay_ then exitConfirmOverlay_:SetVisible(true) end
                    else
                        SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
                    end
                end,
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
                                    dirty_ = true
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

    -- === 删除弹框 ===
    deleteListPanel_ = UI.Panel {
        width = "100%",
        gap = 6,
        paddingLeft = 8, paddingRight = 8,
        overflow = "scroll",
        maxHeight = 240,
        children = {},
    }

    deleteOverlay_ = UI.Panel {
        position = "absolute",
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        visible = false,
        onClick = function(self)
            HideDeleteDialog()
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
                        text = "删除关卡",
                        fontSize = 15, fontWeight = "bold",
                        fontColor = { 255, 255, 255, 240 },
                    },
                    UI.Label {
                        text = "点击 🗑 按钮删除对应文件",
                        fontSize = 11, fontColor = { 255, 150, 150, 180 },
                    },
                    deleteListPanel_,
                    UI.Button {
                        text = "关闭", variant = "outline", height = 32,
                        onClick = function(self) HideDeleteDialog() end,
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

    -- === 退出确认弹框 ===
    exitConfirmOverlay_ = UI.Panel {
        position = "absolute",
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        visible = false,
        onClick = function(self)
            exitConfirmOverlay_:SetVisible(false)
        end,
        children = {
            UI.Panel {
                width = 300, height = 160,
                justifyContent = "center", alignItems = "center",
                gap = 16,
                backgroundColor = { 35, 38, 55, 250 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 80, 90, 120, 200 },
                onClick = function(self) end,  -- 阻止穿透
                children = {
                    UI.Label {
                        text = "当前有未保存的改动",
                        fontSize = 14, fontWeight = "bold",
                        fontColor = { 255, 220, 100, 240 },
                    },
                    UI.Label {
                        text = "离开后未保存的内容将丢失",
                        fontSize = 11, fontColor = { 180, 180, 200, 180 },
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 16,
                        children = {
                            UI.Button {
                                text = "确定离开", variant = "danger", height = 34,
                                onClick = function(self)
                                    exitConfirmOverlay_:SetVisible(false)
                                    uiCooldownTimer_ = UI_COOLDOWN_DURATION
                                    SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
                                end,
                            },
                            UI.Button {
                                text = "取消", variant = "outline", height = 34,
                                onClick = function(self)
                                    exitConfirmOverlay_:SetVisible(false)
                                    uiCooldownTimer_ = UI_COOLDOWN_DURATION
                                end,
                            },
                        },
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
            deleteOverlay_,
            assetPickerOverlay_,
            exitConfirmOverlay_,
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
    dirty_ = true
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
        -- 如果是预制体层且当前选的是尖刺，记录旋转
        local activeLayer = TilemapData.GetActiveLayer()
        if activeLayer and activeLayer.type == "prefab" and currentRotation_ ~= 0 then
            local info = TilemapData.GetPrefabInfo(currentBrushId_)
            if info and info.tag == "spike" then
                TilemapData.SetRotation(anchorRow, anchorCol, currentRotation_)
            end
        end
    end
end

function LevelEditor_HandleUpdate(eventType, eventData)
    require("BGM").Tick()
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
        dirty_ = true
        if currentTool_ == "erase" then
            TilemapData.Paint(row, col, 0)
        else
            PaintWithBrush(row, col)
        end
    end

    -- 更新错误提示计时器
    local dt = eventData["TimeStep"]:GetFloat()
    LevelEditorUI.UpdateErrorToast(dt)

    -- 更新弹窗冷却计时器
    if uiCooldownTimer_ > 0 then
        uiCooldownTimer_ = uiCooldownTimer_ - dt
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

    -- 预制体悬停预览（显示将要放置的预制体图标和颜色）
    if currentTool_ == "paint" and currentTab_ == "prefab" then
        local info = TilemapData.GetPrefabInfo(currentBrushId_)
        if info and info.id ~= 0 then
            local hr = TilemapRenderer.hoverRow
            local hc = TilemapRenderer.hoverCol
            if hr >= 1 and hr <= TilemapData.gridHeight and hc >= 1 and hc <= TilemapData.gridWidth then
                local cellSize = layout_.cellSize
                local ox = layout_.offsetX
                local oy = layout_.offsetY
                local cx = ox + (hc - 1) * cellSize
                local cy = oy + (hr - 1) * cellSize
                local centerX = cx + cellSize / 2
                local centerY = cy + cellSize / 2

                -- 预览：半透明颜色底 + 图标（带旋转）
                nvgSave(nvg_)
                nvgTranslate(nvg_, centerX, centerY)
                if info.tag == "spike" then
                    nvgRotate(nvg_, math.rad(currentRotation_))
                end

                -- 半透明背景
                local c = info.color
                nvgBeginPath(nvg_)
                nvgRoundedRect(nvg_, -cellSize * 0.5 + 2, -cellSize * 0.5 + 2, cellSize - 4, cellSize - 4, 4)
                nvgFillColor(nvg_, nvgRGBA(c[1], c[2], c[3], math.floor(c[4] * 0.35)))
                nvgFill(nvg_)

                -- 边框
                nvgBeginPath(nvg_)
                nvgRoundedRect(nvg_, -cellSize * 0.5 + 2, -cellSize * 0.5 + 2, cellSize - 4, cellSize - 4, 4)
                nvgStrokeColor(nvg_, nvgRGBA(c[1], c[2], c[3], 160))
                nvgStrokeWidth(nvg_, 1.5)
                nvgStroke(nvg_)

                -- 图标
                if info.icon and info.icon ~= "" then
                    nvgFontFace(nvg_, "sans")
                    nvgFontSize(nvg_, cellSize * 0.5)
                    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 180))
                    nvgText(nvg_, 0, 0, info.icon)
                end

                nvgRestore(nvg_)
            end

            -- 尖刺旋转角度提示（右下角）
            if info.tag == "spike" then
                nvgFontFace(nvg_, "sans")
                nvgFontSize(nvg_, 12)
                nvgTextAlign(nvg_, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                nvgFillColor(nvg_, nvgRGBA(220, 50, 50, 220))
                nvgText(nvg_, logW - 16, logH - 56, "旋转: " .. currentRotation_ .. "° [R]")
            end
        end
    end

    -- 错误提示 Toast
    local toastMsg, toastTimer = LevelEditorUI.GetErrorToast()
    if toastTimer > 0 and toastMsg ~= "" then
        local alpha = math.min(1.0, toastTimer / 0.5) * 255
        local tw = 300
        local th = 40
        local tx = (logW - tw) / 2
        local ty = logH * 0.3

        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, tx, ty, tw, th, 8)
        nvgFillColor(nvg_, nvgRGBA(200, 50, 50, math.floor(alpha * 0.9)))
        nvgFill(nvg_)

        nvgFontFace(nvg_, "sans")
        nvgFontSize(nvg_, 14)
        nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg_, nvgRGBA(255, 255, 255, math.floor(alpha)))
        nvgText(nvg_, tx + tw / 2, ty + th / 2, toastMsg)
    end

    nvgEndFrame(nvg_)
end

function LevelEditor_HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local dpr = graphics:GetDPR()
    local mouseX = input.mousePosition.x / dpr
    local mouseY = input.mousePosition.y / dpr

    -- 弹窗打开时阻断所有底层点击/射线
    if IsAnyOverlayVisible() then return end

    -- 弹窗冷却期间不响应地图绘制
    if uiCooldownTimer_ > 0 then return end

    -- 如果鼠标在 UI 面板区域（左侧/右侧/顶栏/底栏），不启动地图绘制
    local inMapArea = (mouseX >= UI_MARGINS.left and mouseX <= (graphics:GetWidth() / dpr - UI_MARGINS.right)
        and mouseY >= UI_MARGINS.top and mouseY <= (graphics:GetHeight() / dpr - UI_MARGINS.bottom))

    if button == MOUSEB_LEFT then
        if inMapArea and layout_ then
            isDrawing_ = true
            TilemapData.BeginBatch()
            local row, col = TilemapRenderer.ScreenToGrid(mouseX, mouseY, layout_)
            dirty_ = true
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
            dirty_ = true
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
        dirty_ = true
    elseif key == KEY_R then
        -- R 键循环旋转角度（0 → 90 → 180 → 270 → 0）
        currentRotation_ = (currentRotation_ + 90) % 360
        print("[LevelEditor] Spike rotation: " .. currentRotation_ .. "°")
    end
end

-- ============================================================================
-- 测试按钮逻辑
-- ============================================================================

--- 显示错误提示（2秒后自动消失）
local errorToastTimer_ = 0
local errorToastMsg_ = ""

--- 启动测试
function LevelEditorUI.LaunchTest()
    -- 验证地图
    local valid, errMsg = EditorTestBridge.Validate()
    if not valid then
        errorToastMsg_ = errMsg
        errorToastTimer_ = 2.5
        print("[LevelEditor] Test validation failed: " .. errMsg)
        return
    end

    -- 转换地图数据
    local levelData = EditorTestBridge.ConvertToLevelData()
    print("[LevelEditor] Launching test: " .. #levelData.platforms .. " platforms, "
        .. #levelData.spikes .. " spikes, playerCount=" .. (levelData.playerCount or 5))

    -- 切换到游戏场景（传递编辑器数据）
    SceneManager.SwitchTo(SceneManager.SCENE_GAME, {
        levelData = levelData,
        fromEditor = true,
    })
end

--- 获取错误提示信息（供渲染器绘制）
function LevelEditorUI.GetErrorToast()
    return errorToastMsg_, errorToastTimer_
end

--- 更新错误提示计时器
function LevelEditorUI.UpdateErrorToast(dt)
    if errorToastTimer_ > 0 then
        errorToastTimer_ = errorToastTimer_ - dt
        if errorToastTimer_ <= 0 then
            errorToastTimer_ = 0
            errorToastMsg_ = ""
        end
    end
end

-- 注册为场景
if SceneManager.SCENE_EDITOR then
    SceneManager.Register(SceneManager.SCENE_EDITOR, LevelEditorUI)
end

return LevelEditorUI

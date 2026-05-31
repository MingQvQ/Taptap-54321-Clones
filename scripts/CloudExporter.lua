-- ============================================================================
-- CloudExporter.lua - 临时模块：从云端导出关卡到本地沙箱
-- 用途：游戏预览时自动从 clientCloud 读取最新编辑器关卡，写入沙箱文件
-- 完成后可删除此文件及 main.lua 中的调用
-- ============================================================================

local TilemapData = require("LevelEditor.TilemapData")
local EditorTestBridge = require("LevelEditor.EditorTestBridge")

local CloudExporter = {}

-- 云端 key → 文件名 映射
local EXPORT_MAP = {
    { key = "lvled_level01", filename = "level01" },
    { key = "lvled_level02", filename = "level02" },
    { key = "lvled_level03", filename = "level03" },
    { key = "lvled_level04", filename = "level04" },
    { key = "lvled_level05", filename = "level05" },
}

--- 将编辑器瓦片地图数据转换为游戏关卡格式
local function ConvertTilemapToLevel(tilemapRawData, levelName)
    TilemapData.Deserialize(tilemapRawData)
    local valid, errMsg = EditorTestBridge.Validate()
    if not valid then
        print("[CloudExporter] Tilemap validation failed for " .. levelName .. ": " .. tostring(errMsg))
        return nil
    end
    local levelData = EditorTestBridge.ConvertToLevelData()
    levelData.name = levelName or levelData.name
    return levelData
end

--- 启动导出流程（异步，需要 clientCloud 可用）
function CloudExporter.Run()
    if not clientCloud then
        print("[CloudExporter] ERROR: clientCloud 不可用，跳过导出")
        return
    end

    print("[CloudExporter] === 开始从云端导出关卡数据 ===")

    -- 先创建输出目录（沙箱内）
    fileSystem:CreateDir("image")

    local batch = clientCloud:BatchGet()
    for _, mapping in ipairs(EXPORT_MAP) do
        batch:Key(mapping.key)
    end

    batch:Fetch({
        ok = function(values, iscores)
            local exported = 0
            for _, mapping in ipairs(EXPORT_MAP) do
                local tilemapData = values[mapping.key]
                if tilemapData then
                    -- 转换为游戏格式
                    local levelData = ConvertTilemapToLevel(tilemapData, mapping.filename)
                    if levelData then
                        -- 编码为 JSON
                        local jsonStr = cjson.encode(levelData)
                        -- 写入沙箱 image/ 目录（不带子目录，确保能写入）
                        local outPath = "image/" .. mapping.filename .. ".json"
                        local file = File(outPath, FILE_WRITE)
                        if file and file:IsOpen() then
                            file:WriteString(jsonStr)
                            file:Close()
                            exported = exported + 1
                            print("[CloudExporter] OK: " .. mapping.key .. " -> " .. outPath)
                        else
                            -- 回退：写到根目录
                            local flatPath = mapping.filename .. ".json"
                            file = File(flatPath, FILE_WRITE)
                            if file and file:IsOpen() then
                                file:WriteString(jsonStr)
                                file:Close()
                                exported = exported + 1
                                print("[CloudExporter] OK(flat): " .. mapping.key .. " -> " .. flatPath)
                            else
                                -- 最终回退：打印到日志
                                print("[CloudExporter] WRITE_FAILED, printing JSON to log:")
                                print("===EXPORT_BEGIN:" .. mapping.filename .. "===")
                                print(jsonStr)
                                print("===EXPORT_END:" .. mapping.filename .. "===")
                            end
                        end
                    else
                        print("[CloudExporter] SKIP: " .. mapping.key .. " 转换失败")
                    end
                else
                    print("[CloudExporter] SKIP: " .. mapping.key .. " 云端无数据")
                end
            end
            print("[CloudExporter] === 导出完成: " .. exported .. "/" .. #EXPORT_MAP .. " 个关卡 ===")
        end,
        error = function(code, reason)
            print("[CloudExporter] ERROR: 云端读取失败 - " .. tostring(reason))
        end,
    })
end

return CloudExporter

-- ============================================================================
-- CloudExporter.lua - 临时模块：从云端读取关卡并输出 JSON 到日志
-- 预览游戏后 AI 从日志文件读取数据，保存到本地
-- 完成后删除此文件及 main.lua 中的调用
-- ============================================================================

local TilemapData = require("LevelEditor.TilemapData")
local EditorTestBridge = require("LevelEditor.EditorTestBridge")

local CloudExporter = {}

local EXPORT_MAP = {
    { key = "lvled_level01", filename = "level01" },
    { key = "lvled_level02", filename = "level02" },
    { key = "lvled_level03", filename = "level03" },
    { key = "lvled_level04", filename = "level04" },
    { key = "lvled_level05", filename = "level05" },
}

local function ConvertTilemapToLevel(tilemapRawData, levelName)
    TilemapData.Deserialize(tilemapRawData)
    local valid, errMsg = EditorTestBridge.Validate()
    if not valid then
        print("[CloudExporter] VALIDATE_FAIL:" .. levelName .. ":" .. tostring(errMsg))
        return nil
    end
    local levelData = EditorTestBridge.ConvertToLevelData()
    levelData.name = levelName or levelData.name
    return levelData
end

function CloudExporter.Run()
    if not clientCloud then
        print("[CloudExporter] NO_CLIENT_CLOUD")
        return
    end

    print("[CloudExporter] FETCHING")

    local batch = clientCloud:BatchGet()
    for _, mapping in ipairs(EXPORT_MAP) do
        batch:Key(mapping.key)
    end

    batch:Fetch({
        ok = function(values, iscores)
            for _, mapping in ipairs(EXPORT_MAP) do
                local tilemapData = values[mapping.key]
                if tilemapData then
                    local levelData = ConvertTilemapToLevel(tilemapData, mapping.filename)
                    if levelData then
                        local jsonStr = cjson.encode(levelData)
                        -- 用唯一标记输出，AI 从日志中提取
                        print("CLOUD_JSON_START:" .. mapping.filename)
                        print(jsonStr)
                        print("CLOUD_JSON_END:" .. mapping.filename)
                    end
                else
                    print("[CloudExporter] EMPTY:" .. mapping.key)
                end
            end
            print("[CloudExporter] DONE")
        end,
        error = function(code, reason)
            print("[CloudExporter] ERROR:" .. tostring(reason))
        end,
    })
end

return CloudExporter

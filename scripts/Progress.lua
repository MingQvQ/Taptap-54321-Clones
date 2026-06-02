-- Progress.lua
-- 关卡进度管理：存档/读档/解锁判定

local Progress = {}

local SAVE_FILE = "progress.json"

-- 内存缓存
local data_ = nil

--- 加载存档（仅加载一次，之后走缓存）
function Progress.Load()
    if data_ then return data_ end

    if fileSystem:FileExists(SAVE_FILE) then
        local file = File(SAVE_FILE, FILE_READ)
        if file:IsOpen() then
            local ok, parsed = pcall(cjson.decode, file:ReadString())
            file:Close()
            if ok and type(parsed) == "table" then
                data_ = parsed
                return data_
            end
        end
    end

    -- 默认数据：只有第1关解锁
    data_ = {
        unlockedLevel = 1,  -- 当前已解锁的最高关卡
    }
    return data_
end

--- 保存存档到本地
function Progress.Save()
    if not data_ then return end
    local file = File(SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(data_))
        file:Close()
    end
end

--- 获取当前解锁的最高关卡编号
function Progress.GetUnlockedLevel()
    local d = Progress.Load()
    return d.unlockedLevel or 1
end

--- 通关某一关后调用：解锁下一关
function Progress.CompleteLevel(levelIndex)
    local d = Progress.Load()
    if levelIndex >= (d.unlockedLevel or 1) then
        d.unlockedLevel = levelIndex + 1
        Progress.Save()
        print("[Progress] Level " .. levelIndex .. " completed! Unlocked up to level " .. d.unlockedLevel)
    end
end

--- 重置进度（调试用）
function Progress.Reset()
    data_ = { unlockedLevel = 1 }
    Progress.Save()
end

return Progress

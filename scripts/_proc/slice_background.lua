-- 切割 background.png - 简化测试
function Start()
    local ok, err = pcall(function()
        print("[slice] Starting...")
        local src = Image()
        local f = cache:GetFile("image/tilemap/background.png")
        if not f then
            print("[slice] ERROR: cannot open file")
            engine:Exit()
            return
        end
        local loaded = src:Load(f)
        if not loaded then
            print("[slice] ERROR: Load failed")
            engine:Exit()
            return
        end
        print("[slice] Loaded: " .. src.width .. "x" .. src.height .. " components=" .. src.components)

        local outDir = "/workspace/assets/image/tilemap/background/"
        fileSystem:CreateDir(outDir)

        -- 先只切一个 sky 试试（不需要透明处理）
        local tileW, tileH = 320, 180
        local skyImg = src:GetSubimage(IntRect(0, 0, tileW, tileH))
        if not skyImg then
            print("[slice] ERROR: GetSubimage returned nil")
            engine:Exit()
            return
        end
        print("[slice] sky subimage: " .. skyImg.width .. "x" .. skyImg.height)

        local saved = skyImg:SavePNG(outDir .. "sky.png")
        print("[slice] sky saved: " .. tostring(saved))
    end)
    if not ok then
        print("[slice] PCALL ERROR: " .. tostring(err))
    end
    engine:Exit()
end

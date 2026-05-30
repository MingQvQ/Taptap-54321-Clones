function Start()
    local ok, err = pcall(function()
        local tasks = {
            { res = "image/character/jump/character_berie_jump.png", outDir = "/workspace/assets/image/character/jump/", prefix = "berie_jump_", frames = 4 },
            { res = "image/character/run/character_berie_run.png", outDir = "/workspace/assets/image/character/run/", prefix = "berie_run_", frames = 6 },
            { res = "image/character/showoff/character_berie_showoff.png", outDir = "/workspace/assets/image/character/showoff/", prefix = "berie_showoff_", frames = 7 },
        }

        for _, task in ipairs(tasks) do
            local img = cache:GetResource("Image", task.res)
            assert(img, "Failed to load: " .. task.res)

            local w = img:GetWidth()
            local h = img:GetHeight()
            local frameW = math.floor(w / task.frames)

            print(("[slice] %s: %dx%d, frames=%d, frameW=%d"):format(task.res, w, h, task.frames, frameW))

            for i = 1, task.frames do
                local x = (i - 1) * frameW
                local sub = img:GetSubimage(IntRect(x, 0, x + frameW, h))
                local outPath = task.outDir .. task.prefix .. i .. ".png"
                assert(sub:SavePNG(outPath), "SavePNG failed: " .. outPath)
                print(("[slice]   frame %d saved"):format(i))
            end
        end

        print("[slice] All done!")
    end)
    if not ok then
        log:Write(LOG_ERROR, "[slice] " .. tostring(err))
    end
    engine:Exit()
end

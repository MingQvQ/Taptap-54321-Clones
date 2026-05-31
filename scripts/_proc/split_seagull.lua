function Start()
    local ok, err = pcall(function()
        local img = Image()
        assert(img:Load(cache:GetFile("image/seagull_fly_20260530231625.png")), "Failed to load seagull sprite sheet")

        local W = img:GetWidth()
        local H = img:GetHeight()
        local frames = 4
        local frameW = math.floor(W / frames)

        print(("[split_seagull] Source: %dx%d, frameW=%d, frames=%d"):format(W, H, frameW, frames))

        for i = 1, frames do
            local x0 = (i - 1) * frameW
            local sub = img:GetSubimage(IntRect(x0, 0, x0 + frameW, H))
            local outPath = ("/workspace/assets/image/enemy/seagull/seagull_fly_%d.png"):format(i)
            assert(sub:SavePNG(outPath), "SavePNG failed for frame " .. i)
            print(("[split_seagull] Saved frame %d -> %s"):format(i, outPath))
        end
    end)
    if not ok then
        log:Write(LOG_ERROR, "[split_seagull] " .. tostring(err))
    end
    engine:Exit()
end

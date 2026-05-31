-- 将木板告示牌图片像素化：每2x2块取左上角颜色填充，制造更大颗粒感
function Start()
    local ok, err = pcall(function()
        local src = Image()
        assert(src:Load(cache:GetFile("image/wooden_sign_8bit_20260531012012.png")), "Load failed")

        local w, h = src.width, src.height
        print(string.format("[pixelate] Original size: %dx%d", w, h))

        -- 创建半尺寸的新图（每2x2采样一个像素）
        local halfW = math.floor(w / 2)
        local halfH = math.floor(h / 2)
        local dst = Image()
        dst:SetSize(halfW, halfH, 4)

        for y = 0, halfH - 1 do
            for x = 0, halfW - 1 do
                local c = src:GetPixel(x * 2, y * 2)
                dst:SetPixel(x, y, c)
            end
        end

        assert(dst:SavePNG("/workspace/assets/image/wooden_sign_final.png"), "SavePNG failed")
        print(string.format("[pixelate] Saved %dx%d to /workspace/assets/image/wooden_sign_final.png", halfW, halfH))
    end)
    if not ok then print("[pixelate] ERROR: " .. tostring(err)) end
    engine:Exit()
end

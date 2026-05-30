-- ============================================================================
-- PlayMode.lua — 游玩模式（角色 WASD 移动 + 碰撞检测）
-- ============================================================================

local MapData = require("MapData")

local PlayMode = {}

-- 角色状态
PlayMode.active = false
PlayMode.playerX = 1.0       -- 浮点地图坐标 (1-based)
PlayMode.playerY = 1.0
PlayMode.moveSpeed = 4.0     -- 格/秒

-- 角色外观
PlayMode.playerColor = { 66, 165, 245 }     -- 蓝色（备用）
PlayMode.shadowColor = { 0, 0, 0, 80 }      -- 阴影
PlayMode.charImage = "Tiles/blacksmith_char.png"  -- 角色图片路径

-- ============================================================================
-- 进入/退出
-- ============================================================================

--- 进入游玩模式，放置角色在地图中心或第一个可行走瓦片
function PlayMode.Enter()
    -- 尝试地图中心
    local cx = math.floor(MapData.MAP_W / 2) + 1
    local cy = math.floor(MapData.MAP_H / 2) + 1

    if MapData.IsWalkable(cx, cy) then
        PlayMode.playerX = cx
        PlayMode.playerY = cy
    else
        -- 搜索第一个可行走瓦片（从中心向外扩散）
        local found = false
        for r = 1, math.max(MapData.MAP_W, MapData.MAP_H) do
            for dy = -r, r do
                for dx = -r, r do
                    if math.abs(dx) == r or math.abs(dy) == r then
                        local tx, ty = cx + dx, cy + dy
                        if MapData.InBounds(tx, ty) and MapData.IsWalkable(tx, ty) then
                            PlayMode.playerX = tx
                            PlayMode.playerY = ty
                            found = true
                            break
                        end
                    end
                end
                if found then break end
            end
            if found then break end
        end

        if not found then
            -- 没有可行走瓦片，放在地图中心
            PlayMode.playerX = cx
            PlayMode.playerY = cy
        end
    end

    PlayMode.active = true
    print(string.format("[PlayMode] 进入游玩模式，角色位置: (%d, %d)", math.floor(PlayMode.playerX), math.floor(PlayMode.playerY)))
end

--- 退出游玩模式
function PlayMode.Exit()
    PlayMode.active = false
    print("[PlayMode] 退出游玩模式")
end

--- 是否处于游玩模式
---@return boolean
function PlayMode.IsActive()
    return PlayMode.active
end

--- 获取角色位置
---@return number, number
function PlayMode.GetPosition()
    return PlayMode.playerX, PlayMode.playerY
end

--- 获取角色所在的格子坐标 (1-based 整数)
---@return number, number
function PlayMode.GetGridPosition()
    return math.floor(PlayMode.playerX + 0.5), math.floor(PlayMode.playerY + 0.5)
end

-- ============================================================================
-- 移动逻辑
-- ============================================================================

--- 每帧更新（处理 WASD 输入和碰撞检测）
---@param dt number 帧间隔
function PlayMode.Update(dt)
    if not PlayMode.active then return end

    -- 等距方向映射：
    -- W = 向"上"（屏幕左上方）→ 地图 (-1, -1)
    -- S = 向"下"（屏幕右下方）→ 地图 (+1, +1)
    -- A = 向"左"（屏幕左下方）→ 地图 (-1, +1)
    -- D = 向"右"（屏幕右上方）→ 地图 (+1, -1)
    local dmx = 0
    local dmy = 0

    if input:GetKeyDown(KEY_W) then dmx = dmx - 1; dmy = dmy - 1 end
    if input:GetKeyDown(KEY_S) then dmx = dmx + 1; dmy = dmy + 1 end
    if input:GetKeyDown(KEY_A) then dmx = dmx - 1; dmy = dmy + 1 end
    if input:GetKeyDown(KEY_D) then dmx = dmx + 1; dmy = dmy - 1 end

    if dmx == 0 and dmy == 0 then return end

    -- 归一化对角线移动速度
    local len = math.sqrt(dmx * dmx + dmy * dmy)
    if len > 0 then
        dmx = dmx / len
        dmy = dmy / len
    end

    local speed = PlayMode.moveSpeed * dt
    local newX = PlayMode.playerX + dmx * speed
    local newY = PlayMode.playerY + dmy * speed

    -- 碰撞检测：检查目标格子是否可走
    local gridX = math.floor(newX + 0.5)
    local gridY = math.floor(newY + 0.5)

    if MapData.IsWalkable(gridX, gridY) then
        -- 目标格可走，直接移动
        PlayMode.playerX = newX
        PlayMode.playerY = newY
    else
        -- 目标格不可走，尝试单轴滑行
        local slideX = PlayMode.playerX + dmx * speed
        local slideY = PlayMode.playerY
        local sgx = math.floor(slideX + 0.5)
        local sgy = math.floor(slideY + 0.5)

        if dmx ~= 0 and MapData.IsWalkable(sgx, sgy) then
            PlayMode.playerX = slideX
        else
            local slideX2 = PlayMode.playerX
            local slideY2 = PlayMode.playerY + dmy * speed
            local sgx2 = math.floor(slideX2 + 0.5)
            local sgy2 = math.floor(slideY2 + 0.5)

            if dmy ~= 0 and MapData.IsWalkable(sgx2, sgy2) then
                PlayMode.playerY = slideY2
            end
            -- 两轴都不可走 → 不动
        end
    end

    -- 边界限制
    PlayMode.playerX = math.max(1, math.min(MapData.MAP_W, PlayMode.playerX))
    PlayMode.playerY = math.max(1, math.min(MapData.MAP_H, PlayMode.playerY))
end

return PlayMode

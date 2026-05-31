-- ============================================================================
-- BGM.lua - 全局背景音乐单例管理器
-- 特性：永远循环，不受游戏暂停/场景切换/事件取消订阅影响
-- 使用方式：在每个场景的 Update handler 中调用 BGM.Tick()
-- ============================================================================

local Config = require("Config")

local BGM = {}

local source_ = nil
local sound_ = nil
local node_ = nil
local scene_ = nil

--- 初始化 BGM（只调用一次）
function BGM.Init()
    if source_ then return end  -- 已初始化，不重复

    -- 创建独立 Scene 持有 SoundSource（不会被游戏场景销毁影响）
    scene_ = Scene()
    node_ = scene_:CreateChild("BGM_Global")
    source_ = node_:CreateComponent("SoundSource")
    source_:SetSoundType("Music")

    sound_ = cache:GetResource("Sound", "audio/bgm/beach_breeze.ogg")
    if sound_ then
        sound_.looped = true
        source_.gain = Config.Settings.MusicVolume
        source_:Play(sound_)
        print("[BGM] Initialized and playing, volume: " .. Config.Settings.MusicVolume)
    else
        print("[BGM] ERROR: Failed to load audio/bgm/beach_breeze.ogg")
    end
end

--- 每帧调用（由各场景的 Update handler 调用）
--- 检测音乐是否停止/暂停，如果是则从头重新播放
--- 同步音量设置
function BGM.Tick()
    if not source_ or not sound_ then return end

    -- 如果音乐因为任何原因停止了，重新从头播放
    if not source_:IsPlaying() then
        sound_.looped = true
        source_:Play(sound_)
        print("[BGM] Restarted playback")
    end

    -- 实时同步音量
    source_.gain = Config.Settings.MusicVolume
end

--- 更新音量（外部设置界面调用）
function BGM.SetVolume(vol)
    Config.Settings.MusicVolume = vol
    if source_ then
        source_.gain = vol
    end
end

--- 获取当前音量
function BGM.GetVolume()
    return Config.Settings.MusicVolume
end

return BGM

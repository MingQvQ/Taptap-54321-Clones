-- ============================================================================
-- Config.lua - 全局配置模块
-- 所有可调参数集中管理，方便后期修改
-- ============================================================================

local Config = {}

-- 游戏基本信息
Config.Title = "克隆小猪"
Config.Version = "1.1.5"

-- 物理常量
Config.Gravity = 20.0              -- 重力加速度
Config.PlayerSpeed = 4.0           -- 玩家水平移动速度（4格/秒）
Config.PlayerJumpSpeed = 7.48      -- 玩家跳跃初速度（最大高度≈1.4格）
Config.PlayerRadius = 0.6          -- 玩家碰撞半径（物理单位）

-- 可变重力系数（上升/下降不同手感）
Config.GravityScaleRising = 1.0    -- 上升阶段重力系数（轻盈）
Config.GravityScaleFalling = 2.5   -- 下降阶段重力系数（快速落地）

-- 录制系统
Config.RecordDuration = 5.0        -- 固定录制时长（秒）
Config.RecordInterval = 1 / 30     -- 动作录制间隔（30fps 采样）

-- 渲染常量
Config.PixelsPerUnit = 50          -- 1物理单位 = 50像素

-- 克隆系统
Config.CloneCount = 5              -- 总角色数（含玩家，数字5-4-3-2-1）
Config.FirstSpawnInterval = 1.5    -- 第一个角色（玩家）生成间隔（秒，快）
Config.CloneInterval = 4.0         -- 后续克隆体生成间隔（秒，慢）

-- 关卡配置
Config.FallDeathY = -2.0           -- 掉落死亡Y坐标（单屏关卡，屏幕下方即死亡）
Config.SpikeKillRadius = 0.3       -- 尖刺伤害半径

-- 颜色配置（RGBA）
Config.Colors = {
    Player = { 80, 160, 255, 255 },       -- 玩家颜色（蓝色）
    Clone1 = { 255, 120, 80, 255 },       -- 克隆1（橙色）
    Clone2 = { 255, 220, 60, 255 },       -- 克隆2（黄色）
    Clone3 = { 120, 220, 80, 255 },       -- 克隆3（绿色）
    Clone4 = { 200, 120, 255, 255 },      -- 克隆4（紫色）
    Platform = { 80, 180, 80, 255 },      -- 平台颜色
    Spike = { 220, 50, 50, 255 },         -- 尖刺颜色
    Goal = { 255, 215, 0, 255 },          -- 终点颜色（金色）
    Background1 = { 40, 44, 62, 255 },    -- 背景渐变上
    Background2 = { 25, 28, 42, 255 },    -- 背景渐变下
    TimerRing = { 100, 200, 255, 255 },   -- 计时器环颜色
    TimerBg = { 40, 45, 60, 200 },        -- 计时器背景
}

-- 克隆体颜色数组（按生成顺序）
Config.CloneColors = {
    Config.Colors.Player,  -- 玩家自己
    Config.Colors.Clone1,
    Config.Colors.Clone2,
    Config.Colors.Clone3,
    Config.Colors.Clone4,
}

-- 运行时设置
Config.Settings = {
    MusicVolume = 0.4,       -- 音乐音量 0.0~1.0
    SFXVolume = 0.4,         -- 音效音量 0.0~1.0
    CameraZoom = 0.95,       -- 相机缩放 0.5~2.0（1.0=自动适配，<1放大，>1缩小看更多）
    CameraOffsetX = 0.0,     -- 相机水平偏移 -5.0~5.0（单位：米）
    CameraOffsetY = -3.6,    -- 相机垂直偏移 -5.0~5.0（单位：米）
}

return Config

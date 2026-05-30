-- ============================================================================
-- main.lua - 54321 Clone Runner 主入口
-- 2D平台跳跃闯关游戏：克隆体复刻玩家动作，全员到达终点即通关
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local Config = require("Config")
local SceneManager = require("SceneManager")
local LevelData = require("LevelData")

-- 加载各模块（注册场景）
require("GameScene")
require("UIScenes")

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    -- 初始化 Sample 基础设施
    SampleStart()

    -- 初始化 UI 系统
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 加载关卡数据
    LevelData.Init()

    -- 设置窗口标题
    graphics.windowTitle = Config.Title

    -- 进入开始界面
    SceneManager.SwitchTo(SceneManager.SCENE_TITLE)

    print("=== " .. Config.Title .. " v" .. Config.Version .. " ===")
    print("模块化架构已加载:")
    print("  - Config.lua (全局配置)")
    print("  - SceneManager.lua (场景管理)")
    print("  - Player.lua (玩家控制)")
    print("  - CloneSystem.lua (克隆系统)")
    print("  - LevelData.lua (关卡数据)")
    print("  - GameScene.lua (游戏主场景)")
    print("  - UIScenes.lua (UI界面)")
end

function Stop()
    -- 退出当前场景
    local currentName = SceneManager.GetCurrent()
    if currentName == SceneManager.SCENE_GAME then
        local GameScene = require("GameScene")
        GameScene.Exit()
    end

    -- 清理 UI 系统
    UI.Shutdown()
end

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
require("LevelEditor.LevelEditorUI")

-- ============================================================================
-- 背景音乐（全局单例模块，不依赖事件订阅，由各场景 Update 驱动）
-- ============================================================================
local BGM = require("BGM")

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    -- 初始化 Sample 基础设施
    SampleStart()

    -- 初始化 UI 系统（PixelForge 像素风格主题）
    local PIXEL_SHADOW = {
        { x = 3, y = 3, blur = 0, color = {10, 10, 26, 204} },
        { x = -1, y = -1, blur = 0, color = {255, 255, 255, 48} },
    }

    local PixelForgeTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        colors = {
            primary = {33, 189, 174, 255},
            primaryHover = {61, 208, 193, 255},
            primaryPressed = {25, 168, 153, 255},
            secondary = {108, 92, 231, 255},
            secondaryHover = {133, 119, 237, 255},
            secondaryPressed = {90, 75, 214, 255},
            background = {15, 15, 35, 255},
            surface = {27, 27, 58, 255},
            surfaceHover = {37, 37, 80, 255},
            text = {240, 240, 240, 255},
            textSecondary = {160, 160, 192, 255},
            textDisabled = {80, 80, 112, 255},
            border = {58, 58, 106, 255},
            borderFocus = {33, 189, 174, 255},
            disabled = {42, 42, 74, 255},
            disabledText = {80, 80, 112, 255},
            success = {80, 200, 120, 255},
            warning = {255, 217, 61, 255},
            error = {255, 71, 87, 255},
            info = {69, 170, 242, 255},
            overlay = {0, 0, 0, 180},
        },
        radius = {
            sm = 0, md = 0, lg = 0, xl = 0, full = 0,
        },
        componentDefaults = {
            borderRadius = 0,
        },
        components = {
            Button = { borderWidth = 2, boxShadow = PIXEL_SHADOW },
            TextField = { borderWidth = 2 },
            Slider = {
                borderWidth = 1,
                trackBgColor = {27, 27, 58, 255},
                trackFillColor = {33, 189, 174, 255},
                thumbColor = {33, 189, 174, 255},
                thumbBorderWidth = 2,
                thumbBorderColor = {27, 176, 161, 255},
            },
            Card = {
                borderWidth = 2,
                boxShadow = {
                    { x = 4, y = 4, blur = 0, color = {10, 10, 26, 204} },
                },
            },
            Modal = {
                borderWidth = 2,
                boxShadow = {
                    { x = 4, y = 4, blur = 0, color = {0, 0, 0, 204} },
                },
            },
        },
    })

    UI.Init({
        theme = PixelForgeTheme,
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/FusionPixel-12px-Prop-zh_hans.ttf",
                bold = "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf",
            } },
            { family = "mono", weights = {
                normal = "Fonts/FusionPixel-12px-Mono-zh_hans.ttf",
            } },
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 加载关卡数据
    LevelData.Init()

    -- 设置窗口标题
    graphics.windowTitle = Config.Title

    -- 初始化并播放背景音乐
    BGM.Init()

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

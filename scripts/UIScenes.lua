-- ============================================================================
-- UIScenes.lua - UI 界面模块
-- 包含：开始游戏界面、关卡选择界面、设置界面
-- 使用 urhox-libs/UI 控件库
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local SceneManager = require("SceneManager")
local LevelData = require("LevelData")

local UIScenes = {}

-- ============================================================================
-- 开始游戏界面 (Title Screen)
-- ============================================================================

local TitleScene = {}

function TitleScene.Enter(params)
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 25, 28, 42, 255 },
        children = {
            UI.Panel {
                width = "90%",
                maxWidth = 400,
                padding = 40,
                gap = 20,
                alignItems = "center",
                backgroundColor = { 35, 40, 58, 240 },
                borderRadius = 20,
                borderWidth = 2,
                borderColor = { 80, 140, 255, 100 },
                children = {
                    -- 游戏标题
                    UI.Label {
                        text = "影子伙伴",
                        fontSize = 48,
                        fontColor = { 100, 200, 255, 255 },
                    },
                    -- 间隔
                    UI.Panel { height = 20 },
                    -- 开始按钮
                    UI.Button {
                        text = "开始游戏",
                        variant = "primary",
                        width = 200,
                        height = 48,
                        onClick = function(self)
                            SceneManager.SwitchTo(SceneManager.SCENE_LEVEL_SELECT)
                        end,
                    },

                    -- 设置按钮
                    UI.Button {
                        text = "设置",
                        variant = "outline",
                        width = 200,
                        height = 44,
                        onClick = function(self)
                            SceneManager.SwitchTo(SceneManager.SCENE_SETTINGS)
                        end,
                    },
                    -- 版本号
                    UI.Panel { height = 10 },
                    UI.Label {
                        text = "v" .. Config.Version,
                        fontSize = 12,
                        fontColor = { 100, 110, 130, 150 },
                    },
                }
            }
        }
    }
    UI.SetRoot(root)
end

function TitleScene.Exit()
    UI.SetRoot(nil)
end

SceneManager.Register(SceneManager.SCENE_TITLE, TitleScene)

-- ============================================================================
-- 关卡选择界面 (Level Select)
-- ============================================================================

local LevelSelectScene = {}

function LevelSelectScene.Enter(params)
    local levelButtons = {}
    local levelCount = LevelData.GetLevelCount()

    for i = 1, levelCount do
        local levelInfo = LevelData.GetLevel(i)
        local levelIndex = i
        table.insert(levelButtons, UI.Button {
            text = "第 " .. i .. " 关\n" .. levelInfo.name,
            width = "100%",
            height = 56,
            marginBottom = 8,
            onClick = function(self)
                SceneManager.SwitchTo(SceneManager.SCENE_GAME, { level = levelIndex })
            end,
        })
    end

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 25, 28, 42, 255 },
        children = {
            UI.Panel {
                width = "90%",
                maxWidth = 400,
                padding = 32,
                gap = 12,
                alignItems = "center",
                backgroundColor = { 35, 40, 58, 240 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 80, 140, 255, 80 },
                children = {
                    UI.Label {
                        text = "选择关卡",
                        fontSize = 28,
                        fontColor = { 255, 255, 255, 255 },
                        marginBottom = 16,
                    },
                    -- 关卡按钮区
                    UI.Panel {
                        width = "100%",
                        gap = 0,
                        children = levelButtons,
                    },
                    -- 返回按钮
                    UI.Panel { height = 12 },
                    UI.Button {
                        text = "返回",
                        variant = "ghost",
                        width = 120,
                        height = 40,
                        onClick = function(self)
                            SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
                        end,
                    },
                }
            }
        }
    }
    UI.SetRoot(root)
end

function LevelSelectScene.Exit()
    UI.SetRoot(nil)
end

SceneManager.Register(SceneManager.SCENE_LEVEL_SELECT, LevelSelectScene)

-- ============================================================================
-- 设置界面 (Settings)
-- ============================================================================

local SettingsScene = {}

function SettingsScene.Enter(params)
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 25, 28, 42, 255 },
        children = {
            UI.Panel {
                width = "90%",
                maxWidth = 400,
                padding = 32,
                gap = 16,
                alignItems = "center",
                backgroundColor = { 35, 40, 58, 240 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 80, 140, 255, 80 },
                children = {
                    UI.Label {
                        text = "设置",
                        fontSize = 28,
                        fontColor = { 255, 255, 255, 255 },
                        marginBottom = 8,
                    },
                    -- 音乐音量
                    UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = "音乐音量",
                                fontSize = 14,
                                fontColor = { 180, 190, 210, 220 },
                            },
                            UI.Slider {
                                value = Config.Settings.MusicVolume * 100,
                                min = 0,
                                max = 100,
                                width = "100%",
                                onChange = function(self, val)
                                    Config.Settings.MusicVolume = val / 100
                                end,
                            },
                        }
                    },
                    -- 音效音量
                    UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = "音效音量",
                                fontSize = 14,
                                fontColor = { 180, 190, 210, 220 },
                            },
                            UI.Slider {
                                value = Config.Settings.SFXVolume * 100,
                                min = 0,
                                max = 100,
                                width = "100%",
                                onChange = function(self, val)
                                    Config.Settings.SFXVolume = val / 100
                                end,
                            },
                        }
                    },
                    -- 游戏说明
                    UI.Panel { height = 8 },
                    UI.Panel {
                        width = "100%",
                        padding = 12,
                        backgroundColor = { 20, 24, 36, 200 },
                        borderRadius = 8,
                        children = {
                            UI.Label {
                                text = "玩法说明:\n" ..
                                    "· 方向键/WASD 移动，空格跳跃\n" ..
                                    "· 出生点计时器每圈生成一个克隆体\n" ..
                                    "· 克隆体会复刻你的全部操作\n" ..
                                    "· 所有角色到达终点即通关\n" ..
                                    "· 任何角色掉落或碰尖刺即失败",
                                fontSize = 12,
                                fontColor = { 160, 170, 190, 200 },
                            },
                        }
                    },
                    -- 返回按钮
                    UI.Panel { height = 12 },
                    UI.Button {
                        text = "返回",
                        variant = "primary",
                        width = 150,
                        height = 44,
                        onClick = function(self)
                            SceneManager.SwitchTo(SceneManager.SCENE_TITLE)
                        end,
                    },
                }
            }
        }
    }
    UI.SetRoot(root)
end

function SettingsScene.Exit()
    UI.SetRoot(nil)
end

SceneManager.Register(SceneManager.SCENE_SETTINGS, SettingsScene)

return UIScenes

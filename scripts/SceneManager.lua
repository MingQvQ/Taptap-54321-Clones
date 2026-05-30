-- ============================================================================
-- SceneManager.lua - 场景/界面切换管理器
-- 管理不同界面之间的切换：开始、关卡选择、游戏、设置
-- ============================================================================

local SceneManager = {}

-- 场景类型枚举
SceneManager.SCENE_TITLE = "title"
SceneManager.SCENE_LEVEL_SELECT = "level_select"
SceneManager.SCENE_GAME = "game"
SceneManager.SCENE_SETTINGS = "settings"


-- 当前场景
SceneManager.currentScene = nil
SceneManager.currentSceneName = ""

-- 场景注册表
local sceneHandlers = {}

--- 注册场景处理器
---@param name string
---@param handler table  需要有 Enter(params) 和 Exit() 方法
function SceneManager.Register(name, handler)
    sceneHandlers[name] = handler
end

--- 切换到指定场景
---@param name string
---@param params table|nil  可选参数传递给新场景
function SceneManager.SwitchTo(name, params)
    -- 退出当前场景
    if SceneManager.currentSceneName ~= "" then
        local current = sceneHandlers[SceneManager.currentSceneName]
        if current and current.Exit then
            current.Exit()
        end
    end

    -- 进入新场景
    SceneManager.currentSceneName = name
    local handler = sceneHandlers[name]
    if handler and handler.Enter then
        handler.Enter(params)
    else
        print("[SceneManager] WARNING: No handler for scene '" .. name .. "'")
    end
end

--- 获取当前场景名称
function SceneManager.GetCurrent()
    return SceneManager.currentSceneName
end

return SceneManager
